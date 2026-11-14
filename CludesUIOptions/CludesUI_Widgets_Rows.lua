if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_Rows.lua
--  Factory rows: buttons, the keybind button, DualRow, TripleRow and the
--  other multi-slot rows. Reads BuildColorSwatch, so it loads after
--  CludesUI_Widgets_Color.lua.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
CludesUI._deferredInits[#CludesUI._deferredInits + 1] = function()
    -- Page reuse: the frames this file builds go through the options frame pool
    -- (CludesUI_FramePool.lua), which hands a kept page its previous build's
    -- frames back reset to new; on any other parent it creates as before. PoolGen
    -- (a frame's dress count) lets a handler that runs after a setter tell that
    -- the setter rebuilt the page and dressed its frames again for a new use.
    local CreateFrame = CludesUI._Pool.CreateFrame
    local PoolGen = CludesUI._Pool.Gen
    local Pix = CludesUI.PanelPP
    local SolidTex = CludesUI.SolidTex
    local MakeFont = CludesUI.MakeFont
    local MakeRoundedBorder = CludesUI.MakeRoundedBorder
    local RowBg = CludesUI.RowBg
    local MakeDropdownArrow = CludesUI.MakeDropdownArrow
    local RegisterWidgetRefresh = CludesUI.RegisterWidgetRefresh
    local EXPRESSWAY = CludesUI.EXPRESSWAY
    local CONTENT_PAD = CludesUI.CONTENT_PAD
    local TEXT_WHITE_R = CludesUI.TEXT_WHITE_R
    local TEXT_WHITE_G = CludesUI.TEXT_WHITE_G
    local TEXT_WHITE_B = CludesUI.TEXT_WHITE_B
    local BORDER_R = CludesUI.BORDER_R
    local BORDER_G = CludesUI.BORDER_G
    local BORDER_B = CludesUI.BORDER_B
    local DD_BG_R = CludesUI.DD_BG_R
    local DD_BG_G = CludesUI.DD_BG_G
    local DD_BG_B = CludesUI.DD_BG_B
    local DD_BG_A = CludesUI.DD_BG_A
    local DD_BG_HA = CludesUI.DD_BG_HA
    local DD_BRD_A = CludesUI.DD_BRD_A
    local DD_TXT_A = CludesUI.DD_TXT_A
    local DUAL_ITEM_W = CludesUI.DUAL_ITEM_W
    local DUAL_GAP = CludesUI.DUAL_GAP
    local TRIPLE_ITEM_W = CludesUI.TRIPLE_ITEM_W
    local TRIPLE_GAP = CludesUI.TRIPLE_GAP
    local MakeStyledButton = CludesUI.MakeStyledButton
    local WB_COLOURS = CludesUI.WB_COLOURS
    local RB_COLOURS = CludesUI.RB_COLOURS
    local ShowWidgetTooltip = CludesUI.ShowWidgetTooltip
    local HideWidgetTooltip = CludesUI.HideWidgetTooltip
    local DisabledTooltip = CludesUI.DisabledTooltip
    local isRussian = GetLocale() == "ruRU"
    local WI = CludesUI._widgetInternals
    local SL = WI.SL
    local TagOptionRow = WI.TagOptionRow
    local DDResolveLabel = WI.DDResolveLabel
    local IndexSlotForSearch = WI.IndexSlotForSearch
    local AddControlDisabledTooltip = WI.AddControlDisabledTooltip
    local PixelizeSliderCfg = WI.PixelizeSliderCfg
    local QueueLabelClamp = WI.QueueLabelClamp
    local LabelTooltipText = WI.LabelTooltipText
    local WidgetFactory = CludesUI.Widgets
    local ResolveDisabledTip = CludesUI.ResolveDisabledTip
    local BuildDropdownMenu = CludesUI.BuildDropdownMenu
    local WireLazyDropdown = WI.WireLazyDropdown
    local WD_DD_COLOURS = CludesUI.WD_DD_COLOURS
    local BuildSliderCore = CludesUI.BuildSliderCore
    local BuildDropdownControl = CludesUI.BuildDropdownControl
    local BuildToggleControl = CludesUI.BuildToggleControl
    local BuildCheckboxControl = CludesUI.BuildCheckboxControl
    local BuildColorSwatch = CludesUI.BuildColorSwatch

    -- cfg.tooltipOnControl: a slider's tooltip also shows while hovering the slider
    -- itself, not only its label (true = cfg.tooltip; a string = its own text for
    -- the slider, the label keeping cfg.tooltip). One motion-only hit frame spans
    -- the track, thumb and value box, so crossing the thumb or the gap never blinks
    -- the tooltip. A frame that takes motion is still the mouse focus and would
    -- drop every click, so clicks (and motion, for the value box's text cursor)
    -- propagate to the controls beneath. Never shown mid-drag or while disabled
    -- (the disabled tooltip covers that); a press hides it.
    local function AttachSliderTooltip(regionFrame, labelText, conf, trackFrame, thumb, valBox)
        local own = type(conf.tooltipOnControl) == "string" and conf.tooltipOnControl
        if not (own or (conf.tooltip and conf.tooltipOnControl)) then
            return
        end
        local hit = CreateFrame("Frame", nil, regionFrame)
        -- Starts half a thumb before the track: the thumb overhangs it at the minimum.
        local overhang = thumb and thumb:GetWidth() / 2 or 0
        hit:SetPoint("TOPLEFT", trackFrame, "LEFT", -overhang, valBox:GetHeight() / 2)
        hit:SetPoint("BOTTOMRIGHT", valBox, "BOTTOMRIGHT")
        -- Above the thumb and value box, below the disabled-tooltip hit (+10).
        hit:SetFrameLevel(trackFrame:GetFrameLevel() + 5)
        hit:SetMouseClickEnabled(false)
        CludesUI.PadHint(hit, "nodeignore")
        hit:SetScript("OnEnter", function()
            if CludesUI._sliderDragging or (conf.disabled and conf.disabled()) then
                return
            end
            ShowWidgetTooltip(
                hit,
                own or LabelTooltipText(regionFrame, labelText, conf.tooltip),
                conf.tooltipOpts
            )
        end)
        local function Hide()
            HideWidgetTooltip()
        end
        hit:SetScript("OnLeave", Hide)
        hit:SetPropagateMouseClicks(true)
        hit:SetPropagateMouseMotion(true)
        trackFrame:HookScript("OnMouseDown", Hide)
        if thumb then
            thumb:HookScript("OnMouseDown", Hide)
        end
        valBox:HookScript("OnMouseDown", Hide)
    end

    -- Button  (execute action, matches the reset/reload button style)
    function WidgetFactory:Button(hostFrame, textValue, yOffset, onClick)
        local ROW_H = 50
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        RowBg(widget, hostFrame)
        TagOptionRow(widget, hostFrame, textValue)
        local btn = CreateFrame("Button", nil, widget)
        Pix.Size(btn, 200, 32)
        Pix.Point(btn, "LEFT", widget, "LEFT", 20, 0)
        btn:SetFrameLevel(widget:GetFrameLevel() + 1)
        MakeStyledButton(btn, textValue, 13, RB_COLOURS, onClick)
        return widget, ROW_H
    end

    -- WideButton  (centered, no row background, customizable width -- for prominent actions)
    function WidgetFactory:WideButton(hostFrame, textValue, yOffset, onClick, btnWidth)
        btnWidth = btnWidth or 450
        local BTN_H = 42
        local ROW_H = BTN_H + 20
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(widget, hostFrame, textValue)
        local btn = CreateFrame("Button", nil, widget)
        Pix.Size(btn, btnWidth, BTN_H)
        Pix.Point(btn, "CENTER", widget, "CENTER", 0, 0)
        btn:SetFrameLevel(widget:GetFrameLevel() + 1)
        MakeStyledButton(btn, textValue, 14, WB_COLOURS, onClick)
        return widget, ROW_H
    end

    -- Spec Overrides capture: append an extra accessor to a region/row's capture config so inline extras (swatches, cog fields, inline toggles) built outside the factory capture TOGETHER with the slot's main setting as one override. acc = { type, text, getValue, setValue, step/values/order/hasAlpha }.
    function CludesUI.AddCaptureAccessor(regionFrame, acc)
        if not (regionFrame and acc and acc.getValue and acc.setValue) then
            return
        end
        local cc = regionFrame._captureCfg
        -- Dedupe by getValue identity: factory paths stash some controls themselves (colorpicker halves, multiSwatch rows) and BuildColorSwatch self-registers, so the same accessor must never join twice.
        if cc then
            if cc.getValue == acc.getValue then
                return
            end
            if cc.accessors then
                for _, a in ipairs(cc.accessors) do
                    if a.getValue == acc.getValue then
                        return
                    end
                end
            end
        end
        if not cc then
            regionFrame._captureCfg = { type = "multi", text = acc.text, accessors = { acc } }
        elseif cc.accessors then
            cc.accessors[#cc.accessors + 1] = acc
        else
            -- Promote a single-accessor widget cfg to a grouped slot cfg.
            regionFrame._captureCfg = { type = "multi", text = cc.text, accessors = { cc, acc } }
        end
    end

    -- Keybind capture button: left-click arms, the next key (with its modifiers) is the
    -- chord, Escape cancels, right-click unbinds. set(chord) writes, set(nil) unbinds;
    -- the caller anchors it. opts: w, h, pp (default PanelPP), level, font, get, set,
    -- tooltip, disabled + disabledTip (string, or fn returning one), mouse (armed clicks bind mouse chords),
    -- plainMouse (with mouse: an armed bare left/right click binds too, so unbind
    -- is a right-click from rest), canArm (returns false to refuse arming).
    -- Returns btn, refresh.
    function CludesUI.BuildKeybindButton(hostFrame, options)
        local btn = CreateFrame("Button", nil, hostFrame)
        local pp = options.pp or Pix
        pp.Size(btn, options.w, options.h)
        btn:SetFrameLevel(hostFrame:GetFrameLevel() + (options.level or 2))
        if options.mouse then
            btn:RegisterForClicks("AnyUp")
        else
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        local backdrop = SolidTex(btn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        backdrop:SetAllPoints()
        btn._border = MakeRoundedBorder(btn, 1, 1, 1, DD_BRD_A, backdrop)
        local labelFS = MakeFont(btn, options.font or 12, nil, 1, 1, 1)
        labelFS:SetAlpha(DD_TXT_A)
        labelFS:SetPoint("CENTER")

        local disabled = options.disabled
        local listening = false
        -- Controller buttons: padArmed while they are captured; padHeld is the button
        -- whose press ended capture, kept captured until its release.
        local padArmed, padWired, padHeld = false, false, nil
        local function Stop()
            listening = false
            btn:EnableKeyboard(false)
            if padArmed and not padHeld then
                padArmed = false
                btn:EnableGamePadButton(false)
            end
            -- OnLeave keeps the hover look while armed; drop it once capture ends.
            if not btn:IsMouseOver() then
                backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
                btn._border:SetColor(1, 1, 1, DD_BRD_A)
            end
        end
        local function FormatKey(key)
            if not key or key == "" then
                return CludesUI.L("Not Bound")
            end
            local parts = {}
            for mod in key:gmatch("(%u+)%-") do
                parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
            end
            parts[#parts + 1] = key:match("[^%-]+$") or key
            return table.concat(parts, " + ")
        end
        local function Refresh()
            if disabled then
                local offset = disabled()
                -- Mouse stays on so the disabled tooltip can show; OnClick refuses.
                btn:SetAlpha(offset and 0.3 or 1)
                if hostFrame._label then
                    hostFrame._label:SetAlpha(offset and 0.3 or 1)
                end
                if offset and listening then
                    Stop()
                end
            end
            if not listening then
                labelFS:SetText(FormatKey(options.get()))
            end
        end
        local function Commit(chord)
            Stop()
            local gen = PoolGen(btn)
            options.set(chord)
            -- A setter that rebuilt the page dressed this button again (page
            -- reuse): that dress painted itself, so this one paints nothing more.
            if PoolGen(btn) ~= gen then
                return
            end
            Refresh()
        end

        btn:SetScript("OnClick", function(self, btnFrame)
            if disabled and disabled() then
                return
            end
            -- OnKeyDown never sees mouse buttons; plain left/right keep arm/unbind
            -- unless plainMouse.
            if
                options.mouse
                and listening
                and (
                    (btnFrame ~= "LeftButton" and btnFrame ~= "RightButton")
                    or IsModifierKeyDown()
                    or options.plainMouse
                )
            then
                Commit(CreateKeyChordStringUsingMetaKeyState(GetConvertedKeyOrButton(btnFrame)))
                return
            end
            if btnFrame == "RightButton" then
                Commit(nil)
                return
            end
            if btnFrame ~= "LeftButton" or listening then
                return
            end
            if options.canArm and not options.canArm() then
                return
            end
            listening = true
            labelFS:SetText(CludesUI.L("Press a key..."))
            self:EnableKeyboard(true)
            -- Controller in use: its buttons are captured too, only while armed (Stop turns it off).
            if CludesUI.PadInUse() then
                if not padWired then
                    padWired = true
                    -- Armed: the button bound to the pause menu cancels, as Escape does on the
                    -- keyboard; a button set up as an emulated modifier passes through so it can
                    -- be held for a chord; anything else is the chord. The press that ends capture
                    -- is consumed down AND up (padHeld): a controller cursor clicks on release, so
                    -- a loose release would click this button again (re-arm, or unbind).
                    self:SetScript("OnGamePadButtonDown", function(s, key)
                        -- SetPropagateKeyboardInput is blocked in combat on every
                        -- frame: the key and pad handlers stand aside there, as the
                        -- popup helpers' do (every host closes as combat starts).
                        if InCombatLockdown() then
                            return
                        end
                        if not listening then
                            s:SetPropagateKeyboardInput(true)
                            return
                        end
                        if GetBindingFromClick(key) == "TOGGLEGAMEMENU" then
                            s:SetPropagateKeyboardInput(false)
                            padHeld = key
                            Stop()
                            Refresh()
                            return
                        end
                        local k = GetConvertedKeyOrButton(key)
                        if
                            IsKeyPressIgnoredForBinding(k)
                            or k == GetCVar("GamePadEmulateShift")
                            or k == GetCVar("GamePadEmulateCtrl")
                            or k == GetCVar("GamePadEmulateAlt")
                        then
                            s:SetPropagateKeyboardInput(true)
                            return
                        end
                        s:SetPropagateKeyboardInput(false)
                        padHeld = key
                        Commit(CreateKeyChordStringUsingMetaKeyState(k))
                    end)
                    self:SetScript("OnGamePadButtonUp", function(s, key)
                        if InCombatLockdown() then
                            return
                        end
                        if key ~= padHeld then
                            s:SetPropagateKeyboardInput(true)
                            return
                        end
                        s:SetPropagateKeyboardInput(false)
                        padHeld = nil
                        if not listening then
                            padArmed = false
                            s:EnableGamePadButton(false)
                        end
                    end)
                end
                padArmed = true
                self:EnableGamePadButton(true)
            end
        end)
        btn:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            -- Bare modifiers pass through so they can be held for the chord.
            if not listening or IsKeyPressIgnoredForBinding(key) then
                self:SetPropagateKeyboardInput(true)
                return
            end
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then
                Stop()
                Refresh()
                return
            end
            Commit(CreateKeyChordStringUsingMetaKeyState(key))
        end)
        btn:SetScript("OnEnter", function(self)
            if disabled and disabled() then
                local tipText = options.disabledTip
                if type(tipText) == "function" then
                    tipText = tipText()
                end
                ShowWidgetTooltip(self, DisabledTooltip(tipText))
                return
            end
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA)
            btn._border:SetColor(1, 1, 1, 0.3)
            ShowWidgetTooltip(
                self,
                options.tooltip or CludesUI.L("Left-click to set a keybind.\nRight-click to unbind.")
            )
        end)
        btn:SetScript("OnLeave", function()
            HideWidgetTooltip()
            if listening then
                return
            end
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
            btn._border:SetColor(1, 1, 1, DD_BRD_A)
        end)
        btn:SetScript("OnHide", function()
            if listening then
                Stop()
                Refresh()
            end
            -- A hidden button gets no release: drop a controller press still held.
            if padHeld then
                padHeld = nil
                padArmed = false
                btn:EnableGamePadButton(false)
            end
            -- Hidden is never hovered: always come back in the resting look.
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
            btn._border:SetColor(1, 1, 1, DD_BRD_A)
            HideWidgetTooltip()
        end)

        Refresh()
        return btn, Refresh
    end

    -- DualRow: two widgets side by side on one full-width row, 1px center divider.
    -- Slider:      { type="slider", text, min, max, step, getValue, setValue }
    -- Dropdown:    { type="dropdown", text, values, getValue, setValue, order }
    -- Toggle:      { type="toggle", text, getValue, setValue }
    -- ColorPicker: { type="colorpicker", text, getValue, setValue, hasAlpha }
    -- A row's hint: the first sentence of its tooltip, shown in small dim text under
    -- the setting's name (the whole tooltip still shows on hover). nil when the
    -- tooltip is not plain text or has nothing to show.
    local function RowHintText(tipText)
        if type(tipText) ~= "string" then
            return nil
        end
        local s = CludesUI.L(tipText):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
        s = s:match("^[^\n]+") or ""
        s = (s:match("^(.-[%.%!%?])%s") or s):gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then
            return nil
        end
        return s
    end

    function WidgetFactory:DualRow(hostFrame, yOffset, leftCfg, rightCfg)
        local ROW_H = 50
        local SIDE_PAD = 20 -- padding inside each half
        -- Blizzard Style: a row whose every control is gated for the active style is built (callers still hang cogs and sync icons on its regions) but hidden, takes no row background or search entry, and returns no height, so the page reads as if it were not there.
        local BS = CludesUI.BlizzStyle
        local hiddenRow = BS and BS.RowHidden and BS.RowHidden(leftCfg, rightCfg)
        local widget = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, totalW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        if not rightCfg then
            widget._skipRowDivider = true
        end
        if not hiddenRow then
            RowBg(widget, hostFrame)
            -- Search metadata: combined label on the frame (inline page search), one global-index entry per slot.
            local dualLabel = (leftCfg and leftCfg.text or "")
            if rightCfg and rightCfg.text then
                dualLabel = dualLabel .. " " .. rightCfg.text
            end
            TagOptionRow(widget, hostFrame, dualLabel, nil, true)
            IndexSlotForSearch(hostFrame, leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
            IndexSlotForSearch(hostFrame, rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)
        end

        -- Half regions: invisible, anchoring only
        local fullWidth = not rightCfg
        local halfW = math.floor(totalW / 2)
        local leftRegion = CreateFrame("Frame", nil, widget)
        leftRegion:SetSize(fullWidth and totalW or halfW, ROW_H)
        leftRegion:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)

        local rightRegion = CreateFrame("Frame", nil, widget)
        rightRegion:SetSize(halfW, ROW_H)
        rightRegion:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)

        local function BuildHalf(regionFrame, conf)
            if not conf then
                return
            end
            local t = conf.type
            -- Spec Overrides capture: expose the widget config so the capture overlay can identify settings. A slot is ONE setting: multiSwatch slots capture all their swatches together, inline extras join via AddCaptureAccessor. cfg.noCapture opts a widget out (used by the Spec Overrides page's own mirrored editors).
            if conf.noCapture then
                regionFrame._captureCfg = nil
                regionFrame._noCapture = true
            elseif t == "segmented" and conf.getValue and conf.setValue then
                regionFrame._captureCfg = {
                    type = "dropdown",
                    text = conf.text,
                    values = conf.values,
                    order = conf.order,
                    getValue = conf.getValue,
                    setValue = conf.setValue,
                }
            elseif conf.getValue and conf.setValue then
                regionFrame._captureCfg = conf
            elseif t == "multiSwatch" and conf.swatches then
                local accs = {}
                for i = 1, #conf.swatches do
                    local sc = conf.swatches[i]
                    if sc.getValue and sc.setValue then
                        accs[#accs + 1] = {
                            type = "colorpicker",
                            text = sc.tooltip or conf.text,
                            hasAlpha = sc.hasAlpha,
                            getValue = sc.getValue,
                            setValue = sc.setValue,
                        }
                    end
                end
                if #accs > 0 then
                    regionFrame._captureCfg = { type = "multi", text = conf.text, accessors = accs }
                end
            end
            -- Empty half-space placeholder for dual/third rows.
            if t == "spacer" then
                regionFrame._control = nil
                return
            end
            -- Label (every type has one). Single-line so the right-edge clamp (QueueLabelClamp) ellipsizes instead of wrapping.
            local labelText = MakeFont(regionFrame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            Pix.Point(labelText, "LEFT", regionFrame, "LEFT", SIDE_PAD, 0)
            labelText:SetJustifyH("LEFT")
            labelText:SetWordWrap(false)
            labelText:SetMaxLines(1)
            labelText:SetText(CludesUI.L(conf.text or ""))
            regionFrame._label = labelText
            regionFrame._cfg = conf
            regionFrame._labelHasHit = (conf.tooltip or conf.disabledTooltip) and true or false

            -- Hint line under the name (RowHintText). The name moves up to make room;
            -- the label clamp sizes the hint to stop short of the control.
            local hintText = t ~= "button" and RowHintText(conf.tooltip)
            regionFrame._labelDY, regionFrame._hint = nil, nil
            if hintText then
                labelText:ClearAllPoints()
                Pix.Point(labelText, "LEFT", regionFrame, "LEFT", SIDE_PAD, 7)
                regionFrame._labelDY = 7
                local hint = MakeFont(
                    regionFrame,
                    11,
                    nil,
                    CludesUI.TEXT_DIM_R,
                    CludesUI.TEXT_DIM_G,
                    CludesUI.TEXT_DIM_B
                )
                hint:SetAlpha(0.85)
                hint:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 0, -2)
                hint:SetJustifyH("LEFT")
                hint:SetWordWrap(false)
                hint:SetMaxLines(1)
                hint:SetWidth(math.max(40, (regionFrame:GetWidth() or 200) * 0.45))
                hint:SetText(hintText)
                regionFrame._hint = hint
            end

            -- Label tooltip. For dropdowns the hitFrame is created after the dropdown button so it can check whether the menu is open.
            -- A half-row button hides its label (the button explains its own lock, below).
            if (conf.tooltip or conf.disabledTooltip) and t ~= "dropdown" and t ~= "button" then
                local ttOpts = conf.tooltipOpts
                local hitFrame = CreateFrame("Frame", nil, regionFrame)
                hitFrame:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
                hitFrame:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
                hitFrame:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
                hitFrame:SetScript("OnEnter", function()
                    if conf.disabled and conf.disabled() and conf.disabledTooltip then
                        local tt = ResolveDisabledTip(conf)
                        if tt then
                            ShowWidgetTooltip(labelText, tt)
                        end
                    elseif conf.tooltip then
                        ShowWidgetTooltip(
                            labelText,
                            LabelTooltipText(regionFrame, labelText, conf.tooltip),
                            ttOpts
                        )
                    elseif regionFrame._labelTruncated then
                        -- Truncated label whose hit exists only for the disabled tooltip: reveal the full text while enabled.
                        ShowWidgetTooltip(labelText, labelText:GetText())
                    end
                end)
                hitFrame:SetScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
                -- Clicks pass through by default so controls stay interactive; intercepted while disabled to block interaction.
                hitFrame:SetMouseClickEnabled(false)
                if conf.disabled and conf.disabledTooltip then
                    local function UpdateHitMouse()
                        hitFrame:SetMouseClickEnabled(conf.disabled() and true or false)
                    end
                    RegisterWidgetRefresh(UpdateHitMouse)
                    UpdateHitMouse()
                end
            end

            -- cfg.disabled: optional fn returning bool; when true the label dims and the control goes non-interactive.
            local disabledOverlay -- optional dark overlay to gray out the whole half
            local controlFrame -- the clickable control (dropdown btn, toggle, etc.)
            local controlAnchor -- main control frame for inline element anchoring

            local function ApplyDisabledState()
                if not conf.disabled then
                    return
                end
                local offset = conf.disabled()
                labelText:SetAlpha(offset and 0.3 or 1)
                if regionFrame._hint then
                    regionFrame._hint:SetAlpha(offset and 0.3 or 0.85)
                end
                if controlFrame then
                    if offset then
                        controlFrame:EnableMouse(false)
                        controlFrame:SetAlpha(0.3)
                    else
                        controlFrame:EnableMouse(true)
                        controlFrame:SetAlpha(1)
                    end
                end
            end

            if t == "slider" then
                local defaultTrackW = isRussian and 120 or 160
                local scfg = PixelizeSliderCfg(conf)
                local trackFrame, valBox, _, slThumb = BuildSliderCore(
                    regionFrame,
                    conf.trackWidth or defaultTrackW,
                    4,
                    14,
                    40,
                    26,
                    13,
                    SL.INPUT_A,
                    scfg.min,
                    scfg.max,
                    scfg.step,
                    scfg.getValue,
                    scfg.setValue,
                    true,
                    conf.snapPoints,
                    conf.valueSnap
                )
                Pix.Point(valBox, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
                controlFrame = nil -- slider owns its disabled state; keep the generic handler off its mouse
                AddControlDisabledTooltip(trackFrame, conf)
                RegisterWidgetRefresh(function()
                    if conf.disabled then
                        local offset = conf.disabled()
                        labelText:SetAlpha(offset and 0.3 or 1)
                        trackFrame:SetAlpha(offset and 0.3 or 1)
                        valBox:EnableMouse(not offset)
                        valBox:SetAlpha(offset and 0.3 or 1)
                        if slThumb then
                            slThumb._sliderDisabled = offset
                        end
                    end
                end)
                if conf.disabled then
                    local offset = conf.disabled()
                    labelText:SetAlpha(offset and 0.3 or 1)
                    trackFrame:SetAlpha(offset and 0.3 or 1)
                    valBox:EnableMouse(not offset)
                    valBox:SetAlpha(offset and 0.3 or 1)
                    if slThumb then
                        slThumb._sliderDisabled = offset
                    end
                end
                AttachSliderTooltip(regionFrame, labelText, conf, trackFrame, slThumb, valBox)
                controlAnchor = trackFrame
            elseif t == "segmented" then
                -- A choice of two or three, as a row of square buttons: the same
                -- cfg as a dropdown (values = { key = "Label" }, order, getValue,
                -- setValue, disabled, tooltip), every option in view at once.
                -- Opt-in per row: a dropdown with many or long options stays one.
                local function Pick(key)
                    if conf.disabled and conf.disabled() then
                        return
                    end
                    if conf.getValue() == key then
                        return
                    end
                    -- Spec Overrides capture and the changed flag, as the other controls report a write.
                    local snap = CludesUI._SOAttribution(regionFrame)
                    conf.setValue(key)
                    CludesUI._NotifySettingWrite(regionFrame, snap)
                    CludesUI._settingsChanged = true
                end
                local segFrame, _, segRefresh = CludesUI.BuildSegmentedControl({
                    parent = regionFrame,
                    square = true,
                    autoWidth = true,
                    height = 26,
                    keys = conf.order,
                    labels = conf.values,
                    getChecked = function(key)
                        return conf.getValue() == key
                    end,
                    isDisabled = conf.disabled and function()
                        return conf.disabled() and true or false
                    end or nil,
                    onToggle = function(key)
                        local g = PoolGen(regionFrame)
                        Pick(key)
                        -- A setter that rebuilt the page dressed this region again: its new build paints.
                        if PoolGen(regionFrame) == g and regionFrame._segRefresh then
                            regionFrame._segRefresh()
                        end
                    end,
                })
                Pix.Point(segFrame, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                segFrame:SetFrameLevel(widget:GetFrameLevel() + 2)
                regionFrame._segRefresh = segRefresh
                controlFrame = segFrame
                controlAnchor = segFrame
                AddControlDisabledTooltip(segFrame, conf)
                RegisterWidgetRefresh(function()
                    if segRefresh then
                        segRefresh()
                    end
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "dropdown" then
                local DD_W = conf.dropdownWidth or 170
                -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
                local ddDisabledFn = conf.disabledValues
                if not ddDisabledFn and conf.itemDisabled then
                    ddDisabledFn = function(val)
                        if conf.itemDisabled(val) then
                            if conf.itemDisabledTooltip then
                                local tipText = conf.itemDisabledTooltip(val)
                                -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                                -- for a bare requirement noun (nil = "enabled", as before).
                                if tipText then
                                    return DisabledTooltip(tipText, conf.itemRequireState)
                                end
                            end
                            return true
                        end
                        return false
                    end
                end
                local ddBtn, ddLbl = BuildDropdownControl(
                    regionFrame,
                    DD_W,
                    widget:GetFrameLevel() + 2,
                    conf.values,
                    conf.order,
                    conf.getValue,
                    conf.setValue,
                    ddDisabledFn
                )
                Pix.Point(ddBtn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = ddBtn
                controlAnchor = ddBtn
                if conf.labelOnlyDisabled then
                    AddControlDisabledTooltip(labelText, conf)
                else
                    AddControlDisabledTooltip(ddBtn, conf)
                end
                -- Tooltip config on the button: WireDropdownScripts and the pre-menu hover scripts read ddBtn._ttText/_ttOpts.
                if conf.tooltip or (conf.disabledTooltip and conf.disabled) then
                    if conf.tooltip then
                        ddBtn._ttText = conf.tooltip
                        ddBtn._ttOpts = conf.tooltipOpts
                    end
                    local ttOpts = conf.tooltipOpts
                    local hitFrame = CreateFrame("Frame", nil, regionFrame)
                    hitFrame:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
                    hitFrame:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
                    hitFrame:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
                    hitFrame:SetScript("OnEnter", function()
                        if conf.disabled and conf.disabled() and conf.disabledTooltip then
                            local tt = ResolveDisabledTip(conf)
                            if tt then
                                ShowWidgetTooltip(labelText, tt)
                            end
                        elseif conf.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                            ShowWidgetTooltip(
                                labelText,
                                LabelTooltipText(regionFrame, labelText, conf.tooltip),
                                ttOpts
                            )
                        elseif
                            regionFrame._labelTruncated and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown())
                        then
                            ShowWidgetTooltip(labelText, labelText:GetText())
                        end
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                    hitFrame:SetMouseClickEnabled(false)
                    -- Intercept clicks over the label area while disabled
                    if conf.disabled and conf.disabledTooltip then
                        local function UpdateHitMouse()
                            hitFrame:SetMouseClickEnabled(conf.disabled() and true or false)
                        end
                        RegisterWidgetRefresh(UpdateHitMouse)
                        UpdateHitMouse()
                    end
                end
                if conf.labelOnlyDisabled and conf.disabled then
                    local function ApplyLabelOnly()
                        local offset = conf.disabled()
                        labelText:SetAlpha(1)
                    end
                    RegisterWidgetRefresh(function()
                        ddLbl:SetText(DDResolveLabel(conf.values, conf.order or {}, conf.getValue()))
                        ApplyLabelOnly()
                    end)
                    ApplyLabelOnly()
                else
                    RegisterWidgetRefresh(function()
                        ddLbl:SetText(DDResolveLabel(conf.values, conf.order or {}, conf.getValue()))
                        ApplyDisabledState()
                    end)
                    ApplyDisabledState()
                end
            elseif t == "toggle" then
                local toggle, _, tgSnap =
                    BuildToggleControl(regionFrame, widget:GetFrameLevel() + 2, conf.getValue, conf.setValue)
                toggle:SetPoint("RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = toggle
                controlAnchor = toggle
                AddControlDisabledTooltip(toggle, conf)
                RegisterWidgetRefresh(function()
                    tgSnap()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "colorpicker" then
                local colorSwatch, _updateSwatch = BuildColorSwatch(
                    regionFrame,
                    widget:GetFrameLevel() + 2,
                    conf.getValue,
                    conf.setValue,
                    conf.hasAlpha
                )
                Pix.Point(colorSwatch, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = colorSwatch
                controlAnchor = colorSwatch
                AddControlDisabledTooltip(colorSwatch, conf)
                RegisterWidgetRefresh(function()
                    _updateSwatch()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "button" then
                -- Half-row button: label hidden, the button IS the content
                labelText:Hide()
                local btn = CreateFrame("Button", nil, regionFrame)
                Pix.Size(btn, conf.width or 180, 32)
                Pix.Point(btn, "CENTER", regionFrame, "CENTER", 0, 0)
                btn:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(btn, conf.text or "", 13, RB_COLOURS, conf.onClick)
                controlFrame = btn
                controlAnchor = btn
                AddControlDisabledTooltip(btn, conf)
                RegisterWidgetRefresh(function()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "labeledButton" then
                -- Standard left label, button anchored right
                local btn = CreateFrame("Button", nil, regionFrame)
                Pix.Size(btn, conf.width or 180, 32)
                Pix.Point(btn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                btn:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(btn, conf.buttonText or conf.text or "", 13, RB_COLOURS, conf.onClick)
                controlFrame = btn
                controlAnchor = btn
                AddControlDisabledTooltip(btn, conf)
                RegisterWidgetRefresh(function()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "multiSwatch" then
                -- Label + N swatches laid out right-to-left from the right edge
                local SWATCH_SZ = 24
                local SWATCH_GAP = 8
                local swatches = conf.swatches or {}
                local anchorX = -SIDE_PAD
                local leftmostSwatch
                for i = #swatches, 1, -1 do
                    local sc = swatches[i]
                    local colorSwatch, updateSwatch = BuildColorSwatch(
                        regionFrame,
                        widget:GetFrameLevel() + 2,
                        sc.getValue,
                        sc.setValue,
                        sc.hasAlpha
                    )
                    Pix.Point(colorSwatch, "RIGHT", regionFrame, "RIGHT", anchorX, 0)
                    anchorX = anchorX - SWATCH_SZ - SWATCH_GAP
                    leftmostSwatch = colorSwatch
                    -- Optional click override (e.g. class color toggle)
                    if sc.onClick then
                        colorSwatch._eabOrigClick = colorSwatch:GetScript("OnClick")
                        colorSwatch:SetScript("OnClick", sc.onClick)
                    end
                    -- Effective disabled = row-level cfg.disabled OR per-swatch sc.disabled
                    local function SwatchEffectiveDisabled()
                        if conf.disabled and conf.disabled() then
                            return true
                        end
                        if sc.disabled ~= nil then
                            if type(sc.disabled) == "function" then
                                return sc.disabled()
                            end
                            return sc.disabled
                        end
                        return false
                    end
                    -- Overlay greys out and blocks the swatch while disabled
                    if conf.disabled or sc.disabled then
                        local swatchBlock = CreateFrame("Frame", nil, colorSwatch)
                        swatchBlock:SetAllPoints()
                        swatchBlock:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                        swatchBlock:EnableMouse(true)
                        swatchBlock:SetScript("OnEnter", function()
                            local source = (sc.disabledTooltip ~= nil) and sc or conf
                            local tipText = ResolveDisabledTip(source)
                            if tipText then
                                ShowWidgetTooltip(colorSwatch, tipText)
                            end
                        end)
                        swatchBlock:SetScript("OnLeave", function()
                            HideWidgetTooltip()
                        end)
                        local function UpdateSwatchDisabled()
                            if SwatchEffectiveDisabled() then
                                colorSwatch:SetAlpha(0.3)
                                swatchBlock:Show()
                            else
                                colorSwatch:SetAlpha(1)
                                swatchBlock:Hide()
                            end
                        end
                        UpdateSwatchDisabled()
                        RegisterWidgetRefresh(UpdateSwatchDisabled)
                    end
                    if sc.tooltip then
                        colorSwatch:HookScript("OnEnter", function()
                            ShowWidgetTooltip(colorSwatch, sc.tooltip)
                        end)
                        colorSwatch:HookScript("OnLeave", function()
                            HideWidgetTooltip()
                        end)
                    end
                    -- Per-swatch alpha refresh (dim inactive, bright active)
                    if sc.refreshAlpha then
                        local _sw, _ra = colorSwatch, sc.refreshAlpha
                        local function UpdateAlpha()
                            -- The disabled handler owns alpha while disabled
                            if SwatchEffectiveDisabled() then
                                return
                            end
                            _sw:SetAlpha(_ra())
                        end
                        UpdateAlpha()
                        RegisterWidgetRefresh(UpdateAlpha)
                    end
                    RegisterWidgetRefresh(function()
                        updateSwatch()
                    end)
                end
                controlAnchor = leftmostSwatch
                RegisterWidgetRefresh(function()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "input" then
                -- Free-text entry box, right-anchored. getValue returns the display
                -- string; setValue receives raw text and parses/validates it. Commits
                -- on Enter and focus loss; Escape reverts.
                -- cfg.inputStyle == "popup" restyles it like the ShowInputPopup field
                -- (near-black fill, subtle border, left-justified) and supports
                -- cfg.placeholder ghost text while empty.
                local isPopupStyle = conf.inputStyle == "popup"
                local boxW = conf.inputWidth or 64
                local boxFrame = CreateFrame("EditBox", nil, regionFrame)
                boxFrame:SetSize(boxW, isPopupStyle and 28 or 22)
                Pix.Point(boxFrame, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                boxFrame:SetAutoFocus(false)
                boxFrame:SetTextColor(1, 1, 1, 0.9)
                local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                if isPopupStyle then
                    -- cfg.inputJustify == "CENTER" centers the text and placeholder (default left).
                    local centered = conf.inputJustify == "CENTER"
                    boxFrame:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                    boxFrame:SetJustifyH(centered and "CENTER" or "LEFT")
                    boxFrame:SetTextInsets(10, 10, 0, 0)
                    boxBg:SetColorTexture(0, 0, 0, 0.5)
                    MakeRoundedBorder(boxFrame, 1, 1, 1, 0.2, boxBg)
                    if conf.placeholder then
                        local ph = boxFrame:CreateFontString(nil, "ARTWORK")
                        ph:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                        ph:SetTextColor(0.7, 0.7, 0.7, 0.45)
                        if centered then
                            ph:SetPoint("CENTER", boxFrame, "CENTER", 0, 0)
                        else
                            ph:SetPoint("LEFT", boxFrame, "LEFT", 10, 0)
                        end
                        ph:SetText(CludesUI.L(conf.placeholder))
                        boxFrame:SetScript("OnTextChanged", function(self)
                            ph:SetShown((self:GetText() or "") == "")
                        end)
                    end
                else
                    boxFrame:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
                    boxFrame:SetJustifyH("CENTER")
                    boxFrame:SetTextInsets(4, 4, 0, 0)
                    boxBg:SetColorTexture(0.12, 0.12, 0.12, 0.85)
                    CludesUI.RoundBody(boxFrame, boxBg)
                end
                local function RefreshInput()
                    if boxFrame:HasFocus() then
                        return
                    end
                    boxFrame:SetText((conf.getValue and conf.getValue()) or "")
                end
                local committing = false
                -- A setter that rebuilds the page can dress this box again for
                -- another row (page reuse): that dress painted itself, so the
                -- commit's own repaint is skipped (here and after Escape, whose
                -- focus loss commits too).
                local function CommitInput()
                    if committing then
                        return
                    end
                    committing = true
                    local gen = PoolGen(boxFrame)
                    boxFrame:ClearFocus()
                    if conf.setValue then
                        conf.setValue(boxFrame:GetText())
                    end
                    if PoolGen(boxFrame) == gen then
                        RefreshInput()
                    end
                    committing = false
                end
                boxFrame:SetScript("OnEnterPressed", CommitInput)
                boxFrame:SetScript("OnEditFocusLost", CommitInput)
                boxFrame:SetScript("OnEscapePressed", function(self)
                    local gen = PoolGen(self)
                    self:ClearFocus()
                    if PoolGen(self) == gen then
                        RefreshInput()
                    end
                end)
                RefreshInput()
                controlFrame = boxFrame
                controlAnchor = boxFrame
                AddControlDisabledTooltip(boxFrame, conf)
                RegisterWidgetRefresh(function()
                    RefreshInput()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            end
            regionFrame._control = controlAnchor or controlFrame
            -- Truncation is deferred (QueueLabelClamp) and the right bound applies ONLY on actual overflow: a bound stretches the label's rect, so anything anchored to its RIGHT edge (e.g. "(Applies to ...)" subtitles) would slide to the far side of the slot on short labels.
            QueueLabelClamp(regionFrame)
        end

        BuildHalf(leftRegion, leftCfg)
        BuildHalf(rightRegion, rightCfg)

        -- Slot-level search labels drive per-slot highlighting
        leftRegion._slotLabel = leftCfg and leftCfg.text or ""
        rightRegion._slotLabel = rightCfg and rightCfg.text or ""

        -- Dropdown getValue/values stashed for dynamic search matching
        if leftCfg and (leftCfg.type == "dropdown" or leftCfg.type == "segmented") then
            leftRegion._ddGetValue = leftCfg.getValue
            leftRegion._ddValues = leftCfg.values
        end
        if rightCfg and (rightCfg.type == "dropdown" or rightCfg.type == "segmented") then
            rightRegion._ddGetValue = rightCfg.getValue
            rightRegion._ddValues = rightCfg.values
        end

        -- 1px center divider (global BORDER style)
        if not fullWidth then
            local div = widget:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
            div:SetWidth(1)
            div:SetPoint("TOP", widget, "TOP", 0, 0)
            div:SetPoint("BOTTOM", widget, "BOTTOM", 0, 0)
        end

        -- Widget cfg on the regions lets sync icons check disabled state
        leftRegion._widgetCfg = leftCfg
        rightRegion._widgetCfg = rightCfg

        -- Half regions exposed so callers can anchor child elements
        widget._leftRegion = leftRegion
        widget._rightRegion = rightRegion

        if hiddenRow then
            -- The inline page search re-shows and re-anchors every row it has
            -- collected whenever it resets; keep this one out of its hands.
            widget._searchIgnore = true
            widget:Hide()
            return widget, 0
        end
        return widget, ROW_H
    end

    -- TripleRow: three widgets on one full-width row, 1px dividers at the splits. Each column uses the DualRow cfg format.
    function WidgetFactory:TripleRow(hostFrame, yOffset, leftCfg, midCfg, rightCfg, splits)
        local ROW_H = (splits and splits.rowHeight) or 50
        local SIDE_PAD = 20
        local widget = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, totalW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        widget._skipRowDivider = true
        RowBg(widget, hostFrame)
        -- Search metadata: combined label on the frame, one global-index entry per slot
        local triLabel = (leftCfg and leftCfg.text or "")
            .. " "
            .. (midCfg and midCfg.text or "")
            .. " "
            .. (rightCfg and rightCfg.text or "")
        TagOptionRow(widget, hostFrame, triLabel, nil, true)
        IndexSlotForSearch(hostFrame, leftCfg and leftCfg.text, leftCfg and leftCfg.tooltip)
        IndexSlotForSearch(hostFrame, midCfg and midCfg.text, midCfg and midCfg.tooltip)
        IndexSlotForSearch(hostFrame, rightCfg and rightCfg.text, rightCfg and rightCfg.tooltip)

        -- Custom or default 44% / 28% / 28% split
        local leftW = math.floor(totalW * ((splits and splits[1]) or 0.44))
        local midW = math.floor(totalW * ((splits and splits[2]) or 0.28))
        local rightW = totalW - leftW - midW

        local leftRegion = CreateFrame("Frame", nil, widget)
        leftRegion:SetSize(leftW, ROW_H)
        leftRegion:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)

        local midRegion = CreateFrame("Frame", nil, widget)
        midRegion:SetSize(midW, ROW_H)
        midRegion:SetPoint("TOPLEFT", leftRegion, "TOPRIGHT", 0, 0)

        local rightRegion = CreateFrame("Frame", nil, widget)
        rightRegion:SetSize(rightW, ROW_H)
        rightRegion:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)

        local function BuildThird(regionFrame, conf)
            if not conf then
                return
            end
            local t = conf.type
            -- Spec Overrides capture: see DualRow BuildHalf.
            if conf.noCapture then
                regionFrame._noCapture = true
            elseif conf.getValue and conf.setValue then
                regionFrame._captureCfg = conf
            end
            local labelText = MakeFont(regionFrame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            Pix.Point(labelText, "LEFT", regionFrame, "LEFT", SIDE_PAD, 0)
            labelText:SetJustifyH("LEFT")
            labelText:SetWordWrap(false)
            labelText:SetMaxLines(1)
            labelText:SetText(CludesUI.L(conf.text or ""))
            regionFrame._label = labelText
            regionFrame._cfg = conf
            regionFrame._labelHasHit = (conf.tooltip or conf.disabledTooltip) and true or false

            if (conf.tooltip or conf.disabledTooltip) and t ~= "dropdown" then
                local ttOpts = conf.tooltipOpts
                local hitFrame = CreateFrame("Frame", nil, regionFrame)
                hitFrame:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
                hitFrame:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
                hitFrame:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
                hitFrame:SetScript("OnEnter", function()
                    if conf.disabled and conf.disabled() and conf.disabledTooltip then
                        local tt = ResolveDisabledTip(conf)
                        if tt then
                            ShowWidgetTooltip(labelText, tt)
                        end
                    elseif conf.tooltip then
                        ShowWidgetTooltip(
                            labelText,
                            LabelTooltipText(regionFrame, labelText, conf.tooltip),
                            ttOpts
                        )
                    elseif regionFrame._labelTruncated then
                        -- Truncated label whose hit exists only for the disabled tooltip: reveal the full text while enabled.
                        ShowWidgetTooltip(labelText, labelText:GetText())
                    end
                end)
                hitFrame:SetScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
                -- Clicks pass through by default so controls stay interactive; intercepted while disabled to block interaction.
                hitFrame:SetMouseClickEnabled(false)
                if conf.disabled and conf.disabledTooltip then
                    local function UpdateHitMouse()
                        hitFrame:SetMouseClickEnabled(conf.disabled() and true or false)
                    end
                    RegisterWidgetRefresh(UpdateHitMouse)
                    UpdateHitMouse()
                end
            end

            local controlFrame, controlAnchor
            local function ApplyDisabledState()
                if not conf.disabled then
                    return
                end
                local offset = conf.disabled()
                labelText:SetAlpha(offset and 0.3 or 1)
                if controlFrame then
                    if offset then
                        controlFrame:EnableMouse(false)
                        controlFrame:SetAlpha(0.3)
                    else
                        controlFrame:EnableMouse(true)
                        controlFrame:SetAlpha(1)
                    end
                end
            end

            if t == "slider" then
                local defaultTrackW = isRussian and 100 or 130
                local scfg = PixelizeSliderCfg(conf)
                local trackFrame, valBox, _, slThumb = BuildSliderCore(
                    regionFrame,
                    conf.trackWidth or defaultTrackW,
                    4,
                    14,
                    40,
                    26,
                    13,
                    SL.INPUT_A,
                    scfg.min,
                    scfg.max,
                    scfg.step,
                    scfg.getValue,
                    scfg.setValue,
                    true,
                    conf.snapPoints,
                    conf.valueSnap
                )
                Pix.Point(valBox, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
                RegisterWidgetRefresh(function()
                    if conf.disabled then
                        local offset = conf.disabled()
                        labelText:SetAlpha(offset and 0.3 or 1)
                        trackFrame:SetAlpha(offset and 0.3 or 1)
                        valBox:EnableMouse(not offset)
                        valBox:SetAlpha(offset and 0.3 or 1)
                        if slThumb then
                            slThumb._sliderDisabled = offset
                        end
                    end
                end)
                if conf.disabled then
                    local offset = conf.disabled()
                    labelText:SetAlpha(offset and 0.3 or 1)
                    trackFrame:SetAlpha(offset and 0.3 or 1)
                    valBox:EnableMouse(not offset)
                    valBox:SetAlpha(offset and 0.3 or 1)
                    if slThumb then
                        slThumb._sliderDisabled = offset
                    end
                end
                AttachSliderTooltip(regionFrame, labelText, conf, trackFrame, slThumb, valBox)
                controlAnchor = trackFrame
            elseif t == "dropdown" then
                local DD_W = conf.dropdownWidth or 170
                -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
                local ddDisabledFn = conf.disabledValues
                if not ddDisabledFn and conf.itemDisabled then
                    ddDisabledFn = function(val)
                        if conf.itemDisabled(val) then
                            if conf.itemDisabledTooltip then
                                local tipText = conf.itemDisabledTooltip(val)
                                -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                                -- for a bare requirement noun (nil = "enabled", as before).
                                if tipText then
                                    return DisabledTooltip(tipText, conf.itemRequireState)
                                end
                            end
                            return true
                        end
                        return false
                    end
                end
                local ddBtn, ddLbl = BuildDropdownControl(
                    regionFrame,
                    DD_W,
                    widget:GetFrameLevel() + 2,
                    conf.values,
                    conf.order,
                    conf.getValue,
                    conf.setValue,
                    ddDisabledFn
                )
                Pix.Point(ddBtn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = ddBtn
                if conf.labelOnlyDisabled then
                    AddControlDisabledTooltip(labelText, conf)
                else
                    AddControlDisabledTooltip(ddBtn, conf)
                end
                if conf.tooltip or (conf.disabledTooltip and conf.disabled) then
                    if conf.tooltip then
                        ddBtn._ttText = conf.tooltip
                        ddBtn._ttOpts = conf.tooltipOpts
                    end
                    local ttOpts = conf.tooltipOpts
                    local hitFrame = CreateFrame("Frame", nil, regionFrame)
                    hitFrame:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
                    hitFrame:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
                    hitFrame:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
                    hitFrame:SetScript("OnEnter", function()
                        if conf.disabled and conf.disabled() and conf.disabledTooltip then
                            local tt = ResolveDisabledTip(conf)
                            if tt then
                                ShowWidgetTooltip(labelText, tt)
                            end
                        elseif conf.tooltip and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown()) then
                            ShowWidgetTooltip(
                                labelText,
                                LabelTooltipText(regionFrame, labelText, conf.tooltip),
                                ttOpts
                            )
                        elseif
                            regionFrame._labelTruncated and not (ddBtn._ddMenu and ddBtn._ddMenu:IsShown())
                        then
                            ShowWidgetTooltip(labelText, labelText:GetText())
                        end
                    end)
                    hitFrame:SetScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                    hitFrame:SetMouseClickEnabled(false)
                    if conf.disabled and conf.disabledTooltip then
                        local function UpdateHitMouse()
                            hitFrame:SetMouseClickEnabled(conf.disabled() and true or false)
                        end
                        RegisterWidgetRefresh(UpdateHitMouse)
                        UpdateHitMouse()
                    end
                end
                if conf.labelOnlyDisabled and conf.disabled then
                    local function ApplyLabelOnly()
                        local offset = conf.disabled()
                        labelText:SetAlpha(1)
                        -- Gray the button label when the current value is disabled,
                        -- through the text colour's alpha (the label's resting alpha);
                        -- _valueDimA keeps the hover colours on that alpha too.
                        if conf.disabledValues then
                            local curVal = conf.getValue()
                            local dimA = conf.disabledValues(curVal) and 0.15 or nil
                            ddBtn._valueDimA = dimA
                            ddLbl:SetTextColor(1, 1, 1, dimA or DD_TXT_A)
                        end
                    end
                    RegisterWidgetRefresh(function()
                        ddLbl:SetText(DDResolveLabel(conf.values, conf.order or {}, conf.getValue()))
                        ApplyLabelOnly()
                        if ddBtn._ddRefresh then
                            ddBtn._ddRefresh()
                        end
                    end)
                    ApplyLabelOnly()
                else
                    RegisterWidgetRefresh(function()
                        ddLbl:SetText(DDResolveLabel(conf.values, conf.order or {}, conf.getValue()))
                        ApplyDisabledState()
                        if ddBtn._ddRefresh then
                            ddBtn._ddRefresh()
                        end
                    end)
                    ApplyDisabledState()
                end
            elseif t == "toggle" then
                local toggle, _, tgSnap =
                    BuildToggleControl(regionFrame, widget:GetFrameLevel() + 2, conf.getValue, conf.setValue)
                toggle:SetPoint("RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = toggle
                AddControlDisabledTooltip(toggle, conf)
                RegisterWidgetRefresh(function()
                    tgSnap()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "colorpicker" then
                local colorSwatch, _updateSwatch = BuildColorSwatch(
                    regionFrame,
                    widget:GetFrameLevel() + 2,
                    conf.getValue,
                    conf.setValue,
                    conf.hasAlpha
                )
                Pix.Point(colorSwatch, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = colorSwatch
                RegisterWidgetRefresh(function()
                    _updateSwatch()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "checkbox" then
                -- Generic label hidden: the checkbox draws its own label + box
                labelText:Hide()
                local btn = CreateFrame("Button", nil, regionFrame)
                btn:SetSize(regionFrame:GetWidth(), ROW_H)
                btn:SetAllPoints(regionFrame)
                btn:SetFrameLevel(widget:GetFrameLevel() + 2)

                local boxFrame, check, boxBorder, cbApply =
                    BuildCheckboxControl(btn, widget:GetFrameLevel() + 2)
                boxFrame:SetPoint("LEFT", btn, "LEFT", SIDE_PAD, 0)

                local cbLabel = MakeFont(btn, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
                cbLabel:SetPoint("LEFT", boxFrame, "RIGHT", 10, 0)
                cbLabel:SetText(CludesUI.L(conf.text or ""))

                local isHovering = false
                local function ApplyCBVisual()
                    local enabled = conf.getValue()
                    cbApply(enabled, isHovering)
                    if enabled then
                        cbLabel:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
                    else
                        local a = isHovering and 1 or 0.8
                        cbLabel:SetTextColor(TEXT_WHITE_R * a, TEXT_WHITE_G * a, TEXT_WHITE_B * a, a)
                    end
                end
                ApplyCBVisual()

                btn:SetScript("OnClick", function()
                    local gen = PoolGen(btn)
                    local val = not conf.getValue()
                    conf.setValue(val)
                    CludesUI._settingsChanged = true
                    -- A setter that rebuilt the page dressed this checkbox again
                    -- (page reuse): that dress painted itself.
                    if PoolGen(btn) ~= gen then
                        return
                    end
                    ApplyCBVisual()
                end)
                btn:SetScript("OnEnter", function()
                    isHovering = true
                    ApplyCBVisual()
                end)
                btn:SetScript("OnLeave", function()
                    isHovering = false
                    ApplyCBVisual()
                end)

                controlFrame = btn
                RegisterWidgetRefresh(function()
                    ApplyCBVisual()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "button" then
                labelText:Hide()
                local btn = CreateFrame("Button", nil, regionFrame)
                Pix.Size(btn, conf.width or 140, 32)
                Pix.Point(btn, "CENTER", regionFrame, "CENTER", 0, 0)
                btn:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(btn, conf.text or "", 13, RB_COLOURS, conf.onClick)
                controlFrame = btn
                RegisterWidgetRefresh(function()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            elseif t == "labeledButton" then
                local btn = CreateFrame("Button", nil, regionFrame)
                Pix.Size(btn, conf.width or 140, 32)
                Pix.Point(btn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                btn:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(btn, conf.buttonText or conf.text or "", 13, RB_COLOURS, conf.onClick)
                controlFrame = btn
                RegisterWidgetRefresh(function()
                    ApplyDisabledState()
                end)
                ApplyDisabledState()
            end
            regionFrame._control = controlAnchor or controlFrame
            -- Truncation is deferred (QueueLabelClamp) and the right bound applies ONLY on actual overflow: a bound stretches the label's rect, so anything anchored to its RIGHT edge (e.g. "(Applies to ...)" subtitles) would slide to the far side of the slot on short labels.
            QueueLabelClamp(regionFrame)
        end

        BuildThird(leftRegion, leftCfg)
        BuildThird(midRegion, midCfg)
        BuildThird(rightRegion, rightCfg)

        -- Slot-level search labels drive per-slot highlighting
        leftRegion._slotLabel = leftCfg and leftCfg.text or ""
        midRegion._slotLabel = midCfg and midCfg.text or ""
        rightRegion._slotLabel = rightCfg and rightCfg.text or ""

        -- Dropdown getValue/values stashed for dynamic search matching
        if leftCfg and leftCfg.type == "dropdown" then
            leftRegion._ddGetValue = leftCfg.getValue
            leftRegion._ddValues = leftCfg.values
        end
        if midCfg and midCfg.type == "dropdown" then
            midRegion._ddGetValue = midCfg.getValue
            midRegion._ddValues = midCfg.values
        end
        if rightCfg and rightCfg.type == "dropdown" then
            rightRegion._ddGetValue = rightCfg.getValue
            rightRegion._ddValues = rightCfg.values
        end

        -- 1px column-boundary dividers (RowBg center-divider style)
        for _, rgn in ipairs({ leftRegion, midRegion }) do
            local div = widget:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.06)
            if div.SetSnapToPixelGrid then
                div:SetSnapToPixelGrid(false)
                div:SetTexelSnappingBias(0)
            end
            div:SetWidth(1)
            Pix.Point(div, "TOP", rgn, "TOPRIGHT", 0, 0)
            Pix.Point(div, "BOTTOM", rgn, "BOTTOMRIGHT", 0, 0)
        end

        leftRegion._widgetCfg = leftCfg
        if midRegion then
            midRegion._widgetCfg = midCfg
        end
        rightRegion._widgetCfg = rightCfg

        widget._leftRegion = leftRegion
        widget._midRegion = midRegion
        widget._rightRegion = rightRegion

        return widget, ROW_H
    end

    -- MultiSwatchRow: label left, N full-size color swatches right with tooltips.
    -- cfg = { text = "Row Label", swatches = {
    --   { tooltip = "Swatch 1", getValue = fn, setValue = fn, hasAlpha = bool }, ... } }
    function WidgetFactory:MultiSwatchRow(hostFrame, yOffset, conf)
        local ROW_H = 50
        local SIDE_PAD = 20
        local SWATCH_GAP = 8
        local widget = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, totalW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        widget._skipRowDivider = true
        RowBg(widget, hostFrame)
        TagOptionRow(widget, hostFrame, conf.text or "")

        local labelText = MakeFont(widget, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        Pix.Point(labelText, "LEFT", widget, "LEFT", SIDE_PAD, 0)
        labelText:SetText(CludesUI.L(conf.text or ""))

        -- Swatches build right-to-left from the right edge
        local swatches = conf.swatches or {}
        if conf.noCapture then
            widget._noCapture = true
        end
        local anchorX = -SIDE_PAD
        for i = #swatches, 1, -1 do
            local sc = swatches[i]
            local colorSwatch, updateSwatch =
                BuildColorSwatch(widget, widget:GetFrameLevel() + 2, sc.getValue, sc.setValue, sc.hasAlpha)
            Pix.Point(colorSwatch, "RIGHT", widget, "RIGHT", anchorX, 0)
            anchorX = anchorX - 24 - SWATCH_GAP

            if sc.disabled then
                local swatchBlock = CreateFrame("Frame", nil, colorSwatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                if sc.disabledTooltip then
                    swatchBlock:SetScript("OnEnter", function()
                        ShowWidgetTooltip(colorSwatch, sc.disabledTooltip)
                    end)
                    swatchBlock:SetScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                if sc.tooltip then -- normal tooltip while enabled
                    colorSwatch:HookScript("OnEnter", function()
                        ShowWidgetTooltip(colorSwatch, sc.tooltip)
                    end)
                    colorSwatch:HookScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                RegisterWidgetRefresh(function()
                    updateSwatch()
                    local offset = sc.disabled()
                    if offset then
                        colorSwatch:SetAlpha(0.3)
                        swatchBlock:Show()
                    else
                        colorSwatch:SetAlpha(1)
                        swatchBlock:Hide()
                    end
                end)
                local offset = sc.disabled()
                if offset then
                    colorSwatch:SetAlpha(0.3)
                    swatchBlock:Show()
                else
                    colorSwatch:SetAlpha(1)
                    swatchBlock:Hide()
                end
            else
                if sc.tooltip then
                    colorSwatch:HookScript("OnEnter", function()
                        ShowWidgetTooltip(colorSwatch, sc.tooltip)
                    end)
                    colorSwatch:HookScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                RegisterWidgetRefresh(function()
                    updateSwatch()
                end)
            end
        end

        -- Spec Overrides capture: the whole row is ONE setting, all swatches capture together (see DualRow BuildHalf).
        do
            local accs = {}
            for i = 1, #swatches do
                local sc = swatches[i]
                if sc.getValue and sc.setValue then
                    accs[#accs + 1] = {
                        type = "colorpicker",
                        text = sc.tooltip or conf.text,
                        hasAlpha = sc.hasAlpha,
                        getValue = sc.getValue,
                        setValue = sc.setValue,
                    }
                end
            end
            if #accs > 0 and not conf.noCapture then
                widget._captureCfg = { type = "multi", text = conf.text, accessors = accs }
            end
        end

        return widget, ROW_H
    end

    -- DropdownWithOffsets: dropdown left, X and Y mini-sliders side by side right.
    -- dropdownCfg: DualRow dropdown cfg (text, values, order, getValue, setValue,
    --              disabledValues, disabled).
    -- xSliderCfg / ySliderCfg: { text, min, max, step, getValue, setValue, disabled }
    function WidgetFactory:DropdownWithOffsets(hostFrame, yOffset, dropdownCfg, xSliderCfg, ySliderCfg)
        local ROW_H = 50
        local SIDE_PAD = 20
        local widget = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, totalW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        RowBg(widget, hostFrame)
        TagOptionRow(
            widget,
            hostFrame,
            (dropdownCfg and dropdownCfg.text or "")
                .. " "
                .. (xSliderCfg and xSliderCfg.text or "")
                .. " "
                .. (ySliderCfg and ySliderCfg.text or ""),
            nil,
            true
        )
        IndexSlotForSearch(hostFrame, dropdownCfg and dropdownCfg.text, dropdownCfg and dropdownCfg.tooltip)
        IndexSlotForSearch(hostFrame, xSliderCfg and xSliderCfg.text, xSliderCfg and xSliderCfg.tooltip)
        IndexSlotForSearch(hostFrame, ySliderCfg and ySliderCfg.text, ySliderCfg and ySliderCfg.tooltip)

        local halfW = math.floor(totalW / 2)

        -- Left half: label + dropdown (as in a DualRow dropdown half)
        local leftRegion = CreateFrame("Frame", nil, widget)
        leftRegion:SetSize(halfW, ROW_H)
        leftRegion:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, 0)

        local ddLabel = MakeFont(leftRegion, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        Pix.Point(ddLabel, "LEFT", leftRegion, "LEFT", SIDE_PAD, 0)
        ddLabel:SetText(CludesUI.L(dropdownCfg.text or ""))

        local DD_W = 170
        local ddBtn, ddLbl = BuildDropdownControl(
            leftRegion,
            DD_W,
            widget:GetFrameLevel() + 2,
            dropdownCfg.values,
            dropdownCfg.order,
            dropdownCfg.getValue,
            dropdownCfg.setValue,
            dropdownCfg.disabledValues
        )
        Pix.Point(ddBtn, "RIGHT", leftRegion, "RIGHT", -SIDE_PAD, 0)

        local function ApplyDDDisabled()
            if not dropdownCfg.disabled then
                return
            end
            local offset = dropdownCfg.disabled()
            ddLabel:SetAlpha(offset and 0.3 or 1)
            ddBtn:EnableMouse(not offset)
            ddBtn:SetAlpha(offset and 0.3 or 1)
        end

        -- Right half: X and Y mini-sliders on one line
        local rightRegion = CreateFrame("Frame", nil, widget)
        rightRegion:SetSize(halfW, ROW_H)
        rightRegion:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, 0)

        local MINI_TRACK_W = 120
        local MINI_VALBOX_W = 30
        local SLIDER_H = 24

        -- align: "LEFT" = label,track,valbox left-to-right; "RIGHT" = the reverse
        local function BuildMiniSlider(slCfg, align)
            local isLeft = (align == "LEFT")

            -- Axis label ("X" or "Y")
            local axisLabel = MakeFont(rightRegion, 12, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            axisLabel:SetAlpha(0.6)
            axisLabel:SetText(CludesUI.L(slCfg.text or ""))

            local trackFrame, valBox, _, slThumb = BuildSliderCore(
                rightRegion,
                MINI_TRACK_W,
                4,
                12,
                MINI_VALBOX_W,
                SLIDER_H,
                11,
                SL.INPUT_A,
                slCfg.min,
                slCfg.max,
                slCfg.step,
                slCfg.getValue,
                slCfg.setValue,
                true,
                slCfg.snapPoints,
                slCfg.valueSnap
            )

            if isLeft then
                Pix.Point(axisLabel, "LEFT", rightRegion, "LEFT", 4, 0)
                Pix.Point(trackFrame, "LEFT", axisLabel, "RIGHT", 6, 0)
                Pix.Point(valBox, "LEFT", trackFrame, "RIGHT", 6, 0)
            else
                Pix.Point(valBox, "RIGHT", rightRegion, "RIGHT", -4, 0)
                Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -6, 0)
                Pix.Point(axisLabel, "RIGHT", trackFrame, "LEFT", -6, 0)
            end

            RegisterWidgetRefresh(function()
                if slCfg.disabled then
                    local offset = slCfg.disabled()
                    axisLabel:SetAlpha(offset and 0.2 or 0.6)
                    trackFrame:SetAlpha(offset and 0.3 or 1)
                    valBox:EnableMouse(not offset)
                    valBox:SetAlpha(offset and 0.3 or 1)
                    if slThumb then
                        slThumb._sliderDisabled = offset
                    end
                end
            end)
            if slCfg.disabled then
                local offset = slCfg.disabled()
                axisLabel:SetAlpha(offset and 0.2 or 0.6)
                trackFrame:SetAlpha(offset and 0.3 or 1)
                valBox:EnableMouse(not offset)
                valBox:SetAlpha(offset and 0.3 or 1)
                if slThumb then
                    slThumb._sliderDisabled = offset
                end
            end
        end

        BuildMiniSlider(xSliderCfg, "LEFT")
        BuildMiniSlider(ySliderCfg, "RIGHT")

        -- 1px center divider between dropdown and sliders
        local div = widget:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
        div:SetWidth(1)
        div:SetPoint("TOP", widget, "TOP", 0, 0)
        div:SetPoint("BOTTOM", widget, "BOTTOM", 0, 0)

        RegisterWidgetRefresh(function()
            ddLbl:SetText(DDResolveLabel(dropdownCfg.values, dropdownCfg.order or {}, dropdownCfg.getValue()))
            ApplyDDDisabled()
        end)
        ApplyDDDisabled()

        -- Regions exposed for eye icon anchoring
        widget._leftRegion = leftRegion
        widget._rightRegion = rightRegion
        -- Slot-level search labels drive per-slot highlighting
        leftRegion._slotLabel = dropdownCfg and dropdownCfg.text or ""
        rightRegion._slotLabel = (xSliderCfg and xSliderCfg.text or "")
            .. " "
            .. (ySliderCfg and ySliderCfg.text or "")

        return widget, ROW_H
    end

    -- WideDualButton: two centered buttons side by side (each 100px narrower and 5px shorter than WideButton)
    function WidgetFactory:WideDualButton(hostFrame, text1, text2, yOffset, onClick1, onClick2, btnWidth)
        btnWidth = btnWidth or DUAL_ITEM_W
        local BTN_H = 37
        local ROW_H = BTN_H + 20
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(widget, hostFrame, (text1 or "") .. " " .. (text2 or ""), nil, true)
        IndexSlotForSearch(hostFrame, text1)
        IndexSlotForSearch(hostFrame, text2)
        local halfGap = DUAL_GAP / 2
        for i, details in ipairs({
            { text1, -(btnWidth / 2 + halfGap), onClick1 },
            { text2, (btnWidth / 2 + halfGap), onClick2 },
        }) do
            local btn = CreateFrame("Button", nil, widget)
            Pix.Size(btn, btnWidth, BTN_H)
            Pix.Point(btn, "CENTER", widget, "CENTER", details[2], 0)
            btn:SetFrameLevel(widget:GetFrameLevel() + 1)
            MakeStyledButton(btn, details[1], 14, WB_COLOURS, details[3])
        end
        return widget, ROW_H
    end

    -- WideTripleButton: three centered buttons side by side, for action rows. disabledOpts (optional): keyed by button index 1..3, e.g. { [3] = { disabled = true, tooltip = "why it's off" } }. A disabled button is dimmed, ignores hover highlight + clicks, and shows its tooltip on hover. Evaluated at build time (callers rebuild on RefreshPage).
    function WidgetFactory:WideTripleButton(
        hostFrame,
        text1,
        text2,
        text3,
        yOffset,
        onClick1,
        onClick2,
        onClick3,
        btnWidth,
        disabledOpts
    )
        btnWidth = btnWidth or 205
        local BTN_H = 37
        local ROW_H = BTN_H + 20
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(
            widget,
            hostFrame,
            (text1 or "") .. " " .. (text2 or "") .. " " .. (text3 or ""),
            nil,
            true
        )
        IndexSlotForSearch(hostFrame, text1)
        IndexSlotForSearch(hostFrame, text2)
        IndexSlotForSearch(hostFrame, text3)
        local gap = DUAL_GAP
        local offsets = { -(btnWidth + gap), 0, (btnWidth + gap) }
        for i, details in ipairs({ { text1, onClick1 }, { text2, onClick2 }, { text3, onClick3 } }) do
            local btn = CreateFrame("Button", nil, widget)
            Pix.Size(btn, btnWidth, BTN_H)
            Pix.Point(btn, "CENTER", widget, "CENTER", offsets[i], 0)
            btn:SetFrameLevel(widget:GetFrameLevel() + 1)
            MakeStyledButton(btn, details[1], 12, WB_COLOURS, details[2])
            local dopt = disabledOpts and disabledOpts[i]
            if dopt and dopt.disabled then
                btn:SetAlpha(0.4)
                btn:SetScript("OnEnter", function()
                    if dopt.tooltip then
                        ShowWidgetTooltip(btn, dopt.tooltip)
                    end
                end)
                btn:SetScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
                btn:SetScript("OnClick", nil)
            end
        end
        return widget, ROW_H
    end

    -- WideDropdown: centered, no row background, title above; prominent selectors.
    -- Its menu is built on the first click, as BuildDropdownControl's: a page
    -- build makes none.
    function WidgetFactory:WideDropdown(
        hostFrame,
        titleText,
        yOffset,
        values,
        getValue,
        setValue,
        sequence,
        btnWidth,
        disabledValuesFn
    )
        btnWidth = btnWidth or 450
        local BTN_H, TITLE_H, GAP = 38, 20, 12
        local ROW_H = TITLE_H + GAP + BTN_H + 5
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(widget, hostFrame, titleText)
        local titleLabel = MakeFont(
            widget,
            13,
            nil,
            CludesUI.TEXT_SECTION_R,
            CludesUI.TEXT_SECTION_G,
            CludesUI.TEXT_SECTION_B,
            CludesUI.TEXT_SECTION_A
        )
        Pix.Point(titleLabel, "TOP", widget, "TOP", 0, 0)
        titleLabel:SetText(CludesUI.L(titleText))
        local ddBtn = CreateFrame("Button", nil, widget)
        Pix.Size(ddBtn, btnWidth, BTN_H)
        Pix.Point(ddBtn, "TOP", titleLabel, "BOTTOM", 0, -GAP)
        ddBtn:SetFrameLevel(widget:GetFrameLevel() + 1)
        local backdrop = SolidTex(ddBtn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        backdrop:SetAllPoints()
        local brd = MakeRoundedBorder(ddBtn, 1, 1, 1, DD_BRD_A, backdrop)
        -- Resting alpha on the text colour, the channel the hover colours write.
        local ddLbl = MakeFont(ddBtn, 13, nil, 1, 1, 1, DD_TXT_A)
        ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 14, 0)
        local arrow = MakeDropdownArrow(ddBtn, 14, Pix)
        if not sequence then
            sequence = {}
            for key in pairs(values) do
                sequence[#sequence + 1] = key
            end
        end
        ddLbl:SetText(DDResolveLabel(values, sequence, getValue()))
        -- Light hover scripts until the first click builds the menu (the shared
        -- lazy dropdown wiring of BuildDropdownControl).
        WireLazyDropdown(ddBtn, ddLbl, backdrop, brd, WD_DD_COLOURS, function()
            local m, _, refresh = BuildDropdownMenu(
                ddBtn,
                btnWidth,
                sequence,
                values,
                getValue,
                setValue,
                ddLbl,
                "wide",
                disabledValuesFn
            )
            return m, refresh
        end)
        RegisterWidgetRefresh(function()
            ddLbl:SetText(DDResolveLabel(values, sequence, getValue()))
            if disabledValuesFn then
                -- A disabled current value rests greyed; _valueDimA keeps the
                -- hover colours on that alpha too.
                local dimA = disabledValuesFn(getValue()) and 0.15 or nil
                ddBtn._valueDimA = dimA
                ddLbl:SetTextColor(1, 1, 1, dimA or DD_TXT_A)
            end
        end)
        return widget, ROW_H
    end

    -- TripleDropdown: 3 normal-sized dropdowns side by side, centered, each with a small title above
    function WidgetFactory:TripleDropdown(hostFrame, configs, yOffset)
        local DD_W, DD_H, TITLE_H, GAP_Y = TRIPLE_ITEM_W, 30, 16, 6
        local ROW_H = TITLE_H + GAP_Y + DD_H + 12
        local widget = CreateFrame("Frame", nil, hostFrame)
        local frameW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, frameW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(
            widget,
            hostFrame,
            (configs[1] and configs[1][1] or "")
                .. " "
                .. (configs[2] and configs[2][1] or "")
                .. " "
                .. (configs[3] and configs[3][1] or ""),
            nil,
            true
        )
        IndexSlotForSearch(hostFrame, configs[1] and configs[1][1])
        IndexSlotForSearch(hostFrame, configs[2] and configs[2][1])
        IndexSlotForSearch(hostFrame, configs[3] and configs[3][1])
        local totalW = DD_W * 3 + TRIPLE_GAP * 2
        local startX = (frameW - totalW) / 2
        for position, conf in ipairs(configs) do
            local column = startX + (position - 1) * (DD_W + TRIPLE_GAP)
            local titleLbl = MakeFont(
                widget,
                11,
                nil,
                CludesUI.TEXT_SECTION_R,
                CludesUI.TEXT_SECTION_G,
                CludesUI.TEXT_SECTION_B,
                CludesUI.TEXT_SECTION_A
            )
            Pix.Point(titleLbl, "TOP", widget, "TOPLEFT", column + DD_W / 2, 0)
            titleLbl:SetText(CludesUI.L(conf.title))
            local ddBtn, ddLbl = BuildDropdownControl(
                widget,
                DD_W,
                widget:GetFrameLevel() + 1,
                conf.values,
                conf.order,
                conf.getValue,
                conf.setValue
            )
            Pix.Point(ddBtn, "TOPLEFT", widget, "TOPLEFT", column, -(TITLE_H + GAP_Y))
            RegisterWidgetRefresh(function()
                ddLbl:SetText(DDResolveLabel(conf.values, conf.order or {}, conf.getValue()))
            end)
        end
        return widget, ROW_H
    end

    -- TripleSlider: three mini-sliders side by side, mirroring TripleDropdown columns. configs = exactly 3 x { title (unused), minVal, maxVal, step, getValue, setValue }
    function WidgetFactory:TripleSlider(hostFrame, configs, yOffset)
        local SL_W, SL_H = TRIPLE_ITEM_W, 26
        local ROW_H = SL_H + 12
        local widget = CreateFrame("Frame", nil, hostFrame)
        local frameW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, frameW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        TagOptionRow(widget, hostFrame, "")
        local totalW = SL_W * 3 + TRIPLE_GAP * 2
        local startX = (frameW - totalW) / 2
        for position, conf in ipairs(configs) do
            local column = startX + (position - 1) * (SL_W + TRIPLE_GAP)
            local minVal = conf.minVal or 16
            local maxVal = conf.maxVal or 40
            local step = conf.step or 1
            local INPUT_W = 36
            local TRACK_W = SL_W - INPUT_W - 16
            local slRow = CreateFrame("Frame", nil, widget)
            Pix.Size(slRow, SL_W, SL_H)
            Pix.Point(slRow, "TOPLEFT", widget, "TOPLEFT", column, -((ROW_H - SL_H) / 2))
            slRow:SetFrameLevel(widget:GetFrameLevel() + 1)
            local trackFrame, valBox = BuildSliderCore(
                slRow,
                TRACK_W,
                4,
                12,
                INPUT_W,
                22,
                12,
                SL.INPUT_A,
                minVal,
                maxVal,
                step,
                conf.getValue,
                conf.setValue,
                true
            )
            Pix.Point(valBox, "RIGHT", slRow, "RIGHT", 0, 0)
            Pix.Point(trackFrame, "LEFT", slRow, "LEFT", 4, 0)
        end
        return widget, ROW_H
    end

    -- Spacer
    function WidgetFactory:Spacer(hostFrame, yOffset, height)
        height = height or 16
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth(), height)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", 0, yOffset)
        widget._isSpacer = true
        return widget, height
    end
end -- end deferred init
