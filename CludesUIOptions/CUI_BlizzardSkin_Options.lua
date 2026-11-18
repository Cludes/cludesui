if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_Options.lua
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIBlizzardSkin"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
local PAGE_WINDOWSKINS = "Blizzard Window Skins"
local PAGE_TOOLTIPS = "Tooltips, Menus & Popups"
local PAGE_DRAGONRIDING = "Dragon Riding"
local PAGE_CHATBUBBLES = "Chat Bubbles"
-- A link tab: opens Quality of Life's Shifter (see pageLinks below).
local PAGE_WINDOWMOVER = "Window Mover"
-- Display-only tab labels: the page names above stay the pages' identities
-- (nav links, Unlock Mode, saved state).
CludesUI.TAB_LABEL_OVERRIDES[PAGE_WINDOWSKINS] = "Window Skins"
CludesUI.TAB_LABEL_OVERRIDES[PAGE_TOOLTIPS] = "Tooltips & Menus"
CludesUI.TAB_LABEL_OVERRIDES[PAGE_DRAGONRIDING] = "Skyriding"
CludesUI.TAB_LABEL_OVERRIDES[PAGE_WINDOWMOVER] = "Window Mover"

-- The account-wide settings table (these tabs' settings live at its top
-- level), made if it is not there yet, for a write.
local function Account()
    if not CludesUIDB then
        CludesUIDB = {}
    end
    return CludesUIDB
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then
        return
    end
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local CreateFrame = CludesUI._Pool.CreateFrame

    -- Border rows shared by the Tooltips page and the Loot Window card, over a key prefix's
    -- <prefix>Border* settings (drawn by _applyConfiguredBorder, CUI_BlizzardSkin_TooltipSkin.lua).
    -- The step the skin renders with: the stored label (an unknown one = thin); unset = the
    -- legacy numeric tooltipBorderSize for the tooltip, 1 otherwise.
    local function BorderStep(prefixText)
        local key = CludesUIDB[prefixText .. "BorderThickness"]
        if key then
            return CludesUI.BORDER_STEP_OF_LABEL[key] or 1
        end
        if prefixText == "tooltip" then
            return CludesUIDB.tooltipBorderSize or 1
        end
        return 1
    end
    -- Border Size in pixels over <prefix>BorderThickness (still a label) and its <prefix>BorderThicknessPx companion.
    -- The short track leaves room for the color swatches beside it.
    local function BorderSizeSlider(prefixText, textValue, disabledFn, apply, disabledTooltip)
        return CludesUI.BorderPxSliderCfg({
            text = textValue,
            disabled = disabledFn,
            disabledTooltip = disabledTooltip,
            trackWidth = 120,
            getStep = function()
                return BorderStep(prefixText)
            end,
            setStep = function(step)
                CludesUIDB[prefixText .. "BorderThickness"] = CludesUI.BORDER_LABEL_OF_STEP[step] or "thin"
            end,
            getTex = function()
                return CludesUIDB[prefixText .. "BorderTexture"] or "solid"
            end,
            getPx = function()
                return CludesUIDB[prefixText .. "BorderThicknessPx"]
            end,
            setPx = function(val)
                CludesUIDB[prefixText .. "BorderThicknessPx"] = val
            end,
            apply = apply,
        })
    end
    -- The registry sizeKey the skin passes beside the addonKey "blizzardSkin" (registered
    -- nowhere, so an UNSET offset resolves to 0/0, never to the global per-texture defaults).
    local function BorderSizeKey(prefixText)
        return CludesUIDB[prefixText .. "BorderThickness"]
            or CludesUI.BORDER_LABEL_OF_STEP[BorderStep(prefixText)]
            or "thin"
    end
    -- The Width Offset | Height Offset cfgs for a textured style; nil for a solid one (no offsets).
    local function BorderOffsetCfgs(prefixText, disabledFn, apply, disabledTooltip)
        local texture = CludesUIDB[prefixText .. "BorderTexture"] or "solid"
        if texture == "" or texture == "solid" then
            return
        end
        return CludesUI.BorderOffsetRowCfgs({
            addonKey = "blizzardSkin",
            disabled = disabledFn,
            disabledTooltip = disabledTooltip,
            getTex = function()
                return CludesUIDB[prefixText .. "BorderTexture"] or "solid"
            end,
            getStep = function()
                return BorderStep(prefixText)
            end,
            getSizeKey = function()
                return BorderSizeKey(prefixText)
            end,
            getPx = function()
                return CludesUIDB[prefixText .. "BorderThicknessPx"]
            end,
            getX = function()
                return CludesUIDB[prefixText .. "BorderOffsetX"]
            end,
            setX = function(val)
                CludesUIDB[prefixText .. "BorderOffsetX"] = val
            end,
            getY = function()
                return CludesUIDB[prefixText .. "BorderOffsetY"]
            end,
            setY = function(val)
                CludesUIDB[prefixText .. "BorderOffsetY"] = val
            end,
            apply = apply,
        })
    end
    -- A border row's inline controls: the Accent | Class | Custom color mode swatches left of
    -- its Border Size, and the Show Behind cog (allowBehind) left of its style. opts: apply =
    -- run after a pick (the Loot Window card's live refresh); quality = { key, tip } adds a
    -- Quality swatch whose own color is saved at key.
    local function AttachBorderControls(row, prefixText, disabledFn, allowBehind, options)
        if CludesUI._prebuilding then
            return
        end
        local Pix = CludesUI.PanelPP
        local apply = options and options.apply
        local leftX, right = row._leftRegion, row._rightRegion
        -- The offsets live in their own row below the style row (BorderOffsetCfgs); the cog
        -- keeps only Show Behind, so a surface without that option gets no cog at all.
        if allowBehind then
            local popupRows = {
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        return CludesUIDB[prefixText .. "BorderBehind"] or false
                    end,
                    set = function(val)
                        CludesUIDB[prefixText .. "BorderBehind"] = val
                        if apply then
                            apply()
                        end
                    end,
                },
            }
            CludesUI.BuildInlineCog(leftX, {
                title = "Border Options",
                rows = popupRows,
                anchorTo = leftX._control,
                disabled = disabledFn,
                disabledTooltip = prefixText == "tooltip" and "Reskin Tooltip" or "Reskin Popups and Menus",
            })
        end

        -- A pickable swatch (Custom, Quality) opens its color picker on a click while its mode
        -- is the active one; colorKey is where it saves (default the Custom color).
        local function AddModeSwatch(anchor, mode, tipText, getColor, pickable, colorKey)
            local sw, refresh = CludesUI.BuildColorSwatch(
                right,
                right:GetFrameLevel() + 5,
                getColor,
                function(r, g, b, a)
                    CludesUIDB[colorKey or (prefixText .. "BorderColor")] = { r = r, g = g, b = b }
                    CludesUIDB[prefixText .. "BorderOpacity"] = a
                    CludesUIDB[prefixText .. "BorderColorMode"] = mode
                    if apply then
                        apply()
                    end
                end,
                pickable,
                20
            )
            Pix.Point(sw, "RIGHT", anchor, "LEFT", -8, 0)
            local orig = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self)
                if not pickable or (CludesUIDB[prefixText .. "BorderColorMode"] or "custom") ~= mode then
                    CludesUIDB[prefixText .. "BorderColorMode"] = mode
                    if apply then
                        apply()
                    end
                    CludesUI:RefreshPage()
                    return
                end
                orig(self)
            end)
            sw:HookScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, tipText)
            end)
            sw:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            -- Applied once at build time too -- widget refresh only fires
            -- on later changes, so without this every swatch opened lit.
            local function UpdSwatchState()
                local off = disabledFn and disabledFn()
                local isActive = (CludesUIDB[prefixText .. "BorderColorMode"] or "custom") == mode
                sw:SetAlpha(off and 0.15 or (isActive and 1 or 0.3))
                sw:EnableMouse(not off)
                refresh()
            end
            CludesUI.RegisterWidgetRefresh(UpdSwatchState)
            UpdSwatchState()
            return sw
        end
        local accent = AddModeSwatch(right._control, "accent", "Accent Color", function()
            local c = CludesUI.CLUDES_GREEN
            return c.r, c.g, c.b, 1
        end, false)
        local class = AddModeSwatch(accent, "class", "Class Color", function()
            local _, k = UnitClass("player")
            local c = RAID_CLASS_COLORS[k]
            return c.r, c.g, c.b, 1
        end, false)
        local last = AddModeSwatch(class, "custom", "Custom Color", function()
            local c = CludesUIDB[prefixText .. "BorderColor"] or { r = 1, g = 1, b = 1 }
            return c.r, c.g, c.b, CludesUIDB[prefixText .. "BorderOpacity"] or CludesUI.RESKIN.BRD_ALPHA
        end, true)
        local q = options and options.quality
        if q then
            last = AddModeSwatch(last, "quality", q.tip, function()
                local c = CludesUIDB[q.key] or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b, CludesUIDB[prefixText .. "BorderOpacity"] or CludesUI.RESKIN.BRD_ALPHA
            end, true, q.key)
        end
        right._lastInline = last
    end

    -- Header builder for runtime-painted samples at their on-screen size: the panel's scale
    -- compensated, each shrunk only when wider than its column. cols = { { show, title } };
    -- show(header, place) builds or re-hangs a sample, place(root) runs before its paint and
    -- place(root, w, h) after it. Titled columns sit side by side, tops on one line under a
    -- small title (the Mythic+ Tools header previews' look); one untitled column centres.
    local PV_TITLE_H = 15
    local function SampleHeaderBuilder(cols)
        return function(header, hdrW)
            local building, H = true, 0
            local num = #cols
            local titled = cols[1].title ~= nil
            local titleH = titled and PV_TITLE_H or 0
            local st = {}
            local lblHost
            if titled then
                lblHost = CreateFrame("Frame", nil, header)
                lblHost:SetAllPoints(header)
                lblHost:SetFrameLevel(header:GetFrameLevel() + 3)
            end
            local function Layout()
                local s = UIParent:GetEffectiveScale() / header:GetEffectiveScale()
                local colW = ((building and hdrW or header:GetWidth()) - 2 * CludesUI.CONTENT_PAD) / num
                local maxH = 0
                for idx = 1, num do
                    local c = st[idx]
                    if c and c.w then
                        local fit = (c.w > 0) and math.min(1, colW / (c.w * s)) or 1
                        c.root:SetScale(s * fit)
                        maxH = math.max(maxH, c.h * s * fit)
                    end
                end
                local blockH = maxH + titleH
                for idx = 1, num do
                    local c = st[idx]
                    if c and c.w then
                        local root = c.root
                        root:ClearAllPoints()
                        if titled then
                            -- Offsets in the sample's own units, snapped to its physical pixels.
                            local hs = root:GetScale()
                            local onePx = CludesUI.PP.perfect / root:GetEffectiveScale()
                            local function Snap(val)
                                return math.floor(val / onePx + 0.5) * onePx
                            end
                            local cx = (-(num - 1) / 2 + (idx - 1)) * colW
                            root:SetPoint(
                                "TOP",
                                header,
                                "CENTER",
                                Snap(cx / hs),
                                Snap((blockH / 2 - titleH) / hs)
                            )
                            c.fs:ClearAllPoints()
                            c.fs:SetPoint("BOTTOMLEFT", root, "TOPLEFT", 0, 3)
                            c.fs:Show()
                        else
                            root:SetPoint("CENTER", header, "CENTER", 0, 0)
                        end
                    end
                end
                H = math.max(80, math.ceil(blockH + 40))
                if not building and header:IsVisible() and math.abs(header:GetHeight() - H) > 1 then
                    CludesUI:SetContentHeaderHeightSilent(H)
                end
            end
            for idx = 1, num do
                local c = {}
                st[idx] = c
                if titled then
                    c.fs = CludesUI.MakeFont(lblHost, 11, nil, 1, 1, 1)
                    c.fs:SetAlpha(0.6)
                    c.fs:SetText(cols[idx].title)
                    c.fs:Hide()
                end
                cols[idx].show(header, function(root, wid, hgt)
                    if not wid then
                        root:SetScale(UIParent:GetEffectiveScale() / header:GetEffectiveScale())
                        return
                    end
                    c.root, c.w, c.h = root, wid, hgt
                    Layout()
                end)
            end
            building = false
            return H
        end
    end
    -- Popups first, as the page's sections run.
    local TooltipHeaderBuilder = SampleHeaderBuilder({
        {
            title = CludesUI.L("Popups"),
            show = function(header, place)
                if CludesUI.ShowPopupPreview then
                    CludesUI.ShowPopupPreview(header, place)
                end
            end,
        },
        {
            title = CludesUI.L("Tooltip"),
            show = function(header, place)
                if CludesUI.ShowTooltipPreview then
                    CludesUI.ShowTooltipPreview(header, place)
                end
            end,
        },
    })
    local function TooltipPreviewRepaint()
        if CludesUI._repaintTooltipPreview then
            CludesUI._repaintTooltipPreview()
        end
    end
    local function PopupPreviewRepaint()
        if CludesUI._repaintPopupPreview then
            CludesUI._repaintPopupPreview()
        end
    end

    local function BuildTooltipsPage(pageName, hostFrame, yOffset)
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt
        -- The border row helpers (BorderSizeSlider, BorderOffsetCfgs, AttachBorderControls) sit
        -- above this page, shared with the Loot Window card.
        -- Width Offset | Height Offset right below a Border Style row, only while its style is
        -- textured (a solid border has no offsets). Built in every pass so the y advance never differs.
        local function BorderOffsetRow(prefixText, disabledFn, apply)
            local ocfgL, ocfgR = BorderOffsetCfgs(prefixText, disabledFn, apply)
            if ocfgL then
                _, hgt = W:DualRow(hostFrame, posY, ocfgL, ocfgR)
                posY = posY - hgt
            end
        end

        -- The sample tooltip and popup head the page.
        if not CludesUI._prebuilding then
            CludesUI:SetContentHeader(TooltipHeaderBuilder)
        elseif CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "BLIZZARD POPUPS & GAME MENU", posY)
        posY = posY - hgt

        local function popupOff()
            return CludesUIDB.reskinPopupsMenus == false
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Reskin Popups and Menus",
            tooltip = "Reskins Blizzard's right-click context menus and pop-ups.",
            getValue = function()
                -- Seeded from the old master by the blizzskin_reskin_master_split_v1
                -- migration; independent thereafter. Default on.
                return not CludesUIDB or CludesUIDB.reskinPopupsMenus ~= false
            end,
            setValue = function(val)
                Account().reskinPopupsMenus = val
                -- Resurrect Accept Glow runs only under the reskin: sync a shown popup now
                if CludesUI._EnsureResurrectGlow then
                    CludesUI._EnsureResurrectGlow()
                end
                CludesUI:RefreshPage() -- update the border cog, swatch and glow disabled states
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Reskin setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }, {
            type = "toggle",
            text = "Resurrect Accept Glow",
            tooltip = "Adds a glowing border around the Accept button of resurrection popups.",
            disabled = popupOff,
            disabledTooltip = "Reskin Popups and Menus",
            getValue = function()
                return CludesUIDB and CludesUIDB.resurrectAcceptGlow or false
            end,
            setValue = function(val)
                Account().resurrectAcceptGlow = val
                if CludesUI._EnsureResurrectGlow then
                    CludesUI._EnsureResurrectGlow()
                end
            end,
        })
        posY = posY - hgt

        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local outer
            outer, hgt = W:DualRow(hostFrame, posY, {
                type = "dropdown",
                text = "Border Style",
                disabled = popupOff,
                values = texValues,
                order = texOrder,
                getValue = function()
                    return CludesUIDB.popupMenuBorderTexture or "solid"
                end,
                setValue = function(val)
                    local c, b = CludesUI.GetBorderStyleSelectDefaults(val)
                    CludesUIDB.popupMenuBorderTexture = val
                    CludesUIDB.popupMenuBorderOffsetX = nil
                    CludesUIDB.popupMenuBorderOffsetY = nil
                    CludesUIDB.popupMenuBorderBehind = b
                    CludesUIDB.popupMenuBorderColor = c
                    if CludesUIDB.popupMenuBorderThicknessPx then
                        CludesUIDB.popupMenuBorderThicknessPx = false
                    end
                    CludesUI:RefreshPage(true)
                end,
            }, BorderSizeSlider("popupMenu", "Border Size", popupOff, PopupPreviewRepaint))
            posY = posY - hgt
            AttachBorderControls(outer, "popupMenu", popupOff, true, { apply = PopupPreviewRepaint })
            BorderOffsetRow("popupMenu", popupOff, PopupPreviewRepaint)
            local buttons
            buttons, hgt = W:DualRow(hostFrame, posY, {
                type = "dropdown",
                text = "Button Border Style",
                disabled = popupOff,
                values = texValues,
                order = texOrder,
                getValue = function()
                    return CludesUIDB.popupMenuButtonBorderTexture or "solid"
                end,
                setValue = function(val)
                    CludesUIDB.popupMenuButtonBorderTexture = val
                    local sc = CludesUI.GetBorderSelectColor(val)
                    if sc then
                        CludesUIDB.popupMenuButtonBorderColor = sc
                    end
                    CludesUIDB.popupMenuButtonBorderOffsetX = nil
                    CludesUIDB.popupMenuButtonBorderOffsetY = nil
                    if CludesUIDB.popupMenuButtonBorderThicknessPx then
                        CludesUIDB.popupMenuButtonBorderThicknessPx = false
                    end
                    CludesUI:RefreshPage(true)
                end,
            }, BorderSizeSlider(
                "popupMenuButton",
                "Button Border Size",
                popupOff,
                PopupPreviewRepaint
            ))
            posY = posY - hgt
            AttachBorderControls(buttons, "popupMenuButton", popupOff, nil, { apply = PopupPreviewRepaint })
            BorderOffsetRow("popupMenuButton", popupOff, PopupPreviewRepaint)
        end

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "colorpicker",
            text = "Button Background",
            hasAlpha = true,
            disabled = popupOff,
            getValue = function()
                local c = CludesUIDB.popupMenuButtonBackgroundColor or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
                return c.r, c.g, c.b, c.a
            end,
            setValue = function(r, g, b, a)
                CludesUIDB.popupMenuButtonBackgroundColor = { r = r, g = g, b = b, a = a }
                PopupPreviewRepaint()
            end,
        }, {
            type = "multiSwatch",
            text = "Element & Text Color",
            disabled = popupOff,
            swatches = {
                -- Effective mode comes from the skin file's resolver: unset =
                -- native unless the legacy Accent Colored Elements opt-in is present.
                -- All four highlights read it so the default state is shown truthfully.
                {
                    tooltip = "Native Colors",
                    hasAlpha = false,
                    getValue = function()
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "native"
                        PopupPreviewRepaint()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                            or "native"
                        return m == "native" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = CludesUI.CLUDES_GREEN
                        return c.r, c.g, c.b
                    end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "accent"
                        PopupPreviewRepaint()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                            or "native"
                        return m == "accent" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = CludesUIDB.popupMenuButtonTextColor or { r = 1, g = 1, b = 1 }
                        return c.r, c.g, c.b
                    end,
                    setValue = function(r, g, b)
                        CludesUIDB.popupMenuButtonTextColorMode = "custom"
                        CludesUIDB.popupMenuButtonTextColor = { r = r, g = g, b = b }
                        PopupPreviewRepaint()
                    end,
                    onClick = function(self)
                        local m = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                            or "native"
                        if m ~= "custom" then
                            CludesUIDB.popupMenuButtonTextColorMode = "custom"
                            PopupPreviewRepaint()
                            CludesUI:RefreshPage()
                            return
                        end
                        self._eabOrigClick(self)
                    end,
                    refreshAlpha = function()
                        local m = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                            or "native"
                        return m == "custom" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local _, k = UnitClass("player")
                        local c = RAID_CLASS_COLORS[k]
                        return c.r, c.g, c.b
                    end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "class"
                        PopupPreviewRepaint()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CludesUI._getPopupMenuElementMode and CludesUI._getPopupMenuElementMode()
                            or "native"
                        return m == "class" and 1 or 0.3
                    end,
                },
            },
        })
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Font Size Scale",
            tooltip = "Scales the font size of reskinned Blizzard tooltips, menus, and popups.",
            min = 0.7,
            max = 1.5,
            step = 0.05,
            format = "%.0f%%",
            displayMul = 100,
            getValue = function()
                return CludesUIDB and CludesUIDB.tooltipFontScale or 1.0
            end,
            setValue = function(val)
                Account().tooltipFontScale = val
                TooltipPreviewRepaint()
            end,
        }, {
            type = "toggle",
            text = "Enable Blizzard Pause Menu",
            tooltip = "Reskins the Escape / Game Menu.",
            getValue = function()
                -- Independent, default on (not tied to any master reskin toggle).
                return not CludesUIDB or CludesUIDB.reskinGameMenu ~= false
            end,
            setValue = function(val)
                Account().reskinGameMenu = val
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing the pause menu reskin requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        })
        posY = posY - hgt

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt

        local heading
        heading, hgt = W:SectionHeader(hostFrame, "BLIZZARD TOOLTIP", posY)
        posY = posY - hgt

        -- "Reskin Tooltip" (customTooltips) is the master for this section: its
        -- reskin-driven sub-settings gray out (and stop applying) when it is off.
        -- Per-line tooltip content settings (titles, item level, M+ score, detailed
        -- tooltips) live in the Tooltip Extras checklist below it. Settings
        -- independent of the skin (Detailed Tooltips, Show Health Strip, Spell ID
        -- on Tooltip, Show Max Stack) stay editable with the reskin off.
        local function ttReskinOff()
            return CludesUIDB and CludesUIDB.customTooltips == false
        end

        -- The Move in Unlock Mode button on the tooltip's first section: its
        -- mover exists only while the fixed anchor is live (reskin on, Anchor
        -- to Cursor off), so the button greys out as the Growth Direction row does.
        CludesUI.BuildSectionUnlockJump(heading, {
            key = "CUI_TooltipAnchor",
            disabled = function()
                return ttReskinOff() or (CludesUIDB and CludesUIDB.tooltipAnchorCursor and true or false)
            end,
            disabledTooltip = function()
                if ttReskinOff() then
                    return "Reskin Tooltip"
                end
                return "This option does not apply while Anchor to Cursor is enabled"
            end,
        })

        -- Show Health Strip works without the reskin as well; its cog restyles
        -- the reskinned bar, so the cog locks with the reskin off.
        local function stripHidden()
            return not (CludesUIDB and CludesUIDB.tooltipHideHealthStrip == false)
        end

        -- Reskin Tooltip | Show Tooltips
        local ttShowRow
        ttShowRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Reskin Tooltip",
            getValue = function()
                return not CludesUIDB or CludesUIDB.customTooltips ~= false
            end,
            setValue = function(val)
                Account().customTooltips = val
                if CludesUI.SyncAuraTooltipSkin then
                    CludesUI.SyncAuraTooltipSkin()
                end
                CludesUI:RefreshPage() -- gray/ungray the rest of the section now
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Reskin setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }, {
            type = "dropdown",
            text = "Show Tooltips",
            disabled = ttReskinOff,
            disabledTooltip = "Reskin Tooltip",
            values = {
                always = "Always",
                outOfCombat = "Out of Combat",
                outOfBossCombat = "Out of Boss Combat",
                never = "Never",
            },
            order = { "always", "outOfCombat", "outOfBossCombat", "never" },
            getValue = function()
                return (CludesUIDB and CludesUIDB.tooltipShowMode) or "always"
            end,
            setValue = function(val)
                Account().tooltipShowMode = val
                CludesUI:RefreshPage() -- update the Use Modifier cog disabled state
            end,
        })
        posY = posY - hgt

        -- "Use Modifier" cog on Show Tooltips (right region): while the chosen
        -- modifier is held, suppression is lifted so a hidden tooltip can be
        -- read on hover (e.g. peeking a spell in combat). Disabled (blocked +
        -- dimmed) when the reskin is off or the mode is "Always" (nothing hides).
        if not CludesUI._prebuilding then
            local rightRgn = ttShowRow._rightRegion
            local function showModOff()
                if ttReskinOff() then
                    return true
                end
                return ((CludesUIDB and CludesUIDB.tooltipShowMode) or "always") == "always"
            end
            CludesUI.BuildInlineCog(rightRgn, {
                gap = 9,
                disabled = showModOff,
                disabledTooltip = function()
                    return ttReskinOff() and "Reskin Tooltip"
                        or "This option requires Show Tooltips to be set to hide tooltips"
                end,
                title = "Show Tooltips",
                rows = {
                    {
                        type = "dropdown",
                        label = "Peek Modifier",
                        values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                        order = { "none", "shift", "control", "alt" },
                        get = function()
                            return (CludesUIDB and CludesUIDB.tooltipShowModifier) or "none"
                        end,
                        set = function(val)
                            Account().tooltipShowModifier = val
                        end,
                    },
                },
            })
        end

        -- Anchor to Cursor | Growth Direction
        local ttAnchorRow
        ttAnchorRow, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "toggle",
                text = "Anchor to Cursor",
                disabled = ttReskinOff,
                disabledTooltip = "Reskin Tooltip",
                getValue = function()
                    return CludesUIDB and CludesUIDB.tooltipAnchorCursor or false
                end,
                setValue = function(val)
                    Account().tooltipAnchorCursor = val
                    if CludesUI._applyTooltipCursorAnchor then
                        CludesUI._applyTooltipCursorAnchor()
                    end
                    -- Re-park the fixed anchor (and seed it if this profile never
                    -- has) so turning the cursor mode off resumes cleanly.
                    if CludesUI._applyTooltipFixedAnchor then
                        CludesUI._applyTooltipFixedAnchor()
                    end
                    CludesUI:RefreshPage() -- update the position cog + Growth Direction disabled states
                end,
            },
            -- Default screen-anchored tooltip only (see ApplyGrowthDirection in
            -- CUI_BlizzardSkin_TooltipAnchor.lua): Blizzard picks the anchored corner
            -- dynamically from the tooltip's screen position; "Expand Up"/"Expand Down"
            -- force the vertical component of that corner. The cursor anchor re-points
            -- the tooltip itself, so this grays out while Anchor to Cursor is on.
            {
                type = "dropdown",
                text = "Growth Direction",
                disabled = function()
                    return ttReskinOff() or (CludesUIDB and CludesUIDB.tooltipAnchorCursor and true or false)
                end,
                disabledTooltip = function()
                    if ttReskinOff() then
                        return "Reskin Tooltip"
                    end
                    return "This option does not apply while Anchor to Cursor is enabled"
                end,
                values = { default = "Default", up = "Expand Up", down = "Expand Down" },
                order = { "default", "up", "down" },
                getValue = function()
                    return (CludesUIDB and CludesUIDB.tooltipGrowthDirection) or "default"
                end,
                setValue = function(val)
                    Account().tooltipGrowthDirection = val
                end,
            }
        )
        posY = posY - hgt

        -- Position control on Anchor to Cursor (left region): position + X/Y offset
        if not CludesUI._prebuilding then
            local leftRgn = ttAnchorRow._leftRegion
            local function ttCursorOff()
                return not (CludesUIDB and CludesUIDB.tooltipAnchorCursor)
            end
            CludesUI.BuildInlineCog(leftRgn, {
                gap = 9,
                disabled = ttCursorOff,
                disabledTooltip = "Anchor to Cursor",
                title = "Cursor Tooltip Position",
                rows = {
                    {
                        type = "dropdown",
                        label = "Position",
                        values = {
                            bottomright = "Bottom Right",
                            bottomleft = "Bottom Left",
                            topright = "Top Right",
                            topleft = "Top Left",
                            right = "Right",
                            left = "Left",
                            top = "Top",
                            bottom = "Bottom",
                            center = "Center",
                        },
                        order = {
                            "bottomright",
                            "bottomleft",
                            "topright",
                            "topleft",
                            "right",
                            "left",
                            "top",
                            "bottom",
                            "center",
                        },
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipCursorPosition or "top"
                        end,
                        set = function(val)
                            Account().tooltipCursorPosition = val
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return (CludesUIDB and CludesUIDB.tooltipCursorOffsetX) or 0
                        end,
                        set = function(val)
                            Account().tooltipCursorOffsetX = val
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return (CludesUIDB and CludesUIDB.tooltipCursorOffsetY) or 0
                        end,
                        set = function(val)
                            Account().tooltipCursorOffsetY = val
                        end,
                    },
                },
            })
        end

        -- Tooltip Extras | Spell ID on Tooltip
        -- Tooltip Extras (left): the per-line tooltip content as one checklist,
        -- each entry on the key it has always used. It stays active with the
        -- reskin off because Detailed Tooltips (the UberTooltips CVar) works with
        -- the default Blizzard tooltip too; the reskin-driven entries lock instead.
        local ttExtrasRow
        ttExtrasRow, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "dropdown",
                text = "Tooltip Extras",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            },
            -- Front-end duplicate of the toggle in Global Settings > Developer;
            -- same CludesUIDB.showSpellID key read by the tooltip logic in
            -- CludesUI.lua (no separate backend). Independent of the reskin.
            {
                type = "toggle",
                text = "Spell ID on Tooltip",
                getValue = function()
                    return CludesUI.SpellIDOn()
                end,
                setValue = function(val)
                    Account().showSpellID = val
                    if CludesUI.SyncAuraSpellIDCVar then
                        CludesUI.SyncAuraSpellIDCVar()
                    end
                    CludesUI:RefreshPage() -- update the Use Modifier cog disabled state
                end,
            }
        )
        posY = posY - hgt

        if not CludesUI._prebuilding then
            local Pix = CludesUI.PanelPP
            local lrgn = ttExtrasRow._leftRegion
            if lrgn._control then
                lrgn._control:Hide()
            end
            -- Unset value of each reskin-driven key ("uber" is the CVar entry).
            local EXTRA_DEFAULTS = {
                tooltipPlayerTitles = false,
                tooltipItemLevel = true,
                tooltipMythicScore = true,
                tooltipShowMount = false,
                tooltipShowGuildRank = false,
                tooltipShowTarget = false,
                tooltipLevelColor = false,
                tooltipClassLineColor = false,
                tooltipFactionColor = false,
                tooltipGuildmateColor = false,
                tooltipCompactLevel = false,
                tooltipAFKTag = false,
            }
            local lockTip = CludesUI.DisabledTooltip("Reskin Tooltip")
            local extrasDD, extrasRefresh = CludesUI.BuildVisOptsCBDropdown(
                lrgn,
                170,
                lrgn:GetFrameLevel() + 2,
                {
                    {
                        key = "tooltipPlayerTitles",
                        label = "Player Titles",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipItemLevel",
                        label = "Item Level",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipMythicScore",
                        label = "M+ Score",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipShowMount",
                        label = "Mount",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds the mount a player is riding to their tooltip, with a green check if you own it or a red X if you don't.",
                    },
                    {
                        key = "tooltipShowGuildRank",
                        label = "Guild Rank",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipShowTarget",
                        label = "Unit Target",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds a Targeting line showing who the hovered player or NPC is targeting, in green when it's you.",
                    },
                    {
                        key = "tooltipLevelColor",
                        label = "Level Difficulty Color",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the level number from gray (trivial) to red (much higher than you).",
                    },
                    {
                        key = "tooltipClassLineColor",
                        label = "Class Colored Spec",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors a player's spec and class line in their class color.",
                    },
                    {
                        key = "tooltipFactionColor",
                        label = "Faction Color",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the Alliance and Horde line in blue and red.",
                    },
                    {
                        key = "tooltipGuildmateColor",
                        label = "Highlight Guildmates",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the guild name (and rank, if shown) of members of your own guild in your guild chat color.",
                    },
                    {
                        key = "tooltipCompactLevel",
                        label = "Compact Level Line",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = 'Shortens the level line to the level and race, or level, rank and type for NPCs ("90 Tauren", "90 Elite Humanoid").',
                    },
                    {
                        key = "tooltipAFKTag",
                        label = "Away Tag",
                        lockedFn = ttReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds <Away> or <Busy> after the name of players who are away or busy.",
                    },
                    { key = "uber", label = "Detailed Tooltips" },
                },
                function(k)
                    if k == "uber" then
                        return GetCVar("UberTooltips") == "1"
                    end
                    local val = CludesUIDB and CludesUIDB[k]
                    if val == nil then
                        return EXTRA_DEFAULTS[k]
                    end
                    return val and true or false
                end,
                function(k, val)
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    if k == "uber" then
                        -- Only enforced on login after the user has toggled it once.
                        CludesUIDB.uberTooltipsManual = true
                        CludesUIDB.uberTooltips = val
                        CludesUI.SetCVar("UberTooltips", val and "1" or "0", "CludesUIBlizzardSkin")
                    else
                        CludesUIDB[k] = val
                        TooltipPreviewRepaint()
                    end
                end
            )
            Pix.Point(extrasDD, "RIGHT", lrgn, "RIGHT", -20, 0)
            lrgn._control = extrasDD
            lrgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(extrasRefresh)
        end

        -- "Use Modifier" cog on Spell ID on Tooltip (right region): the spell/item
        -- ID lines only show while the chosen modifier is held. Disabled (blocked +
        -- dimmed) when Spell ID on Tooltip is off, mirroring the cursor-position cog.
        if not CludesUI._prebuilding then
            local rightRgn = ttExtrasRow._rightRegion
            local function sidOff()
                return not CludesUI.SpellIDOn()
            end
            CludesUI.BuildInlineCog(rightRgn, {
                gap = 9,
                disabled = sidOff,
                disabledTooltip = "Spell ID on Tooltip",
                title = "Spell ID",
                rows = {
                    {
                        type = "dropdown",
                        label = "Use Modifier",
                        values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                        order = { "none", "shift", "control", "alt" },
                        get = function()
                            return (CludesUIDB and CludesUIDB.spellIDModifier) or "none"
                        end,
                        set = function(val)
                            Account().spellIDModifier = val
                            -- Modifier choice gates the engine-side combat
                            -- aura-ID CVar (12.1; no-op on retail).
                            if CludesUI.SyncAuraSpellIDCVar then
                                CludesUI.SyncAuraSpellIDCVar()
                            end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Icon ID",
                        get = function()
                            return not CludesUIDB or CludesUIDB.showIconID ~= false
                        end,
                        set = function(val)
                            Account().showIconID = val
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Item ID",
                        get = function()
                            return not CludesUIDB or CludesUIDB.showItemID ~= false
                        end,
                        set = function(val)
                            Account().showItemID = val
                        end,
                    },
                },
            })
        end

        -- Show Max Stack for Items | Show Player Buffs
        local ttStackRow
        ttStackRow, hgt = W:DualRow(
            hostFrame,
            posY,
            -- Independent of the reskin, so it is NOT gated by "Reskin
            -- Tooltip" -- like Spell ID on Tooltip.
            {
                type = "toggle",
                text = "Show Max Stack for Items",
                tooltip = "Appends an item's max stack count on tooltip.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.showItemMaxStacks or false
                end,
                setValue = function(val)
                    Account().showItemMaxStacks = val
                    CludesUI:RefreshPage() -- update the Use Modifier cog disabled state
                end,
            },
            {
                type = "toggle",
                text = "Show Player Buffs",
                disabled = ttReskinOff,
                disabledTooltip = "Reskin Tooltip",
                getValue = function()
                    return CludesUIDB and CludesUIDB.tooltipShowBuffs or false
                end,
                setValue = function(val)
                    Account().tooltipShowBuffs = val
                    if CludesUI._applyTooltipBuffs then
                        CludesUI._applyTooltipBuffs()
                    end
                    CludesUI:RefreshPage() -- update the position cog disabled state
                end,
            }
        )
        posY = posY - hgt

        -- "Use Modifier" cog on Show Max Stack for Items (left region): the Max
        -- Stack line only shows while the chosen modifier is held. Disabled
        -- (blocked + dimmed) when the toggle is off, mirroring the Spell ID cog.
        if not CludesUI._prebuilding then
            local leftRgn = ttStackRow._leftRegion
            local function iStacksOff()
                return not (CludesUIDB and CludesUIDB.showItemMaxStacks)
            end
            CludesUI.BuildInlineCog(leftRgn, {
                gap = 9,
                disabled = iStacksOff,
                disabledTooltip = "Show Max Stack for Items",
                title = "Item Stacks",
                rows = {
                    {
                        type = "dropdown",
                        label = "Use Modifier",
                        values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                        order = { "none", "shift", "control", "alt" },
                        get = function()
                            return (CludesUIDB and CludesUIDB.itemStackModifier) or "none"
                        end,
                        set = function(val)
                            Account().itemStackModifier = val
                        end,
                    },
                },
            })
        end

        -- Tooltip Buffs cog on Show Player Buffs (right region)
        if not CludesUI._prebuilding then
            local function ttBuffsOff()
                return ttReskinOff() or not (CludesUIDB and CludesUIDB.tooltipShowBuffs)
            end
            local function setBuffs(key, val)
                Account()[key] = val
                if CludesUI._applyTooltipBuffs then
                    CludesUI._applyTooltipBuffs()
                end
            end
            CludesUI.BuildInlineCog(ttStackRow._rightRegion, {
                gap = 9,
                disabled = ttBuffsOff,
                disabledTooltip = function()
                    return ttReskinOff() and "Reskin Tooltip" or "Show Player Buffs"
                end,
                title = "Tooltip Buffs",
                rows = {
                    {
                        type = "dropdown",
                        label = "Position",
                        values = { bottom = "Bottom", top = "Top", left = "Left", right = "Right" },
                        order = { "bottom", "top", "left", "right" },
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipBuffPosition or "bottom"
                        end,
                        set = function(val)
                            setBuffs("tooltipBuffPosition", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Icon Size",
                        min = 12,
                        max = 40,
                        step = 1,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipBuffSize or 20
                        end,
                        set = function(val)
                            setBuffs("tooltipBuffSize", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Icons Per Row",
                        min = 1,
                        max = 16,
                        step = 1,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipBuffsPerRow or 8
                        end,
                        set = function(val)
                            setBuffs("tooltipBuffsPerRow", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipBuffOffsetX or 0
                        end,
                        set = function(val)
                            setBuffs("tooltipBuffOffsetX", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipBuffOffsetY or 0
                        end,
                        set = function(val)
                            setBuffs("tooltipBuffOffsetY", val)
                        end,
                    },
                },
            })
        end

        -- Show Health Strip | Background
        -- Background, the unified tooltip background: controls BOTH the Blizzard
        -- tooltip reskin and the CUI custom tooltips (read live via
        -- CludesUI.GetTooltipBg). Defaults to the RESKIN palette (#111111 @ 92%);
        -- the next tooltip shown picks up changes, so no reload is needed. One
        -- setting, like Global Settings > Colors' Dark Mode Background: the opacity
        -- slider with its color as an inline swatch.
        local ttStripRow
        ttStripRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Health Strip",
            tooltip = "Shows the health bar on the bottom of unit tooltips.",
            getValue = function()
                return not stripHidden()
            end,
            setValue = function(val)
                Account().tooltipHideHealthStrip = not val
                if CludesUI._applyTooltipHealthStrip then
                    CludesUI._applyTooltipHealthStrip()
                end
                CludesUI:RefreshPage() -- update the strip cog disabled state
            end,
        }, {
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            tooltip = "Color and opacity of the tooltip background.",
            tooltipOnControl = "Background Opacity",
            trackWidth = 120,
            disabled = ttReskinOff,
            disabledTooltip = "Reskin Tooltip",
            getValue = function()
                local a = (CludesUIDB and CludesUIDB.tooltipBgOpacity) or CludesUI.RESKIN.TT_ALPHA
                return math.floor(a * 100 + 0.5)
            end,
            setValue = function(val)
                Account().tooltipBgOpacity = val / 100
                if CludesUI.SyncAuraTooltipSkin then
                    CludesUI.SyncAuraTooltipSkin()
                end
            end,
        })
        posY = posY - hgt

        if not CludesUI._prebuilding then
            local leftRgn = ttStripRow._leftRegion
            -- Health strip texture dropdown: the shared bar catalogue behind a
            -- "Blizzard" entry (the unset default). The triple lives on ns so the
            -- SharedMedia appender, which registers by table identity, gets the same
            -- tables on every build.
            if not mod.ttStripTex then
                local texture, nameList, sequence = CludesUI.BuildBarTextureTables()
                mod.ttStripTex = { tex = texture, names = nameList, order = sequence }
            end
            local st = mod.ttStripTex
            CludesUI.AppendSharedMediaTextures(st.names, st.order, nil, st.tex)
            local stripTexValues, stripTexOrder = { blizzard = "Blizzard" }, { "blizzard" }
            for _, key in ipairs(st.order) do
                if key ~= "---" then
                    stripTexValues[key] = st.names[key] or key
                    stripTexOrder[#stripTexOrder + 1] = key
                end
            end
            stripTexValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if key == "blizzard" then
                        return "Interface\\TargetingFrame\\UI-StatusBar"
                    end
                    return CludesUI.ResolveTexturePath(st.tex, key, nil)
                end,
            }
            local function applyStripStyle()
                if CludesUI._applyTooltipHealthStripStyle then
                    CludesUI._applyTooltipHealthStripStyle()
                end
            end
            CludesUI.BuildInlineCog(leftRgn, {
                gap = 9,
                disabled = function()
                    return ttReskinOff() or stripHidden()
                end,
                disabledTooltip = function()
                    return ttReskinOff() and "Reskin Tooltip" or "Show Health Strip"
                end,
                title = "Health Strip",
                rows = {
                    {
                        type = "dropdown",
                        label = "Texture",
                        values = stripTexValues,
                        order = stripTexOrder,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipHealthStripTexture or "blizzard"
                        end,
                        set = function(val)
                            Account().tooltipHealthStripTexture = (val ~= "blizzard") and val or nil
                            applyStripStyle()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Height",
                        min = 1,
                        max = 8,
                        step = 1,
                        get = function()
                            return CludesUIDB and CludesUIDB.tooltipHealthStripHeight or 3
                        end,
                        set = function(val)
                            Account().tooltipHealthStripHeight = (val ~= 3) and val or nil
                            applyStripStyle()
                        end,
                    },
                },
            })

            CludesUI.BuildInlineSwatches(ttStripRow._rightRegion, {
                {
                    tooltip = "Background Color",
                    getValue = function()
                        local c = CludesUIDB and CludesUIDB.tooltipBgColor
                        if c then
                            return c.r, c.g, c.b, 1
                        end
                        local R = CludesUI.RESKIN
                        return R.BG_R, R.BG_G, R.BG_B, 1
                    end,
                    setValue = function(r, g, b)
                        Account().tooltipBgColor = { r = r, g = g, b = b }
                        if CludesUI.SyncAuraTooltipSkin then
                            CludesUI.SyncAuraTooltipSkin()
                        end
                    end,
                },
            }, { size = 20, disabled = ttReskinOff, disabledTooltip = "Reskin Tooltip" })
        end

        -- Border Style | Border Size
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local tooltipBorder
            tooltipBorder, hgt = W:DualRow(
                hostFrame,
                posY,
                {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = ttReskinOff,
                    values = texValues,
                    order = texOrder,
                    getValue = function()
                        return CludesUIDB.tooltipBorderTexture or "solid"
                    end,
                    setValue = function(val)
                        local c, b = CludesUI.GetBorderStyleSelectDefaults(val)
                        CludesUIDB.tooltipBorderTexture = val
                        CludesUIDB.tooltipBorderOffsetX = nil
                        CludesUIDB.tooltipBorderOffsetY = nil
                        CludesUIDB.tooltipBorderBehind = b
                        CludesUIDB.tooltipBorderColor = c
                        if CludesUIDB.tooltipBorderThicknessPx then
                            CludesUIDB.tooltipBorderThicknessPx = false
                        end
                        if CludesUI.SyncAuraTooltipSkin then
                            CludesUI.SyncAuraTooltipSkin()
                        end
                        CludesUI:RefreshPage(true)
                    end,
                },
                BorderSizeSlider("tooltip", "Border Size", ttReskinOff, function()
                    if CludesUI.SyncAuraTooltipSkin then
                        CludesUI.SyncAuraTooltipSkin()
                    end
                end)
            )
            posY = posY - hgt
            -- The engine aura tooltip follows the border only when synced (the sync repaints the preview too)
            local function TooltipBorderApply()
                if CludesUI.SyncAuraTooltipSkin then
                    CludesUI.SyncAuraTooltipSkin()
                else
                    TooltipPreviewRepaint()
                end
            end
            AttachBorderControls(tooltipBorder, "tooltip", ttReskinOff, true, { apply = TooltipBorderApply })
            BorderOffsetRow("tooltip", ttReskinOff, TooltipBorderApply)
        end

        -----------------------------------------------------------------------
        --  Blizzard Bars, Popups & Buttons: on-screen elements that are not
        --  windows, so they get plain toggles here rather than cards on the
        --  Window Skins page.
        --
        --  EXACTLY TWO configs per DualRow below. W:DualRow takes a left and
        --  a right and SILENTLY DROPS a third -- a row shipped with three once
        --  rendered only two toggles and nothing errored.
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "BLIZZARD BARS, POPUPS & BUTTONS", posY)
        posY = posY - hgt

        -- The slot configs, laid out per client below: WoW Forever has no
        -- extra action button, so its toggle is not built there and the
        -- queue pair moves up a slot.
        local widgetCfg = {
            type = "toggle",
            text = "Reskin Widget Bars",
            tooltip = "Restyles Blizzard's on-screen progress bars (event objectives, nameplate counters)",
            getValue = function()
                return not CludesUIDB or CludesUIDB.reskinWidgetBars ~= false
            end,
            setValue = function(val)
                Account().reskinWidgetBars = val and true or false
                -- Reload-bound, like the window packs: turned OFF, the skin
                -- registers no events at all rather than running and
                -- returning early, so the decision is taken once at login.
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Widget bar reskin requires a UI reload to apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }
        local extraCfg = not CludesUI.IS_FOREVER
                and {
                    type = "toggle",
                    text = "Reskin Extra Action Buttons",
                    getValue = function()
                        -- DEFAULT OFF: opt-in, so nil reads as unchecked.
                        return CludesUIDB and CludesUIDB.reskinExtraActionButton == true
                    end,
                    setValue = function(val)
                        Account().reskinExtraActionButton = val and true or false
                    end,
                }
            or nil
        local queueCfg = {
            type = "toggle",
            text = "Reskin Queue Popup",
            tooltip = "Reskins the dungeon and battleground queue accept popups and adds an accept countdown timer bar to the dungeon one.",
            getValue = function()
                -- Independent, default on (not tied to any master reskin toggle).
                return not CludesUIDB or CludesUIDB.reskinQueuePopup ~= false
            end,
            setValue = function(val)
                Account().reskinQueuePopup = val
                if not val and CludesUI.ShowConfirmPopup then
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Disabling queue popup reskin requires a UI reload to restore Blizzard's default style.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end
            end,
        }
        local timerCfg = {
            type = "toggle",
            text = "Show Queue Timer",
            getValue = function()
                return not CludesUIDB or CludesUIDB.showQueueTimer ~= false
            end,
            setValue = function(val)
                Account().showQueueTimer = val
                CludesUI:RefreshPage() -- update the style cog + swatch disabled states
            end,
        }

        -- The regions the inline controls below sit on, whichever slot their
        -- toggle took.
        local hudRow, queueRow, widgetRgn, queueRgn, timerRgn
        if extraCfg then
            hudRow, hgt = W:DualRow(hostFrame, posY, widgetCfg, extraCfg)
            posY = posY - hgt
            queueRow, hgt = W:DualRow(hostFrame, posY, queueCfg, timerCfg)
            posY = posY - hgt
            widgetRgn = hudRow and hudRow._leftRegion
            queueRgn = queueRow and queueRow._leftRegion
            timerRgn = queueRow and queueRow._rightRegion
        else
            hudRow, hgt = W:DualRow(hostFrame, posY, widgetCfg, queueCfg)
            posY = posY - hgt
            queueRow, hgt = W:DualRow(hostFrame, posY, timerCfg, CludesUI.BlankRowCfg())
            posY = posY - hgt
            widgetRgn = hudRow and hudRow._leftRegion
            queueRgn = hudRow and hudRow._rightRegion
            timerRgn = queueRow and queueRow._leftRegion
        end

        -- Minimum widget bar size (plate-hosted covers), a cog on "Reskin Widget
        -- Bars": the floor below which a shrunken nameplate's bar scales itself
        -- up. 0 = off (default, mirror Blizzard's rect exactly).
        if widgetRgn and not CludesUI._prebuilding then
            local lrgn = widgetRgn
            local function CogOff()
                -- Same default-on test the toggle itself uses: nil means on.
                return not (not CludesUIDB or CludesUIDB.reskinWidgetBars ~= false)
            end
            CludesUI.BuildInlineCog(lrgn, {
                anchorTo = lrgn._control,
                disabled = CogOff,
                disabledTooltip = "Reskin Widget Bars",
                tip = "Smallest on-screen size a reskinned bar is drawn at.\n\n"
                    .. "Widget bars on a nameplate inherit that nameplate's scale, so "
                    .. "they come out tiny on small units. Below this size the bar is "
                    .. "scaled up instead, text and all.\n\nSet to 0 to mirror "
                    .. "Blizzard's size exactly.",
                title = "Widget Bar Size",
                rows = {
                    {
                        type = "slider",
                        label = "Minimum",
                        min = 0,
                        max = 24,
                        step = 1,
                        get = function()
                            local val = CludesUIDB and CludesUIDB.widgetBarMinSize
                            if type(val) == "number" then
                                return val
                            end
                            return 0
                        end,
                        set = function(val)
                            Account().widgetBarMinSize = val
                            -- Live: the seam re-reads and books one refresh; nil
                            -- only while the reskin is off (cog greyed then).
                            if CludesUI._HUDWidgetSetMinSize then
                                CludesUI._HUDWidgetSetMinSize()
                            end
                        end,
                    },
                },
            })
        end

        -- Red "!" warning left of the Reskin Queue Popup toggle while a mover addon
        -- that conflicts with the reskin is loaded
        local _eqolLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EnhanceQoL")
        if _eqolLoaded and queueRgn and not CludesUI._prebuilding then
            local region = queueRgn
            local toggle = region._control
            if toggle then
                local fontFile = (CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                local warnBtn = CreateFrame("Button", nil, region)
                warnBtn:SetSize(28, 28)
                warnBtn:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
                warnBtn:SetFrameLevel(region:GetFrameLevel() + 5)
                local warnFS = warnBtn:CreateFontString(nil, "OVERLAY")
                warnFS:SetFont(fontFile, 28, "")
                warnFS:SetTextColor(1, 0.3, 0.3, 1)
                warnFS:SetText("!")
                warnFS:SetPoint("CENTER")
                warnBtn:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(
                        self,
                        "Enhance QoL's Mover may conflict with this reskin. The reskin is auto-disabled when its mover is active."
                    )
                end)
                warnBtn:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end
        end

        -- Style cog + countdown text color swatch (left of it) on the Show Queue Timer toggle.
        if timerRgn and not CludesUI._prebuilding then
            local Pix = CludesUI.PanelPP
            local QT = CludesUI.QUEUE_TIMER
            local function timerOff()
                return CludesUIDB and CludesUIDB.showQueueTimer == false
            end
            local function Get(key, default)
                return (CludesUIDB and CludesUIDB[key]) or default
            end
            local function Set(key, val)
                Account()[key] = val
                if CludesUI.RefreshQueueTimerStyle then
                    CludesUI.RefreshQueueTimerStyle()
                end
            end

            CludesUI.BuildInlineCog(timerRgn, {
                disabled = timerOff,
                disabledTooltip = "Show Queue Timer",
                title = "Queue Timer Style",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        get = function()
                            return Get("queueTimerTextSize", QT.TEXT_SIZE)
                        end,
                        set = function(val)
                            Set("queueTimerTextSize", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Bar Height",
                        min = 4,
                        max = 24,
                        step = 1,
                        get = function()
                            return Get("queueTimerBarHeight", QT.BAR_HEIGHT)
                        end,
                        set = function(val)
                            Set("queueTimerBarHeight", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Offset Y",
                        min = -20,
                        max = 20,
                        step = 1,
                        tooltip = "Moves the countdown number up or down relative to the bar.",
                        get = function()
                            return Get("queueTimerTextOffsetY", QT.TEXT_OFFSET_Y)
                        end,
                        set = function(val)
                            Set("queueTimerTextOffsetY", val)
                        end,
                    },
                },
            })

            local qtSwatch, qtSwatchRefresh = CludesUI.BuildColorSwatch(
                timerRgn,
                timerRgn:GetFrameLevel() + 5,
                function()
                    local c = CludesUIDB and CludesUIDB.queueTimerTextColor
                    return (c and c.r) or QT.TEXT_R, (c and c.g) or QT.TEXT_G, (c and c.b) or QT.TEXT_B
                end,
                function(r, g, b)
                    Set("queueTimerTextColor", { r = r, g = g, b = b })
                end,
                false,
                20
            )
            Pix.Point(qtSwatch, "RIGHT", timerRgn._lastInline or timerRgn._control, "LEFT", -8, 0)
            timerRgn._lastInline = qtSwatch
            qtSwatch:HookScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, "Countdown Text Color")
            end)
            qtSwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Called at build time too: the refresh list only runs on page show.
            local function UpdQueueTimerState()
                local off = timerOff()
                qtSwatch:SetAlpha(off and 0.15 or 1)
                qtSwatch:EnableMouse(not off)
                qtSwatchRefresh()
            end
            CludesUI.RegisterWidgetRefresh(UpdQueueTimerState)
            UpdQueueTimerState()
        end

        return math.abs(posY)
    end

    ---------------------------------------------------------------------------
    --  Character Sheet card content (Blizzard Window Skins page). The style
    --  choice lives on the card header dropdown; everything here is the
    --  window's sub-settings, built as direct children of the page wrapper so
    --  inline search and nav deep-links still see them.
    ---------------------------------------------------------------------------
    -- Section headers inside window-skin cards: title indented 5px to sit
    -- with the card chrome (the divider stays full width).
    local function WSCardSection(hostFrame, textValue, posY)
        local W = CludesUI.Widgets
        local hf, hgt = W:SectionHeader(hostFrame, textValue, posY)
        if hf and hf._label then
            CludesUI.PanelPP.Point(hf._label, "BOTTOMLEFT", hf, "BOTTOMLEFT", 5, 8)
        end
        return hf, hgt
    end

    local function BuildCharacterSheetContent(hostFrame, posY)
        local W = CludesUI.Widgets
        local _, hgt
        local Pix = CludesUI.PanelPP

        local function themedOff()
            return CludesUIDB and CludesUIDB.themedCharacterSheet == false
        end
        -- The card's Blizz Default, as the sheet runs it this session (the
        -- choice is latched at load; a change reloads).
        local stock = mod.CharSheetStock()
        -- Blizz Default only: "Blizzard UI Color" (on unless turned off)
        -- paints every stat category in Blizzard's yellow, so the colour
        -- swatches stand down while it is on. On WoW Forever Blizz Default
        -- keeps Blizzard's own stats list, colours included, so they always
        -- stand down.
        local function blizzColorsOn()
            return stock
                and (CludesUI.IS_FOREVER or not (CludesUIDB and CludesUIDB.charSheetBlizzColors == false))
        end

        local function AttachDisabledOverlay(target)
            local block = CreateFrame("Frame", nil, target)
            block:SetAllPoints(target)
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            local backdrop = CludesUI.SolidTex(block, "BACKGROUND", 0, 0, 0, 0)
            backdrop:SetAllPoints()
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(block, CludesUI.DisabledTooltip("Character Sheet"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function refresh()
                if themedOff() then
                    block:Show()
                    target:SetAlpha(0.3)
                else
                    block:Hide()
                    target:SetAlpha(1)
                end
            end
            CludesUI.RegisterWidgetRefresh(refresh)
            refresh()
        end

        -- Blizz Default keeps Blizzard's own character sheet with our stats
        -- section, slot text and socket strip: the gem icons and Icon Zoom
        -- are the CludesUI sheet's own, so Gems leaves the Item Details
        -- list and Icon Zoom greys out there.
        local function csGate(conf)
            if stock then
                conf.disabled = function()
                    return true
                end
                conf.disabledTooltip = "Character Sheet: Blizz Default"
                conf.requireState = "disabled"
                conf.rawTooltip = nil
                conf._blizzGated = true
            end
            return conf
        end

        ---------------------------------------------------------------------------
        --  CORE OPTIONS
        ---------------------------------------------------------------------------
        _, hgt = WSCardSection(hostFrame, "CORE OPTIONS", posY)
        posY = posY - hgt

        -- Blizzard's own slot icons under Blizz Default (the inspect sheet
        -- keeps its stored zoom).
        local iconZoomCfg = csGate({
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 0.20,
            step = 0.01,
            tooltip = "Crops the border of the equipment-slot item icons on the character and inspect sheets. 0 shows the full icon. Only affects the themed character sheet.",
            getValue = function()
                return (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07
            end,
            setValue = function(val)
                Account().charSheetIconZoom = val
                if CludesUI._refreshCharSheetIconZoom then
                    CludesUI._refreshCharSheetIconZoom()
                end
            end,
        })

        if not CludesUI.IS_FOREVER then
            -- Mythic+ Rating | Item Details: a checkbox dropdown, a view over
            -- the item level, upgrade track and gem keys (each on unless
            -- false). The gem icons are the CludesUI sheet's own, so Blizz
            -- Default leaves Gems out of the list. Tertiary Stats only adds to
            -- Stat Letters, so it locks while that is off.
            local function statLettersOff()
                return not (CludesUIDB and CludesUIDB.charSheetItemStats == true)
            end
            local ITEM_DETAILS = {
                { key = "showItemLevel", label = "Item Level", refresh = "_refreshItemLevelVisibility" },
                {
                    key = "showUpgradeTrack",
                    label = "Upgrade Track",
                    refresh = "_refreshUpgradeTrackVisibility",
                },
                {
                    key = "charSheetItemStats",
                    label = "Stat Letters",
                    refresh = "_refreshCharSheetSlotLabels",
                    optIn = true,
                },
                {
                    key = "charSheetItemStatsTertiary",
                    label = "Tertiary Stats",
                    refresh = "_refreshCharSheetSlotLabels",
                    optIn = true,
                    lockedFn = statLettersOff,
                    excludeFromSummaryFn = statLettersOff,
                    lockedTooltip = CludesUI.DisabledTooltip("Stat Letters"),
                },
            }
            if not stock then
                ITEM_DETAILS[#ITEM_DETAILS + 1] =
                    { key = "showGems", label = "Gems", refresh = "_refreshGemsVisibility" }
            end
            local coreRow1
            coreRow1, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Mythic+ Rating",
                tooltip = "Display your Mythic+ rating above the item level on the character sheet.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.showMythicRating or false
                end,
                setValue = function(val)
                    Account().showMythicRating = val
                    if CludesUI._updateMythicRatingDisplay then
                        CludesUI._updateMythicRatingDisplay()
                    end
                end,
            }, {
                type = "label",
                text = "Item Details",
                tooltip = "Choose what shows on each equipped item.",
            })
            posY = posY - hgt
            if not CludesUI._prebuilding then
                local region = coreRow1._rightRegion
                -- Keys are on unless false; an optIn key is off unless true.
                local refreshOf, optIn = {}, {}
                for _, item in ipairs(ITEM_DETAILS) do
                    refreshOf[item.key] = item.refresh
                    optIn[item.key] = item.optIn
                end
                local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    region,
                    210,
                    region:GetFrameLevel() + 2,
                    ITEM_DETAILS,
                    function(key)
                        if optIn[key] then
                            return CludesUIDB and CludesUIDB[key] == true or false
                        end
                        return not (CludesUIDB and CludesUIDB[key] == false)
                    end,
                    function(key, val)
                        Account()[key] = val
                        local refresh = CludesUI[refreshOf[key]]
                        if refresh then
                            refresh()
                        end
                    end
                )
                Pix.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
                region._control = cbDD
                region._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            AttachDisabledOverlay(coreRow1)

            -- Socket Panel | Icon Zoom (greyed under Blizz Default). Both
            -- looks show the socket strip: under Blizz Default it hangs below
            -- Blizzard's sheet in its tab art
            -- (CludesUIBlizzardSkin_SocketPanel.lua).
            local socketRow
            socketRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Socket Panel",
                tooltip = "Show a panel of equipped-gear sockets on the character sheet; click a socket to gem it.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.charSheetSocketPanel ~= false
                end,
                setValue = function(val)
                    Account().charSheetSocketPanel = val
                    if CludesUI._refreshCharSheetSocketPanel then
                        CludesUI._refreshCharSheetSocketPanel()
                    end
                    CludesUI:RefreshPage()
                end,
            }, iconZoomCfg)
            posY = posY - hgt
            AttachDisabledOverlay(socketRow)

            -- Inline cog on Socket Panel: stat letters on the gem icons (off
            -- unless turned on).
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(socketRow._leftRegion, {
                    disabled = function()
                        return CludesUIDB and CludesUIDB.charSheetSocketPanel == false
                    end,
                    disabledTooltip = "Socket Panel",
                    title = "Socket Panel Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Stat Letters",
                            tooltip = "Shows each socketed gem's secondary stats as letters on its icon, largest first (C Crit, H Haste, M Mastery, V Versatility).",
                            get = function()
                                return CludesUIDB and CludesUIDB.charSheetSocketPanelStats == true or false
                            end,
                            set = function(val)
                                Account().charSheetSocketPanelStats = val
                                if CludesUI._refreshCharSheetSocketPanel then
                                    CludesUI._refreshCharSheetSocketPanel()
                                end
                            end,
                        },
                    },
                })
            end
        else
            -- WoW Forever has no Mythic+, item level text, upgrade tracks or
            -- sockets: the track key shows each item's main and secondary stat
            -- (or its armor when it has none) and each weapon's damage per
            -- second there. Icon Zoom greys out under Blizz Default.
            local statsRow
            statsRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Show Item Stats",
                tooltip = "Show each item's main and secondary stat (or its armor) and each weapon's damage per second beside its slot.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.showUpgradeTrack ~= false
                end,
                setValue = function(val)
                    Account().showUpgradeTrack = val
                    if CludesUI._refreshUpgradeTrackVisibility then
                        CludesUI._refreshUpgradeTrackVisibility()
                    end
                end,
            }, iconZoomCfg)
            posY = posY - hgt
            AttachDisabledOverlay(statsRow)
        end

        -- Enchants (this sheet and the inspect sheet): a view over the
        -- sheet's shown key (on unless false) and its names key; None leaves
        -- the names key as it was. WoW Forever's enchants carry no icon, so
        -- the middle mode is the plain name there and Text the colored one.
        -- The Text Size cog shows only while the enchants show as text.
        local function EnchantValues()
            if CludesUI.IS_FOREVER then
                return { none = "None", icons = "Text", text = "Colored Text" }
            end
            return { none = "None", icons = "Icons + Hover", text = "Text" }
        end
        local function EnchantMode(showKey, namesKey)
            if CludesUIDB and CludesUIDB[showKey] == false then
                return "none"
            end
            if CludesUIDB and CludesUIDB[namesKey] then
                return "text"
            end
            return "icons"
        end
        local function SetEnchantMode(showKey, namesKey, val)
            Account()[showKey] = val ~= "none"
            if val ~= "none" then
                CludesUIDB[namesKey] = val == "text"
            end
        end
        local function EnchantTextShown(showKey, namesKey)
            local mode = EnchantMode(showKey, namesKey)
            return mode == "text" or (CludesUI.IS_FOREVER and mode == "icons")
        end

        local enchGemRow
        enchGemRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Enchants",
            tooltip = "How enchants show beside each item.",
            values = EnchantValues(),
            order = { "none", "icons", "text" },
            getValue = function()
                return EnchantMode("showEnchants", "charSheetEnchantNames")
            end,
            setValue = function(val)
                SetEnchantMode("showEnchants", "charSheetEnchantNames", val)
                if CludesUI._refreshEnchantsVisibility then
                    CludesUI._refreshEnchantsVisibility()
                end
                if CludesUI._refreshCharSheetSlotLabels then
                    CludesUI._refreshCharSheetSlotLabels()
                end
                -- Shows or hides the Text Size cog
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Show PvP Item Level",
            tooltip = "Display your PvP item level above the Mythic+ rating on the character sheet.",
            getValue = function()
                return CludesUIDB and CludesUIDB.showPvpItemLevel or false
            end,
            setValue = function(val)
                Account().showPvpItemLevel = val
                if CludesUI._updatePvpIlvlDisplay then
                    CludesUI._updatePvpIlvlDisplay()
                end
            end,
        })
        posY = posY - hgt
        AttachDisabledOverlay(enchGemRow)

        if not CludesUI._prebuilding then
            local cogBtn = CludesUI.BuildInlineCog(enchGemRow._leftRegion, {
                title = "Enchant Text",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function()
                            return (CludesUIDB and CludesUIDB.charSheetEnchantSize) or 9
                        end,
                        set = function(val)
                            Account().charSheetEnchantSize = val
                            if CludesUI._refreshCharSheetSlotLabels then
                                CludesUI._refreshCharSheetSlotLabels()
                            end
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                cogBtn:SetShown(EnchantTextShown("showEnchants", "charSheetEnchantNames"))
            end
            CludesUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end

        -- Durability | Season Panel. The panel greys out with the sheet off;
        -- durability stays live either way. The panel is retail only.
        local seasonCfg
        if not CludesUI.IS_FOREVER then
            seasonCfg = {
                type = "toggle",
                text = "Season Panel",
                tooltip = "Show an Omnium Folio shortcut to the right of the socket panel during Midnight seasons. The cog adds a Great Vault shortcut.",
                disabled = themedOff,
                disabledTooltip = "Character Sheet",
                getValue = function()
                    return not (CludesUIDB and CludesUIDB.charSheetSeasonPanel == false)
                end,
                setValue = function(val)
                    Account().charSheetSeasonPanel = val
                    if CludesUI._refreshCharSheetSocketPanel then
                        CludesUI._refreshCharSheetSocketPanel()
                    end
                    CludesUI:RefreshPage()
                end,
            }
        end
        local durSeasonRow
        durSeasonRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Item Durability",
            tooltip = "Show total equipped durability above the character model, colored from green to red.",
            getValue = function()
                return CludesUIDB and CludesUIDB.showCharSheetDurability or false
            end,
            setValue = function(val)
                Account().showCharSheetDurability = val
                if val then
                    if CludesUIDB.charSheetDurabilityLocation == nil then
                        CludesUIDB.charSheetDurabilityLocation = "model"
                    end
                    if CludesUIDB.charSheetDurabilityShowLabel == nil then
                        CludesUIDB.charSheetDurabilityShowLabel = true
                    end
                end
                if CludesUI._updateCharSheetDurability then
                    CludesUI._updateCharSheetDurability()
                end
                if CludesUI._updateScrollHeaderOffset then
                    CludesUI._updateScrollHeaderOffset()
                end
                CludesUI:RefreshPage()
            end,
        }, seasonCfg or CludesUI.BlankRowCfg())
        posY = posY - hgt

        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(durSeasonRow._leftRegion, {
                disabled = function()
                    return not (CludesUIDB and CludesUIDB.showCharSheetDurability)
                end,
                disabledTooltip = "Show Item Durability",
                title = "Durability Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Location",
                        values = { model = "Above Model", header = "Stats Header", footer = "Frame Footer" },
                        order = { "model", "header", "footer" },
                        get = function()
                            return CludesUIDB and CludesUIDB.charSheetDurabilityLocation or "model"
                        end,
                        set = function(val)
                            Account().charSheetDurabilityLocation = val
                            if CludesUI._updateCharSheetDurability then
                                CludesUI._updateCharSheetDurability()
                            end
                            if CludesUI._updateScrollHeaderOffset then
                                CludesUI._updateScrollHeaderOffset()
                            end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Label",
                        tooltip = 'Prefix the durability percent with "Durability:".',
                        get = function()
                            return not CludesUIDB or CludesUIDB.charSheetDurabilityShowLabel ~= false
                        end,
                        set = function(val)
                            Account().charSheetDurabilityShowLabel = val
                            if CludesUI._updateCharSheetDurability then
                                CludesUI._updateCharSheetDurability()
                            end
                        end,
                    },
                },
            })

            -- Inline cog on Season Panel: the Great Vault shortcut is its own opt-in.
            if seasonCfg then
                CludesUI.BuildInlineCog(durSeasonRow._rightRegion, {
                    disabled = function()
                        return themedOff() or (CludesUIDB and CludesUIDB.charSheetSeasonPanel == false)
                    end,
                    disabledTooltip = function()
                        return themedOff() and "Character Sheet" or "Season Panel"
                    end,
                    title = "Season Panel Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Great Vault Shortcut",
                            tooltip = "Add a Great Vault button to the Season Panel.",
                            get = function()
                                return CludesUIDB and CludesUIDB.charSheetSeasonVault == true or false
                            end,
                            set = function(val)
                                Account().charSheetSeasonVault = val
                                if CludesUI._refreshCharSheetSocketPanel then
                                    CludesUI._refreshCharSheetSocketPanel()
                                end
                            end,
                        },
                    },
                })
            end
        end

        _, hgt = W:Spacer(hostFrame, posY, 10)
        posY = posY - hgt

        ---------------------------------------------------------------------------
        --  GEAR FLYOUT
        ---------------------------------------------------------------------------
        -- The popup of same-slot items from an equipped slot. Item levels and
        -- stat letters enhance Blizzard's own flyout, so they stay live with the
        -- sheet off; the slot arrows belong to the sheet and grey out with it.
        -- The sheet's own slot letters live under Item Details (Stat Letters,
        -- Tertiary Stats). All off unless turned on.
        _, hgt = WSCardSection(hostFrame, "GEAR FLYOUT", posY)
        posY = posY - hgt

        local flyoutStatsCfg
        if not CludesUI.IS_FOREVER then
            flyoutStatsCfg = {
                type = "toggle",
                text = "Show Item Stats",
                tooltip = "Shows each item's secondary stats as letters in the gear flyout, largest first (C Crit, H Haste, M Mastery, V Versatility), so items with the same icon are told apart.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.flyoutItemStats or false
                end,
                setValue = function(val)
                    Account().flyoutItemStats = val
                    CludesUI:RefreshPage()
                end,
            }
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Item Levels",
            tooltip = "Shows the item level on each item in the character sheet gear flyout (the popup of same-slot bag items that appears when hovering an equipped slot), coloured by quality.",
            getValue = function()
                return CludesUIDB and CludesUIDB.flyoutItemLevels or false
            end,
            setValue = function(val)
                Account().flyoutItemLevels = val
            end,
        }, flyoutStatsCfg or CludesUI.BlankRowCfg())
        posY = posY - hgt

        if not CludesUI.IS_FOREVER then
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Tertiary Stat Letters",
                tooltip = "Adds Leech, Avoidance and Speed (L, A, S) in smaller letters behind the secondary stats in the gear flyout.",
                disabled = function()
                    return not (CludesUIDB and CludesUIDB.flyoutItemStats)
                end,
                disabledTooltip = "Show Item Stats",
                getValue = function()
                    return CludesUIDB and CludesUIDB.flyoutItemStatsTertiary == true or false
                end,
                setValue = function(val)
                    Account().flyoutItemStatsTertiary = val
                end,
            }, {
                type = "toggle",
                text = "Hide Slot Flyout Arrows",
                tooltip = "Hide the arrows beside equipment slots on the Equipment tab. The slot flyouts remain usable.",
                disabled = themedOff,
                disabledTooltip = "Character Sheet",
                getValue = function()
                    return CludesUIDB and CludesUIDB.charSheetHideSlotFlyoutArrows == true
                end,
                setValue = function(val)
                    Account().charSheetHideSlotFlyoutArrows = val
                    if CludesUI._refreshCharSheetSlotFlyoutArrows then
                        CludesUI._refreshCharSheetSlotFlyoutArrows()
                    end
                end,
            })
            posY = posY - hgt
        end

        _, hgt = W:Spacer(hostFrame, posY, 10)
        posY = posY - hgt

        ---------------------------------------------------------------------------
        --  STAT DISPLAY
        ---------------------------------------------------------------------------
        _, hgt = WSCardSection(hostFrame, "STAT DISPLAY", posY)
        posY = posY - hgt

        -- Every control here is a view over the keys the sheet already reads
        -- (showStatCategory_*, the Secondary/Tertiary Raw and Both pairs, the
        -- highlight pair, showManaStat, showCrest_*, statCategoryColors):
        -- nothing new is stored and nothing is written until a control changes.
        -- key = the showStatCategory_ suffix, color = the statCategoryColors key.
        local STAT_SECTIONS = {
            {
                key = "Attributes",
                label = "Attributes",
                color = "Attributes",
                def = { r = 0.298, g = 0.788, b = 0.941 },
            },
            {
                key = "SecondaryStats",
                label = "Secondary Stats",
                color = "Secondary Stats",
                def = { r = 0.471, g = 0.255, b = 0.784 },
            },
            {
                key = "Tertiary",
                label = "Tertiary Stats",
                color = "Tertiary Stats",
                def = { r = 0.859, g = 0.325, b = 0.855 },
            },
            {
                key = "Attack",
                label = "Attack",
                color = "Attack",
                def = { r = 1, g = 0.353, b = 0.122 },
            },
            {
                key = "Defense",
                label = "Defense",
                color = "Defense",
                def = { r = 0.247, g = 0.655, b = 1 },
            },
            {
                key = "Crests",
                label = "Crests",
                color = "Crests",
                def = { r = 1, g = 0.784, b = 0.341 },
            },
            {
                key = "PvP",
                label = "PvP",
                color = "PvP",
                def = { r = 0.671, g = 0.431, b = 0.349 },
            },
        }
        -- Same test as the sheet's own UpdateStatCategoryVisibility
        local function SectionShown(key)
            return not (CludesUIDB and CludesUIDB["showStatCategory_" .. key] == false)
        end
        local function SecOrTerShown()
            return SectionShown("SecondaryStats") or SectionShown("Tertiary")
        end

        -- Stat Sections (checkbox dropdown + cog) | Show Diminishing Returns
        local sectionsRow
        sectionsRow, hgt = W:DualRow(hostFrame, posY, { type = "label", text = "Stat Sections" }, {
            type = "toggle",
            text = "Show Diminishing Returns",
            tooltip = "Adds diminishing returns info to Secondary and Tertiary stat tooltips.",
            getValue = function()
                return CludesUIDB and CludesUIDB.showAdjustedStats or false
            end,
            setValue = function(val)
                Account().showAdjustedStats = val
            end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            local leftRgn = sectionsRow._leftRegion
            -- Each section's colour swatch sits on its row of the dropdown; dimmed while
            -- Blizzard UI Color applies or the section is unchecked.
            local itemList = {}
            for idx, sec in ipairs(STAT_SECTIONS) do
                local key, labelText, colorKey, def = sec.key, sec.label, sec.color, sec.def
                itemList[idx] = {
                    key = key,
                    label = labelText,
                    swatch = {
                        get = function()
                            local c = CludesUIDB
                                and CludesUIDB.statCategoryColors
                                and CludesUIDB.statCategoryColors[colorKey]
                            if c then
                                return c.r, c.g, c.b, 1
                            end
                            return def.r, def.g, def.b, 1
                        end,
                        set = function(r, g, b)
                            if not CludesUIDB then
                                CludesUIDB = {}
                            end
                            if not CludesUIDB.statCategoryColors then
                                CludesUIDB.statCategoryColors = {}
                            end
                            if not CludesUIDB.statCategoryUseColor then
                                CludesUIDB.statCategoryUseColor = {}
                            end
                            CludesUIDB.statCategoryColors[colorKey] = { r = r, g = g, b = b }
                            CludesUIDB.statCategoryUseColor[colorKey] = true
                            if CludesUI._refreshCharacterSheetColors then
                                CludesUI._refreshCharacterSheetColors()
                            end
                        end,
                        disabled = function()
                            return blizzColorsOn() or not SectionShown(key)
                        end,
                        -- Two requirements with opposite wording: pre-wrapped, so raw.
                        disabledTooltip = function()
                            if blizzColorsOn() then
                                return not CludesUI.IS_FOREVER
                                        and CludesUI.DisabledTooltip("Blizzard UI Color", "disabled")
                                    or nil
                            end
                            return CludesUI.DisabledTooltip(labelText)
                        end,
                        rawTooltip = true,
                    },
                }
            end
            local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                leftRgn,
                210,
                leftRgn:GetFrameLevel() + 2,
                itemList,
                SectionShown,
                function(key, val)
                    Account()["showStatCategory_" .. key] = val
                    if CludesUI._updateStatCategoryVisibility then
                        CludesUI._updateStatCategoryVisibility()
                    end
                    local sf = CharacterFrame and CludesUI._GetFFD(CharacterFrame).scrollFrame
                    if sf then
                        sf:SetVerticalScroll(0)
                    end
                    CludesUI:RefreshPage()
                end
            )
            Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Cog: the per-section extras the old per-section rows held
            local rowList = {
                {
                    type = "toggle",
                    label = "Show Mana",
                    tooltip = "Adds Mana to the Attributes section.",
                    disabled = function()
                        return not SectionShown("Attributes")
                    end,
                    disabledTooltip = "Attributes",
                    get = function()
                        return CludesUIDB and CludesUIDB.showManaStat == true
                    end,
                    set = function(val)
                        Account().showManaStat = val
                        if CludesUI._refreshStatsVisibility then
                            CludesUI._refreshStatsVisibility()
                        end
                    end,
                },
                {
                    type = "reordercheck",
                    label = "Crests",
                    ddWidth = 150,
                    disabled = function()
                        return not SectionShown("Crests")
                    end,
                    disabledTooltip = "Crests",
                    items = {
                        { key = "Myth", label = "Myth", fixed = true },
                        { key = "Hero", label = "Hero", fixed = true },
                        { key = "Champion", label = "Champion", fixed = true },
                        { key = "Veteran", label = "Veteran", fixed = true },
                        { key = "Adventurer", label = "Adventurer", fixed = true },
                    },
                    get = function(key)
                        return not (CludesUIDB and CludesUIDB["showCrest_" .. key] == false)
                    end,
                    set = function(key, val)
                        Account()["showCrest_" .. key] = val
                        if CludesUI._refreshStatsVisibility then
                            CludesUI._refreshStatsVisibility()
                        end
                    end,
                },
            }
            -- Blizz Default only (not WoW Forever, whose sheet has no
            -- CludesUI stats section): on unless turned off.
            if stock and not CludesUI.IS_FOREVER then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Blizzard UI Color",
                    tooltip = "Shows the item level and stat titles in Blizzard's yellow.",
                    get = function()
                        return not (CludesUIDB and CludesUIDB.charSheetBlizzColors == false)
                    end,
                    set = function(val)
                        Account().charSheetBlizzColors = val
                        if CludesUI._refreshCharacterSheetColors then
                            CludesUI._refreshCharacterSheetColors()
                        end
                        CludesUI:RefreshPage()
                    end,
                }
            end
            CludesUI.BuildInlineCog(leftRgn, {
                title = "Stat Section Settings",
                rows = rowList,
                disabled = themedOff,
                disabledTooltip = "Character Sheet",
            })
        end
        AttachDisabledOverlay(sectionsRow)

        -- Secondary/Tertiary Text | Secondary/Tertiary Highlights (both write
        -- the Secondary and the Tertiary keys; the Secondary pair is shown)
        local stRow
        stRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Secondary/Tertiary Text",
            tooltip = "How Secondary and Tertiary stat values are shown.",
            values = { pct = "Percent", value = "Value", both = "Value (Percent)" },
            order = { "pct", "value", "both" },
            disabled = function()
                return not SecOrTerShown()
            end,
            disabledTooltip = "Secondary Stats or Tertiary Stats",
            getValue = function()
                -- Both wins over Raw, as on the sheet
                if CludesUIDB and CludesUIDB.showSecondaryBoth then
                    return "both"
                end
                if CludesUIDB and CludesUIDB.showSecondaryRaw then
                    return "value"
                end
                return "pct"
            end,
            setValue = function(val)
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                local raw, both = val == "value", val == "both"
                CludesUIDB.showSecondaryRaw, CludesUIDB.showSecondaryBoth = raw, both
                CludesUIDB.showTertiaryRaw, CludesUIDB.showTertiaryBoth = raw, both
                if CludesUI._refreshStatFormats then
                    CludesUI._refreshStatFormats()
                end
            end,
        }, {
            type = "toggle",
            text = "Secondary/Tertiary Highlights",
            tooltip = "Hovering a Secondary or Tertiary stat highlights the gear that has it.",
            disabled = function()
                return not SecOrTerShown()
            end,
            disabledTooltip = "Secondary Stats or Tertiary Stats",
            getValue = function()
                return CludesUIDB
                        and (CludesUIDB.highlightSecondaryItems == true or CludesUIDB.highlightTertiaryItems == true)
                    or false
            end,
            setValue = function(val)
                Account().highlightSecondaryItems = val
                CludesUIDB.highlightTertiaryItems = val
            end,
        })
        posY = posY - hgt
        AttachDisabledOverlay(stRow)

        ---------------------------------------------------------------------------
        --  INSPECT SHEET
        ---------------------------------------------------------------------------
        _, hgt = WSCardSection(hostFrame, "INSPECT SHEET", posY)
        posY = posY - hgt

        local themedInspectSheetRow
        themedInspectSheetRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Inspect Sheet",
            tooltip = "Applies CludesUI theme styling to the inspect sheet window.",
            getValue = function()
                return not CludesUIDB or CludesUIDB.themedInspectSheet ~= false
            end,
            setValue = function(val)
                Account().themedInspectSheet = val
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Inspect Sheet theme setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Enchants",
            tooltip = "How enchants show beside each item.",
            values = EnchantValues(),
            order = { "none", "icons", "text" },
            disabled = function()
                return CludesUIDB and CludesUIDB.themedInspectSheet == false
            end,
            disabledTooltip = "Inspect Sheet",
            getValue = function()
                return EnchantMode("inspectShowEnchants", "inspectEnchantNames")
            end,
            setValue = function(val)
                SetEnchantMode("inspectShowEnchants", "inspectEnchantNames", val)
                if CludesUI._refreshInspectSlotLabels then
                    CludesUI._refreshInspectSlotLabels()
                end
                -- Shows or hides the Text Size cog
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt

        -- Text Size (unset follows the character sheet's), shown only while
        -- the enchants show as text.
        if not CludesUI._prebuilding then
            local cogBtn = CludesUI.BuildInlineCog(themedInspectSheetRow._rightRegion, {
                title = "Enchant Text",
                disabled = function()
                    return CludesUIDB and CludesUIDB.themedInspectSheet == false
                end,
                disabledTooltip = "Inspect Sheet",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function()
                            return (
                                CludesUIDB
                                and (CludesUIDB.inspectEnchantSize or CludesUIDB.charSheetEnchantSize)
                            ) or 9
                        end,
                        set = function(val)
                            Account().inspectEnchantSize = val
                            if CludesUI._refreshInspectSlotLabels then
                                CludesUI._refreshInspectSlotLabels()
                            end
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                cogBtn:SetShown(EnchantTextShown("inspectShowEnchants", "inspectEnchantNames"))
            end
            CludesUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end

        local itemLevelInspectRow
        itemLevelInspectRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Item Level",
            tooltip = "Toggle visibility of item level text on the inspect sheet.",
            getValue = function()
                return CludesUIDB and CludesUIDB.inspectShowItemLevel ~= false
            end,
            setValue = function(val)
                Account().inspectShowItemLevel = val
                if CludesUI._refreshInspectItemLevelVisibility then
                    CludesUI._refreshInspectItemLevelVisibility()
                end
            end,
        }, {
            type = "toggle",
            text = "Upgrade Track",
            tooltip = "Toggle visibility of upgrade track text on the inspect sheet.",
            getValue = function()
                return CludesUIDB and CludesUIDB.inspectShowUpgradeTrack ~= false
            end,
            setValue = function(val)
                Account().inspectShowUpgradeTrack = val
                if CludesUI._refreshInspectUpgradeTrackVisibility then
                    CludesUI._refreshInspectUpgradeTrackVisibility()
                end
            end,
        })
        posY = posY - hgt

        if not CludesUI._prebuilding then
            local function themedOff()
                return not (CludesUIDB and CludesUIDB.themedInspectSheet)
            end

            local itemLevelInspectBlock = CreateFrame("Frame", nil, itemLevelInspectRow)
            itemLevelInspectBlock:SetAllPoints(itemLevelInspectRow)
            itemLevelInspectBlock:SetFrameLevel(itemLevelInspectRow:GetFrameLevel() + 10)
            itemLevelInspectBlock:EnableMouse(true)
            local itemLevelInspectBg = CludesUI.SolidTex(itemLevelInspectBlock, "BACKGROUND", 0, 0, 0, 0)
            itemLevelInspectBg:SetAllPoints()
            itemLevelInspectBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(itemLevelInspectBlock, CludesUI.DisabledTooltip("Inspect Sheet"))
            end)
            itemLevelInspectBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            CludesUI.RegisterWidgetRefresh(function()
                if themedOff() then
                    itemLevelInspectBlock:Show()
                    itemLevelInspectRow:SetAlpha(0.3)
                else
                    itemLevelInspectBlock:Hide()
                    itemLevelInspectRow:SetAlpha(1)
                end
            end)
            if themedOff() then
                itemLevelInspectBlock:Show()
                itemLevelInspectRow:SetAlpha(0.3)
            else
                itemLevelInspectBlock:Hide()
                itemLevelInspectRow:SetAlpha(1)
            end
        end

        return posY
    end

    ---------------------------------------------------------------------------
    --  LFG Menu card content
    ---------------------------------------------------------------------------
    local function BuildLFGMenuContent(hostFrame, posY)
        local W = CludesUI.Widgets
        local _, hgt

        _, hgt = WSCardSection(hostFrame, "QUALITY OF LIFE", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Remember Sign-Up Roles",
            tooltip = "Remembers the Tank/Healer/DPS roles you last applied with and restores them the next time you sign up to a premade group (limited to roles your current spec can fill). Works with or without the reskin.",
            getValue = function()
                return CludesUIDB and CludesUIDB.lfgRememberRoles == true
            end,
            setValue = function(val)
                Account().lfgRememberRoles = val
                if CludesUI._GroupFinder_RefreshQoL then
                    CludesUI._GroupFinder_RefreshQoL()
                end
            end,
        }, { type = "label", text = "" })
        posY = posY - hgt

        return posY
    end

    ---------------------------------------------------------------------------
    --  Friends List card content (WoW Forever only, where the Friends List
    --  module never loads): what that module offers retail's friends list,
    --  from the shared friends kit, and the custom friends list (its switch,
    --  Custom Friends List Tiles, and its Tile Height), on the card's own
    --  settings (CludesUIDB.friendsListCard through ns.FriendsCardGet / Set,
    --  in CludesUIBlizzardSkin_FriendsForever.lua). The switch follows the
    --  card's look until picked (on while the card is skinned, off under
    --  Blizz Default); the tile settings grey out while neither the tiles on
    --  Blizzard's cards nor the custom list draws; auto-accept runs whatever
    --  the skin.
    ---------------------------------------------------------------------------
    local function BuildFriendsCardContent(hostFrame, posY)
        local W = CludesUI.Widgets
        local _, row, hgt
        local Kit = CludesUI.FriendsKit

        local CUSTOM = "Custom Friends List Tiles"
        local function customOff()
            return mod.FriendsCardGet("customTiles") ~= true
        end
        -- Blizz Default keeps Blizzard's cards, so only the custom list draws tiles there
        local function tilesOff()
            return CludesUI.GetBlizzWindowStyle("socialui") == "off" and customOff()
        end
        local function tileGate(conf, off)
            conf.disabled = off or tilesOff
            conf.disabledTooltip = CUSTOM
            return conf
        end

        _, hgt = WSCardSection(hostFrame, "DISPLAY", posY)
        posY = posY - hgt

        -- Custom Friends List Tiles | Tile Height: the custom friends list
        -- (CludesUI_FriendsList.lua) and its own height
        local tileMin, tileMax = CludesUI.FriendsList.TileRange()
        row, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "toggle",
                text = CUSTOM,
                tooltip = "CludesUI's own friends list, with a tile height you choose and friend groups. Right click a friend to set its group.",
                getValue = function()
                    return not customOff()
                end,
                setValue = function(val)
                    mod.FriendsCardSet("customTiles", val and true or false)
                    CludesUI:RefreshPage() -- the tile settings' disabled state
                end,
            },
            tileGate({
                type = "slider",
                text = "Tile Height",
                min = tileMin,
                max = tileMax,
                step = 1,
                tooltip = "The height of each friend in the custom friends list. Shorter tiles show fewer lines.",
                getValue = function()
                    return mod.FriendsCardGet("tileHeight")
                end,
                setValue = function(val)
                    mod.FriendsCardSet("tileHeight", val)
                end,
            }, customOff)
        )
        posY = posY - hgt

        -- Tile Features | Class Icon Theme
        row, hgt = W:DualRow(
            hostFrame,
            posY,
            tileGate({
                type = "dropdown",
                text = "Tile Features",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }),
            tileGate({
                type = "dropdown",
                text = "Class Icon Theme",
                values = Kit.ICON_STYLE_VALUES,
                order = Kit.ICON_STYLE_ORDER,
                getValue = function()
                    return mod.FriendsCardGet("iconStyle")
                end,
                setValue = function(val)
                    mod.FriendsCardSet("iconStyle", val)
                end,
            })
        )
        posY = posY - hgt

        -- Tile Features: one checkbox dropdown over the three tile switches,
        -- each still its own key, in place of the row's placeholder.
        if not CludesUI._prebuilding then
            local region = row._leftRegion
            if region._control then
                region._control:Hide()
            end
            local dropdown, refresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                220,
                region:GetFrameLevel() + 2,
                {
                    { key = "factionBanners", label = "Faction Banners" },
                    {
                        key = "showRegionIcons",
                        label = "Region Icons",
                        tooltip = "Shows a map icon of the friend's region if they are not playing within your region",
                    },
                    { key = "classColorNames", label = "Class Colored Names" },
                },
                function(key)
                    return mod.FriendsCardGet(key) == true
                end,
                function(key, val)
                    mod.FriendsCardSet(key, val and true or false)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = tilesOff, disabledTooltip = CUSTOM }
            )
            CludesUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        -- Auto-Accept Friend Invites
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Auto-Accept Friend Invites",
            tooltip = "Auto-accepts all group invites from people on your friends list",
            getValue = function()
                return mod.FriendsCardGet("autoAcceptFriendInvites") == true
            end,
            setValue = function(val)
                mod.FriendsCardSet("autoAcceptFriendInvites", val)
                CludesUI:RefreshPage() -- the guildmate cog's disabled state
            end,
        }, CludesUI.BlankRowCfg())
        posY = posY - hgt

        -- Guildmates in a cog on Auto-Accept Friend Invites: it only extends
        -- that feature, so the cog blocks while the toggle is off.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Auto Accept Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Accept Invites from Guildmates",
                        get = function()
                            return mod.FriendsCardGet("autoAcceptGuildInvites") == true
                        end,
                        set = function(val)
                            mod.FriendsCardSet("autoAcceptGuildInvites", val)
                        end,
                    },
                },
                disabled = function()
                    return mod.FriendsCardGet("autoAcceptFriendInvites") ~= true
                end,
                disabledTooltip = "Auto-Accept Friend Invites",
            })
        end

        return posY
    end

    local function BuildMerchantContent(hostFrame, posY)
        local W = CludesUI.Widgets
        local _, hgt

        local function themedOff()
            return CludesUIDB and CludesUIDB.reskinMerchant == false
        end

        local function AttachDisabledOverlay(target)
            local block = CreateFrame("Frame", nil, target)
            block:SetAllPoints(target)
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            local backdrop = CludesUI.SolidTex(block, "BACKGROUND", 0, 0, 0, 0)
            backdrop:SetAllPoints()
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(block, CludesUI.DisabledTooltip("Merchant"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function refresh()
                if themedOff() then
                    block:Show()
                    target:SetAlpha(0.3)
                else
                    block:Hide()
                    target:SetAlpha(1)
                end
            end
            CludesUI.RegisterWidgetRefresh(refresh)
            refresh()
        end

        _, hgt = WSCardSection(hostFrame, "MERCHANT OPTIONS", posY)
        posY = posY - hgt

        local function merchantShowAsListOff()
            return CludesUIDB and CludesUIDB.merchantShowAsList == false
        end

        local row
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show As List",
            tooltip = "Shows the items as a list instead of pages.",
            getValue = function()
                return CludesUIDB and CludesUIDB.merchantShowAsList == true
            end,
            setValue = function(val)
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                local previousValue = CludesUIDB.merchantShowAsList
                CludesUIDB.merchantShowAsList = val

                -- Enabling the setting breaks the UI immediately, a reload is required
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Merchant Show As List setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Cancel",
                    reload = true,
                    onCancel = function()
                        CludesUIDB.merchantShowAsList = previousValue
                        CludesUI:RefreshPage()
                    end,
                })
            end,
        }, {
            type = "slider",
            text = "Row Height",
            min = 24,
            max = 40,
            step = 1,
            disabled = merchantShowAsListOff,
            disabledTooltip = "Show As List",
            getValue = function()
                return (CludesUIDB and CludesUIDB.merchantListRowHeight) or 32
            end,
            setValue = function(val)
                Account().merchantListRowHeight = val
                if CludesUI._Merchant_RefreshRowHeight then
                    CludesUI._Merchant_RefreshRowHeight()
                end
            end,
        })
        posY = posY - hgt
        AttachDisabledOverlay(row)

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Item Level",
            tooltip = "Shows the item level on weapons and armor a vendor sells.",
            getValue = function()
                return CludesUIDB and CludesUIDB.merchantShowItemLevel == true
            end,
            setValue = function(val)
                Account().merchantShowItemLevel = val
                if CludesUI._Merchant_RefreshItemLevels then
                    CludesUI._Merchant_RefreshItemLevels()
                end
            end,
        }, {
            type = "toggle",
            text = "Bulk Buy",
            tooltip = "Shift-click a vendor item to buy more than one stack at a time.",
            disabled = function()
                return CludesUI.PadGamepadUI()
            end,
            disabledTooltip = "This option does not work with the Gamepad interface style.",
            getValue = function()
                return CludesUIDB and CludesUIDB.merchantBulkBuy == true
            end,
            setValue = function(val)
                Account().merchantBulkBuy = val
                if CludesUI._Merchant_RefreshBulkBuy then
                    CludesUI._Merchant_RefreshBulkBuy()
                end
            end,
        })
        posY = posY - hgt

        -- Expand Vendor UI: a bigger grid in the vendor window. The cog sets its
        -- size; 2 x 5 is Blizzard's own layout. Needs the Merchant skin (the
        -- card overlay) and is not used with Show As List.
        local function merchantShowAsListOn()
            return CludesUIDB and CludesUIDB.merchantShowAsList == true
        end
        local function BuildExpandCog(region)
            if CludesUI._prebuilding then
                return
            end
            local function setSize(key, val)
                Account()[key] = val
                if CludesUI._Merchant_RefreshExpand then
                    CludesUI._Merchant_RefreshExpand()
                end
            end
            CludesUI.BuildInlineCog(region, {
                title = "Expand Vendor UI Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Vendor Columns",
                        min = 2,
                        max = 6,
                        step = 1,
                        get = function()
                            return (CludesUIDB and CludesUIDB.merchantCols) or 2
                        end,
                        set = function(val)
                            setSize("merchantCols", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Vendor Rows",
                        min = 5,
                        max = 10,
                        step = 1,
                        get = function()
                            return (CludesUIDB and CludesUIDB.merchantRows) or 5
                        end,
                        set = function(val)
                            setSize("merchantRows", val)
                        end,
                    },
                },
                gap = 9,
                disabled = function()
                    return merchantShowAsListOn() or not (CludesUIDB and CludesUIDB.merchantExpand)
                end,
                disabledTooltip = function()
                    if merchantShowAsListOn() then
                        return "This option does not work with Show As List."
                    end
                    return "Expand Vendor UI"
                end,
            })
        end

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Expand Vendor UI",
            tooltip = "Shows more vendor items at once, in the columns and rows set in the cog.",
            disabled = merchantShowAsListOn,
            disabledTooltip = "This option does not work with Show As List.",
            getValue = function()
                return CludesUIDB and CludesUIDB.merchantExpand == true
            end,
            setValue = function(val)
                Account().merchantExpand = val
                if CludesUI._Merchant_RefreshExpand then
                    CludesUI._Merchant_RefreshExpand()
                end
                CludesUI:RefreshPage()
            end,
        }, CludesUI.BlankRowCfg())
        posY = posY - hgt
        BuildExpandCog(row._leftRegion)
        AttachDisabledOverlay(row)

        return posY
    end

    ---------------------------------------------------------------------------
    --  Loot Window card: BORDER, an optional border in place of the window
    --  border (ApplyLootBorder, CludesUIBlizzardSkin_WindowPacks.lua; Default
    --  leaves the setting unset), and ICON BORDER, the item icons' border in a
    --  picked style. The Tooltips page's border rows (the shared helpers above,
    --  under the "lootWindow" and "lootIcon" prefixes), plus a Quality color mode.
    ---------------------------------------------------------------------------
    local function BuildLootContent(hostFrame, posY)
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local W = CludesUI.Widgets
        local _, hgt
        local prefixText = "lootWindow"
        local iconPrefix = "lootIcon"

        local function lootOff()
            return CludesUI.GetBlizzWindowStyle("loot") == "off"
        end
        local function iconOff()
            return lootOff() or not CludesUIDB.lootIconBorder
        end
        local function refresh()
            if CludesUI._Loot_RefreshBorder then
                CludesUI._Loot_RefreshBorder()
            end
        end

        _, hgt = WSCardSection(hostFrame, "BORDER", posY)
        posY = posY - hgt

        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        texValues.default = "Default"
        table.insert(texOrder, 1, "default")

        local row
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Border Style",
            tooltip = "Replaces the loot window's border. Default keeps the standard window border.",
            disabled = lootOff,
            disabledTooltip = "Loot Window",
            values = texValues,
            order = texOrder,
            getValue = function()
                return CludesUIDB and CludesUIDB[prefixText .. "BorderTexture"] or "default"
            end,
            setValue = function(val)
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                local saved = CludesUIDB
                if val == "default" then
                    saved[prefixText .. "BorderTexture"] = nil
                else
                    local c, b = CludesUI.GetBorderStyleSelectDefaults(val)
                    saved[prefixText .. "BorderTexture"] = val
                    saved[prefixText .. "BorderBehind"] = b
                    saved[prefixText .. "BorderColor"] = c
                    -- Full opacity and the style's own size: the 18% default leaves textured art faded
                    saved[prefixText .. "BorderOpacity"] = 1
                    local size = CludesUI.GetBorderDefaultSize(nil, val)
                    if size then
                        saved[prefixText .. "BorderThickness"] = CludesUI.BORDER_LABEL_OF_STEP[size]
                    end
                end
                saved[prefixText .. "BorderOffsetX"] = nil
                saved[prefixText .. "BorderOffsetY"] = nil
                if saved[prefixText .. "BorderThicknessPx"] then
                    saved[prefixText .. "BorderThicknessPx"] = false
                end
                refresh()
                CludesUI:RefreshPage(true)
            end,
        }, BorderSizeSlider(prefixText, "Border Size", lootOff, refresh, "Loot Window"))
        posY = posY - hgt

        -- Accent | Class | Custom | Quality swatches beside Border Size, as on the Tooltips page.
        AttachBorderControls(row, prefixText, lootOff, false, {
            apply = refresh,
            quality = {
                key = prefixText .. "BorderQualityColor",
                tip = "Quality Color: the best item's, or this color for Poor and Common",
            },
        })

        -- Width | Height Offset, only for a textured style (art with built-in padding needs fitting).
        local ocfgL, ocfgR = BorderOffsetCfgs(prefixText, lootOff, refresh, "Loot Window")
        if ocfgL then
            _, hgt = W:DualRow(hostFrame, posY, ocfgL, ocfgR)
            posY = posY - hgt
        end

        -- ICON BORDER: the item icons' quality border in a picked style and size (color stays the item quality).
        _, hgt = WSCardSection(hostFrame, "ICON BORDER", posY)
        posY = posY - hgt

        local iconValues, iconOrder = CludesUI.GetBorderTextureDropdown()
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Icon Borders",
            tooltip = "Draws the item icons' quality border in the style and size below.",
            disabled = lootOff,
            disabledTooltip = "Loot Window",
            getValue = function()
                return CludesUIDB.lootIconBorder == true
            end,
            setValue = function(val)
                CludesUIDB.lootIconBorder = val
                refresh()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Icon Border Style",
            disabled = iconOff,
            disabledTooltip = "Icon Borders",
            values = iconValues,
            order = iconOrder,
            getValue = function()
                return CludesUIDB[iconPrefix .. "BorderTexture"] or "solid"
            end,
            setValue = function(val)
                local saved = CludesUIDB
                saved[iconPrefix .. "BorderTexture"] = val
                saved[iconPrefix .. "BorderOffsetX"] = nil
                saved[iconPrefix .. "BorderOffsetY"] = nil
                if saved[iconPrefix .. "BorderThicknessPx"] then
                    saved[iconPrefix .. "BorderThicknessPx"] = false
                end
                refresh()
                CludesUI:RefreshPage(true)
            end,
        })
        posY = posY - hgt

        local iconSize = BorderSizeSlider(iconPrefix, "Icon Border Size", iconOff, refresh, "Icon Borders")
        iconSize.trackWidth = nil -- no swatches beside it: the full track
        -- Textured styles add the two offsets: Size | Width Offset, then Height Offset | blank.
        local icL, icR = BorderOffsetCfgs(iconPrefix, iconOff, refresh, "Icon Borders")
        if icL then
            _, hgt = W:DualRow(hostFrame, posY, iconSize, icL)
            posY = posY - hgt
            _, hgt = W:DualRow(hostFrame, posY, icR, CludesUI.BlankRowCfg())
            posY = posY - hgt
        else
            _, hgt = W:DualRow(hostFrame, posY, iconSize, CludesUI.BlankRowCfg())
            posY = posY - hgt
        end

        return posY
    end

    local function BuildLootToastContent(hostFrame, posY)
        local W = CludesUI.Widgets
        local _, hgt

        _, hgt = WSCardSection(hostFrame, "QUALITY OF LIFE", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Quality Strip",
            tooltip = "Adds a strip down the left edge of a loot toast in the item's quality color. The flat skin drops Blizzard's quality ring around the icon, so this puts that rarity cue back.",
            getValue = function()
                return not CludesUIDB or CludesUIDB.lootToastQualityStrip ~= false
            end,
            setValue = function(val)
                Account().lootToastQualityStrip = val
                if CludesUI._LootToast_Refresh then
                    CludesUI._LootToast_Refresh()
                end
            end,
        }, {
            type = "toggle",
            text = "Gold Toast Strip",
            tooltip = "Also show the strip on gold toasts, in the header's gold color. Gold has no rarity to signal, so this is off by default.",
            getValue = function()
                return CludesUIDB and CludesUIDB.lootToastQualityStripMoney == true
            end,
            setValue = function(val)
                Account().lootToastQualityStripMoney = val
                if CludesUI._LootToast_Refresh then
                    CludesUI._LootToast_Refresh()
                end
            end,
        })
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Toast Scale",
            tooltip = "Scales the loot and gold toasts.",
            min = 0.5,
            max = 1.5,
            step = 0.05,
            format = "%.0f%%",
            displayMul = 100,
            getValue = function()
                return CludesUIDB and CludesUIDB.lootToastScale or 1.0
            end,
            setValue = function(val)
                Account().lootToastScale = val
                if CludesUI._LootToast_Refresh then
                    CludesUI._LootToast_Refresh()
                end
            end,
        }, { type = "label", text = "" })
        posY = posY - hgt

        return posY
    end

    ---------------------------------------------------------------------------
    --  Mail card, ALT LIST section (retail): the Alt List beside Send Mail
    --  (CludesUIBlizzardSkin_MailAlts.lua, ns.MailAlts), whatever the card's
    --  style. Sort, cap and minimum level ride the toggle's cog; Shown
    --  Characters lists every recorded character under its realm.
    ---------------------------------------------------------------------------
    local function BuildMailAltList(hostFrame, posY)
        local MA = mod.MailAlts
        if not MA then
            return posY
        end
        local W = CludesUI.Widgets
        local _, row, hgt
        local REQ = "Show Alt List"
        local function On()
            return CludesUIDB and CludesUIDB.mailAltList == true
        end
        local function Off()
            return not On()
        end
        local function Get(key, default)
            local val = CludesUIDB and CludesUIDB[key]
            if val == nil then
                return default
            end
            return val
        end
        local function Set(key, val)
            Account()[key] = val
            MA.Refresh()
        end
        -- Every recorded character, a header per realm (rebuilt on each open).
        local function Items()
            local itemList, lastRealm = {}, nil
            for _, e in ipairs(MA.Entries()) do
                if e.realm ~= lastRealm then
                    lastRealm = e.realm
                    itemList[#itemList + 1] = { isHeader = true, label = e.realm }
                end
                local c = CludesUI.GetClassColor(e.class)
                itemList[#itemList + 1] = {
                    key = e.guid,
                    label = CludesUI.HexColor(c.r, c.g, c.b) .. e.name .. "|r",
                    tooltip = MA.Describe(e),
                }
            end
            return itemList
        end

        _, hgt = WSCardSection(hostFrame, "ALT LIST", posY)
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Alt List",
            tooltip = "Lists your alts beside Send Mail.",
            getValue = On,
            setValue = function(val)
                Set("mailAltList", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Shown Characters",
            tooltip = "Untick a character to leave it off the list.",
            disabled = Off,
            disabledTooltip = REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        posY = posY - hgt

        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Alt List",
                disabled = Off,
                disabledTooltip = REQ,
                rows = {
                    {
                        type = "dropdown",
                        label = "Sort By",
                        values = { recent = "Last Played", level = "Level", name = "Name" },
                        order = { "recent", "level", "name" },
                        get = function()
                            return Get("mailAltListSort", MA.DEFAULT_SORT)
                        end,
                        set = function(val)
                            Set("mailAltListSort", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Max Characters Shown",
                        min = 1,
                        max = MA.MAX_ROWS,
                        step = 1,
                        get = function()
                            return Get("mailAltListMax", MA.DEFAULT_MAX)
                        end,
                        set = function(val)
                            Set("mailAltListMax", val)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Minimum Level",
                        min = 1,
                        max = GetMaxLevelForLatestExpansion(),
                        step = 1,
                        get = function()
                            return Get("mailAltListMinLevel", MA.DEFAULT_MIN_LEVEL)
                        end,
                        set = function(val)
                            Set("mailAltListMinLevel", val)
                        end,
                    },
                },
            })
            -- Shown Characters: the checkbox dropdown in place of the row's
            -- placeholder; a long roster gets the search box.
            local region = row._rightRegion
            if region._control then
                region._control:Hide()
            end
            local dropdown, refresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                220,
                region:GetFrameLevel() + 2,
                Items,
                MA.IsShown,
                MA.SetShown,
                nil,
                10,
                #MA.Entries() > 12,
                nil,
                nil,
                { disabled = Off, disabledTooltip = REQ, countLabel = true }
            )
            CludesUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        return posY
    end

    ---------------------------------------------------------------------------
    --  Blizzard Window Skins page: one expandable card per reskinned window.
    --  Card headers are custom chrome, but every sub-setting ROW is a standard
    --  W: widget built as a direct child of the page wrapper, so inline search
    --  and nav deep-links keep working. Expand state is session-only; clicking
    --  a header rebuilds the page with that card open or closed.
    ---------------------------------------------------------------------------
    local WS_ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
    local WS_ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
    local WS_CARD_INSET = 0 -- card edges align with the DualRow content width
    local WS_HEADER_H = 54
    local WS_CARD_GAP = 14

    local _wsExpanded = {}
    local _wsApplyAllStyle = "cui" -- set-all dropdown pick (session-only)

    local function WSReloadPopup(message)
        CludesUI:ShowConfirmPopup({
            title = "Reload Required",
            message = message,
            confirmText = "Reload Now",
            cancelText = "Later",
            reload = true,
        })
    end

    -- Style vocabulary shared by the per-card dropdowns and the set-all row.
    local WS_STYLE_VALUES = { cui = "CludesUI", modern = "Modern", off = "Blizz Default" }
    local WS_STYLE_ORDER = { "cui", "modern", "off" }
    -- The Character Sheet's own: its Blizz Default keeps Blizzard's sheet
    -- with the CludesUI stats, slot text and socket panel; Off leaves the
    -- sheet untouched.
    local WS_CHARSHEET_VALUES =
        { cui = "CludesUI", modern = "Modern", blizzard = "Blizz Default", off = "Off" }
    local WS_CHARSHEET_ORDER = { "cui", "modern", "blizzard", "off" }

    -- Modern background color + opacity: ONE global setting for the Modern
    -- style, resolved by the window-skin engine and applied live to every
    -- window currently set to Modern.
    local function WSModernGet()
        if mod.WSkin and mod.WSkin.GetModernBG then
            return mod.WSkin.GetModernBG()
        end
        return 0.067, 0.067, 0.067, 0.97
    end
    local function WSModernSet(r, g, b, a)
        Account().blizzWindowModernDefault = { r = r, g = g, b = b, a = a }
        if CludesUI._WSkinRefreshStyles then
            CludesUI._WSkinRefreshStyles()
        end
    end

    -- Single Modern color swatch left of the set-all dropdown, greyed and
    -- blocked while isOff() (that dropdown is not on Modern). The picker
    -- carries the opacity slider; edits write the Modern preset directly, so
    -- windows already on Modern recolor immediately (no Apply to All).
    local function AttachModernSwatch(host, anchorTo, isOff)
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(host, host:GetFrameLevel() + 5, function()
            return WSModernGet()
        end, function(r, g, b, a)
            WSModernSet(r, g, b, a)
        end, true, 20)
        CludesUI.PanelPP.Point(colorSwatch, "RIGHT", anchorTo, "LEFT", -8, 0)
        colorSwatch:HookScript("OnEnter", function(s)
            CludesUI.ShowWidgetTooltip(s, "Background color for the Modern style.")
        end)
        colorSwatch:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local block = CreateFrame("Frame", nil, colorSwatch)
        block:SetAllPoints()
        block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(
                colorSwatch,
                CludesUI.DisabledTooltip("This option requires the Modern style.")
            )
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function Refresh()
            updateSwatch()
            local off = isOff()
            colorSwatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end
        CludesUI.RegisterWidgetRefresh(Refresh)
        Refresh()
    end

    -- Global look settings (Global Options section): central tables, nil =
    -- defaults, resolved by the window-skin engine and applied live.
    local function WSLook(key)
        return CludesUIDB and CludesUIDB[key]
    end
    local function WSLookSet(key, field, val)
        if not CludesUIDB then
            CludesUIDB = {}
        end
        local t = CludesUIDB[key]
        if not t then
            t = {}
            CludesUIDB[key] = t
        end
        t[field] = val
        if CludesUI._WSkinRefreshLooks then
            CludesUI._WSkinRefreshLooks()
        end
    end

    -- Inline accent|custom swatch pair on a DualRow region (the standard
    -- dual-swatch treatment): custom sits nearest the control, accent left of
    -- it; the active mode renders bright, the other dimmed.
    local function AttachLookSwatches(region, row, key)
        local Pix = CludesUI.PanelPP
        local ctrl = region._control

        local customSwatch, updateCustom = CludesUI.BuildColorSwatch(
            region,
            row:GetFrameLevel() + 3,
            function()
                local c = WSLook(key)
                local col = c and c.color
                if col then
                    return col.r or 1, col.g or 1, col.b or 1
                end
                return 1, 1, 1
            end,
            function(r, g, b)
                WSLookSet(key, "color", { r = r, g = g, b = b })
                WSLookSet(key, "useCustom", true)
                CludesUI:RefreshPage()
            end,
            false,
            20
        )
        Pix.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            local c = WSLook(key)
            if not (c and c.useCustom) then
                WSLookSet(key, "useCustom", true)
                CludesUI:RefreshPage()
                return
            end
            if origClick then
                origClick(self, ...)
            end
        end)
        CludesUI.HoverTip(customSwatch, "Custom Color")

        local accentSwatch, updateAccent = CludesUI.BuildColorSwatch(
            region,
            row:GetFrameLevel() + 3,
            function()
                return CludesUI.ResolveActiveAccent()
            end,
            function()
                WSLookSet(key, "useCustom", false)
                CludesUI:RefreshPage()
            end,
            false,
            20
        )
        Pix.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        accentSwatch:SetScript("OnClick", function()
            WSLookSet(key, "useCustom", false)
            CludesUI:RefreshPage()
        end)
        CludesUI.HoverTip(accentSwatch, "Accent Color")
        region._lastInline = accentSwatch

        local function refreshPair()
            updateCustom()
            updateAccent()
            local c = WSLook(key)
            local useCustom = c and c.useCustom
            customSwatch:SetAlpha(useCustom and 1 or 0.3)
            accentSwatch:SetAlpha(useCustom and 0.3 or 1)
        end
        CludesUI.RegisterWidgetRefresh(refreshPair)
        refreshPair()
    end

    local WINDOWS = {
        {
            key = "charsheet",
            title = "Character Sheet",
            desc = "Equipment panel with stat categories, item level, enchants, gems, and the inspect sheet.",
            reloadMsg = "Character Sheet theme setting requires a UI reload to fully apply.",
            styleValues = WS_CHARSHEET_VALUES,
            styleOrder = WS_CHARSHEET_ORDER,
            -- What the set-all row's Blizz Default gives this card.
            blizzDefault = "blizzard",
            setEnabled = function(val)
                Account().themedCharacterSheet = val
                CludesUIDB.themedInspectSheet = val
                -- Individual feature toggles retain their values.
            end,
            buildContent = BuildCharacterSheetContent,
        },
        {
            key = "lfg",
            -- Forever's window is titled "Looking For Group"; the parens keep "lfg"
            -- searchable there (the card search indexes title + desc).
            title = CludesUI.IS_FOREVER and "Looking For Group (LFG)" or "LFG Menu",
            desc = CludesUI.IS_FOREVER
                    and "Looking For Group window: group listing, group browser and who list, plus the group tooltip."
                or "Group Finder and Premade Groups window, plus browsing quality-of-life extras.",
            reloadMsg = "Changing the Group Finder reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLFGMenu = val
            end,
            -- Its one extra (Remember Sign-Up Roles) hooks retail's premade sign-up
            -- dialog, which Forever does not have.
            buildContent = not CludesUI.IS_FOREVER and BuildLFGMenuContent or nil,
        },
        {
            key = "legacysystem",
            title = "Progress Legacy",
            desc = "Restyles the Progress Legacy window (reward track, challenges and the legacy tree) in the CludesUI style.",
            reloadMsg = "Changing the Progress Legacy reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLegacySystem = val
            end,
        },
        {
            key = "greatvault",
            title = "Great Vault",
            desc = "Weekly rewards window with custom tile backgrounds, progress colors, and completion states.",
            reloadMsg = "Changing the Great Vault reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinGreatVault = val
            end,
        },
        {
            key = "adventureguide",
            title = "Adventure Guide",
            desc = "Encounter Journal: instance select, boss details, loot lists, and the bottom nav tabs.",
            reloadMsg = "Changing the Adventure Guide reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinAdventureGuide = val
            end,
        },
        {
            key = "collections",
            title = "Collections",
            desc = "Mounts, pets, toys, heirlooms, appearances, and campsites.",
            reloadMsg = "Changing the Collections reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinCollections = val
            end,
        },
        {
            key = "playerspells",
            title = "Talents & Spellbook",
            desc = "The Player Spells window: talents, spec selection, and the spellbook.",
            reloadMsg = "Changing the Talents & Spellbook reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinPlayerSpells = val
            end,
        },
        {
            key = "professionsbook",
            title = "Professions",
            desc = "The professions overview book with squared icons and flat progress bars.",
            reloadMsg = "Changing the Professions reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinProfessionsBook = val
            end,
        },
        {
            key = "professions",
            title = "Profession Crafting",
            desc = "The profession crafting window: recipe list, schematic, specializations, and crafting orders.",
            reloadMsg = "Changing the Profession Crafting reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinProfessions = val
            end,
        },
        {
            key = "worldmap",
            title = "Map & Quest Log",
            desc = "The world map window chrome and the quest log side panel.",
            reloadMsg = "Changing the Map & Quest Log reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinWorldMap = val
            end,
        },
        {
            key = "guild",
            title = "Guild & Communities",
            desc = "The Guild & Communities window: roster, chat, and the community list.",
            reloadMsg = "Changing the Guild & Communities reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinGuild = val
            end,
        },
        {
            key = "calendar",
            title = "Calendar",
            desc = "The monthly calendar grid, event dialogs, and navigation arrows.",
            reloadMsg = "Changing the Calendar reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinCalendar = val
            end,
        },
        {
            key = "achievements",
            title = "Achievements",
            desc = "The achievement window: categories, rows, progress bars, and search.",
            reloadMsg = "Changing the Achievements reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinAchievements = val
            end,
        },
        {
            key = "mail",
            title = "Mail",
            desc = "The mailbox: inbox rows, send mail, open mail, and attachment slots.",
            reloadMsg = "Changing the Mail reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinMail = val
            end,
            buildContent = not CludesUI.IS_FOREVER and BuildMailAltList or nil,
            searchText = not CludesUI.IS_FOREVER and { "Show Alt List", "Shown Characters" } or nil,
        },
        {
            key = "catalyst",
            title = "Catalyst",
            desc = "The item conversion window (catalyst and similar kiosks).",
            reloadMsg = "Changing the Catalyst reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinCatalyst = val
            end,
        },
        {
            key = "socket",
            title = "Gem Socketing",
            desc = "The gem socketing window with squared gem slots.",
            reloadMsg = "Changing the Gem Socketing reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinSocket = val
            end,
        },
        {
            key = "itemupgrade",
            title = "Item Upgrades",
            desc = "The item upgrade window: upgrade slot, track selector, cost, and the currency strip.",
            reloadMsg = "Changing the Item Upgrades reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinItemUpgrade = val
            end,
        },
        {
            key = "loot",
            title = "Loot Window",
            desc = "The loot window: item rows with squared icons, kept item quality colors.",
            reloadMsg = "Changing the Loot Window reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLoot = val
            end,
            buildContent = BuildLootContent,
        },
        {
            key = "loottoast",
            title = "Loot Toasts",
            desc = 'The "You received" popups for loot, currency, and upgrades.',
            reloadMsg = "Changing the Loot Toasts reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLootToast = val
            end,
            buildContent = BuildLootToastContent,
        },
        {
            key = "bnettoast",
            title = "Friend Notifications",
            desc = "The Battle.net popup when a friend comes online or goes offline, plus broadcasts and invites.",
            reloadMsg = "Changing the Friend Notifications reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinBNetToast = val
            end,
        },
        {
            key = "lootroll",
            title = "Loot Roll Popups",
            desc = "The need / greed / pass roll popups, with a squared icon and a flat roll timer.",
            reloadMsg = "Changing the Loot Roll Popups reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLootRoll = val
            end,
        },
        {
            key = "loothistory",
            title = "Loot Rolls Window",
            desc = "The pending-rolls window: encounter picker, roll timer, and the result rows.",
            reloadMsg = "Changing the Loot Rolls Window reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinLootHistory = val
            end,
        },
        {
            key = "groupinvite",
            title = "Group Invite Popup",
            desc = 'The "you have been invited to a group" dialogs, with your role and Accept / Decline.',
            reloadMsg = "Changing the Group Invite Popup reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinGroupInvite = val
            end,
        },
        {
            key = "readycheck",
            title = "Ready Check",
            desc = "The ready check prompt with its Yes / No buttons.",
            reloadMsg = "Changing the Ready Check reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinReadyCheck = val
            end,
        },
        {
            key = "housing",
            title = "Housing Dashboard",
            desc = "The housing dashboard window background, border, and title bar.",
            reloadMsg = "Changing the Housing Dashboard reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinHousing = val
            end,
        },
        {
            key = "micromenu",
            title = "Micro Menu",
            desc = "Flattens the micro menu buttons into the CludesUI style.",
            reloadMsg = "Changing the Micro Menu reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinMicroMenu = val
            end,
        },
        {
            key = "bagbar",
            title = "Bag Bar",
            desc = "Flattens the bag bar slot buttons into the CludesUI style.",
            reloadMsg = "Changing the Bag Bar reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinBagBar = val
            end,
        },
        {
            key = "dressup",
            title = "Dressing Room",
            desc = "The item preview / transmog dressing room window.",
            reloadMsg = "Changing the Dressing Room reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinDressUp = val
            end,
        },
        {
            key = "transmog",
            title = "Transmogrifier",
            desc = "The transmogrification window at the transmogrifier.",
            reloadMsg = "Changing the Transmogrifier reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinTransmog = val
            end,
        },
        {
            key = "merchant",
            title = "Merchant",
            desc = "The vendor window: item list, buyback, and bottom money bar.",
            reloadMsg = "Changing the Merchant reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinMerchant = val
            end,
            buildContent = BuildMerchantContent,
        },
        {
            key = "auctionhouse",
            title = "Auction House",
            desc = "The auction house: browse, sell, and my auctions views.",
            reloadMsg = "Changing the Auction House reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinAuctionHouse = val
            end,
        },
        {
            key = "macros",
            title = "Macros",
            desc = "The macro editor: tabs, icon grid, text well, and buttons.",
            reloadMsg = "Changing the Macros reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinMacros = val
            end,
        },
        {
            key = "settings",
            title = "Options Panel",
            desc = "Blizzard's options window chrome: frame, tabs, search, and category rail.",
            reloadMsg = "Changing the Options Panel reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinSettings = val
            end,
        },
        {
            key = "addonlist",
            title = "AddOn List",
            desc = "The addon manager: list rows, checkboxes, and buttons.",
            reloadMsg = "Changing the AddOn List reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinAddonList = val
            end,
        },
        {
            key = "craftorders",
            title = "Crafting Orders",
            desc = "The customer crafting orders window: browse, order form, and my orders.",
            reloadMsg = "Changing the Crafting Orders reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinCraftOrders = val
            end,
        },
        {
            key = "trainer",
            title = "Trainer",
            desc = "The class and profession trainer window: skill list, train button, and cost display.",
            reloadMsg = "Changing the Trainer reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinTrainer = val
            end,
        },
        {
            key = "gossip",
            title = "Gossip",
            desc = "The NPC dialog window: greeting text, gossip and quest options, and goodbye button.",
            reloadMsg = "Changing the Gossip reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinGossip = val
            end,
        },
        {
            key = "quest",
            title = "Quest",
            desc = "The NPC quest window: quest detail, progress, and reward panels plus the multi-quest greeting list.",
            reloadMsg = "Changing the Quest reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinQuest = val
            end,
        },
        {
            key = "inspectrecipe",
            title = "Inspect Recipe",
            desc = "The recipe preview window shown from a linked recipe or an inspected crafter.",
            reloadMsg = "Changing the Inspect Recipe reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinInspectRecipe = val
            end,
        },
        {
            key = "delves",
            title = "Delves Companion",
            desc = "Brann's configuration window: role and trinket slots, abilities, and the ability list.",
            reloadMsg = "Changing the Delves Companion reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinDelves = val
            end,
        },
        {
            key = "socialui",
            title = "Friends List",
            -- Retail: the Friends List module repaints its window to this card
            -- live. WoW Forever: the card drives that client's friends packs
            -- and hosts the friend tiles and auto-accept the module gives retail.
            desc = CludesUI.IS_FOREVER
                    and "The Social window frame, border, title bar, Battle.net bar, search boxes, filter dropdowns and buttons, and the friend tiles with class icons, class-colored names and region icons. The side tab icons stay untouched."
                or "The friends window backdrop, frame border, tabs, search boxes, bottom buttons and close button. Friend entries stay untouched; Blizz Default keeps the Friends List module's own flat look.",
            reloadMsg = CludesUI.IS_FOREVER
                    and "Changing the Friends List reskin requires a UI reload to fully swap between Blizzard and Cludes styles."
                or nil,
            setEnabled = function(val)
                Account().reskinSocialUI = val
            end,
            buildContent = CludesUI.IS_FOREVER and BuildFriendsCardContent or nil,
            searchText = CludesUI.IS_FOREVER
                    and { "Custom Friends List Tiles", "Tile Height", "Tile Features" }
                or nil,
        },
        {
            key = "queuestatus",
            title = "Queue Status",
            desc = "The panel the minimap Group Finder eye shows on hover: queue titles, role icons and counts, and time in queue.",
            reloadMsg = "Changing the Queue Status reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinQueueStatus = val
            end,
        },
        {
            key = "delvepicker",
            title = "Delve Tier Picker",
            desc = "The delve difficulty window: tier dropdown, reward list and Enter button. The Map Properties row is left stock -- it is a Blizzard widget display and is not safe to restyle.",
            reloadMsg = "Changing the Delve Tier Picker reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinDelvePicker = val
            end,
        },
        {
            key = "playerchoice",
            title = "Choice Windows",
            desc = 'Weekly and event choice windows such as Abundance harvests and "how will you aid..." pickers: option plates, headers, reward icons and buttons. Option artwork stays.',
            reloadMsg = "Changing the Choice Windows reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinPlayerChoice = val
            end,
        },
        {
            key = "trade",
            title = "Trade",
            desc = "The player-to-player trade window: frame, both item columns, the enchant slots, money rows and buttons. Item icons are squared and carry a rarity border. Both portraits are removed, as on every other window.",
            reloadMsg = "Changing the Trade reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinTrade = val
            end,
        },
        {
            key = "flagcarrier",
            title = "Flag Carriers",
            desc = "The battleground flag and orb carrier frames, dressed like CludesUI unit frames: health in the carrier's class color and power in its power color inside a thin black border, a square spec icon, a bordered trinket and cast bar, and the carrier's pet. The faction icon and the cast bar's fill stay as Blizzard draws them. To move them, turn on Move Flag Carriers in Layout Mode on the Utilities Shifter page.",
            reloadMsg = "Changing the Flag Carriers reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val)
                Account().reskinFlagCarriers = val
            end,
        },
    }

    -- WoW Forever drops the cards for windows it does not skin or has no use
    -- for: the Delve Tier Picker and Housing Dashboard never load on that
    -- client, and the Great Vault has no content there. Retail drops the Bag
    -- Bar card (a Forever-only skin). Saved enable keys stay untouched.
    if CludesUI.IS_FOREVER then
        local foreverDropped = {
            greatvault = true,
            delvepicker = true,
            housing = true,
        }
        for idx = #WINDOWS, 1, -1 do
            if foreverDropped[WINDOWS[idx].key] then
                table.remove(WINDOWS, idx)
            end
        end
    else
        -- The Bag Bar and Progress Legacy skins exist only on Forever; drop
        -- their cards on retail.
        for idx = #WINDOWS, 1, -1 do
            local key = WINDOWS[idx].key
            if key == "bagbar" or key == "legacysystem" then
                table.remove(WINDOWS, idx)
            end
        end
    end

    local function WSGetStyle(window)
        return CludesUI.GetBlizzWindowStyle(window.key)
    end

    -- Window skins a module's Style page choice overrides: while that module
    -- renders a stock style its pack stands down, so the card's style
    -- dropdown is blocked and Apply to All leaves the card alone.
    local WS_STYLE_OWNERS = { socialui = "friends" }
    local function WSStyleOwned(window)
        local ownerFrame = WS_STYLE_OWNERS[window.key]
        return ownerFrame and CludesUI.BlizzStyle and CludesUI.BlizzStyle.Get(ownerFrame) or false
    end

    -- Applies a style to one window. Returns true when the change crosses the
    -- on/off boundary, or the character sheet's Blizz Default one (= needs a
    -- reload). suppressPopup lets Apply to All show one popup for the whole
    -- batch instead of one per window.
    local function WSSetStyle(window, style, suppressPopup)
        local old = WSGetStyle(window)
        if old == style then
            return false
        end
        if not CludesUIDB then
            CludesUIDB = {}
        end
        -- A pick here belongs to the whole UI's current look: the Style
        -- page's Apply to All saves it into that look's window slot when
        -- the look changes (CludesUI.SwapWindowSkinStyle).
        window.setEnabled(style ~= "off")
        if style ~= "off" then
            -- Remember which skin set this window uses; kept while "off" so
            -- re-enabling restores the same pick.
            if not CludesUIDB.blizzWindowSkinStyles then
                CludesUIDB.blizzWindowSkinStyles = {}
            end
            CludesUIDB.blizzWindowSkinStyles[window.key] = style
        end
        -- A card with no reloadMsg swaps live both ways (retail Friends List).
        local oldClass = (old == "off" and 0) or (old == "blizzard" and 1) or 2
        local newClass = (style == "off" and 0) or (style == "blizzard" and 1) or 2
        local crossed = window.reloadMsg ~= nil and oldClass ~= newClass
        -- cui<->modern applies live (shell backdrops swap in place).
        if CludesUI._WSkinRefreshStyles then
            CludesUI._WSkinRefreshStyles()
        end
        if crossed and not suppressPopup then
            WSReloadPopup(window.reloadMsg)
        end
        return crossed
    end

    -- A card's style as a dropdown row on another page (Action Bars' Menu,
    -- Bags & Rep Bars mirrors the Micro Menu and Bag Bar cards): the card's
    -- own list, read and write, reload popup included, greyed while window
    -- skins are off for the profile. nil for a card this client does not
    -- offer (the Bag Bar off WoW Forever).
    function CludesUI.WindowSkinStyleCfg(winKey, textValue, tooltip)
        local window
        for idx = 1, #WINDOWS do
            if WINDOWS[idx].key == winKey then
                window = WINDOWS[idx]
                break
            end
        end
        if not window then
            return nil
        end
        return {
            type = "dropdown",
            text = textValue,
            tooltip = tooltip,
            values = window.styleValues or WS_STYLE_VALUES,
            order = window.styleOrder or WS_STYLE_ORDER,
            disabled = CludesUI.BlizzWindowSkinsKilled,
            disabledTooltip = "Window Skins",
            getValue = function()
                return WSGetStyle(window)
            end,
            setValue = function(val)
                WSSetStyle(window, val)
                CludesUI:RefreshPage()
            end,
        }
    end

    -- One expandable card: custom header (mini-window glyph + title + style
    -- dropdown + chevron) over a shared card background, with the window's
    -- rows below when expanded. Returns the new y cursor.
    local function BuildWindowCard(hostFrame, posY, window)
        local Pix = CludesUI.PanelPP
        local ACC = CludesUI.CLUDES_GREEN
        local L = CludesUI.L
        local hasSettings = window.buildContent ~= nil
        local expanded = hasSettings and _wsExpanded[window.key]
        local cardTop = posY
        local brd -- whole-card border, created with the bg below (hover closure)

        -- Explicit size + single TOPLEFT anchor (the widget contract): inline
        -- search re-anchors and restores direct children through their FIRST
        -- point only, so a frame that gets its width from a second point
        -- collapses to zero width the first time a search is cleared.
        local cardW = hostFrame:GetWidth() - (CludesUI.CONTENT_PAD - WS_CARD_INSET) * 2
        local heading = CreateFrame("Button", nil, hostFrame)
        Pix.Size(heading, cardW, WS_HEADER_H)
        Pix.Point(heading, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD - WS_CARD_INSET, posY)
        heading:SetFrameLevel(hostFrame:GetFrameLevel() + 3)

        -- Search metadata: the header acts as its own section, so searching a
        -- window's title or description returns the card (style dropdown and
        -- all) as a result. Deep links are unaffected: they match the exact
        -- section names created inside buildContent, never this joined string.
        -- win.searchText: the labels of a card's own settings (the Mail card's
        -- Alt List), each a locale key, found while the card is closed.
        local extra, extraLoc = "", ""
        if window.searchText then
            for _, labelText in ipairs(window.searchText) do
                extra = extra .. " " .. labelText
                extraLoc = extraLoc .. " " .. L(labelText)
            end
        end
        local searchName = window.title .. " " .. (window.desc or "") .. extra
        heading._isSectionHeader = true
        heading._sectionName = searchName
        local searchNameLoc = L(window.title) .. " " .. L(window.desc or "") .. extraLoc
        if searchNameLoc ~= searchName then
            heading._sectionNameLoc = searchNameLoc
        end

        -- Global (sidebar) search: the card header never goes through
        -- SectionHeader, so the index would otherwise have no entry for it --
        -- searching a window's title/description found it inline but not in
        -- the sidebar results. Register it with the same title + description
        -- keywords the inline pseudo-section matches (title as the display
        -- label, description via the tooltip field, which the fuzzy scorer
        -- also searches). section = the exact joined string stamped above, so
        -- a jump scrolls to and glows this header; the page's
        -- NavigateToElementSettings pre-hook expands the cards first.
        if CludesUI._RegisterSearchEntry then
            local titleLoc = L(window.title)
            local descSearch = window.desc or ""
            local descLoc = L(window.desc or "")
            if descLoc ~= descSearch then
                descSearch = descSearch .. " " .. descLoc
            end
            descSearch = descSearch .. extra
            if extraLoc ~= extra then
                descSearch = descSearch .. extraLoc
            end
            CludesUI._RegisterSearchEntry(
                window.title,
                titleLoc ~= window.title and titleLoc or nil,
                descSearch,
                CludesUI._buildingModule,
                CludesUI._buildingPage,
                searchName,
                nil,
                nil,
                true
            )
        end

        -- Hover wash (transparent when idle; the card bg below provides the fill)
        -- The header hover fill sits on the card (built below), inside its corners.
        local hbg

        -- Procedural mini-window glyph: a tiny framed "window" with a title
        -- bar. The bar lights up in accent while the reskin is enabled, but
        -- only on cards that actually have settings.
        local icon = CreateFrame("Frame", nil, heading)
        Pix.Size(icon, 22, 16)
        Pix.Point(icon, "LEFT", heading, "LEFT", 16, 0)
        local glyphBrd = CludesUI.MakeBorder(icon, 1, 1, 1, 0.35, Pix)
        local glyphBar = icon:CreateTexture(nil, "ARTWORK")
        glyphBar:SetHeight(4)
        Pix.Point(glyphBar, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        Pix.Point(glyphBar, "TOPRIGHT", icon, "TOPRIGHT", -1, -1)
        if glyphBar.SetSnapToPixelGrid then
            glyphBar:SetSnapToPixelGrid(false)
            glyphBar:SetTexelSnappingBias(0)
        end

        local title = CludesUI.MakeFont(heading, 14, nil, 1, 1, 1, 0.9)
        Pix.Point(title, "TOPLEFT", heading, "TOPLEFT", 50, -12)
        title:SetText(L(window.title))

        local desc = CludesUI.MakeFont(heading, 11, nil, 1, 1, 1, 0.42)
        Pix.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        desc:SetWidth(590)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)
        desc:SetText(L(window.desc))

        -- Expand chevron only on cards that actually have settings; cards
        -- without any are not expandable at all.
        local chev
        if hasSettings then
            chev = heading:CreateTexture(nil, "OVERLAY")
            Pix.Size(chev, 16, 16)
            Pix.Point(chev, "RIGHT", heading, "RIGHT", -16, 0)
            chev:SetTexture(expanded and WS_ARROW_UP or WS_ARROW_DOWN)
            chev:SetAlpha(0.45)
            if expanded then
                chev:SetVertexColor(ACC.r, ACC.g, ACC.b)
            end
        end

        -- Style dropdown: pick CludesUI / Modern / Blizz Default for this
        -- window without expanding the card (the card's own list, when it
        -- has one).
        local dropdown = CludesUI.BuildDropdownControl(
            heading,
            148,
            heading:GetFrameLevel() + 2,
            window.styleValues or WS_STYLE_VALUES,
            window.styleOrder or WS_STYLE_ORDER,
            function()
                return WSGetStyle(window)
            end,
            function(val)
                WSSetStyle(window, val)
                CludesUI:RefreshPage()
            end
        )
        Pix.Point(dropdown, "RIGHT", heading, "RIGHT", -44, 0)
        local ownerFrame = WS_STYLE_OWNERS[window.key]
        if ownerFrame and CludesUI.BlizzStyle then
            CludesUI.BlizzStyle.BlockInline(ownerFrame, dropdown)
        end

        local strip -- accent strip on the header's left edge (created with bg)
        local function RefreshCardState()
            local on = WSGetStyle(window) ~= "off"
            glyphBrd:SetColor(1, 1, 1, on and 0.4 or 0.2)
            -- Glyph title bar: accent is reserved for cards that have settings; windows
            -- without any keep a gray bar darker than the glyph border.
            if not hasSettings then
                glyphBar:SetColorTexture(1, 1, 1, 0.12)
            elseif on then
                glyphBar:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85)
            else
                glyphBar:SetColorTexture(1, 1, 1, 0.2)
            end
            -- Accent edge marks cards that actually have settings; windows
            -- without any keep the faint neutral strip.
            if strip then
                if hasSettings then
                    strip:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.7)
                else
                    strip:SetColorTexture(1, 1, 1, 0.10)
                end
            end
            if dropdown._refreshLabel then
                dropdown._refreshLabel()
            end
        end

        local function ApplyHeaderHover()
            hbg:SetColorTexture(1, 1, 1, 0.05)
            title:SetAlpha(1)
            chev:SetAlpha(0.85)
            if brd then
                brd:SetColor(1, 1, 1, 0.22)
            end
        end
        local function ClearHeaderHover()
            -- Moving between the header and its dropdown fires OnLeave first;
            -- keep the row highlight while the pointer is still inside the header.
            if heading:IsMouseOver() then
                return
            end
            hbg:SetColorTexture(0, 0, 0, 0)
            title:SetAlpha(0.9)
            chev:SetAlpha(0.45)
            if brd then
                brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12)
            end
        end
        -- Cards without settings are inert: no hover wash, no click-to-expand.
        -- Their dropdown still works on its own.
        if hasSettings then
            heading:SetScript("OnEnter", ApplyHeaderHover)
            heading:SetScript("OnLeave", ClearHeaderHover)
            -- The dropdown keeps its own hover scripts; hook (not replace) so the
            -- full row highlight also holds while the pointer is on the dropdown.
            dropdown:HookScript("OnEnter", ApplyHeaderHover)
            dropdown:HookScript("OnLeave", ClearHeaderHover)
            heading:SetScript("OnClick", function()
                _wsExpanded[window.key] = not _wsExpanded[window.key]
                CludesUI:RefreshPage(true)
            end)
        end

        posY = posY - WS_HEADER_H

        if expanded then
            -- Divider between the header and the card's settings
            local div = heading:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.07)
            div:SetHeight(1)
            Pix.Point(div, "BOTTOMLEFT", heading, "BOTTOMLEFT", 1, 0)
            Pix.Point(div, "BOTTOMRIGHT", heading, "BOTTOMRIGHT", -1, 0)
            Pix.DisablePixelSnap(div)

            posY = posY - 8
            posY = window.buildContent(hostFrame, posY)
            posY = posY - 8
        end

        -- Card background + border spanning the header and any expanded content. Child
        -- of the header, NOT the page wrapper: the inline search walks direct wrapper
        -- children, and as a header child the bg is never collected as a row, follows
        -- the header wherever the search re-flows it, and hides/shows with it for free.
        -- Explicitly sized because the header's own rect is the only anchor left.
        local backdrop = CreateFrame("Frame", nil, heading)
        backdrop:SetFrameLevel(hostFrame:GetFrameLevel())
        Pix.Size(backdrop, cardW, cardTop - posY)
        Pix.Point(backdrop, "TOPLEFT", heading, "TOPLEFT", 0, 0)
        brd = CludesUI.MakeRoundedCard(backdrop, expanded and 0.16 or 0.12)
        hbg = backdrop:CreateTexture(nil, "BACKGROUND", nil, 1)
        hbg:SetAllPoints(heading)
        hbg:SetColorTexture(0, 0, 0, 0)
        brd:Clip(hbg)

        -- Header-height only: the strip marks the header, never the expanded
        -- settings block below it.
        strip = backdrop:CreateTexture(nil, "ARTWORK")
        brd:Clip(strip)
        strip:SetWidth(2)
        Pix.Point(strip, "TOPLEFT", heading, "TOPLEFT", 1, -1)
        Pix.Point(strip, "BOTTOMLEFT", heading, "BOTTOMLEFT", 1, 1)
        if strip.SetSnapToPixelGrid then
            strip:SetSnapToPixelGrid(false)
            strip:SetTexelSnappingBias(0)
        end

        CludesUI.RegisterWidgetRefresh(RefreshCardState)
        RefreshCardState()

        return posY - WS_CARD_GAP
    end

    -- Per-profile master kill switch (the ONLY per-profile setting in this
    -- section): profile-root key disableWindowSkins, resolved live by
    -- CludesUI.BlizzWindowSkinsKilled(). Skins install at load, so every
    -- toggle shows the reload popup.
    local function WSKillSwitchSet(disabled)
        local prof = CludesUI.GetActiveProfileData()
        if not prof then
            return
        end
        prof.disableWindowSkins = disabled and true or nil
        -- Structural change (settings <-> hero takeover): force a rebuild,
        -- a plain refresh only re-reads widget values on the cached page.
        CludesUI:RefreshPage(true)
        WSReloadPopup(
            disabled
                    and "Window skins are now disabled for this profile. A UI reload is required to restore the stock Blizzard windows."
                or "Window skins are now enabled for this profile. A UI reload is required to apply them."
        )
    end

    -- Feature hero shown INSTEAD of the page content while window skins are
    -- disabled for this profile: the intro popup's art (three mini windows,
    -- eyebrow, bullets) rebuilt inline, with one big Enable button.
    local function BuildWindowSkinsDisabledHero(hostFrame, yOffset)
        local Pix = CludesUI.PanelPP
        local ACC = CludesUI.CLUDES_GREEN
        local L = CludesUI.L
        local MakeBorder = CludesUI.MakeBorder
        local FONT = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

        local HERO_H = 470
        local host = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(host, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, HERO_H)
        Pix.Point(host, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, yOffset - 24)

        -- Three mini Blizzard "windows" with colored title bars (the intro
        -- popup's header visual): center one scaled up with a resize grip.
        local CARD_W, CARD_H, CARD_GAP = 124, 52, 14
        local titleColors = {
            { ACC.r, ACC.g, ACC.b },
            { 0.25, 0.50, 0.90 },
            { 0.64, 0.39, 0.93 },
        }
        for idx = 1, 3 do
            local isCenter = (idx == 2)
            local wid = CARD_W
            local ch = isCenter and (CARD_H + 10) or CARD_H
            local cardFrame = CreateFrame("Frame", nil, host)
            cardFrame:SetFrameLevel(host:GetFrameLevel() + 1)
            Pix.Size(cardFrame, wid, ch)
            Pix.Point(cardFrame, "CENTER", host, "TOP", (idx - 2) * (CARD_W + CARD_GAP), -64)
            local cbg = cardFrame:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.121, 0.113, 0.106, 1)
            local c = titleColors[idx]
            local bar = cardFrame:CreateTexture(nil, "ARTWORK")
            bar:SetColorTexture(c[1], c[2], c[3], isCenter and 0.95 or 0.75)
            bar:SetHeight(8)
            Pix.Point(bar, "TOPLEFT", cardFrame, "TOPLEFT", 1, -1)
            Pix.Point(bar, "TOPRIGHT", cardFrame, "TOPRIGHT", -1, -1)
            if bar.SetSnapToPixelGrid then
                bar:SetSnapToPixelGrid(false)
                bar:SetTexelSnappingBias(0)
            end
            local dot = cardFrame:CreateTexture(nil, "OVERLAY")
            dot:SetColorTexture(0, 0, 0, 0.4)
            Pix.Size(dot, 4, 4)
            Pix.Point(dot, "RIGHT", bar, "RIGHT", -3, 0)
            local l1 = cardFrame:CreateTexture(nil, "ARTWORK")
            l1:SetColorTexture(1, 1, 1, isCenter and 0.42 or 0.32)
            Pix.Size(l1, wid - 26, 5)
            Pix.Point(l1, "TOPLEFT", cardFrame, "TOPLEFT", 13, -18)
            local l2 = cardFrame:CreateTexture(nil, "ARTWORK")
            l2:SetColorTexture(1, 1, 1, 0.18)
            Pix.Size(l2, wid - 46, 5)
            Pix.Point(l2, "TOPLEFT", l1, "BOTTOMLEFT", 0, -7)
            if isCenter then
                local l3 = cardFrame:CreateTexture(nil, "ARTWORK")
                l3:SetColorTexture(1, 1, 1, 0.14)
                Pix.Size(l3, wid - 66, 5)
                Pix.Point(l3, "TOPLEFT", l2, "BOTTOMLEFT", 0, -7)
                local grip = cardFrame:CreateTexture(nil, "OVERLAY")
                grip:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85)
                Pix.Size(grip, 5, 5)
                Pix.Point(grip, "BOTTOMRIGHT", cardFrame, "BOTTOMRIGHT", -2, 2)
            end
            MakeBorder(cardFrame, 1, 1, 1, isCenter and 0.16 or 0.10, Pix)
        end

        local eyebrow = host:CreateFontString(nil, "OVERLAY")
        eyebrow:SetFont(FONT, 13, "")
        eyebrow:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        Pix.Point(eyebrow, "TOP", host, "TOP", 0, -122)
        eyebrow:SetText(L("CUI FEATURE"))

        local title = host:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 25, "")
        title:SetTextColor(1, 1, 1, 1)
        Pix.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
        title:SetText(L("Blizzard Window Skinning"))

        local desc = host:CreateFontString(nil, "OVERLAY")
        desc:SetFont(FONT, 15, "")
        desc:SetTextColor(1, 1, 1, 0.5)
        desc:SetWidth(430)
        desc:SetJustifyH("CENTER")
        desc:SetWordWrap(true)
        Pix.Point(desc, "TOP", title, "BOTTOM", 0, -12)
        desc:SetText(
            L(
                "Blizzard's windows match the CludesUI theme with a WoW 2.0 Dark Theme, from the Dungeon Journal to the Auction House and beyond."
            )
        )

        local BULLETS = {
            "Every major Blizzard window themed to match CUI",
            "Recolor the theme to any color and opacity you like",
            "Scale any window larger or smaller with Shifter",
        }
        local prev
        for idx, textValue in ipairs(BULLETS) do
            local bl = host:CreateFontString(nil, "OVERLAY")
            bl:SetFont(FONT, 14, "")
            bl:SetTextColor(1, 1, 1, 0.72)
            bl:SetJustifyH("LEFT")
            if idx == 1 then
                Pix.Point(bl, "TOP", host, "TOP", -20, -252)
                bl:SetPoint("LEFT", host, "CENTER", -160, 0)
            else
                Pix.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
            end
            bl:SetText(L(textValue))
            local bdot = host:CreateTexture(nil, "OVERLAY")
            bdot:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
            Pix.Size(bdot, 5, 5)
            Pix.Point(bdot, "RIGHT", bl, "LEFT", -10, 0)
            prev = bl
        end

        local enableBtn = CreateFrame("Button", nil, host)
        Pix.Size(enableBtn, 220, 40)
        Pix.Point(enableBtn, "TOP", host, "TOP", 0, -344)
        enableBtn:SetFrameLevel(host:GetFrameLevel() + 2)
        CludesUI.MakeStyledButton(enableBtn, "Enable Window Skins", 15, CludesUI.WB_COLOURS, function()
            WSKillSwitchSet(false)
        end)

        local footnote = host:CreateFontString(nil, "OVERLAY")
        footnote:SetFont(FONT, 12, "")
        footnote:SetTextColor(1, 1, 1, 0.35)
        Pix.Point(footnote, "TOP", enableBtn, "BOTTOM", 0, -12)
        footnote:SetText(L("Window skins are currently disabled for this profile."))

        -- Builders return the page's total HEIGHT (positive), same as the
        -- normal page's math.abs(y) tail.
        return math.abs(yOffset - 24 - HERO_H)
    end

    ---------------------------------------------------------------------------
    --  THIRD-PARTY ADDONS section: addons that registered for CUI skinning
    --  via CludesUI.RegisterSkin (SkinAPI). Deliberately independent of
    --  the per-profile kill switch and of every per-window setting -- window
    --  styles only decide WHICH theme third-party skins get -- so it renders
    --  on both the normal page and the disabled hero. Hidden entirely when
    --  no addon has registered. Skins install at load: turning a toggle ON
    --  applies live when possible, turning OFF is reload-bound.
    ---------------------------------------------------------------------------
    local function BuildThirdPartySection(hostFrame, posY)
        local W = CludesUI.Widgets
        local entries = mod.GetThirdPartySkinList and mod.GetThirdPartySkinList()
        if not entries or #entries == 0 then
            return posY
        end

        local _, hgt
        _, hgt = W:Spacer(hostFrame, posY, 10)
        posY = posY - hgt
        _, hgt = W:SectionHeader(hostFrame, "THIRD-PARTY ADDONS", posY)
        posY = posY - hgt

        local function MasterOff()
            return (CludesUIDB and CludesUIDB.thirdPartySkinsOff) and true or false
        end
        local function TurnedOn()
            -- Live-apply any skins that can install right now; only removal
            -- needs the reload.
            local fired = mod.TryDispatchThirdPartySkins and mod.TryDispatchThirdPartySkins()
            CludesUI:RefreshPage()
            if not fired then
                WSReloadPopup("Some addon skins could not apply live. A UI reload will fully apply them.")
            end
        end

        local itemList = {}
        itemList[1] = {
            type = "toggle",
            text = "Skin Third-Party Addons",
            tooltip = "Master switch for skinning other addons that support the CludesUI skinning API.",
            getValue = function()
                return not MasterOff()
            end,
            setValue = function(val)
                Account().thirdPartySkinsOff = (not val) and true or nil
                if val then
                    TurnedOn()
                else
                    CludesUI:RefreshPage()
                    WSReloadPopup("Removing third-party addon skins requires a UI reload.")
                end
            end,
        }
        for _, details in ipairs(entries) do
            local name = details.name
            itemList[#itemList + 1] = {
                type = "toggle",
                text = name,
                tooltip = "Skin " .. name .. " to match the CludesUI theme.",
                disabled = MasterOff,
                disabledTooltip = "Enable Skin Third-Party Addons",
                getValue = function()
                    local t = CludesUIDB and CludesUIDB.thirdPartySkinAddons
                    return not (t and t[name] == false)
                end,
                setValue = function(val)
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    local t = CludesUIDB.thirdPartySkinAddons
                    if not t then
                        t = {}
                        CludesUIDB.thirdPartySkinAddons = t
                    end
                    if val then
                        t[name] = nil
                    else
                        t[name] = false
                    end
                    if val then
                        TurnedOn()
                    else
                        WSReloadPopup("Removing " .. name .. "'s skin requires a UI reload.")
                    end
                end,
            }
        end
        local h2
        for idx = 1, #itemList, 2 do
            _, h2 =
                W:DualRow(hostFrame, posY, itemList[idx], itemList[idx + 1] or { type = "label", text = "" })
            posY = posY - h2
        end
        return posY
    end

    local function BuildWindowSkinsPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PanelPP
        local L = CludesUI.L
        local posY = yOffset
        local _, hgt

        hostFrame._showRowDivider = true

        -- Per-profile kill switch takeover: while window skins are disabled
        -- for this profile, hide every setting and show the feature hero.
        -- Third-party skinning is decoupled from the kill switch, so its
        -- section stays reachable below the hero.
        if CludesUI.BlizzWindowSkinsKilled and CludesUI.BlizzWindowSkinsKilled() then
            local heroH = BuildWindowSkinsDisabledHero(hostFrame, yOffset)
            local y2 = BuildThirdPartySection(hostFrame, -heroH)
            return math.abs(y2)
        end

        _, hgt = W:Spacer(hostFrame, posY, 14)
        posY = posY - hgt

        -- Hosted on a sized frame (not a raw region on the wrapper) so the
        -- inline search hides it while filtering and restores it on clear;
        -- regions are invisible to the search and would float over results.
        local introHost = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(introHost, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, 20)
        Pix.Point(introHost, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, posY)
        local intro = CludesUI.MakeFont(introHost, 13, nil, 1, 1, 1, 0.5)
        Pix.Point(intro, "TOP", introHost, "TOP", 0, 0)
        intro:SetText(L("Pick a style for all reskinned Blizzard windows."))

        -- Per-profile master switch (top right; the only per-profile setting
        -- in this section). One step below Blizz Default: no-ops the whole
        -- window engine + CharacterSheet/Inspect + LFG skinning. Reload-bound.
        local disBtn = CreateFrame("Button", nil, introHost)
        Pix.Size(disBtn, 160, 24)
        Pix.Point(disBtn, "RIGHT", introHost, "RIGHT", 0, 0)
        disBtn:SetFrameLevel(introHost:GetFrameLevel() + 3)
        CludesUI.MakeStyledButton(disBtn, "Disable Window Skins", 11, CludesUI.WB_COLOURS, function()
            WSKillSwitchSet(true)
        end)
        disBtn:HookScript("OnEnter", function(s)
            CludesUI.ShowWidgetTooltip(
                s,
                L("Turns off ALL window skinning for this profile. Requires a reload.")
            )
        end)
        disBtn:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)

        posY = posY - 28

        -- Set-all row: pick a style, then push it to every window below. The
        -- swatch + cog edit the GLOBAL Modern background (windows without a
        -- per-window override follow it).
        local allDD = CludesUI.BuildDropdownControl(
            hostFrame,
            170,
            hostFrame:GetFrameLevel() + 3,
            WS_STYLE_VALUES,
            WS_STYLE_ORDER,
            function()
                return _wsApplyAllStyle
            end,
            function(val)
                _wsApplyAllStyle = val
                CludesUI:RefreshPage()
            end
        )
        Pix.Point(allDD, "TOPLEFT", hostFrame, "TOP", -115, posY)
        allDD._ttText = "Style to apply to every window below."
        AttachModernSwatch(hostFrame, allDD, function()
            return _wsApplyAllStyle ~= "modern"
        end)

        local applyBtn = CreateFrame("Button", nil, hostFrame)
        Pix.Size(applyBtn, 110, 30)
        Pix.Point(applyBtn, "LEFT", allDD, "RIGHT", 10, 0)
        applyBtn:SetFrameLevel(hostFrame:GetFrameLevel() + 3)
        CludesUI.MakeStyledButton(applyBtn, "Apply to All", 12, CludesUI.WB_COLOURS, function()
            local crossed = false
            for _, window in ipairs(WINDOWS) do
                local style = (_wsApplyAllStyle == "off" and window.blizzDefault) or _wsApplyAllStyle
                if not WSStyleOwned(window) and WSSetStyle(window, style, true) then
                    crossed = true
                end
            end
            CludesUI:RefreshPage()
            if crossed then
                WSReloadPopup("Changing window skin styles requires a UI reload to fully apply.")
            end
        end)
        posY = posY - 30 - 26

        -- GLOBAL OPTIONS: look settings shared by every reskinned window.
        _, hgt = W:SectionHeader(hostFrame, "GLOBAL OPTIONS", posY)
        posY = posY - hgt

        local gRow1
        gRow1, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Accent Bar",
            tooltip = "Accent bar on the active tab of reskinned windows.",
            getValue = function()
                local c = WSLook("blizzWinAccentBar")
                return not (c and c.enabled == false)
            end,
            setValue = function(val)
                WSLookSet("blizzWinAccentBar", "enabled", val and true or false)
            end,
        }, {
            type = "slider",
            text = "Bar Fill Opacity",
            min = 10,
            max = 100,
            step = 1,
            getValue = function()
                local c = WSLook("blizzWinBarFill")
                return math.floor(((c and c.alpha) or 0.95) * 100 + 0.5)
            end,
            setValue = function(val)
                WSLookSet("blizzWinBarFill", "alpha", val / 100)
            end,
        })
        if not CludesUI._prebuilding then
            AttachLookSwatches(gRow1._leftRegion, gRow1, "blizzWinAccentBar")
            AttachLookSwatches(gRow1._rightRegion, gRow1, "blizzWinBarFill")
        end
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "multiSwatch",
            text = "Link Color",
            swatches = {
                {
                    tooltip = "Accent Color",
                    getValue = function()
                        return CludesUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        WSLookSet("blizzWinLinks", "useCustom", false)
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = WSLook("blizzWinLinks")
                        return (c and c.useCustom) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Custom Color",
                    getValue = function()
                        local c = WSLook("blizzWinLinks")
                        local col = c and c.color
                        if col then
                            return col.r or 1, col.g or 1, col.b or 1
                        end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        WSLookSet("blizzWinLinks", "color", { r = r, g = g, b = b })
                        WSLookSet("blizzWinLinks", "useCustom", true)
                        CludesUI:RefreshPage()
                    end,
                    onClick = function(self)
                        local c = WSLook("blizzWinLinks")
                        if not (c and c.useCustom) then
                            WSLookSet("blizzWinLinks", "useCustom", true)
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local c = WSLook("blizzWinLinks")
                        return (c and c.useCustom) and 1 or 0.3
                    end,
                },
            },
        }, { type = "label", text = "" })
        posY = posY - hgt

        -- Breathing room between the global settings and the window cards.
        posY = posY - 30

        -- Cards with their own settings content (buildContent) sit at the top of the
        -- list, keeping their relative order; plain style-only cards follow in theirs.
        -- WINDOWS itself stays in its defined order -- the apply-all and reset loops
        -- don't care, and new entries keep being added by category there.
        local ordered = {}
        for _, window in ipairs(WINDOWS) do
            if window.buildContent then
                ordered[#ordered + 1] = window
            end
        end
        for _, window in ipairs(WINDOWS) do
            if not window.buildContent then
                ordered[#ordered + 1] = window
            end
        end
        for _, window in ipairs(ordered) do
            posY = BuildWindowCard(hostFrame, posY, window)
        end

        posY = BuildThirdPartySection(hostFrame, posY)

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        return math.abs(posY)
    end

    ---------------------------------------------------------------------------
    --  Dragon Riding page
    ---------------------------------------------------------------------------
    local function EDR_DB()
        return mod.edrDB and mod.edrDB.profile
    end
    local function EDR_Cfg(k)
        local p = EDR_DB()
        return p and p[k]
    end
    local function EDR_Set(k, val)
        local p = EDR_DB()
        if p then
            p[k] = val
        end
    end
    local function EDR_SetField(k, field, val)
        local t = EDR_Cfg(k)
        if t then
            t[field] = val
        end
    end
    local function EDR_Rebuild()
        if mod.edrRebuild then
            mod.edrRebuild()
        end
        CludesUI:RefreshPage()
    end
    local function EDR_Redraw()
        if mod.edrRedraw then
            mod.edrRedraw()
        end
    end

    -------------------------------------------------------------------
    --  Bar texture dropdown tables (shared media path, same as ERB)
    -------------------------------------------------------------------
    local EDR_BAR_TEXTURES = mod.EDR_BAR_TEXTURES
    local _, EDR_BAR_TEXTURE_NAMES, EDR_BAR_TEXTURE_ORDER = CludesUI.BuildBarTextureTables()

    -- Live sample bubble in the content header; sized to the bubble plus margin.
    local function ChatBubblesHeaderBuilder(header)
        local building = true
        local function HeightFor(bubbleH)
            return math.max(80, math.floor(bubbleH + 40))
        end
        local bubble = CludesUI.ChatBubbles.ShowPreview(header, function(bubbleH)
            local wanted = HeightFor(bubbleH)
            if not building and header:IsVisible() and math.abs(header:GetHeight() - wanted) > 1 then
                CludesUI:SetContentHeaderHeightSilent(wanted)
            end
        end)
        building = false
        return HeightFor(bubble:GetHeight())
    end

    -- Sample Skyriding HUD in the content header, painted by the HUD's own
    -- passes (ns.EDR_ShowSample).
    local SkyridingHeaderBuilder = SampleHeaderBuilder({
        {
            show = function(header, place)
                if mod.EDR_ShowSample then
                    mod.EDR_ShowSample(header, place)
                end
            end,
        },
    })

    local function BuildChatBubblesPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local posY = yOffset
        local _, hgt

        hostFrame._showRowDivider = true
        if not CludesUI._prebuilding then
            CludesUI:SetContentHeader(ChatBubblesHeaderBuilder)
        elseif CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end

        local CBM = CludesUI.ChatBubbles
        -- Reads never create the profile table; writes do.
        local function BBDB()
            return CBM.DB(true)
        end
        -- Same defaults table the renderer reads, so a widget can never offer a value the
        -- bubble would not actually draw.
        local function CBVal(key)
            local saved = CBM.DB(false)
            local val = saved and saved[key]
            if val ~= nil then
                return val
            end
            return CBM.Defaults()[key]
        end
        -- Structural write: can change whether we draw at all, or which of Blizzard's
        -- CVars we hold down, so it runs the renderer's full pass.
        local function CBSet(key, val)
            local saved = BBDB()
            if not saved then
                return
            end
            saved[key] = val
            CBM.Refresh()
        end
        -- Appearance write: nothing here can move a channel or one of Blizzard's CVars, so
        -- it only re-styles what is already on screen. Worth the split because a slider
        -- fires this per STEP while it is dragged, and the full pass re-diffs every event
        -- registration and round-trips Blizzard's three switches every time.
        local function CBSetStyle(key, val)
            local saved = BBDB()
            if not saved then
                return
            end
            saved[key] = val
            CBM.RefreshStyle()
        end
        -- A cog or row control on one style key: reads it through CBVal, writes
        -- it through CBSetStyle.
        local function CBGetter(key)
            return function()
                return CBVal(key)
            end
        end
        local function CBSetter(key)
            return function(val)
                CBSetStyle(key, val)
            end
        end
        local function CBColor(key)
            local c = CBVal(key)
            if not c then
                return 1, 1, 1, 1
            end
            return c.r, c.g, c.b, c.a or 1
        end
        local function Off()
            return CBVal("enabled") ~= true
        end
        local GATE = "Enable Chat Bubbles Customization"
        -- The toggle's own label reads as an instruction; DisabledTooltip wraps whatever it
        -- is handed in "This option requires %1$s to be enabled", which needs a plain noun.
        local GATE_REQ = "Chat Bubbles"

        -- Red warning banner: NOT a section header for what follows -- our own bubbles
        -- never show inside instances, unconditionally, and that has to be visible before
        -- the player reads any option below it, not styled as their category label.
        -- Skipped while the search index prebuilds the page off screen: the banner carries
        -- no setting to index and parent:GetWidth() is not meaningful there. The height
        -- still comes off y in both passes, so everything below lands identically.
        if not CludesUI._prebuilding then
            local warnFrame = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(warnFrame, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, 30)
            Pix.Point(warnFrame, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, posY)
            local warnFS = CludesUI.MakeFont(warnFrame, 14, "", 1, 0.25, 0.25, 1)
            warnFS:SetPoint("LEFT", warnFrame, "LEFT", 0, 0)
            warnFS:SetText(CludesUI.L("Only works outside of Instances"))
        end
        posY = posY - 30

        _, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt

        local channelsRow
        channelsRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = GATE,
            getValue = function()
                return CBVal("enabled") == true
            end,
            setValue = function(val)
                if not val then
                    CBSet("enabled", false)
                    CludesUI:RefreshPage()
                    return
                end
                local message =
                    "CludesUI restyles Blizzard's chat bubbles and turns on the switches it needs. Party and Raid keep your current setting, and everything is put back when you turn this off."
                CludesUI:ShowConfirmPopup({
                    title = GATE,
                    message = message,
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = function()
                        CBSet("enabled", true)
                        CludesUI:RefreshPage()
                    end,
                    onCancel = function()
                        CludesUI:RefreshPage()
                    end,
                })
            end,
        }, {
            type = "dropdown",
            text = "Channels",
            tooltip = "Choose which channels get a bubble.",
            disabled = Off,
            disabledTooltip = GATE_REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        posY = posY - hgt

        if not CludesUI._prebuilding then
            local region = channelsRow._rightRegion
            if region._control then
                region._control:Hide()
            end
            local channelItems = {
                { key = "say", label = "Say" },
                { key = "yell", label = "Yell" },
                { key = "party", label = "Party", tooltip = "Includes instance chat." },
                { key = "raid", label = "Raid" },
                { key = "npc", label = "NPCs" },
                { key = "emote", label = "Emotes" },
            }
            local chDD, chDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                240,
                region:GetFrameLevel() + 2,
                channelItems,
                function(k)
                    return CBVal(k) == true
                end,
                function(k, val)
                    CBSet(k, val)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = Off, disabledTooltip = GATE_REQ }
            )
            CludesUI.PanelPP.Point(chDD, "RIGHT", region, "RIGHT", -20, 0)
            region._control = chDD
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(chDDRefresh)
        end

        -- Structural, not appearance: it decides which of Blizzard's switches we hold and at
        -- what value, so it takes the full pass. Half-empty right slot is allowed here because
        -- this is the last row of its section.
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Hide Chat Bubbles in Instances",
            getValue = function()
                return CBVal("hideInInstances") == true
            end,
            setValue = function(val)
                CBSet("hideInInstances", val)
            end,
            disabled = Off,
            disabledTooltip = GATE_REQ,
        }, { type = "label", text = "" })
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "APPEARANCE", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Padding",
            min = 2,
            max = 24,
            step = 1,
            tooltip = "Space between the text and the edge of the bubble.",
            getValue = CBGetter("padding"),
            setValue = CBSetter("padding"),
            disabled = Off,
            disabledTooltip = GATE_REQ,
        }, {
            type = "slider",
            text = "Maximum Width",
            min = 120,
            max = 500,
            step = 10,
            getValue = CBGetter("maxWidth"),
            setValue = CBSetter("maxWidth"),
            disabled = Off,
            disabledTooltip = GATE_REQ,
        })
        posY = posY - hgt

        local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
        local fontBorderRow
        fontBorderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Font",
            values = fontValues,
            order = fontOrder,
            getValue = CBGetter("font"),
            setValue = CBSetter("font"),
            disabled = Off,
            disabledTooltip = GATE_REQ,
        }, {
            type = "slider",
            text = "Border",
            min = 0,
            max = 4,
            step = 1,
            getValue = CBGetter("borderSize"),
            setValue = CBSetter("borderSize"),
            disabled = Off,
            disabledTooltip = GATE_REQ,
        })
        posY = posY - hgt

        if not CludesUI._prebuilding then
            -- Built BEFORE the swatch on purpose: the cog sits beside the control, and
            -- BuildInlineSwatches chains _lastInline, so the swatch lands to its left.
            CludesUI.BuildInlineCog(fontBorderRow._leftRegion, {
                disabled = Off,
                disabledTooltip = GATE_REQ,
                title = "Font",
                rows = {
                    {
                        type = "slider",
                        label = "Font Size",
                        min = 8,
                        max = 24,
                        step = 1,
                        get = CBGetter("fontSize"),
                        set = CBSetter("fontSize"),
                    },
                    {
                        type = "dropdown",
                        label = "Outline",
                        values = {
                            __global = "CUI Global Outline",
                            none = "Drop Shadow",
                            outline = "Outline",
                            thick = "Thick Outline",
                        },
                        order = { "__global", "none", "outline", "thick" },
                        get = CBGetter("outline"),
                        set = CBSetter("outline"),
                    },
                    {
                        type = "toggle",
                        label = "Follow Blizzard Default Color",
                        get = function()
                            return CBVal("followBlizzardColor") == true
                        end,
                        set = function(val)
                            CBSetStyle("followBlizzardColor", val)
                            CludesUI:RefreshPage()
                        end,
                    },
                },
            })

            -- BuildInlineSwatches, not a hand-rolled BuildColorSwatch: it is the house form for
            -- a swatch riding on a control half. It anchors through PP.Point, registers the
            -- swatch's refresh so a profile switch repaints it, and builds the greyed-out block
            -- plus tooltip from opts.disabled.
            CludesUI.BuildInlineSwatches(fontBorderRow._leftRegion, {
                {
                    getValue = function()
                        local r, g, b = CBColor("textColor")
                        return r, g, b, 1
                    end,
                    setValue = function(r, g, b)
                        CBSetStyle("textColor", { r = r, g = g, b = b })
                    end,
                    -- Two reasons this swatch can be dead, so the tip is resolved per reason.
                    disabled = function()
                        return Off() or CBVal("followBlizzardColor") == true
                    end,
                    disabledTooltip = function()
                        return Off() and GATE_REQ or "Follow Blizzard Default Color"
                    end,
                    requireState = function()
                        return Off() and "enabled" or "disabled"
                    end,
                },
            }, { disabled = Off, disabledTooltip = GATE_REQ })

            CludesUI.BuildInlineSwatches(fontBorderRow._rightRegion, {
                {
                    getValue = function()
                        return CBColor("borderColor")
                    end,
                    setValue = function(r, g, b, a)
                        CBSetStyle("borderColor", { r = r, g = g, b = b, a = a })
                    end,
                    hasAlpha = true,
                },
            }, { disabled = Off, disabledTooltip = GATE_REQ })
        end

        local nameRow
        nameRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Show Speaker Name",
            tooltip = "Choose which channels show the speaker.",
            disabled = Off,
            disabledTooltip = GATE_REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, {
            type = "slider",
            text = "Vertical Offset",
            min = -80,
            max = 80,
            step = 2,
            getValue = CBGetter("offsetY"),
            setValue = CBSetter("offsetY"),
            disabled = Off,
            disabledTooltip = GATE_REQ,
        })
        posY = posY - hgt

        -- Same build as the Channels dropdown above.
        if not CludesUI._prebuilding then
            local region = nameRow._leftRegion
            if region._control then
                region._control:Hide()
            end
            local nameItems = {
                { key = "say", label = "Say" },
                { key = "yell", label = "Yell" },
                { key = "party", label = "Party" },
                { key = "raid", label = "Raid" },
                { key = "npc", label = "NPCs" },
                { key = "emote", label = "Emotes" },
            }
            local nmDD, nmDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                240,
                region:GetFrameLevel() + 2,
                nameItems,
                function(k)
                    local t = CBVal("showName")
                    return type(t) == "table" and t[k] == true
                end,
                function(k, val)
                    local saved = BBDB()
                    if not saved then
                        return
                    end
                    if type(saved.showName) ~= "table" then
                        saved.showName = {}
                    end
                    saved.showName[k] = val or nil
                    CBM.RefreshStyle()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = Off, disabledTooltip = GATE_REQ }
            )
            CludesUI.PanelPP.Point(nmDD, "RIGHT", region, "RIGHT", -20, 0)
            region._control = nmDD
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(nmDDRefresh)

            CludesUI.BuildInlineCog(region, {
                disabled = Off,
                disabledTooltip = GATE_REQ,
                title = "Speaker Name",
                rows = {
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = {
                            TOPLEFT = "Top Left",
                            TOP = "Top",
                            TOPRIGHT = "Top Right",
                            BOTTOMLEFT = "Bottom Left",
                            BOTTOM = "Bottom",
                            BOTTOMRIGHT = "Bottom Right",
                        },
                        order = { "TOPLEFT", "TOP", "TOPRIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
                        get = CBGetter("nameAnchor"),
                        set = CBSetter("nameAnchor"),
                    },
                    {
                        type = "slider",
                        label = "Font Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        get = CBGetter("nameFontSize"),
                        set = CBSetter("nameFontSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = CBGetter("nameOffsetX"),
                        set = CBSetter("nameOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = CBGetter("nameOffsetY"),
                        set = CBSetter("nameOffsetY"),
                    },
                },
            })
        end

        -- Last row of the section, so the empty right slot is allowed.
        local bgRow
        bgRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Background",
            getValue = function()
                return CBVal("background") ~= false
            end,
            setValue = function(val)
                CBSetStyle("background", val)
                CludesUI:RefreshPage()
            end,
            disabled = Off,
            disabledTooltip = GATE_REQ,
        }, { type = "label", text = "" })
        posY = posY - hgt

        -- Colour and opacity are one swatch but two stored keys, so the write goes straight
        -- to the DB rather than through CBSetStyle.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineSwatches(bgRow._leftRegion, {
                {
                    getValue = function()
                        local r, g, b = CBColor("bgColor")
                        return r, g, b, CBVal("bgAlpha")
                    end,
                    setValue = function(r, g, b, a)
                        local saved = BBDB()
                        if not saved then
                            return
                        end
                        saved.bgColor = { r = r, g = g, b = b }
                        saved.bgAlpha = a
                        CBM.RefreshStyle()
                    end,
                    hasAlpha = true,
                    disabled = function()
                        return Off() or CBVal("background") == false
                    end,
                    disabledTooltip = function()
                        return Off() and GATE_REQ or "Background"
                    end,
                },
            })
        end

        return math.abs(posY)
    end

    local function BuildDragonRidingPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt

        hostFrame._showRowDivider = true

        -- Append SharedMedia textures (safe to call multiple times)
        CludesUI.AppendSharedMediaTextures(
            EDR_BAR_TEXTURE_NAMES,
            EDR_BAR_TEXTURE_ORDER,
            nil,
            EDR_BAR_TEXTURES
        )
        local edrTexValues = {}
        local edrTexOrder = {}
        for _, key in ipairs(EDR_BAR_TEXTURE_ORDER) do
            if key ~= "---" then
                edrTexValues[key] = EDR_BAR_TEXTURE_NAMES[key] or key
                edrTexOrder[#edrTexOrder + 1] = key
            end
        end
        edrTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return EDR_BAR_TEXTURES[key]
            end,
        }

        local justifyValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local justifyOrder = { "LEFT", "CENTER", "RIGHT" }

        -- The bar art is chosen on Global Settings > Style ("Skyriding HUD")
        -- and latched for the session like every other module's style, so
        -- the rows below are laid out for the look the HUD renders.
        local BS = CludesUI.BlizzStyle
        local edrStyle = BS.Active("dragonriding")

        -- The sample HUD heads the page while the bar is on; off, the page
        -- hides everything below its first row and shows no header either.
        if not CludesUI._prebuilding and EDR_Cfg("enabled") == true then
            CludesUI:SetContentHeader(SkyridingHeaderBuilder)
        elseif CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end

        -- The Move in Unlock Mode button on the bar's first section, built
        -- whatever Enable Skyriding Bar says: its disabled state explains itself.
        local heading
        heading, hgt = W:SectionHeader(hostFrame, "GENERAL", posY)
        posY = posY - hgt
        CludesUI.BuildSectionUnlockJump(heading, {
            key = "EDR_Cluster",
            disabled = function()
                return EDR_Cfg("enabled") ~= true
            end,
            disabledTooltip = "Skyriding Bar",
        })
        posY = BS.Note(hostFrame, posY, "dragonriding")
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Skyriding Bar",
            getValue = function()
                return EDR_Cfg("enabled") == true
            end,
            -- DependentSetValue: everything below Row 1 is hidden while the
            -- bar is off; the flip forces the full rebuild.
            setValue = CludesUI.DependentSetValue(function()
                return EDR_Cfg("enabled") == true
            end, function(val)
                EDR_Set("enabled", val)
                EDR_Rebuild()
            end),
        }, {
            type = "toggle",
            text = "Hide in Combat",
            disabled = function()
                return EDR_Cfg("enabled") ~= true
            end,
            disabledTooltip = "Skyriding Bar",
            getValue = function()
                return EDR_Cfg("hideInCombat") == true
            end,
            setValue = function(val)
                EDR_Set("hideInCombat", val)
                EDR_Rebuild()
            end,
        })
        posY = posY - hgt

        -- Everything below Row 1 (the rest of GENERAL plus the LAYOUT and
        -- SPEED BAR sections) is HIDDEN entirely while the bar is off.
        if EDR_Cfg("enabled") == true then
            local function EDR_IsGems()
                return EDR_Cfg("vigorStyle") == "gems"
            end
            local function EDR_ShowSpeed()
                return EDR_Cfg("showSpeed") ~= false
            end
            local function EDR_ShowSW()
                return EDR_Cfg("showSecondWind") ~= false
            end
            local function EDR_WSOff()
                return EDR_Cfg("showWhirlingSurge") == false
            end
            -- The icon's automatic size, in the Icon Size slider's range.
            local function EDR_AutoIconSize()
                local val = math.floor(((mod.edrIconSize and mod.edrIconSize()) or 34) + 0.5)
                return math.max(16, math.min(80, val))
            end

            -- The parts the HUD shows. The speed bar's and Second Wind's own
            -- rows exist only while they are shown, so those two rebuild the page.
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Show Speed Bar",
                getValue = EDR_ShowSpeed,
                setValue = CludesUI.DependentSetValue(EDR_ShowSpeed, function(val)
                    EDR_Set("showSpeed", val)
                    EDR_Rebuild()
                end),
            }, {
                type = "toggle",
                text = "Show Second Wind",
                getValue = EDR_ShowSW,
                setValue = CludesUI.DependentSetValue(EDR_ShowSW, function(val)
                    EDR_Set("showSecondWind", val)
                    EDR_Rebuild()
                end),
            })
            posY = posY - hgt
            local wsRow
            wsRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Show Whirling Surge",
                getValue = function()
                    return not EDR_WSOff()
                end,
                setValue = function(val)
                    EDR_Set("showWhirlingSurge", val)
                    EDR_Rebuild()
                end,
            }, {
                type = "toggle",
                text = "Show Icon Cooldown Text",
                disabled = EDR_WSOff,
                disabledTooltip = "Show Whirling Surge",
                getValue = function()
                    return EDR_Cfg("whirlingSurgeText") and EDR_Cfg("whirlingSurgeText").enabled ~= false
                end,
                setValue = function(val)
                    EDR_SetField("whirlingSurgeText", "enabled", val)
                    EDR_Redraw()
                end,
            })
            posY = posY - hgt
            -- Icon size: automatic (as tall as the bars) while Auto Size is on;
            -- turning it off hands the slider the current automatic size.
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(wsRow._leftRegion, {
                    title = "Whirling Surge Icon",
                    disabled = EDR_WSOff,
                    disabledTooltip = "Show Whirling Surge",
                    rows = {
                        {
                            type = "toggle",
                            label = "Auto Size",
                            tooltip = "Keeps the icon as tall as the bars.",
                            get = function()
                                return EDR_Cfg("iconSize") == nil
                            end,
                            set = function(val)
                                if val then
                                    EDR_Set("iconSize", nil)
                                else
                                    EDR_Set("iconSize", EDR_AutoIconSize())
                                end
                                EDR_Rebuild()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Icon Size",
                            min = 16,
                            max = 80,
                            step = 1,
                            disabled = function()
                                return EDR_Cfg("iconSize") == nil
                            end,
                            disabledTooltip = "Auto Size",
                            requireState = "disabled",
                            get = function()
                                return EDR_Cfg("iconSize") or EDR_AutoIconSize()
                            end,
                            set = function(val)
                                EDR_Set("iconSize", val)
                                EDR_Rebuild()
                            end,
                        },
                    },
                })
            end
            -- Classic Gems replaces the charge row with Blizzard's original gems
            -- (the page rebuilds: the Charge row and the gem scale follow it).
            -- The cog holds the full-charge chime and, for the gems, their scale.
            local vigorRow
            vigorRow, hgt = W:DualRow(hostFrame, posY, {
                type = "segmented",
                text = "Vigor Style",
                values = { bars = "Bars", gems = "Classic Gems" },
                order = { "bars", "gems" },
                tooltip = "Classic Gems brings back Blizzard's original vigor display above the bars.",
                getValue = function()
                    return EDR_Cfg("vigorStyle") or "bars"
                end,
                setValue = CludesUI.DependentSetValue(EDR_IsGems, function(val)
                    EDR_Set("vigorStyle", val)
                    EDR_Rebuild()
                end),
            }, {
                type = "slider",
                pixel = true,
                text = "Stack Spacing",
                min = 0,
                max = 10,
                step = 1,
                -- The gap between pips: nothing to space with no pip row shown.
                disabled = function()
                    return EDR_IsGems() and not EDR_ShowSW()
                end,
                disabledTooltip = "This option requires the Bars vigor style or Show Second Wind",
                getValue = function()
                    return EDR_Cfg("stackSpacing")
                end,
                setValue = function(val)
                    EDR_Set("stackSpacing", val)
                    EDR_Rebuild()
                end,
            })
            posY = posY - hgt
            if not CludesUI._prebuilding then
                local vigorRows = {
                    {
                        type = "toggle",
                        label = "Play Sound on Full Charge",
                        tooltip = "Plays Blizzard's vigor chime each time a skyriding charge fills.",
                        get = function()
                            return EDR_Cfg("chargeSound") == true
                        end,
                        set = function(val)
                            EDR_Set("chargeSound", val)
                        end,
                    },
                }
                if EDR_IsGems() then
                    vigorRows[2] = {
                        type = "slider",
                        label = "Gem Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.05,
                        get = function()
                            return EDR_Cfg("classicScale") or 1
                        end,
                        set = function(val)
                            EDR_Set("classicScale", val)
                            EDR_Rebuild()
                        end,
                    }
                end
                CludesUI.BuildInlineCog(vigorRow._leftRegion, { title = "Vigor", rows = vigorRows })
            end
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "slider",
                text = "Width",
                min = 80,
                max = 600,
                step = 1,
                getValue = function()
                    return EDR_Cfg("width")
                end,
                setValue = function(val)
                    EDR_Set("width", val)
                    EDR_Rebuild()
                end,
            }, {
                type = "slider",
                pixel = true,
                text = "Element Spacing",
                min = 0,
                max = 12,
                step = 1,
                getValue = function()
                    return EDR_Cfg("gap")
                end,
                setValue = function(val)
                    EDR_Set("gap", val)
                    EDR_Rebuild()
                end,
            })
            posY = posY - hgt
            -- Border Size: the CludesUI border and its colour on the
            -- CludesUI look; under Classic WoW UI the slot sizes the vanilla
            -- frame, as the Resource Bars' Border Size does; Blizzard Style's
            -- panel has no size to set.
            local borderCfg
            if edrStyle == "classic" then
                borderCfg = BS.ClassicBorderSizeCfg(function()
                    return EDR_Cfg("classicFrameSize")
                end, function(val)
                    EDR_Set("classicFrameSize", val)
                    EDR_Rebuild()
                end)
            else
                borderCfg = BS.Gate("dragonriding", {
                    type = "slider",
                    text = "Border Size",
                    min = 0,
                    max = 4,
                    step = 1,
                    getValue = function()
                        return EDR_Cfg("borderThickness") or 0
                    end,
                    setValue = function(val)
                        EDR_Set("borderThickness", val)
                        EDR_Redraw()
                        CludesUI:RefreshPage()
                    end,
                })
            end
            local borderRow
            borderRow, hgt = W:DualRow(hostFrame, posY, borderCfg, {
                type = "dropdown",
                text = "Bar Texture",
                values = edrTexValues,
                order = edrTexOrder,
                getValue = function()
                    return EDR_Cfg("barTexture") or "none"
                end,
                setValue = function(val)
                    EDR_Set("barTexture", val)
                    EDR_Redraw()
                end,
            })
            posY = posY - hgt
            if not CludesUI._prebuilding and edrStyle == "cui" then
                local region = borderRow._leftRegion
                local ctrl = region._control
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    borderRow:GetFrameLevel() + 3,
                    function()
                        local t = EDR_Cfg("borderColor")
                        return t.r, t.g, t.b, t.a
                    end,
                    function(r, g, b, a)
                        local p = EDR_Cfg("borderColor")
                        p.r, p.g, p.b, p.a = r, g, b, a
                        EDR_Redraw()
                    end,
                    true,
                    20
                )
                CludesUI.PanelPP.Point(colorSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                region._lastInline = colorSwatch
                -- No border to colour at size 0: dimmed and blocked.
                local block = CreateFrame("Frame", nil, colorSwatch)
                block:SetAllPoints()
                block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        colorSwatch,
                        CludesUI.DisabledTooltip("This option requires a Border Size above 0.")
                    )
                end)
                block:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateSwatchState()
                    if (EDR_Cfg("borderThickness") or 0) == 0 then
                        colorSwatch:SetAlpha(0.3)
                        block:Show()
                    else
                        colorSwatch:SetAlpha(1)
                        block:Hide()
                    end
                end
                CludesUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    UpdateSwatchState()
                end)
                UpdateSwatchState()
            end
            _, hgt = W:Spacer(hostFrame, posY, 20)
            posY = posY - hgt

            -- Charge and Second Wind rows, each only while its part is shown
            -- (Classic Gems replaces the charge row); no section without either.
            local showCharges, showSW = not EDR_IsGems(), EDR_ShowSW()
            if showCharges or showSW then
                _, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
                posY = posY - hgt
                if showCharges then
                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "slider",
                        text = "Charge Height",
                        min = 2,
                        max = 24,
                        step = 1,
                        getValue = function()
                            return EDR_Cfg("skyridingHeight")
                        end,
                        setValue = function(val)
                            EDR_Set("skyridingHeight", val)
                            EDR_Rebuild()
                        end,
                    }, {
                        type = "multiSwatch",
                        text = "Charge Color",
                        swatches = {
                            {
                                text = "Background",
                                getValue = function()
                                    local t = EDR_Cfg("skyridingBg")
                                    return t.r, t.g, t.b, t.a
                                end,
                                setValue = function(r, g, b, a)
                                    local p = EDR_Cfg("skyridingBg")
                                    p.r, p.g, p.b, p.a = r, g, b, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Background",
                            },
                            {
                                text = "Stacks",
                                getValue = function()
                                    local t = EDR_Cfg("skyridingFilled")
                                    return t.r, t.g, t.b, t.a
                                end,
                                setValue = function(r, g, b, a)
                                    local p = EDR_Cfg("skyridingFilled")
                                    p.r, p.g, p.b, p.a = r, g, b, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Charges",
                            },
                        },
                    })
                    posY = posY - hgt
                end
                if showSW then
                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "slider",
                        text = "Second Wind Height",
                        min = 2,
                        max = 24,
                        step = 1,
                        getValue = function()
                            return EDR_Cfg("secondWindHeight")
                        end,
                        setValue = function(val)
                            EDR_Set("secondWindHeight", val)
                            EDR_Rebuild()
                        end,
                    }, {
                        type = "multiSwatch",
                        text = "Second Wind Color",
                        swatches = {
                            {
                                text = "Background",
                                getValue = function()
                                    local t = EDR_Cfg("secondWindBg")
                                    return t.r, t.g, t.b, t.a
                                end,
                                setValue = function(r, g, b, a)
                                    local p = EDR_Cfg("secondWindBg")
                                    p.r, p.g, p.b, p.a = r, g, b, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Background",
                            },
                            {
                                text = "Second Wind",
                                getValue = function()
                                    local t = EDR_Cfg("secondWindFilled")
                                    return t.r, t.g, t.b, t.a
                                end,
                                setValue = function(r, g, b, a)
                                    local p = EDR_Cfg("secondWindFilled")
                                    p.r, p.g, p.b, p.a = r, g, b, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Second Wind",
                            },
                        },
                    })
                    posY = posY - hgt
                end
                _, hgt = W:Spacer(hostFrame, posY, 20)
                posY = posY - hgt
            end

            -- The speed bar's own section only while the bar is shown.
            if EDR_ShowSpeed() then
                _, hgt = W:SectionHeader(hostFrame, "SPEED BAR", posY)
                posY = posY - hgt
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "slider",
                    text = "Height",
                    min = 4,
                    max = 40,
                    step = 1,
                    getValue = function()
                        return EDR_Cfg("speedHeight")
                    end,
                    setValue = function(val)
                        EDR_Set("speedHeight", val)
                        EDR_Rebuild()
                    end,
                }, {
                    type = "toggle",
                    text = "Thrill Color Change",
                    getValue = function()
                        return EDR_Cfg("thrillColorToggle") == true
                    end,
                    setValue = function(val)
                        EDR_Set("thrillColorToggle", val)
                        EDR_Redraw()
                    end,
                })
                posY = posY - hgt
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "multiSwatch",
                    text = "Speed Color",
                    swatches = {
                        {
                            text = "Background",
                            getValue = function()
                                local t = EDR_Cfg("speedBarBg")
                                return t.r, t.g, t.b, t.a
                            end,
                            setValue = function(r, g, b, a)
                                local p = EDR_Cfg("speedBarBg")
                                p.r, p.g, p.b, p.a = r, g, b, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Background",
                        },
                        {
                            text = "Speed",
                            getValue = function()
                                local t = EDR_Cfg("normalColor")
                                return t.r, t.g, t.b, t.a
                            end,
                            setValue = function(r, g, b, a)
                                local p = EDR_Cfg("normalColor")
                                p.r, p.g, p.b, p.a = r, g, b, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Speed",
                        },
                    },
                }, {
                    type = "multiSwatch",
                    text = "Thrill Color",
                    swatches = {
                        {
                            text = "Hash",
                            getValue = function()
                                local t = EDR_Cfg("tickColor")
                                return t.r, t.g, t.b, t.a
                            end,
                            setValue = function(r, g, b, a)
                                local p = EDR_Cfg("tickColor")
                                p.r, p.g, p.b, p.a = r, g, b, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Hash Marker",
                        },
                        {
                            text = "Thrill",
                            getValue = function()
                                local t = EDR_Cfg("thrillColor")
                                return t.r, t.g, t.b, t.a
                            end,
                            setValue = function(r, g, b, a)
                                local p = EDR_Cfg("thrillColor")
                                p.r, p.g, p.b, p.a = r, g, b, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Thrill",
                        },
                    },
                })
                posY = posY - hgt
                local speedTextRow
                speedTextRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Show Speed Text",
                    getValue = function()
                        return EDR_Cfg("speedText") and EDR_Cfg("speedText").enabled ~= false
                    end,
                    setValue = function(val)
                        EDR_SetField("speedText", "enabled", val)
                        EDR_Redraw()
                    end,
                }, {
                    type = "dropdown",
                    text = "Text Align",
                    values = justifyValues,
                    order = justifyOrder,
                    getValue = function()
                        return (EDR_Cfg("speedText") or {}).justify or "CENTER"
                    end,
                    setValue = function(val)
                        EDR_SetField("speedText", "justify", val)
                        EDR_Redraw()
                    end,
                })
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(speedTextRow._rightRegion, {
                        title = "Speed Text Position",
                        rows = {
                            {
                                type = "slider",
                                label = "Size",
                                min = 6,
                                max = 32,
                                step = 1,
                                get = function()
                                    return (EDR_Cfg("speedText") or {}).size or 12
                                end,
                                set = function(val)
                                    EDR_SetField("speedText", "size", val)
                                    EDR_Redraw()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Offset X",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return (EDR_Cfg("speedText") or {}).offsetX or 0
                                end,
                                set = function(val)
                                    EDR_SetField("speedText", "offsetX", val)
                                    EDR_Redraw()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Offset Y",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = function()
                                    return (EDR_Cfg("speedText") or {}).offsetY or 0
                                end,
                                set = function(val)
                                    EDR_SetField("speedText", "offsetY", val)
                                    EDR_Redraw()
                                end,
                            },
                        },
                    })
                end
                posY = posY - hgt
                _, hgt = W:Spacer(hostFrame, posY, 20)
                posY = posY - hgt
            end -- Show Speed Bar
        end -- close Dragon Riding hidden-while-disabled gate

        -- The wrapper is SetAllPoints-anchored, so SetHeight on it is inert;
        -- return the measured height so the scroll range is correct.
        return math.abs(posY)
    end

    -- WoW Forever has no skyriding: the Dragon Riding tab is not registered there
    -- (its resident file returns at load, so the page would have no DB to read).
    -- Window Mover, right after Window Skins, links to Quality of Life's Shifter,
    -- so it is offered only while Quality of Life is loaded.
    local pages = CludesUI.IS_FOREVER and { PAGE_WINDOWSKINS, PAGE_TOOLTIPS, PAGE_CHATBUBBLES }
        or { PAGE_WINDOWSKINS, PAGE_TOOLTIPS, PAGE_CHATBUBBLES, PAGE_DRAGONRIDING }
    if CludesUI._ModuleNS["CludesUIQoL"] then
        table.insert(pages, 2, PAGE_WINDOWMOVER)
    end
    -- Panel shown, or unfolded from its mini window (no page callback runs then): a shown
    -- sample catches up on writes it skipped while hidden (Unlock Mode, other pages). Each
    -- repaint checks that its own sample is the one on screen.
    local function CatchUpPreviews()
        TooltipPreviewRepaint()
        PopupPreviewRepaint()
        if mod.EDR_RepaintSample then
            mod.EDR_RepaintSample()
        end
    end
    CludesUI:RegisterOnShow(CatchUpPreviews)
    CludesUI:RegisterOnCollapse(function(on)
        if not on then
            CatchUpPreviews()
        end
    end)
    CludesUI:RegisterModule("CludesUIBlizzardSkin", {
        title = "Window Skins",
        description = CludesUI.IS_FOREVER
                and "Themed Blizzard frames: window skins, tooltips, menus, popups, chat bubbles."
            or "Themed Blizzard frames: window skins, tooltips, menus, popups, chat bubbles, Dragon Riding HUD.",
        searchTerms = "blizzard skin character sheet tooltip menu popup dragon riding skyriding window skins lfg group finder premade queue pause game menu great vault inspect collections mounts pets toys spellbook talents adventure guide encounter journal professions guild communities calendar achievements mail catalyst gem socket item upgrade upgrades crest loot window loot toast you received popup micro menu modern delves companion brann loot roll need greed pass disenchant loot rolls pending rolls group invite invited to a group role chat bubbles bubble speech balloon",
        pages = pages,
        pageLinks = { [PAGE_WINDOWMOVER] = { module = "CludesUIQoL", page = "Shifter" } },
        buildPage = function(pageName, hostFrame, yOffset)
            if pageName == PAGE_WINDOWSKINS then
                return BuildWindowSkinsPage(pageName, hostFrame, yOffset)
            end
            if pageName == PAGE_TOOLTIPS then
                return BuildTooltipsPage(pageName, hostFrame, yOffset)
            end
            if pageName == PAGE_CHATBUBBLES then
                return BuildChatBubblesPage(pageName, hostFrame, yOffset)
            end
            if pageName == PAGE_DRAGONRIDING then
                return BuildDragonRidingPage(pageName, hostFrame, yOffset)
            end
        end,
        -- The Tooltips, Chat Bubbles and Skyriding previews live in the content header; a
        -- cached page whose header was dropped rebuilds with it.
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_TOOLTIPS then
                return TooltipHeaderBuilder
            end
            if pageName == PAGE_CHATBUBBLES then
                return ChatBubblesHeaderBuilder
            end
            if pageName == PAGE_DRAGONRIDING and EDR_Cfg("enabled") == true then
                return SkyridingHeaderBuilder
            end
        end,
        -- A kept page shown again: its preview paints again (the Fonts and Textures pages,
        -- Unlock Mode and a profile switch write its keys from elsewhere).
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_TOOLTIPS then
                TooltipPreviewRepaint()
                PopupPreviewRepaint()
            end
            if pageName == PAGE_DRAGONRIDING and mod.EDR_RepaintSample then
                mod.EDR_RepaintSample()
            end
        end,
        resetScope = "account",
        onReset = function()
            if CludesUIDragonRidingDB then
                CludesUIDragonRidingDB.profiles = nil
                CludesUIDragonRidingDB.profileKeys = nil
            end
            -- Per-profile master kill switch: reset re-enables skins for the
            -- ACTIVE profile (other profiles keep their own choice).
            do
                local prof = CludesUI.GetActiveProfileData()
                if prof then
                    prof.disableWindowSkins = nil
                end
                -- Per-profile Chat Bubbles; Refresh hands back any CVars it held.
                if prof then
                    prof.chatBubbles = nil
                end
                if CludesUI.ChatBubbles then
                    CludesUI.ChatBubbles.Refresh()
                end
            end
            if CludesUIDB then
                -- Every setting on the two tabs: the export bundle's own list
                -- (CludesUI_Profiles.lua), so a setting added there resets too.
                for _, k in ipairs(CludesUI.BLIZZ_SKIN_GLOBAL_KEYS) do
                    CludesUIDB[k] = nil
                end
                -- Then the state the bundle leaves out (the Mail card's roster of
                -- the player's own characters stays).
                for _, k in ipairs({
                    "lfgSavedRoles",
                    "charSheetCollapsedSections",
                    "characterFramePos",
                    "friendsFramePos",
                    "windowSkinsStockSeeded",
                    "mailAltHidden",
                    "tooltipFixedPos", -- stale key from the account-global build
                    "blizzWindowModernBG", -- dead key
                }) do
                    CludesUIDB[k] = nil
                end
                -- The per-profile fixed tooltip position: cleared, it re-seeds from
                -- Blizzard's CURRENT Edit Mode spot on the next tooltip show.
                local prof = CludesUI.GetActiveProfileData()
                if prof then
                    prof.tooltipFixedPos = nil
                end
                if CludesUI._applyTooltipBuffs then
                    CludesUI._applyTooltipBuffs()
                end
                -- Any glow on a popup on screen goes (the hooks stay, inert).
                if CludesUI._EnsureResurrectGlow then
                    CludesUI._EnsureResurrectGlow()
                end
                if CludesUI.SyncAuraTooltipSkin then
                    CludesUI.SyncAuraTooltipSkin()
                end
            end
            if CludesUI._applyTooltipCursorAnchor then
                CludesUI._applyTooltipCursorAnchor()
            end
            if CludesUI._applyTooltipFixedAnchor then
                CludesUI._applyTooltipFixedAnchor()
            end
            if CludesUI._applyTooltipHealthStrip then
                CludesUI._applyTooltipHealthStrip()
            end
            if CludesUI._applyTooltipHealthStripStyle then
                CludesUI._applyTooltipHealthStripStyle()
            end
            if CludesUI._refreshCharSheetSocketPanel then
                CludesUI._refreshCharSheetSocketPanel()
            end
            if CludesUI._refreshCharSheetSlotFlyoutArrows then
                CludesUI._refreshCharSheetSlotFlyoutArrows()
            end
            if CludesUI._refreshStatFormats then
                CludesUI._refreshStatFormats()
            end
            if CludesUI._refreshCharSheetSlotLabels then
                CludesUI._refreshCharSheetSlotLabels()
            end
            if CludesUI._refreshInspectSlotLabels then
                CludesUI._refreshInspectSlotLabels()
            end
            -- WoW Forever's Friends List card (auto-accept and the tiles)
            if mod.FriendsCardRefresh then
                mod.FriendsCardRefresh()
            end
            -- The Mail card's Alt List (retail)
            if mod.MailAlts then
                mod.MailAlts.Refresh()
            end
        end,
    })

    -- Deep links (What's New, search) into the Window Skins page target rows
    -- that only exist while a card is expanded. Pre-hook: expand every card and
    -- drop the page cache so the nav's SelectPage cold-builds with all rows
    -- present before it resolves the section/highlight.
    local origNav = CludesUI.NavigateToElementSettings
    if origNav then
        function CludesUI:NavigateToElementSettings(
            moduleName,
            pageName,
            sectionName,
            preSelectFn,
            highlightText
        )
            -- The original refuses in combat: no page state changes then.
            if InCombatLockdown() then
                return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
            end
            if
                moduleName == "CludesUIBlizzardSkin"
                and pageName == PAGE_WINDOWSKINS
                and (sectionName or highlightText)
            then
                local changed = false
                for _, window in ipairs(WINDOWS) do
                    if not _wsExpanded[window.key] then
                        _wsExpanded[window.key] = true
                        changed = true
                    end
                end
                if changed and CludesUI.InvalidatePageCache then
                    CludesUI:InvalidatePageCache()
                end
            end
            return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
        end
    end

    SLASH_EBSK1 = "/cbsk"
    SlashCmdList.EBSK = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIBlizzardSkin")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
