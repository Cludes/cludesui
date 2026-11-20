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

    -- A row slider dims (label, track and value box) and stops taking input
    -- while conf.disabled() holds: applied now and on every widget refresh.
    local function TrackSliderDisabled(rowConf, labelText, trackFrame, valBox, slThumb)
        local function Apply()
            if not rowConf.disabled then
                return
            end
            local off = rowConf.disabled()
            local alpha = off and 0.3 or 1
            labelText:SetAlpha(alpha)
            trackFrame:SetAlpha(alpha)
            valBox:EnableMouse(not off)
            valBox:SetAlpha(alpha)
            if slThumb then
                slThumb._sliderDisabled = off
            end
        end
        RegisterWidgetRefresh(Apply)
        Apply()
    end

    -- A colour swatch's own tooltip (sc.tooltip, read on each hover), added to
    -- whatever hover it already has.
    local function HookSwatchTooltip(swatch, sc)
        swatch:HookScript("OnEnter", function()
            ShowWidgetTooltip(swatch, sc.tooltip)
        end)
        swatch:HookScript("OnLeave", function()
            HideWidgetTooltip()
        end)
    end

    -- A row label's tooltip: a frame a little larger than the label that, on
    -- hover, shows the disabled reason while conf.disabled() holds (and then
    -- also swallows clicks over the label), else conf.tooltip, else the full
    -- text of a label cut short. Clicks pass through while enabled. With a
    -- dropdown (ddBtn), nothing but the disabled reason shows while its menu
    -- is open.
    local function AddLabelTooltipHit(regionFrame, labelText, rowConf, dropdownBtn)
        local function MenuOpen()
            return dropdownBtn and dropdownBtn._ddMenu and dropdownBtn._ddMenu:IsShown()
        end
        local ttOpts = rowConf.tooltipOpts
        local hit = CreateFrame("Frame", nil, regionFrame)
        hit:SetPoint("TOPLEFT", labelText, "TOPLEFT", -5, 5)
        hit:SetPoint("BOTTOMRIGHT", labelText, "BOTTOMRIGHT", 5, -5)
        hit:SetFrameLevel(regionFrame:GetFrameLevel() + 10)
        hit:SetScript("OnEnter", function()
            if rowConf.disabled and rowConf.disabled() and rowConf.disabledTooltip then
                local reason = ResolveDisabledTip(rowConf)
                if reason then
                    ShowWidgetTooltip(labelText, reason)
                end
            elseif rowConf.tooltip and not MenuOpen() then
                ShowWidgetTooltip(labelText, LabelTooltipText(regionFrame, labelText, rowConf.tooltip), ttOpts)
            elseif regionFrame._labelTruncated and not MenuOpen() then
                ShowWidgetTooltip(labelText, labelText:GetText())
            end
        end)
        hit:SetScript("OnLeave", function()
            HideWidgetTooltip()
        end)
        hit:SetMouseClickEnabled(false)
        if rowConf.disabled and rowConf.disabledTooltip then
            local function BlockWhileDisabled()
                hit:SetMouseClickEnabled(rowConf.disabled() and true or false)
            end
            RegisterWidgetRefresh(BlockWhileDisabled)
            BlockWhileDisabled()
        end
    end
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
    local function AttachSliderTooltip(regionFrame, labelText, rowConf, trackFrame, thumb, valBox)
        local own = type(rowConf.tooltipOnControl) == "string" and rowConf.tooltipOnControl
        if not (own or (rowConf.tooltip and rowConf.tooltipOnControl)) then
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
            if CludesUI._sliderDragging or (rowConf.disabled and rowConf.disabled()) then
                return
            end
            ShowWidgetTooltip(
                hit,
                own or LabelTooltipText(regionFrame, labelText, rowConf.tooltip),
                rowConf.tooltipOpts
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
        local button = CreateFrame("Button", nil, widget)
        Pix.Size(button, 200, 32)
        Pix.Point(button, "LEFT", widget, "LEFT", 20, 0)
        button:SetFrameLevel(widget:GetFrameLevel() + 1)
        MakeStyledButton(button, textValue, 13, RB_COLOURS, onClick)
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
        local button = CreateFrame("Button", nil, widget)
        Pix.Size(button, btnWidth, BTN_H)
        Pix.Point(button, "CENTER", widget, "CENTER", 0, 0)
        button:SetFrameLevel(widget:GetFrameLevel() + 1)
        MakeStyledButton(button, textValue, 14, WB_COLOURS, onClick)
        return widget, ROW_H
    end

    -- Spec Overrides capture: append an extra accessor to a region/row's capture config so inline extras (swatches, cog fields, inline toggles) built outside the factory capture TOGETHER with the slot's main setting as one override. acc = { type, text, getValue, setValue, step/values/order/hasAlpha }.
    function CludesUI.AddCaptureAccessor(regionFrame, acc)
        if not (regionFrame and acc and acc.getValue and acc.setValue) then
            return
        end
        local classColor = regionFrame._captureCfg
        -- Dedupe by getValue identity: factory paths stash some controls themselves (colorpicker halves, multiSwatch rows) and BuildColorSwatch self-registers, so the same accessor must never join twice.
        if classColor then
            if classColor.getValue == acc.getValue then
                return
            end
            if classColor.accessors then
                for _, a in ipairs(classColor.accessors) do
                    if a.getValue == acc.getValue then
                        return
                    end
                end
            end
        end
        if not classColor then
            regionFrame._captureCfg = { type = "multi", text = acc.text, accessors = { acc } }
        elseif classColor.accessors then
            classColor.accessors[#classColor.accessors + 1] = acc
        else
            -- Promote a single-accessor widget cfg to a grouped slot cfg.
            regionFrame._captureCfg = { type = "multi", text = classColor.text, accessors = { classColor, acc } }
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
        local button = CreateFrame("Button", nil, hostFrame)
        local pp = options.pp or Pix
        pp.Size(button, options.w, options.h)
        button:SetFrameLevel(hostFrame:GetFrameLevel() + (options.level or 2))
        if options.mouse then
            button:RegisterForClicks("AnyUp")
        else
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
        local backdrop = SolidTex(button, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        backdrop:SetAllPoints()
        button._border = MakeRoundedBorder(button, 1, 1, 1, DD_BRD_A, backdrop)
        local labelFS = MakeFont(button, options.font or 12, nil, 1, 1, 1)
        labelFS:SetAlpha(DD_TXT_A)
        labelFS:SetPoint("CENTER")

        local disabled = options.disabled
        local listening = false
        -- Controller buttons: padArmed while they are captured; padHeld is the button
        -- whose press ended capture, kept captured until its release.
        local padArmed, padWired, padHeld = false, false, nil
        local function StopListening()
            listening = false
            button:EnableKeyboard(false)
            if padArmed and not padHeld then
                padArmed = false
                button:EnableGamePadButton(false)
            end
            -- OnLeave keeps the hover look while armed; drop it once capture ends.
            if not button:IsMouseOver() then
                backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
                button._border:SetColor(1, 1, 1, DD_BRD_A)
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
        local function SyncRowState()
            if disabled then
                local off = disabled()
                -- Mouse stays on so the disabled tooltip can show; OnClick refuses.
                button:SetAlpha(off and 0.3 or 1)
                if hostFrame._label then
                    hostFrame._label:SetAlpha(off and 0.3 or 1)
                end
                if off and listening then
                    StopListening()
                end
            end
            if not listening then
                labelFS:SetText(FormatKey(options.get()))
            end
        end
        local function Commit(chord)
            StopListening()
            local gen = PoolGen(button)
            options.set(chord)
            -- A setter that rebuilt the page dressed this button again (page
            -- reuse): that dress painted itself, so this one paints nothing more.
            if PoolGen(button) ~= gen then
                return
            end
            SyncRowState()
        end

        button:SetScript("OnClick", function(self, btnFrame)
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
                            StopListening()
                            SyncRowState()
                            return
                        end
                        local keyName = GetConvertedKeyOrButton(key)
                        if
                            IsKeyPressIgnoredForBinding(keyName)
                            or keyName == GetCVar("GamePadEmulateShift")
                            or keyName == GetCVar("GamePadEmulateCtrl")
                            or keyName == GetCVar("GamePadEmulateAlt")
                        then
                            s:SetPropagateKeyboardInput(true)
                            return
                        end
                        s:SetPropagateKeyboardInput(false)
                        padHeld = key
                        Commit(CreateKeyChordStringUsingMetaKeyState(keyName))
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
        button:SetScript("OnKeyDown", function(self, key)
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
                StopListening()
                SyncRowState()
                return
            end
            Commit(CreateKeyChordStringUsingMetaKeyState(key))
        end)
        button:SetScript("OnEnter", function(self)
            if disabled and disabled() then
                local tipText = options.disabledTip
                if type(tipText) == "function" then
                    tipText = tipText()
                end
                ShowWidgetTooltip(self, DisabledTooltip(tipText))
                return
            end
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA)
            button._border:SetColor(1, 1, 1, 0.3)
            ShowWidgetTooltip(
                self,
                options.tooltip or CludesUI.L("Left-click to set a keybind.\nRight-click to unbind.")
            )
        end)
        button:SetScript("OnLeave", function()
            HideWidgetTooltip()
            if listening then
                return
            end
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
            button._border:SetColor(1, 1, 1, DD_BRD_A)
        end)
        button:SetScript("OnHide", function()
            if listening then
                StopListening()
                SyncRowState()
            end
            -- A hidden button gets no release: drop a controller press still held.
            if padHeld then
                padHeld = nil
                padArmed = false
                button:EnableGamePadButton(false)
            end
            -- Hidden is never hovered: always come back in the resting look.
            backdrop:SetColorTexture(DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
            button._border:SetColor(1, 1, 1, DD_BRD_A)
            HideWidgetTooltip()
        end)

        SyncRowState()
        return button, SyncRowState
    end

    -- DualRow: two widgets side by side on one full-width row, 1px center divider.
    -- Slider:      { type="slider", text, min, max, step, getValue, setValue }
    -- Dropdown:    { type="dropdown", text, values, getValue, setValue, order }
    -- Toggle:      { type="toggle", text, getValue, setValue }
    -- ColorPicker: { type="colorpicker", text, getValue, setValue, hasAlpha }
    -- A row's hint: the first sentence of its tooltip, shown in small dim text under
    -- the setting's name (the whole tooltip still shows on hover). nil when the
    -- tooltip is not plain text or has nothing to show.
    -- A toggle row answers a click anywhere on its name or the space before
    -- the switch, not only on the switch itself. Clicks only: the name's
    -- tooltip still shows on hover (its hover frame lets clicks through), and
    -- the cogs and swatches beside a name sit above this and keep their own
    -- clicks. A switch that is disabled (its mouse off) ignores it too.
    local function ClickRowToToggle(regionFrame, toggle)
        local catcher = CreateFrame("Button", nil, regionFrame)
        catcher:SetPoint("TOPLEFT", regionFrame, "TOPLEFT")
        catcher:SetPoint("BOTTOM", regionFrame, "BOTTOM")
        catcher:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
        catcher:SetFrameLevel(regionFrame:GetFrameLevel() + 1)
        catcher:SetMouseMotionEnabled(false)
        catcher:RegisterForClicks("LeftButtonUp")
        catcher:SetScript("OnClick", function()
            if not toggle:IsMouseEnabled() then
                return
            end
            local click = toggle:GetScript("OnClick")
            if click then
                click(toggle, "LeftButton")
            end
        end)
    end

    local function RowHintText(tipText)
        if type(tipText) ~= "string" then
            return nil
        end
        local text = CludesUI.L(tipText):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
        text = text:match("^[^\n]+") or ""
        text = (text:match("^(.-[%.%!%?])%s") or text):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            return nil
        end
        return text
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

        local function BuildHalf(regionFrame, rowConf)
            if not rowConf then
                return
            end
            local t = rowConf.type
            -- Spec Overrides capture: expose the widget config so the capture overlay can identify settings. A slot is ONE setting: multiSwatch slots capture all their swatches together, inline extras join via AddCaptureAccessor. cfg.noCapture opts a widget out (used by the Spec Overrides page's own mirrored editors).
            if rowConf.noCapture then
                regionFrame._captureCfg = nil
                regionFrame._noCapture = true
            elseif t == "segmented" and rowConf.getValue and rowConf.setValue then
                regionFrame._captureCfg = {
                    type = "dropdown",
                    text = rowConf.text,
                    values = rowConf.values,
                    order = rowConf.order,
                    getValue = rowConf.getValue,
                    setValue = rowConf.setValue,
                }
            elseif rowConf.getValue and rowConf.setValue then
                regionFrame._captureCfg = rowConf
            elseif t == "multiSwatch" and rowConf.swatches then
                local accs = {}
                for i = 1, #rowConf.swatches do
                    local sc = rowConf.swatches[i]
                    if sc.getValue and sc.setValue then
                        accs[#accs + 1] = {
                            type = "colorpicker",
                            text = sc.tooltip or rowConf.text,
                            hasAlpha = sc.hasAlpha,
                            getValue = sc.getValue,
                            setValue = sc.setValue,
                        }
                    end
                end
                if #accs > 0 then
                    regionFrame._captureCfg = { type = "multi", text = rowConf.text, accessors = accs }
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
            labelText:SetText(CludesUI.L(rowConf.text or ""))
            regionFrame._label = labelText
            regionFrame._cfg = rowConf
            regionFrame._labelHasHit = (rowConf.tooltip or rowConf.disabledTooltip) and true or false

            -- Hint line under the name (RowHintText). The name moves up to make room;
            -- the label clamp sizes the hint to stop short of the control.
            local hintText = t ~= "button" and RowHintText(rowConf.tooltip)
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
            if (rowConf.tooltip or rowConf.disabledTooltip) and t ~= "dropdown" and t ~= "button" then
                AddLabelTooltipHit(regionFrame, labelText, rowConf)
            end

            -- cfg.disabled: optional fn returning bool; when true the label dims and the control goes non-interactive.
            local disabledOverlay -- optional dark overlay to gray out the whole half
            local controlFrame -- the clickable control (dropdown btn, toggle, etc.)
            local controlAnchor -- main control frame for inline element anchoring

            local function SyncDisabled()
                if not rowConf.disabled then
                    return
                end
                local off = rowConf.disabled()
                labelText:SetAlpha(off and 0.3 or 1)
                if regionFrame._hint then
                    regionFrame._hint:SetAlpha(off and 0.3 or 0.85)
                end
                if controlFrame then
                    if off then
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
                local scfg = PixelizeSliderCfg(rowConf)
                local trackFrame, valBox, _, slThumb = BuildSliderCore(
                    regionFrame,
                    rowConf.trackWidth or defaultTrackW,
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
                    rowConf.snapPoints,
                    rowConf.valueSnap
                )
                Pix.Point(valBox, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
                controlFrame = nil -- slider owns its disabled state; keep the generic handler off its mouse
                AddControlDisabledTooltip(trackFrame, rowConf)
                TrackSliderDisabled(rowConf, labelText, trackFrame, valBox, slThumb)
                AttachSliderTooltip(regionFrame, labelText, rowConf, trackFrame, slThumb, valBox)
                controlAnchor = trackFrame
            elseif t == "segmented" then
                -- A choice of two or three, as a row of square buttons: the same
                -- cfg as a dropdown (values = { key = "Label" }, order, getValue,
                -- setValue, disabled, tooltip), every option in view at once.
                -- Opt-in per row: a dropdown with many or long options stays one.
                local function Pick(key)
                    if rowConf.disabled and rowConf.disabled() then
                        return
                    end
                    if rowConf.getValue() == key then
                        return
                    end
                    -- Spec Overrides capture and the changed flag, as the other controls report a write.
                    local snap = CludesUI._SOAttribution(regionFrame)
                    rowConf.setValue(key)
                    CludesUI._NotifySettingWrite(regionFrame, snap)
                    CludesUI._settingsChanged = true
                end
                local segFrame, _, segRefresh = CludesUI.BuildSegmentedControl({
                    parent = regionFrame,
                    square = true,
                    autoWidth = true,
                    height = 26,
                    keys = rowConf.order,
                    labels = rowConf.values,
                    getChecked = function(key)
                        return rowConf.getValue() == key
                    end,
                    isDisabled = rowConf.disabled and function()
                        return rowConf.disabled() and true or false
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
                AddControlDisabledTooltip(segFrame, rowConf)
                RegisterWidgetRefresh(function()
                    if segRefresh then
                        segRefresh()
                    end
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "dropdown" then
                local DD_W = rowConf.dropdownWidth or 170
                -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
                local ddDisabledFn = rowConf.disabledValues
                if not ddDisabledFn and rowConf.itemDisabled then
                    ddDisabledFn = function(val)
                        if rowConf.itemDisabled(val) then
                            if rowConf.itemDisabledTooltip then
                                local tipText = rowConf.itemDisabledTooltip(val)
                                -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                                -- for a bare requirement noun (nil = "enabled", as before).
                                if tipText then
                                    return DisabledTooltip(tipText, rowConf.itemRequireState)
                                end
                            end
                            return true
                        end
                        return false
                    end
                end
                local dropdownBtn, dropCaption = BuildDropdownControl(
                    regionFrame,
                    DD_W,
                    widget:GetFrameLevel() + 2,
                    rowConf.values,
                    rowConf.order,
                    rowConf.getValue,
                    rowConf.setValue,
                    ddDisabledFn
                )
                Pix.Point(dropdownBtn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = dropdownBtn
                controlAnchor = dropdownBtn
                if rowConf.labelOnlyDisabled then
                    AddControlDisabledTooltip(labelText, rowConf)
                else
                    AddControlDisabledTooltip(dropdownBtn, rowConf)
                end
                -- Tooltip config on the button: WireDropdownScripts and the pre-menu hover scripts read ddBtn._ttText/_ttOpts.
                if rowConf.tooltip or (rowConf.disabledTooltip and rowConf.disabled) then
                    if rowConf.tooltip then
                        dropdownBtn._ttText = rowConf.tooltip
                        dropdownBtn._ttOpts = rowConf.tooltipOpts
                    end
                    AddLabelTooltipHit(regionFrame, labelText, rowConf, dropdownBtn)
                end
                if rowConf.labelOnlyDisabled and rowConf.disabled then
                    local function PaintLabelOnly()
                        local off = rowConf.disabled()
                        labelText:SetAlpha(1)
                    end
                    RegisterWidgetRefresh(function()
                        dropCaption:SetText(DDResolveLabel(rowConf.values, rowConf.order or {}, rowConf.getValue()))
                        PaintLabelOnly()
                    end)
                    PaintLabelOnly()
                else
                    RegisterWidgetRefresh(function()
                        dropCaption:SetText(DDResolveLabel(rowConf.values, rowConf.order or {}, rowConf.getValue()))
                        SyncDisabled()
                    end)
                    SyncDisabled()
                end
            elseif t == "toggle" then
                local toggle, _, tgSnap =
                    BuildToggleControl(regionFrame, widget:GetFrameLevel() + 2, rowConf.getValue, rowConf.setValue)
                toggle:SetPoint("RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                ClickRowToToggle(regionFrame, toggle)
                controlFrame = toggle
                controlAnchor = toggle
                AddControlDisabledTooltip(toggle, rowConf)
                RegisterWidgetRefresh(function()
                    tgSnap()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "colorpicker" then
                local colorSwatch, _updateSwatch = BuildColorSwatch(
                    regionFrame,
                    widget:GetFrameLevel() + 2,
                    rowConf.getValue,
                    rowConf.setValue,
                    rowConf.hasAlpha
                )
                Pix.Point(colorSwatch, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = colorSwatch
                controlAnchor = colorSwatch
                AddControlDisabledTooltip(colorSwatch, rowConf)
                RegisterWidgetRefresh(function()
                    _updateSwatch()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "button" then
                -- Half-row button: label hidden, the button IS the content
                labelText:Hide()
                local button = CreateFrame("Button", nil, regionFrame)
                Pix.Size(button, rowConf.width or 180, 32)
                Pix.Point(button, "CENTER", regionFrame, "CENTER", 0, 0)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(button, rowConf.text or "", 13, RB_COLOURS, rowConf.onClick)
                controlFrame = button
                controlAnchor = button
                AddControlDisabledTooltip(button, rowConf)
                RegisterWidgetRefresh(function()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "labeledButton" then
                -- Standard left label, button anchored right
                local button = CreateFrame("Button", nil, regionFrame)
                Pix.Size(button, rowConf.width or 180, 32)
                Pix.Point(button, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(button, rowConf.buttonText or rowConf.text or "", 13, RB_COLOURS, rowConf.onClick)
                controlFrame = button
                controlAnchor = button
                AddControlDisabledTooltip(button, rowConf)
                RegisterWidgetRefresh(function()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "multiSwatch" then
                -- Label + N swatches laid out right-to-left from the right edge
                local SWATCH_SZ = 24
                local SWATCH_GAP = 8
                local swatches = rowConf.swatches or {}
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
                        if rowConf.disabled and rowConf.disabled() then
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
                    if rowConf.disabled or sc.disabled then
                        local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
                        swatchBlock:SetScript("OnEnter", function()
                            local source = (sc.disabledTooltip ~= nil) and sc or rowConf
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
                        HookSwatchTooltip(colorSwatch, sc)
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
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "input" then
                -- Free-text entry box, right-anchored. getValue returns the display
                -- string; setValue receives raw text and parses/validates it. Commits
                -- on Enter and focus loss; Escape reverts.
                -- cfg.inputStyle == "popup" restyles it like the ShowInputPopup field
                -- (near-black fill, subtle border, left-justified) and supports
                -- cfg.placeholder ghost text while empty.
                local isPopupStyle = rowConf.inputStyle == "popup"
                local boxW = rowConf.inputWidth or 64
                local boxFrame = CreateFrame("EditBox", nil, regionFrame)
                boxFrame:SetSize(boxW, isPopupStyle and 28 or 22)
                Pix.Point(boxFrame, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                boxFrame:SetAutoFocus(false)
                boxFrame:SetTextColor(1, 1, 1, 0.9)
                local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                if isPopupStyle then
                    -- cfg.inputJustify == "CENTER" centers the text and placeholder (default left).
                    local centered = rowConf.inputJustify == "CENTER"
                    boxFrame:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                    boxFrame:SetJustifyH(centered and "CENTER" or "LEFT")
                    boxFrame:SetTextInsets(10, 10, 0, 0)
                    boxBg:SetColorTexture(0, 0, 0, 0.5)
                    MakeRoundedBorder(boxFrame, 1, 1, 1, 0.2, boxBg)
                    if rowConf.placeholder then
                        local ph = boxFrame:CreateFontString(nil, "ARTWORK")
                        ph:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                        ph:SetTextColor(0.7, 0.7, 0.7, 0.45)
                        if centered then
                            ph:SetPoint("CENTER", boxFrame, "CENTER", 0, 0)
                        else
                            ph:SetPoint("LEFT", boxFrame, "LEFT", 10, 0)
                        end
                        ph:SetText(CludesUI.L(rowConf.placeholder))
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
                local function SyncInputText()
                    if boxFrame:HasFocus() then
                        return
                    end
                    boxFrame:SetText((rowConf.getValue and rowConf.getValue()) or "")
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
                    if rowConf.setValue then
                        rowConf.setValue(boxFrame:GetText())
                    end
                    if PoolGen(boxFrame) == gen then
                        SyncInputText()
                    end
                    committing = false
                end
                boxFrame:SetScript("OnEnterPressed", CommitInput)
                boxFrame:SetScript("OnEditFocusLost", CommitInput)
                boxFrame:SetScript("OnEscapePressed", function(self)
                    local gen = PoolGen(self)
                    self:ClearFocus()
                    if PoolGen(self) == gen then
                        SyncInputText()
                    end
                end)
                SyncInputText()
                controlFrame = boxFrame
                controlAnchor = boxFrame
                AddControlDisabledTooltip(boxFrame, rowConf)
                RegisterWidgetRefresh(function()
                    SyncInputText()
                    SyncDisabled()
                end)
                SyncDisabled()
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

        local function BuildThird(regionFrame, rowConf)
            if not rowConf then
                return
            end
            local t = rowConf.type
            -- Spec Overrides capture: see DualRow BuildHalf.
            if rowConf.noCapture then
                regionFrame._noCapture = true
            elseif rowConf.getValue and rowConf.setValue then
                regionFrame._captureCfg = rowConf
            end
            local labelText = MakeFont(regionFrame, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
            Pix.Point(labelText, "LEFT", regionFrame, "LEFT", SIDE_PAD, 0)
            labelText:SetJustifyH("LEFT")
            labelText:SetWordWrap(false)
            labelText:SetMaxLines(1)
            labelText:SetText(CludesUI.L(rowConf.text or ""))
            regionFrame._label = labelText
            regionFrame._cfg = rowConf
            regionFrame._labelHasHit = (rowConf.tooltip or rowConf.disabledTooltip) and true or false

            if (rowConf.tooltip or rowConf.disabledTooltip) and t ~= "dropdown" then
                AddLabelTooltipHit(regionFrame, labelText, rowConf)
            end

            local controlFrame, controlAnchor
            local function SyncDisabled()
                if not rowConf.disabled then
                    return
                end
                local off = rowConf.disabled()
                labelText:SetAlpha(off and 0.3 or 1)
                if controlFrame then
                    if off then
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
                local scfg = PixelizeSliderCfg(rowConf)
                local trackFrame, valBox, _, slThumb = BuildSliderCore(
                    regionFrame,
                    rowConf.trackWidth or defaultTrackW,
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
                    rowConf.snapPoints,
                    rowConf.valueSnap
                )
                Pix.Point(valBox, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)
                TrackSliderDisabled(rowConf, labelText, trackFrame, valBox, slThumb)
                AttachSliderTooltip(regionFrame, labelText, rowConf, trackFrame, slThumb, valBox)
                controlAnchor = trackFrame
            elseif t == "dropdown" then
                local DD_W = rowConf.dropdownWidth or 170
                -- Bridge itemDisabled/itemDisabledTooltip into disabledValuesFn
                local ddDisabledFn = rowConf.disabledValues
                if not ddDisabledFn and rowConf.itemDisabled then
                    ddDisabledFn = function(val)
                        if rowConf.itemDisabled(val) then
                            if rowConf.itemDisabledTooltip then
                                local tipText = rowConf.itemDisabledTooltip(val)
                                -- cfg.itemRequireState: "disabled" flips the wrapper's verb
                                -- for a bare requirement noun (nil = "enabled", as before).
                                if tipText then
                                    return DisabledTooltip(tipText, rowConf.itemRequireState)
                                end
                            end
                            return true
                        end
                        return false
                    end
                end
                local dropdownBtn, dropCaption = BuildDropdownControl(
                    regionFrame,
                    DD_W,
                    widget:GetFrameLevel() + 2,
                    rowConf.values,
                    rowConf.order,
                    rowConf.getValue,
                    rowConf.setValue,
                    ddDisabledFn
                )
                Pix.Point(dropdownBtn, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = dropdownBtn
                if rowConf.labelOnlyDisabled then
                    AddControlDisabledTooltip(labelText, rowConf)
                else
                    AddControlDisabledTooltip(dropdownBtn, rowConf)
                end
                if rowConf.tooltip or (rowConf.disabledTooltip and rowConf.disabled) then
                    if rowConf.tooltip then
                        dropdownBtn._ttText = rowConf.tooltip
                        dropdownBtn._ttOpts = rowConf.tooltipOpts
                    end
                    AddLabelTooltipHit(regionFrame, labelText, rowConf, dropdownBtn)
                end
                if rowConf.labelOnlyDisabled and rowConf.disabled then
                    local function PaintLabelOnly()
                        local off = rowConf.disabled()
                        labelText:SetAlpha(1)
                        -- Gray the button label when the current value is disabled,
                        -- through the text colour's alpha (the label's resting alpha);
                        -- _valueDimA keeps the hover colours on that alpha too.
                        if rowConf.disabledValues then
                            local curVal = rowConf.getValue()
                            local dimA = rowConf.disabledValues(curVal) and 0.15 or nil
                            dropdownBtn._valueDimA = dimA
                            dropCaption:SetTextColor(1, 1, 1, dimA or DD_TXT_A)
                        end
                    end
                    RegisterWidgetRefresh(function()
                        dropCaption:SetText(DDResolveLabel(rowConf.values, rowConf.order or {}, rowConf.getValue()))
                        PaintLabelOnly()
                        if dropdownBtn._ddRefresh then
                            dropdownBtn._ddRefresh()
                        end
                    end)
                    PaintLabelOnly()
                else
                    RegisterWidgetRefresh(function()
                        dropCaption:SetText(DDResolveLabel(rowConf.values, rowConf.order or {}, rowConf.getValue()))
                        SyncDisabled()
                        if dropdownBtn._ddRefresh then
                            dropdownBtn._ddRefresh()
                        end
                    end)
                    SyncDisabled()
                end
            elseif t == "toggle" then
                local toggle, _, tgSnap =
                    BuildToggleControl(regionFrame, widget:GetFrameLevel() + 2, rowConf.getValue, rowConf.setValue)
                toggle:SetPoint("RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                ClickRowToToggle(regionFrame, toggle)
                controlFrame = toggle
                AddControlDisabledTooltip(toggle, rowConf)
                RegisterWidgetRefresh(function()
                    tgSnap()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "colorpicker" then
                local colorSwatch, _updateSwatch = BuildColorSwatch(
                    regionFrame,
                    widget:GetFrameLevel() + 2,
                    rowConf.getValue,
                    rowConf.setValue,
                    rowConf.hasAlpha
                )
                Pix.Point(colorSwatch, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                controlFrame = colorSwatch
                RegisterWidgetRefresh(function()
                    _updateSwatch()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "checkbox" then
                -- Generic label hidden: the checkbox draws its own label + box
                labelText:Hide()
                local button = CreateFrame("Button", nil, regionFrame)
                button:SetSize(regionFrame:GetWidth(), ROW_H)
                button:SetAllPoints(regionFrame)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)

                local boxFrame, check, boxBorder, cbApply = BuildCheckboxControl(button, widget:GetFrameLevel() + 2)
                boxFrame:SetPoint("LEFT", button, "LEFT", SIDE_PAD, 0)

                local cbLabel = MakeFont(button, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
                cbLabel:SetPoint("LEFT", boxFrame, "RIGHT", 10, 0)
                cbLabel:SetText(CludesUI.L(rowConf.text or ""))

                local isHovering = false
                local function PaintCheckbox()
                    local enabled = rowConf.getValue()
                    cbApply(enabled, isHovering)
                    if enabled then
                        cbLabel:SetTextColor(TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B, 1)
                    else
                        local a = isHovering and 1 or 0.8
                        cbLabel:SetTextColor(TEXT_WHITE_R * a, TEXT_WHITE_G * a, TEXT_WHITE_B * a, a)
                    end
                end
                PaintCheckbox()

                button:SetScript("OnClick", function()
                    local gen = PoolGen(button)
                    local val = not rowConf.getValue()
                    rowConf.setValue(val)
                    CludesUI._settingsChanged = true
                    -- A setter that rebuilt the page dressed this checkbox again
                    -- (page reuse): that dress painted itself.
                    if PoolGen(button) ~= gen then
                        return
                    end
                    PaintCheckbox()
                end)
                button:SetScript("OnEnter", function()
                    isHovering = true
                    PaintCheckbox()
                end)
                button:SetScript("OnLeave", function()
                    isHovering = false
                    PaintCheckbox()
                end)

                controlFrame = button
                RegisterWidgetRefresh(function()
                    PaintCheckbox()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "button" then
                labelText:Hide()
                local button = CreateFrame("Button", nil, regionFrame)
                Pix.Size(button, rowConf.width or 140, 32)
                Pix.Point(button, "CENTER", regionFrame, "CENTER", 0, 0)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(button, rowConf.text or "", 13, RB_COLOURS, rowConf.onClick)
                controlFrame = button
                RegisterWidgetRefresh(function()
                    SyncDisabled()
                end)
                SyncDisabled()
            elseif t == "labeledButton" then
                local button = CreateFrame("Button", nil, regionFrame)
                Pix.Size(button, rowConf.width or 140, 32)
                Pix.Point(button, "RIGHT", regionFrame, "RIGHT", -SIDE_PAD, 0)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)
                MakeStyledButton(button, rowConf.buttonText or rowConf.text or "", 13, RB_COLOURS, rowConf.onClick)
                controlFrame = button
                RegisterWidgetRefresh(function()
                    SyncDisabled()
                end)
                SyncDisabled()
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
        for _, region in ipairs({ leftRegion, midRegion }) do
            local div = widget:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.06)
            if div.SetSnapToPixelGrid then
                div:SetSnapToPixelGrid(false)
                div:SetTexelSnappingBias(0)
            end
            div:SetWidth(1)
            Pix.Point(div, "TOP", region, "TOPRIGHT", 0, 0)
            Pix.Point(div, "BOTTOM", region, "BOTTOMRIGHT", 0, 0)
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
    function WidgetFactory:MultiSwatchRow(hostFrame, yOffset, rowConf)
        local ROW_H = 50
        local SIDE_PAD = 20
        local SWATCH_GAP = 8
        local widget = CreateFrame("Frame", nil, hostFrame)
        local totalW = hostFrame:GetWidth() - CONTENT_PAD * 2
        Pix.Size(widget, totalW, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        widget._skipRowDivider = true
        RowBg(widget, hostFrame)
        TagOptionRow(widget, hostFrame, rowConf.text or "")

        local labelText = MakeFont(widget, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        Pix.Point(labelText, "LEFT", widget, "LEFT", SIDE_PAD, 0)
        labelText:SetText(CludesUI.L(rowConf.text or ""))

        -- Swatches build right-to-left from the right edge
        local swatches = rowConf.swatches or {}
        if rowConf.noCapture then
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
                local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
                if sc.disabledTooltip then
                    swatchBlock:SetScript("OnEnter", function()
                        ShowWidgetTooltip(colorSwatch, sc.disabledTooltip)
                    end)
                    swatchBlock:SetScript("OnLeave", function()
                        HideWidgetTooltip()
                    end)
                end
                if sc.tooltip then -- normal tooltip while enabled
                    HookSwatchTooltip(colorSwatch, sc)
                end
                RegisterWidgetRefresh(function()
                    updateSwatch()
                    local off = sc.disabled()
                    if off then
                        colorSwatch:SetAlpha(0.3)
                        swatchBlock:Show()
                    else
                        colorSwatch:SetAlpha(1)
                        swatchBlock:Hide()
                    end
                end)
                local off = sc.disabled()
                if off then
                    colorSwatch:SetAlpha(0.3)
                    swatchBlock:Show()
                else
                    colorSwatch:SetAlpha(1)
                    swatchBlock:Hide()
                end
            else
                if sc.tooltip then
                    HookSwatchTooltip(colorSwatch, sc)
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
                        text = sc.tooltip or rowConf.text,
                        hasAlpha = sc.hasAlpha,
                        getValue = sc.getValue,
                        setValue = sc.setValue,
                    }
                end
            end
            if #accs > 0 and not rowConf.noCapture then
                widget._captureCfg = { type = "multi", text = rowConf.text, accessors = accs }
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
        local dropdownBtn, dropCaption = BuildDropdownControl(
            leftRegion,
            DD_W,
            widget:GetFrameLevel() + 2,
            dropdownCfg.values,
            dropdownCfg.order,
            dropdownCfg.getValue,
            dropdownCfg.setValue,
            dropdownCfg.disabledValues
        )
        Pix.Point(dropdownBtn, "RIGHT", leftRegion, "RIGHT", -SIDE_PAD, 0)

        local function ApplyDDDisabled()
            if not dropdownCfg.disabled then
                return
            end
            local off = dropdownCfg.disabled()
            ddLabel:SetAlpha(off and 0.3 or 1)
            dropdownBtn:EnableMouse(not off)
            dropdownBtn:SetAlpha(off and 0.3 or 1)
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
                    local off = slCfg.disabled()
                    axisLabel:SetAlpha(off and 0.2 or 0.6)
                    trackFrame:SetAlpha(off and 0.3 or 1)
                    valBox:EnableMouse(not off)
                    valBox:SetAlpha(off and 0.3 or 1)
                    if slThumb then
                        slThumb._sliderDisabled = off
                    end
                end
            end)
            if slCfg.disabled then
                local off = slCfg.disabled()
                axisLabel:SetAlpha(off and 0.2 or 0.6)
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                valBox:SetAlpha(off and 0.3 or 1)
                if slThumb then
                    slThumb._sliderDisabled = off
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
            dropCaption:SetText(DDResolveLabel(dropdownCfg.values, dropdownCfg.order or {}, dropdownCfg.getValue()))
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
            local button = CreateFrame("Button", nil, widget)
            Pix.Size(button, btnWidth, BTN_H)
            Pix.Point(button, "CENTER", widget, "CENTER", details[2], 0)
            button:SetFrameLevel(widget:GetFrameLevel() + 1)
            MakeStyledButton(button, details[1], 14, WB_COLOURS, details[3])
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
            local button = CreateFrame("Button", nil, widget)
            Pix.Size(button, btnWidth, BTN_H)
            Pix.Point(button, "CENTER", widget, "CENTER", offsets[i], 0)
            button:SetFrameLevel(widget:GetFrameLevel() + 1)
            MakeStyledButton(button, details[1], 12, WB_COLOURS, details[2])
            local dopt = disabledOpts and disabledOpts[i]
            if dopt and dopt.disabled then
                button:SetAlpha(0.4)
                button:SetScript("OnEnter", function()
                    if dopt.tooltip then
                        ShowWidgetTooltip(button, dopt.tooltip)
                    end
                end)
                button:SetScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
                button:SetScript("OnClick", nil)
            end
        end
        return widget, ROW_H
    end

    -- WideDropdown: centered, no row background, title above; prominent selectors.
    -- Its menu is built on the first click, as BuildDropdownControl's: a page
    -- build makes none.
    function WidgetFactory:WideDropdown(
        hostFrame,
        title,
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
        TagOptionRow(widget, hostFrame, title)
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
        titleLabel:SetText(CludesUI.L(title))
        local dropdownBtn = CreateFrame("Button", nil, widget)
        Pix.Size(dropdownBtn, btnWidth, BTN_H)
        Pix.Point(dropdownBtn, "TOP", titleLabel, "BOTTOM", 0, -GAP)
        dropdownBtn:SetFrameLevel(widget:GetFrameLevel() + 1)
        local backdrop = SolidTex(dropdownBtn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        backdrop:SetAllPoints()
        local brd = MakeRoundedBorder(dropdownBtn, 1, 1, 1, DD_BRD_A, backdrop)
        -- Resting alpha on the text colour, the channel the hover colours write.
        local dropCaption = MakeFont(dropdownBtn, 13, nil, 1, 1, 1, DD_TXT_A)
        dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 14, 0)
        local arrow = MakeDropdownArrow(dropdownBtn, 14, Pix)
        if not sequence then
            sequence = {}
            for key in pairs(values) do
                sequence[#sequence + 1] = key
            end
        end
        dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))
        -- Light hover scripts until the first click builds the menu (the shared
        -- lazy dropdown wiring of BuildDropdownControl).
        WireLazyDropdown(dropdownBtn, dropCaption, backdrop, brd, WD_DD_COLOURS, function()
            local m, _, refresh = BuildDropdownMenu(
                dropdownBtn,
                btnWidth,
                sequence,
                values,
                getValue,
                setValue,
                dropCaption,
                "wide",
                disabledValuesFn
            )
            return m, refresh
        end)
        RegisterWidgetRefresh(function()
            dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))
            if disabledValuesFn then
                -- A disabled current value rests greyed; _valueDimA keeps the
                -- hover colours on that alpha too.
                local dimA = disabledValuesFn(getValue()) and 0.15 or nil
                dropdownBtn._valueDimA = dimA
                dropCaption:SetTextColor(1, 1, 1, dimA or DD_TXT_A)
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
        for position, rowConf in ipairs(configs) do
            local col = startX + (position - 1) * (DD_W + TRIPLE_GAP)
            local titleLbl = MakeFont(
                widget,
                11,
                nil,
                CludesUI.TEXT_SECTION_R,
                CludesUI.TEXT_SECTION_G,
                CludesUI.TEXT_SECTION_B,
                CludesUI.TEXT_SECTION_A
            )
            Pix.Point(titleLbl, "TOP", widget, "TOPLEFT", col + DD_W / 2, 0)
            titleLbl:SetText(CludesUI.L(rowConf.title))
            local dropdownBtn, dropCaption = BuildDropdownControl(
                widget,
                DD_W,
                widget:GetFrameLevel() + 1,
                rowConf.values,
                rowConf.order,
                rowConf.getValue,
                rowConf.setValue
            )
            Pix.Point(dropdownBtn, "TOPLEFT", widget, "TOPLEFT", col, -(TITLE_H + GAP_Y))
            RegisterWidgetRefresh(function()
                dropCaption:SetText(DDResolveLabel(rowConf.values, rowConf.order or {}, rowConf.getValue()))
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
        for position, rowConf in ipairs(configs) do
            local col = startX + (position - 1) * (SL_W + TRIPLE_GAP)
            local minVal = rowConf.minVal or 16
            local maxVal = rowConf.maxVal or 40
            local step = rowConf.step or 1
            local INPUT_W = 36
            local TRACK_W = SL_W - INPUT_W - 16
            local slRow = CreateFrame("Frame", nil, widget)
            Pix.Size(slRow, SL_W, SL_H)
            Pix.Point(slRow, "TOPLEFT", widget, "TOPLEFT", col, -((ROW_H - SL_H) / 2))
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
                rowConf.getValue,
                rowConf.setValue,
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
