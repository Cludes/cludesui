if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_Options.lua
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIBlizzardSkin"] -- module namespace (published by the module at its load)
if not mod then return end -- module disabled: no options page
local PAGE_WINDOWSKINS = "Blizzard Window Skins"
local PAGE_TOOLTIPS = "Tooltips, Menus & Popups"
local PAGE_DRAGONRIDING = "Dragon Riding"
local PAGE_CHATBUBBLES = "Chat Bubbles"
-- Display-only tab labels: the page names above stay the pages' identities
-- (nav links, Unlock Mode, saved state).
CUI.TAB_LABEL_OVERRIDES[PAGE_WINDOWSKINS] = "Window Skins"
CUI.TAB_LABEL_OVERRIDES[PAGE_TOOLTIPS] = "Tooltips & Menus"
CUI.TAB_LABEL_OVERRIDES[PAGE_DRAGONRIDING] = "Skyriding"

-- The account-wide settings table (these tabs' settings live at its top
-- level), made if it is not there yet, for a write.
local function Account()
    if not CludesUIDB then CludesUIDB = {} end
    return CludesUIDB
end
-- Row accessors over Account(): a key read (or its default) and written.
local function AccountField(settingKey)
    return function(value) Account()[settingKey] = value end
end
local function AccountFieldThen(settingKey)
    return function(value)
        Account()[settingKey] = value
        if CUI._LootToast_Refresh then CUI._LootToast_Refresh() end
    end
end

CUI.AtOptionsLogin(function()
    -- Page reuse (CludesUI_FramePool.lua): a frame made under a page pool
    -- host comes from the pool and is dressed again by every later build; under
    -- any other parent it is a plain new frame.
    local CreateFrame = CUI._Pool.CreateFrame

    -- Border rows shared by the Tooltips page and the Loot Window card, over a key prefix's
    -- <prefix>Border* settings (drawn by _applyConfiguredBorder, CUI_BlizzardSkin_TooltipSkin.lua).
    -- The step the skin renders with: the stored label (an unknown one = thin); unset = the
    -- legacy numeric tooltipBorderSize for the tooltip, 1 otherwise.
    local function BorderStep(prefixText)
        local settingKey = CludesUIDB[prefixText .. "BorderThickness"]
        if settingKey then return CUI.BORDER_STEP_OF_LABEL[settingKey] or 1 end
        if prefixText == "tooltip" then return CludesUIDB.tooltipBorderSize or 1 end
        return 1
    end
    -- Border Size in pixels over <prefix>BorderThickness (still a label) and its <prefix>BorderThicknessPx companion.
    -- The short track leaves room for the color swatches beside it.
    local function BorderSizeSlider(prefixText, textValue, disabledFn, apply, disabledTooltip)
        return CUI.BorderPxSliderCfg({
            text = textValue,
            disabled = disabledFn,
            disabledTooltip = disabledTooltip,
            trackWidth = 120,
            getStep = function() return BorderStep(prefixText) end,
            setStep = function(step)
                CludesUIDB[prefixText .. "BorderThickness"] = CUI.BORDER_LABEL_OF_STEP[step] or "thin"
            end,
            getTex = function() return CludesUIDB[prefixText .. "BorderTexture"] or "solid" end,
            getPx = function() return CludesUIDB[prefixText .. "BorderThicknessPx"] end,
            setPx = function(val) CludesUIDB[prefixText .. "BorderThicknessPx"] = val end,
            apply = apply,
        })
    end
    -- The registry sizeKey the skin passes beside the addonKey "blizzardSkin" (registered
    -- nowhere, so an UNSET offset resolves to 0/0, never to the global per-texture defaults).
    local function BorderSizeKey(prefixText)
        return CludesUIDB[prefixText .. "BorderThickness"]
            or CUI.BORDER_LABEL_OF_STEP[BorderStep(prefixText)]
            or "thin"
    end
    -- The Width Offset | Height Offset cfgs for a textured style; nil for a solid one (no offsets).
    local function BorderOffsetCfgs(prefixText, disabledFn, apply, disabledTooltip)
        local texture = CludesUIDB[prefixText .. "BorderTexture"] or "solid"
        if texture == "" or texture == "solid" then return end
        return CUI.BorderOffsetRowCfgs({
            addonKey = "blizzardSkin",
            disabled = disabledFn,
            disabledTooltip = disabledTooltip,
            getTex = function() return CludesUIDB[prefixText .. "BorderTexture"] or "solid" end,
            getStep = function() return BorderStep(prefixText) end,
            getSizeKey = function() return BorderSizeKey(prefixText) end,
            getPx = function() return CludesUIDB[prefixText .. "BorderThicknessPx"] end,
            getX = function() return CludesUIDB[prefixText .. "BorderOffsetX"] end,
            setX = function(val) CludesUIDB[prefixText .. "BorderOffsetX"] = val end,
            getY = function() return CludesUIDB[prefixText .. "BorderOffsetY"] end,
            setY = function(val) CludesUIDB[prefixText .. "BorderOffsetY"] = val end,
            apply = apply,
        })
    end
    -- A border row's inline controls: the Accent | Class | Custom color mode swatches left of
    -- its Border Size, and the Show Behind cog (allowBehind) left of its style. opts: apply =
    -- run after a pick (the Loot Window card's live refresh); quality = { key, tip } adds a
    -- Quality swatch whose own color is saved at key.
    local function AttachBorderControls(row, prefixText, disabledFn, allowBehind, options)
        if CUI._prebuilding then return end
        local Pix = CUI.PanelPP
        local apply = options and options.apply
        local leftX, right = row._leftRegion, row._rightRegion
        -- The offsets live in their own row below the style row (BorderOffsetCfgs); the cog
        -- keeps only Show Behind, so a surface without that option gets no cog at all.
        if allowBehind then
            local popupRows = {
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function() return CludesUIDB[prefixText .. "BorderBehind"] or false end,
                    set = function(val)
                        CludesUIDB[prefixText .. "BorderBehind"] = val
                        if apply then apply() end
                    end,
                },
            }
            CUI.BuildInlineCog(leftX, {
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
            local sw, refreshFn = CUI.BuildColorSwatch(
                right,
                right:GetFrameLevel() + 5,
                getColor,
                function(red, green, blue, a)
                    CludesUIDB[colorKey or (prefixText .. "BorderColor")] = { r = red, g = green, b = blue }
                    CludesUIDB[prefixText .. "BorderOpacity"] = a
                    CludesUIDB[prefixText .. "BorderColorMode"] = mode
                    if apply then apply() end
                end,
                pickable,
                20
            )
            Pix.Point(sw, "RIGHT", anchor, "LEFT", -8, 0)
            local orig = sw:GetScript("OnClick")
            sw:SetScript("OnClick", function(self)
                if not pickable or (CludesUIDB[prefixText .. "BorderColorMode"] or "custom") ~= mode then
                    CludesUIDB[prefixText .. "BorderColorMode"] = mode
                    if apply then apply() end
                    CUI:RefreshPage()
                    return
                end
                orig(self)
            end)
            sw:HookScript("OnEnter", function(self) CUI.ShowWidgetTooltip(self, tipText) end)
            sw:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            -- Applied once at build time too -- widget refresh only fires
            -- on later changes, so without this every swatch opened lit.
            local function UpdSwatchState()
                local off = disabledFn and disabledFn()
                local isActive = (CludesUIDB[prefixText .. "BorderColorMode"] or "custom") == mode
                sw:SetAlpha(off and 0.15 or (isActive and 1 or 0.3))
                sw:EnableMouse(not off)
                refreshFn()
            end
            CUI.RegisterWidgetRefresh(UpdSwatchState)
            UpdSwatchState()
            return sw
        end
        local accent = AddModeSwatch(right._control, "accent", "Accent Color", function()
            local color = CUI.CLUDES_GREEN
            return color.r, color.g, color.b, 1
        end, false)
        local class = AddModeSwatch(accent, "class", "Class Color", function()
            local _, k = UnitClass("player")
            local color = RAID_CLASS_COLORS[k]
            return color.r, color.g, color.b, 1
        end, false)
        local last = AddModeSwatch(class, "custom", "Custom Color", function()
            local color = CludesUIDB[prefixText .. "BorderColor"] or { r = 1, g = 1, b = 1 }
            return color.r,
                color.g,
                color.b,
                CludesUIDB[prefixText .. "BorderOpacity"] or CUI.RESKIN.BRD_ALPHA
        end, true)
        local q = options and options.quality
        if q then
            last = AddModeSwatch(last, "quality", q.tip, function()
                local color = CludesUIDB[q.key] or { r = 1, g = 1, b = 1 }
                return color.r,
                    color.g,
                    color.b,
                    CludesUIDB[prefixText .. "BorderOpacity"] or CUI.RESKIN.BRD_ALPHA
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
        return function(headerText, hdrW)
            local building, H = true, 0
            local num = #cols
            local titled = cols[1].title ~= nil
            local titleH = titled and PV_TITLE_H or 0
            local state = {}
            local lblHost
            if titled then
                lblHost = CreateFrame("Frame", nil, headerText)
                lblHost:SetAllPoints(headerText)
                lblHost:SetFrameLevel(headerText:GetFrameLevel() + 3)
            end
            local function Layout()
                local uiScale = UIParent:GetEffectiveScale() / headerText:GetEffectiveScale()
                local colW = ((building and hdrW or headerText:GetWidth()) - 2 * CUI.CONTENT_PAD) / num
                local maxH = 0
                for idx = 1, num do
                    local cell = state[idx]
                    if cell and cell.w then
                        local fit = (cell.w > 0) and math.min(1, colW / (cell.w * uiScale)) or 1
                        cell.root:SetScale(uiScale * fit)
                        maxH = math.max(maxH, cell.h * uiScale * fit)
                    end
                end
                local blockH = maxH + titleH
                for idx = 1, num do
                    local cell = state[idx]
                    if cell and cell.w then
                        local rootFrame = cell.root
                        rootFrame:ClearAllPoints()
                        if titled then
                            -- Offsets in the sample's own units, snapped to its physical pixels.
                            local hs = rootFrame:GetScale()
                            local onePx = CUI.PP.perfect / rootFrame:GetEffectiveScale()
                            local function Snap(val) return math.floor(val / onePx + 0.5) * onePx end
                            local cx = (-(num - 1) / 2 + (idx - 1)) * colW
                            rootFrame:SetPoint(
                                "TOP",
                                headerText,
                                "CENTER",
                                Snap(cx / hs),
                                Snap((blockH / 2 - titleH) / hs)
                            )
                            cell.fs:ClearAllPoints()
                            cell.fs:SetPoint("BOTTOMLEFT", rootFrame, "TOPLEFT", 0, 3)
                            cell.fs:Show()
                        else
                            rootFrame:SetPoint("CENTER", headerText, "CENTER", 0, 0)
                        end
                    end
                end
                H = math.max(80, math.ceil(blockH + 40))
                if not building and headerText:IsVisible() and math.abs(headerText:GetHeight() - H) > 1 then
                    CUI:SetContentHeaderHeightSilent(H)
                end
            end
            for idx = 1, num do
                local c = {}
                state[idx] = c
                if titled then
                    c.fs = CUI.MakeFont(lblHost, 11, nil, 1, 1, 1)
                    c.fs:SetAlpha(0.6)
                    c.fs:SetText(cols[idx].title)
                    c.fs:Hide()
                end
                cols[idx].show(headerText, function(rootFrame, wid, height)
                    if not wid then
                        rootFrame:SetScale(UIParent:GetEffectiveScale() / headerText:GetEffectiveScale())
                        return
                    end
                    c.root, c.w, c.h = rootFrame, wid, height
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
            title = CUI.L("Popups"),
            show = function(headerText, place)
                if CUI.ShowPopupPreview then CUI.ShowPopupPreview(headerText, place) end
            end,
        },
        {
            title = CUI.L("Tooltip"),
            show = function(headerText, place)
                if CUI.ShowTooltipPreview then CUI.ShowTooltipPreview(headerText, place) end
            end,
        },
    })
    local function RepaintTooltipPreview()
        if CUI._repaintTooltipPreview then CUI._repaintTooltipPreview() end
    end
    local function RepaintPopupPreview()
        if CUI._repaintPopupPreview then CUI._repaintPopupPreview() end
    end

    local function BuildTooltipsPage(pageTitle, hostFrame, yOffset)
        if not CludesUIDB then CludesUIDB = {} end
        local Widg = CUI.Widgets
        local cursorY = yOffset
        local _, height
        -- The border row helpers (BorderSizeSlider, BorderOffsetCfgs, AttachBorderControls) sit
        -- above this page, shared with the Loot Window card.
        -- Width Offset | Height Offset right below a Border Style row, only while its style is
        -- textured (a solid border has no offsets). Built in every pass so the y advance never differs.
        local function BorderOffsetRow(prefixText, disabledFn, apply)
            local ocfgL, ocfgR = BorderOffsetCfgs(prefixText, disabledFn, apply)
            if ocfgL then
                _, height = Widg:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                cursorY = cursorY - height
            end
        end

        -- The sample tooltip and popup head the page.
        if not CUI._prebuilding then
            CUI:SetContentHeader(TooltipHeaderBuilder)
        elseif CUI.ClearContentHeader then
            CUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        _, height = Widg:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        _, height = Widg:SectionHeader(hostFrame, "BLIZZARD POPUPS & GAME MENU", cursorY)
        cursorY = cursorY - height

        local function popupOff() return CludesUIDB.reskinPopupsMenus == false end
        _, height = Widg:DualRow(hostFrame, cursorY, {
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
                if CUI._EnsureResurrectGlow then CUI._EnsureResurrectGlow() end
                CUI:RefreshPage() -- update the border cog, swatch and glow disabled states
                CUI:ShowConfirmPopup({
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
            getValue = function() return CludesUIDB and CludesUIDB.resurrectAcceptGlow or false end,
            setValue = function(val)
                Account().resurrectAcceptGlow = val
                if CUI._EnsureResurrectGlow then CUI._EnsureResurrectGlow() end
            end,
        })
        cursorY = cursorY - height

        do
            local texValues, texOrder = CUI.GetBorderTextureDropdown()
            local outer
            outer, height = Widg:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Border Style",
                disabled = popupOff,
                values = texValues,
                order = texOrder,
                getValue = function() return CludesUIDB.popupMenuBorderTexture or "solid" end,
                setValue = function(val)
                    local c, b = CUI.GetBorderStyleSelectDefaults(val)
                    CludesUIDB.popupMenuBorderTexture = val
                    CludesUIDB.popupMenuBorderOffsetX = nil
                    CludesUIDB.popupMenuBorderOffsetY = nil
                    CludesUIDB.popupMenuBorderBehind = b
                    CludesUIDB.popupMenuBorderColor = c
                    if CludesUIDB.popupMenuBorderThicknessPx then
                        CludesUIDB.popupMenuBorderThicknessPx = false
                    end
                    CUI:RefreshPage(true)
                end,
            }, BorderSizeSlider("popupMenu", "Border Size", popupOff, RepaintPopupPreview))
            cursorY = cursorY - height
            AttachBorderControls(outer, "popupMenu", popupOff, true, { apply = RepaintPopupPreview })
            BorderOffsetRow("popupMenu", popupOff, RepaintPopupPreview)
            local buttons
            buttons, height = Widg:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Button Border Style",
                disabled = popupOff,
                values = texValues,
                order = texOrder,
                getValue = function() return CludesUIDB.popupMenuButtonBorderTexture or "solid" end,
                setValue = function(val)
                    CludesUIDB.popupMenuButtonBorderTexture = val
                    local sc = CUI.GetBorderSelectColor(val)
                    if sc then CludesUIDB.popupMenuButtonBorderColor = sc end
                    CludesUIDB.popupMenuButtonBorderOffsetX = nil
                    CludesUIDB.popupMenuButtonBorderOffsetY = nil
                    if CludesUIDB.popupMenuButtonBorderThicknessPx then
                        CludesUIDB.popupMenuButtonBorderThicknessPx = false
                    end
                    CUI:RefreshPage(true)
                end,
            }, BorderSizeSlider(
                "popupMenuButton",
                "Button Border Size",
                popupOff,
                RepaintPopupPreview
            ))
            cursorY = cursorY - height
            AttachBorderControls(buttons, "popupMenuButton", popupOff, nil, { apply = RepaintPopupPreview })
            BorderOffsetRow("popupMenuButton", popupOff, RepaintPopupPreview)
        end

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "colorpicker",
            text = "Button Background",
            hasAlpha = true,
            disabled = popupOff,
            getValue = function()
                local color = CludesUIDB.popupMenuButtonBackgroundColor
                    or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
                return color.r, color.g, color.b, color.a
            end,
            setValue = function(red, green, blue, a)
                CludesUIDB.popupMenuButtonBackgroundColor = { r = red, g = green, b = blue, a = a }
                RepaintPopupPreview()
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
                    getValue = function() return 1, 1, 1 end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "native"
                        RepaintPopupPreview()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CUI._getPopupMenuElementMode and CUI._getPopupMenuElementMode()
                            or "native"
                        return m == "native" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = CUI.CLUDES_GREEN
                        return color.r, color.g, color.b
                    end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "accent"
                        RepaintPopupPreview()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CUI._getPopupMenuElementMode and CUI._getPopupMenuElementMode()
                            or "native"
                        return m == "accent" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = CludesUIDB.popupMenuButtonTextColor or { r = 1, g = 1, b = 1 }
                        return color.r, color.g, color.b
                    end,
                    setValue = function(red, green, blue)
                        CludesUIDB.popupMenuButtonTextColorMode = "custom"
                        CludesUIDB.popupMenuButtonTextColor = { r = red, g = green, b = blue }
                        RepaintPopupPreview()
                    end,
                    onClick = function(self)
                        local m = CUI._getPopupMenuElementMode and CUI._getPopupMenuElementMode()
                            or "native"
                        if m ~= "custom" then
                            CludesUIDB.popupMenuButtonTextColorMode = "custom"
                            RepaintPopupPreview()
                            CUI:RefreshPage()
                            return
                        end
                        self._eabOrigClick(self)
                    end,
                    refreshAlpha = function()
                        local m = CUI._getPopupMenuElementMode and CUI._getPopupMenuElementMode()
                            or "native"
                        return m == "custom" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local _, k = UnitClass("player")
                        local color = RAID_CLASS_COLORS[k]
                        return color.r, color.g, color.b
                    end,
                    setValue = function() end,
                    onClick = function()
                        CludesUIDB.popupMenuButtonTextColorMode = "class"
                        RepaintPopupPreview()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local m = CUI._getPopupMenuElementMode and CUI._getPopupMenuElementMode()
                            or "native"
                        return m == "class" and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Font Size Scale",
            tooltip = "Scales the font size of reskinned Blizzard tooltips, menus, and popups.",
            min = 0.7,
            max = 1.5,
            step = 0.05,
            format = "%.0f%%",
            displayMul = 100,
            getValue = function() return CludesUIDB and CludesUIDB.tooltipFontScale or 1.0 end,
            setValue = function(val)
                Account().tooltipFontScale = val
                RepaintTooltipPreview()
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
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing the pause menu reskin requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        })
        cursorY = cursorY - height

        _, height = Widg:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        local heading
        heading, height = Widg:SectionHeader(hostFrame, "BLIZZARD TOOLTIP", cursorY)
        cursorY = cursorY - height

        -- "Reskin Tooltip" (customTooltips) is the master for this section: its
        -- reskin-driven sub-settings gray out (and stop applying) when it is off.
        -- Per-line tooltip content settings (titles, item level, M+ score, detailed
        -- tooltips) live in the Tooltip Extras checklist below it. Settings
        -- independent of the skin (Detailed Tooltips, Show Health Strip, Spell ID
        -- on Tooltip, Show Max Stack) stay editable with the reskin off.
        local function tipReskinOff() return CludesUIDB and CludesUIDB.customTooltips == false end

        -- The Move in Unlock Mode button on the tooltip's first section: its
        -- mover exists only while the fixed anchor is live (reskin on, Anchor
        -- to Cursor off), so the button greys out as the Growth Direction row does.
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_TooltipAnchor",
            disabled = function()
                return tipReskinOff() or (CludesUIDB and CludesUIDB.tooltipAnchorCursor and true or false)
            end,
            disabledTooltip = function()
                if tipReskinOff() then return "Reskin Tooltip" end
                return "This option does not apply while Anchor to Cursor is enabled"
            end,
        })

        -- Show Health Strip works without the reskin as well; its cog restyles
        -- the reskinned bar, so the cog locks with the reskin off.
        local function stripHidden() return not (CludesUIDB and CludesUIDB.tooltipHideHealthStrip == false) end

        -- Reskin Tooltip | Show Tooltips
        local ttShowRow
        ttShowRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Reskin Tooltip",
            getValue = function() return not CludesUIDB or CludesUIDB.customTooltips ~= false end,
            setValue = function(val)
                Account().customTooltips = val
                if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
                CUI:RefreshPage() -- gray/ungray the rest of the section now
                CUI:ShowConfirmPopup({
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
            disabled = tipReskinOff,
            disabledTooltip = "Reskin Tooltip",
            values = {
                always = "Always",
                outOfCombat = "Out of Combat",
                outOfBossCombat = "Out of Boss Combat",
                never = "Never",
            },
            order = { "always", "outOfCombat", "outOfBossCombat", "never" },
            getValue = function() return (CludesUIDB and CludesUIDB.tooltipShowMode) or "always" end,
            setValue = function(val)
                Account().tooltipShowMode = val
                CUI:RefreshPage() -- update the Use Modifier cog disabled state
            end,
        })
        cursorY = cursorY - height

        -- "Use Modifier" cog on Show Tooltips (right region): while the chosen
        -- modifier is held, suppression is lifted so a hidden tooltip can be
        -- read on hover (e.g. peeking a spell in combat). Disabled (blocked +
        -- dimmed) when the reskin is off or the mode is "Always" (nothing hides).
        if not CUI._prebuilding then
            local rightRegion = ttShowRow._rightRegion
            local function showModOff()
                if tipReskinOff() then return true end
                return ((CludesUIDB and CludesUIDB.tooltipShowMode) or "always") == "always"
            end
            CUI.BuildInlineCog(rightRegion, {
                gap = 9,
                disabled = showModOff,
                disabledTooltip = function()
                    return tipReskinOff() and "Reskin Tooltip"
                        or "This option requires Show Tooltips to be set to hide tooltips"
                end,
                title = "Show Tooltips",
                rows = {
                    {
                        type = "dropdown",
                        label = "Peek Modifier",
                        values = { none = "None", shift = "Shift", control = "Control", alt = "Alt" },
                        order = { "none", "shift", "control", "alt" },
                        get = function() return (CludesUIDB and CludesUIDB.tooltipShowModifier) or "none" end,
                        set = AccountField("tooltipShowModifier"),
                    },
                },
            })
        end

        -- Anchor to Cursor | Growth Direction
        local ttAnchorRow
        ttAnchorRow, height = Widg:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = "Anchor to Cursor",
                disabled = tipReskinOff,
                disabledTooltip = "Reskin Tooltip",
                getValue = function() return CludesUIDB and CludesUIDB.tooltipAnchorCursor or false end,
                setValue = function(val)
                    Account().tooltipAnchorCursor = val
                    if CUI._applyTooltipCursorAnchor then CUI._applyTooltipCursorAnchor() end
                    -- Re-park the fixed anchor (and seed it if this profile never
                    -- has) so turning the cursor mode off resumes cleanly.
                    if CUI._applyTooltipFixedAnchor then CUI._applyTooltipFixedAnchor() end
                    CUI:RefreshPage() -- update the position cog + Growth Direction disabled states
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
                    return tipReskinOff() or (CludesUIDB and CludesUIDB.tooltipAnchorCursor and true or false)
                end,
                disabledTooltip = function()
                    if tipReskinOff() then return "Reskin Tooltip" end
                    return "This option does not apply while Anchor to Cursor is enabled"
                end,
                values = { default = "Default", up = "Expand Up", down = "Expand Down" },
                order = { "default", "up", "down" },
                getValue = function() return (CludesUIDB and CludesUIDB.tooltipGrowthDirection) or "default" end,
                setValue = AccountField("tooltipGrowthDirection"),
            }
        )
        cursorY = cursorY - height

        -- Position control on Anchor to Cursor (left region): position + X/Y offset
        if not CUI._prebuilding then
            local leftRegion = ttAnchorRow._leftRegion
            local function ttCursorOff() return not (CludesUIDB and CludesUIDB.tooltipAnchorCursor) end
            CUI.BuildInlineCog(leftRegion, {
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
                        get = function() return CludesUIDB and CludesUIDB.tooltipCursorPosition or "top" end,
                        set = AccountField("tooltipCursorPosition"),
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.tooltipCursorOffsetX) or 0 end,
                        set = AccountField("tooltipCursorOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.tooltipCursorOffsetY) or 0 end,
                        set = AccountField("tooltipCursorOffsetY"),
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
        ttExtrasRow, height = Widg:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Tooltip Extras",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            },
            -- Front-end duplicate of the toggle in Global Settings > Developer;
            -- same CludesUIDB.showSpellID key read by the tooltip logic in
            -- CludesUI.lua (no separate backend). Independent of the reskin.
            {
                type = "toggle",
                text = "Spell ID on Tooltip",
                getValue = function() return CUI.SpellIDOn() end,
                setValue = function(val)
                    Account().showSpellID = val
                    if CUI.SyncAuraSpellIDCVar then CUI.SyncAuraSpellIDCVar() end
                    CUI:RefreshPage() -- update the Use Modifier cog disabled state
                end,
            }
        )
        cursorY = cursorY - height

        if not CUI._prebuilding then
            local Pix = CUI.PanelPP
            local lrgn = ttExtrasRow._leftRegion
            if lrgn._control then lrgn._control:Hide() end
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
            local lockTip = CUI.DisabledTooltip("Reskin Tooltip")
            local extrasDD, extrasRefresh = CUI.BuildVisOptsCBDropdown(
                lrgn,
                170,
                lrgn:GetFrameLevel() + 2,
                {
                    {
                        key = "tooltipPlayerTitles",
                        label = "Player Titles",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipItemLevel",
                        label = "Item Level",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipMythicScore",
                        label = "M+ Score",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipShowMount",
                        label = "Mount",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds the mount a player is riding to their tooltip, with a green check if you own it or a red X if you don't.",
                    },
                    {
                        key = "tooltipShowGuildRank",
                        label = "Guild Rank",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                    },
                    {
                        key = "tooltipShowTarget",
                        label = "Unit Target",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds a Targeting line showing who the hovered player or NPC is targeting, in green when it's you.",
                    },
                    {
                        key = "tooltipLevelColor",
                        label = "Level Difficulty Color",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the level number from gray (trivial) to red (much higher than you).",
                    },
                    {
                        key = "tooltipClassLineColor",
                        label = "Class Colored Spec",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors a player's spec and class line in their class color.",
                    },
                    {
                        key = "tooltipFactionColor",
                        label = "Faction Color",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the Alliance and Horde line in blue and red.",
                    },
                    {
                        key = "tooltipGuildmateColor",
                        label = "Highlight Guildmates",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Colors the guild name (and rank, if shown) of members of your own guild in your guild chat color.",
                    },
                    {
                        key = "tooltipCompactLevel",
                        label = "Compact Level Line",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = 'Shortens the level line to the level and race, or level, rank and type for NPCs ("90 Tauren", "90 Elite Humanoid").',
                    },
                    {
                        key = "tooltipAFKTag",
                        label = "Away Tag",
                        lockedFn = tipReskinOff,
                        lockedTooltip = lockTip,
                        tooltip = "Adds <Away> or <Busy> after the name of players who are away or busy.",
                    },
                    { key = "uber", label = "Detailed Tooltips" },
                },
                function(key)
                    if key == "uber" then return GetCVar("UberTooltips") == "1" end
                    local val = CludesUIDB and CludesUIDB[key]
                    if val == nil then return EXTRA_DEFAULTS[key] end
                    return val and true or false
                end,
                function(key, val)
                    if not CludesUIDB then CludesUIDB = {} end
                    if key == "uber" then
                        -- Only enforced on login after the user has toggled it once.
                        CludesUIDB.uberTooltipsManual = true
                        CludesUIDB.uberTooltips = val
                        CUI.SetCVar("UberTooltips", val and "1" or "0", "CludesUIBlizzardSkin")
                    else
                        CludesUIDB[key] = val
                        RepaintTooltipPreview()
                    end
                end
            )
            Pix.Point(extrasDD, "RIGHT", lrgn, "RIGHT", -20, 0)
            lrgn._control = extrasDD
            lrgn._lastInline = nil
            CUI.RegisterWidgetRefresh(extrasRefresh)
        end

        -- "Use Modifier" cog on Spell ID on Tooltip (right region): the spell/item
        -- ID lines only show while the chosen modifier is held. Disabled (blocked +
        -- dimmed) when Spell ID on Tooltip is off, mirroring the cursor-position cog.
        if not CUI._prebuilding then
            local rightRegion = ttExtrasRow._rightRegion
            local function sidOff() return not CUI.SpellIDOn() end
            CUI.BuildInlineCog(rightRegion, {
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
                        get = function() return (CludesUIDB and CludesUIDB.spellIDModifier) or "none" end,
                        set = function(val)
                            Account().spellIDModifier = val
                            -- Modifier choice gates the engine-side combat
                            -- aura-ID CVar (12.1; no-op on retail).
                            if CUI.SyncAuraSpellIDCVar then CUI.SyncAuraSpellIDCVar() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Icon ID",
                        get = function() return not CludesUIDB or CludesUIDB.showIconID ~= false end,
                        set = AccountField("showIconID"),
                    },
                    {
                        type = "toggle",
                        label = "Show Item ID",
                        get = function() return not CludesUIDB or CludesUIDB.showItemID ~= false end,
                        set = AccountField("showItemID"),
                    },
                },
            })
        end

        -- Show Max Stack for Items | Show Player Buffs
        local ttStackRow
        ttStackRow, height = Widg:DualRow(
            hostFrame,
            cursorY,
            -- Independent of the reskin, so it is NOT gated by "Reskin
            -- Tooltip" -- like Spell ID on Tooltip.
            {
                type = "toggle",
                text = "Show Max Stack for Items",
                tooltip = "Appends an item's max stack count on tooltip.",
                getValue = function() return CludesUIDB and CludesUIDB.showItemMaxStacks or false end,
                setValue = function(val)
                    Account().showItemMaxStacks = val
                    CUI:RefreshPage() -- update the Use Modifier cog disabled state
                end,
            },
            {
                type = "toggle",
                text = "Show Player Buffs",
                disabled = tipReskinOff,
                disabledTooltip = "Reskin Tooltip",
                getValue = function() return CludesUIDB and CludesUIDB.tooltipShowBuffs or false end,
                setValue = function(val)
                    Account().tooltipShowBuffs = val
                    if CUI._applyTooltipBuffs then CUI._applyTooltipBuffs() end
                    CUI:RefreshPage() -- update the position cog disabled state
                end,
            }
        )
        cursorY = cursorY - height

        -- "Use Modifier" cog on Show Max Stack for Items (left region): the Max
        -- Stack line only shows while the chosen modifier is held. Disabled
        -- (blocked + dimmed) when the toggle is off, mirroring the Spell ID cog.
        if not CUI._prebuilding then
            local leftRegion = ttStackRow._leftRegion
            local function iStacksOff() return not (CludesUIDB and CludesUIDB.showItemMaxStacks) end
            CUI.BuildInlineCog(leftRegion, {
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
                        get = function() return (CludesUIDB and CludesUIDB.itemStackModifier) or "none" end,
                        set = AccountField("itemStackModifier"),
                    },
                },
            })
        end

        -- Tooltip Buffs cog on Show Player Buffs (right region)
        if not CUI._prebuilding then
            local function ttBuffsOff()
                return tipReskinOff() or not (CludesUIDB and CludesUIDB.tooltipShowBuffs)
            end
            local function setBuffs(settingKey, val)
                Account()[settingKey] = val
                if CUI._applyTooltipBuffs then CUI._applyTooltipBuffs() end
            end
            CUI.BuildInlineCog(ttStackRow._rightRegion, {
                gap = 9,
                disabled = ttBuffsOff,
                disabledTooltip = function()
                    return tipReskinOff() and "Reskin Tooltip" or "Show Player Buffs"
                end,
                title = "Tooltip Buffs",
                rows = {
                    {
                        type = "dropdown",
                        label = "Position",
                        values = { bottom = "Bottom", top = "Top", left = "Left", right = "Right" },
                        order = { "bottom", "top", "left", "right" },
                        get = function() return CludesUIDB and CludesUIDB.tooltipBuffPosition or "bottom" end,
                        set = function(val) setBuffs("tooltipBuffPosition", val) end,
                    },
                    {
                        type = "slider",
                        label = "Icon Size",
                        min = 12,
                        max = 40,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.tooltipBuffSize or 20 end,
                        set = function(val) setBuffs("tooltipBuffSize", val) end,
                    },
                    {
                        type = "slider",
                        label = "Icons Per Row",
                        min = 1,
                        max = 16,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.tooltipBuffsPerRow or 8 end,
                        set = function(val) setBuffs("tooltipBuffsPerRow", val) end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.tooltipBuffOffsetX or 0 end,
                        set = function(val) setBuffs("tooltipBuffOffsetX", val) end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function() return CludesUIDB and CludesUIDB.tooltipBuffOffsetY or 0 end,
                        set = function(val) setBuffs("tooltipBuffOffsetY", val) end,
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
        ttStripRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Health Strip",
            tooltip = "Shows the health bar on the bottom of unit tooltips.",
            getValue = function() return not stripHidden() end,
            setValue = function(val)
                Account().tooltipHideHealthStrip = not val
                if CUI._applyTooltipHealthStrip then CUI._applyTooltipHealthStrip() end
                CUI:RefreshPage() -- update the strip cog disabled state
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
            disabled = tipReskinOff,
            disabledTooltip = "Reskin Tooltip",
            getValue = function()
                local a = (CludesUIDB and CludesUIDB.tooltipBgOpacity) or CUI.RESKIN.TT_ALPHA
                return math.floor(a * 100 + 0.5)
            end,
            setValue = function(val)
                Account().tooltipBgOpacity = val / 100
                if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
            end,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            local leftRegion = ttStripRow._leftRegion
            -- Health strip texture dropdown: the shared bar catalogue behind a
            -- "Blizzard" entry (the unset default). The triple lives on ns so the
            -- SharedMedia appender, which registers by table identity, gets the same
            -- tables on every build.
            if not mod.ttStripTex then
                local texture, nameList, sequence = CUI.BuildBarTextureTables()
                mod.ttStripTex = { tex = texture, names = nameList, order = sequence }
            end
            local state = mod.ttStripTex
            CUI.AppendSharedMediaTextures(state.names, state.order, nil, state.tex)
            local stripTexValues, stripTexOrder = { blizzard = "Blizzard" }, { "blizzard" }
            for _, settingKey in ipairs(state.order) do
                if settingKey ~= "---" then
                    stripTexValues[settingKey] = state.names[settingKey] or settingKey
                    stripTexOrder[#stripTexOrder + 1] = settingKey
                end
            end
            stripTexValues._menuOpts = {
                itemHeight = 28,
                background = function(settingKey)
                    if settingKey == "blizzard" then return "Interface\\TargetingFrame\\UI-StatusBar" end
                    return CUI.ResolveTexturePath(state.tex, settingKey, nil)
                end,
            }
            local function applyStripStyle()
                if CUI._applyTooltipHealthStripStyle then CUI._applyTooltipHealthStripStyle() end
            end
            CUI.BuildInlineCog(leftRegion, {
                gap = 9,
                disabled = function() return tipReskinOff() or stripHidden() end,
                disabledTooltip = function()
                    return tipReskinOff() and "Reskin Tooltip" or "Show Health Strip"
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
                        get = function() return CludesUIDB and CludesUIDB.tooltipHealthStripHeight or 3 end,
                        set = function(val)
                            Account().tooltipHealthStripHeight = (val ~= 3) and val or nil
                            applyStripStyle()
                        end,
                    },
                },
            })

            CUI.BuildInlineSwatches(ttStripRow._rightRegion, {
                {
                    tooltip = "Background Color",
                    getValue = function()
                        local color = CludesUIDB and CludesUIDB.tooltipBgColor
                        if color then return color.r, color.g, color.b, 1 end
                        local R = CUI.RESKIN
                        return R.BG_R, R.BG_G, R.BG_B, 1
                    end,
                    setValue = function(red, green, blue)
                        Account().tooltipBgColor = { r = red, g = green, b = blue }
                        if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
                    end,
                },
            }, { size = 20, disabled = tipReskinOff, disabledTooltip = "Reskin Tooltip" })
        end

        -- Border Style | Border Size
        do
            local texValues, texOrder = CUI.GetBorderTextureDropdown()
            local tooltipBorder
            tooltipBorder, height = Widg:DualRow(
                hostFrame,
                cursorY,
                {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = tipReskinOff,
                    values = texValues,
                    order = texOrder,
                    getValue = function() return CludesUIDB.tooltipBorderTexture or "solid" end,
                    setValue = function(val)
                        local c, b = CUI.GetBorderStyleSelectDefaults(val)
                        CludesUIDB.tooltipBorderTexture = val
                        CludesUIDB.tooltipBorderOffsetX = nil
                        CludesUIDB.tooltipBorderOffsetY = nil
                        CludesUIDB.tooltipBorderBehind = b
                        CludesUIDB.tooltipBorderColor = c
                        if CludesUIDB.tooltipBorderThicknessPx then
                            CludesUIDB.tooltipBorderThicknessPx = false
                        end
                        if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
                        CUI:RefreshPage(true)
                    end,
                },
                BorderSizeSlider("tooltip", "Border Size", tipReskinOff, function()
                    if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
                end)
            )
            cursorY = cursorY - height
            -- The engine aura tooltip follows the border only when synced (the sync repaints the preview too)
            local function TooltipBorderApply()
                if CUI.SyncAuraTooltipSkin then
                    CUI.SyncAuraTooltipSkin()
                else
                    RepaintTooltipPreview()
                end
            end
            AttachBorderControls(tooltipBorder, "tooltip", tipReskinOff, true, { apply = TooltipBorderApply })
            BorderOffsetRow("tooltip", tipReskinOff, TooltipBorderApply)
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
        _, height = Widg:SectionHeader(hostFrame, "BLIZZARD BARS, POPUPS & BUTTONS", cursorY)
        cursorY = cursorY - height

        -- The slot configs, laid out per client below: WoW Forever has no
        -- extra action button, so its toggle is not built there and the
        -- queue pair moves up a slot.
        local widgetCfg = {
            type = "toggle",
            text = "Reskin Widget Bars",
            tooltip = "Restyles Blizzard's on-screen progress bars (event objectives, nameplate counters)",
            getValue = function() return not CludesUIDB or CludesUIDB.reskinWidgetBars ~= false end,
            setValue = function(val)
                Account().reskinWidgetBars = val and true or false
                -- Reload-bound, like the window packs: turned OFF, the skin
                -- registers no events at all rather than running and
                -- returning early, so the decision is taken once at login.
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Widget bar reskin requires a UI reload to apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }
        local extraCfg = not CUI.IS_FOREVER
                and {
                    type = "toggle",
                    text = "Reskin Extra Action Buttons",
                    getValue = function()
                        -- DEFAULT OFF: opt-in, so nil reads as unchecked.
                        return CludesUIDB and CludesUIDB.reskinExtraActionButton == true
                    end,
                    setValue = function(val) Account().reskinExtraActionButton = val and true or false end,
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
                if not val and CUI.ShowConfirmPopup then
                    CUI:ShowConfirmPopup({
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
            getValue = function() return not CludesUIDB or CludesUIDB.showQueueTimer ~= false end,
            setValue = function(val)
                Account().showQueueTimer = val
                CUI:RefreshPage() -- update the style cog + swatch disabled states
            end,
        }

        -- The regions the inline controls below sit on, whichever slot their
        -- toggle took.
        local hudRow, queueRow, widgetRgn, queueRgn, timerRgn
        if extraCfg then
            hudRow, height = Widg:DualRow(hostFrame, cursorY, widgetCfg, extraCfg)
            cursorY = cursorY - height
            queueRow, height = Widg:DualRow(hostFrame, cursorY, queueCfg, timerCfg)
            cursorY = cursorY - height
            widgetRgn = hudRow and hudRow._leftRegion
            queueRgn = queueRow and queueRow._leftRegion
            timerRgn = queueRow and queueRow._rightRegion
        else
            hudRow, height = Widg:DualRow(hostFrame, cursorY, widgetCfg, queueCfg)
            cursorY = cursorY - height
            queueRow, height = Widg:DualRow(hostFrame, cursorY, timerCfg, CUI.BlankRowCfg())
            cursorY = cursorY - height
            widgetRgn = hudRow and hudRow._leftRegion
            queueRgn = hudRow and hudRow._rightRegion
            timerRgn = queueRow and queueRow._leftRegion
        end

        -- Minimum widget bar size (plate-hosted covers), a cog on "Reskin Widget
        -- Bars": the floor below which a shrunken nameplate's bar scales itself
        -- up. 0 = off (default, mirror Blizzard's rect exactly).
        if widgetRgn and not CUI._prebuilding then
            local lrgn = widgetRgn
            local function CogOff()
                -- Same default-on test the toggle itself uses: nil means on.
                return not (not CludesUIDB or CludesUIDB.reskinWidgetBars ~= false)
            end
            CUI.BuildInlineCog(lrgn, {
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
                            if type(val) == "number" then return val end
                            return 0
                        end,
                        set = function(val)
                            Account().widgetBarMinSize = val
                            -- Live: the seam re-reads and books one refresh; nil
                            -- only while the reskin is off (cog greyed then).
                            if CUI._HUDWidgetSetMinSize then CUI._HUDWidgetSetMinSize() end
                        end,
                    },
                },
            })
        end

        -- Red "!" warning left of the Reskin Queue Popup toggle while a mover addon
        -- that conflicts with the reskin is loaded
        local _eqolLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EnhanceQoL")
        if _eqolLoaded and queueRgn and not CUI._prebuilding then
            local region = queueRgn
            local toggle = region._control
            if toggle then
                local fontFile = (CUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                local warnBtn = CreateFrame("Button", nil, region)
                warnBtn:SetSize(28, 28)
                warnBtn:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
                warnBtn:SetFrameLevel(region:GetFrameLevel() + 5)
                local warnLabel = warnBtn:CreateFontString(nil, "OVERLAY")
                warnLabel:SetFont(fontFile, 28, "")
                warnLabel:SetTextColor(1, 0.3, 0.3, 1)
                warnLabel:SetText("!")
                warnLabel:SetPoint("CENTER")
                warnBtn:SetScript(
                    "OnEnter",
                    function(self)
                        CUI.ShowWidgetTooltip(
                            self,
                            "Enhance QoL's Mover may conflict with this reskin. The reskin is auto-disabled when its mover is active."
                        )
                    end
                )
                warnBtn:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            end
        end

        -- Style cog + countdown text color swatch (left of it) on the Show Queue Timer toggle.
        if timerRgn and not CUI._prebuilding then
            local Pix = CUI.PanelPP
            local QT = CUI.QUEUE_TIMER
            local function timerOff() return CludesUIDB and CludesUIDB.showQueueTimer == false end
            local function Get(settingKey, default) return (CludesUIDB and CludesUIDB[settingKey]) or default end
            local function Set(settingKey, val)
                Account()[settingKey] = val
                if CUI.RefreshQueueTimerStyle then CUI.RefreshQueueTimerStyle() end
            end

            CUI.BuildInlineCog(timerRgn, {
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
                        get = function() return Get("queueTimerTextSize", QT.TEXT_SIZE) end,
                        set = function(val) Set("queueTimerTextSize", val) end,
                    },
                    {
                        type = "slider",
                        label = "Bar Height",
                        min = 4,
                        max = 24,
                        step = 1,
                        get = function() return Get("queueTimerBarHeight", QT.BAR_HEIGHT) end,
                        set = function(val) Set("queueTimerBarHeight", val) end,
                    },
                    {
                        type = "slider",
                        label = "Text Offset Y",
                        min = -20,
                        max = 20,
                        step = 1,
                        tooltip = "Moves the countdown number up or down relative to the bar.",
                        get = function() return Get("queueTimerTextOffsetY", QT.TEXT_OFFSET_Y) end,
                        set = function(val) Set("queueTimerTextOffsetY", val) end,
                    },
                },
            })

            local qtSwatch, qtSwatchRefresh = CUI.BuildColorSwatch(
                timerRgn,
                timerRgn:GetFrameLevel() + 5,
                function()
                    local color = CludesUIDB and CludesUIDB.queueTimerTextColor
                    return (color and color.r) or QT.TEXT_R,
                        (color and color.g) or QT.TEXT_G,
                        (color and color.b) or QT.TEXT_B
                end,
                function(red, green, blue) Set("queueTimerTextColor", { r = red, g = green, b = blue }) end,
                false,
                20
            )
            Pix.Point(qtSwatch, "RIGHT", timerRgn._lastInline or timerRgn._control, "LEFT", -8, 0)
            timerRgn._lastInline = qtSwatch
            qtSwatch:HookScript(
                "OnEnter",
                function(self) CUI.ShowWidgetTooltip(self, "Countdown Text Color") end
            )
            qtSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)

            -- Called at build time too: the refresh list only runs on page show.
            local function UpdQueueTimerState()
                local off = timerOff()
                qtSwatch:SetAlpha(off and 0.15 or 1)
                qtSwatch:EnableMouse(not off)
                qtSwatchRefresh()
            end
            CUI.RegisterWidgetRefresh(UpdQueueTimerState)
            UpdQueueTimerState()
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Character Sheet card content (Blizzard Window Skins page). The style
    --  choice lives on the card header dropdown; everything here is the
    --  window's sub-settings, built as direct children of the page wrapper so
    --  inline search and nav deep-links still see them.
    ---------------------------------------------------------------------------
    -- Section headers inside window-skin cards: title indented 5px to sit
    -- with the card chrome (the divider stays full width).
    local function WSCardSection(hostFrame, textValue, cursorY)
        local Widg = CUI.Widgets
        local hf, height = Widg:SectionHeader(hostFrame, textValue, cursorY)
        if hf and hf._label then CUI.PanelPP.Point(hf._label, "BOTTOMLEFT", hf, "BOTTOMLEFT", 5, 8) end
        return hf, height
    end

    local function BuildCharacterSheetContent(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local _, height
        local Pix = CUI.PanelPP

        local function themeOff() return CludesUIDB and CludesUIDB.themedCharacterSheet == false end
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
                and (CUI.IS_FOREVER or not (CludesUIDB and CludesUIDB.charSheetBlizzColors == false))
        end

        local function AddDisabledCover(goal)
            local cover = CreateFrame("Frame", nil, goal)
            cover:SetAllPoints(goal)
            cover:SetFrameLevel(goal:GetFrameLevel() + 10)
            cover:EnableMouse(true)
            local backdrop = CUI.SolidTex(cover, "BACKGROUND", 0, 0, 0, 0)
            backdrop:SetAllPoints()
            cover:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(cover, CUI.DisabledTooltip("Character Sheet")) end
            )
            cover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function refreshFn()
                if themeOff() then
                    cover:Show()
                    goal:SetAlpha(0.3)
                else
                    cover:Hide()
                    goal:SetAlpha(1)
                end
            end
            CUI.RegisterWidgetRefresh(refreshFn)
            refreshFn()
        end

        -- Blizz Default keeps Blizzard's own character sheet with our stats
        -- section, slot text and socket strip: the gem icons and Icon Zoom
        -- are the CludesUI sheet's own, so Gems leaves the Item Details
        -- list and Icon Zoom greys out there.
        local function csGate(rowConf)
            if stock then
                rowConf.disabled = function() return true end
                rowConf.disabledTooltip = "Character Sheet: Blizz Default"
                rowConf.requireState = "disabled"
                rowConf.rawTooltip = nil
                rowConf._blizzGated = true
            end
            return rowConf
        end

        ---------------------------------------------------------------------------
        --  CORE OPTIONS
        ---------------------------------------------------------------------------
        _, height = WSCardSection(hostFrame, "CORE OPTIONS", cursorY)
        cursorY = cursorY - height

        -- Blizzard's own slot icons under Blizz Default (the inspect sheet
        -- keeps its stored zoom).
        local iconZoomCfg = csGate({
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 0.20,
            step = 0.01,
            tooltip = "Crops the border of the equipment-slot item icons on the character and inspect sheets. 0 shows the full icon. Only affects the themed character sheet.",
            getValue = function() return (CludesUIDB and CludesUIDB.charSheetIconZoom) or 0.07 end,
            setValue = function(val)
                Account().charSheetIconZoom = val
                if CUI._refreshCharSheetIconZoom then CUI._refreshCharSheetIconZoom() end
            end,
        })

        if not CUI.IS_FOREVER then
            -- Mythic+ Rating | Item Details: a checkbox dropdown, a view over
            -- the item level, upgrade track and gem keys (each on unless
            -- false). The gem icons are the CludesUI sheet's own, so Blizz
            -- Default leaves Gems out of the list. Tertiary Stats only adds to
            -- Stat Letters, so it locks while that is off.
            local function statLettersOff() return not (CludesUIDB and CludesUIDB.charSheetItemStats == true) end
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
                    lockedTooltip = CUI.DisabledTooltip("Stat Letters"),
                },
            }
            if not stock then
                ITEM_DETAILS[#ITEM_DETAILS + 1] =
                    { key = "showGems", label = "Gems", refresh = "_refreshGemsVisibility" }
            end
            local coreRow1
            coreRow1, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Mythic+ Rating",
                tooltip = "Display your Mythic+ rating above the item level on the character sheet.",
                getValue = function() return CludesUIDB and CludesUIDB.showMythicRating or false end,
                setValue = function(val)
                    Account().showMythicRating = val
                    if CUI._updateMythicRatingDisplay then CUI._updateMythicRatingDisplay() end
                end,
            }, {
                type = "label",
                text = "Item Details",
                tooltip = "Choose what shows on each equipped item.",
            })
            cursorY = cursorY - height
            if not CUI._prebuilding then
                local region = coreRow1._rightRegion
                -- Keys are on unless false; an optIn key is off unless true.
                local refreshOf, optIn = {}, {}
                for _, entry in ipairs(ITEM_DETAILS) do
                    refreshOf[entry.key] = entry.refresh
                    optIn[entry.key] = entry.optIn
                end
                local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                    region,
                    210,
                    region:GetFrameLevel() + 2,
                    ITEM_DETAILS,
                    function(settingKey)
                        if optIn[settingKey] then
                            return CludesUIDB and CludesUIDB[settingKey] == true or false
                        end
                        return not (CludesUIDB and CludesUIDB[settingKey] == false)
                    end,
                    function(settingKey, val)
                        Account()[settingKey] = val
                        local refreshFn = CUI[refreshOf[settingKey]]
                        if refreshFn then refreshFn() end
                    end
                )
                Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
                region._control = checkDrop
                region._lastInline = nil
                CUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            AddDisabledCover(coreRow1)

            -- Socket Panel | Icon Zoom (greyed under Blizz Default). Both
            -- looks show the socket strip: under Blizz Default it hangs below
            -- Blizzard's sheet in its tab art
            -- (CludesUIBlizzardSkin_SocketPanel.lua).
            local socketRow
            socketRow, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Socket Panel",
                tooltip = "Show a panel of equipped-gear sockets on the character sheet; click a socket to gem it.",
                getValue = function() return CludesUIDB and CludesUIDB.charSheetSocketPanel ~= false end,
                setValue = function(val)
                    Account().charSheetSocketPanel = val
                    if CUI._refreshCharSheetSocketPanel then CUI._refreshCharSheetSocketPanel() end
                    CUI:RefreshPage()
                end,
            }, iconZoomCfg)
            cursorY = cursorY - height
            AddDisabledCover(socketRow)

            -- Inline cog on Socket Panel: stat letters on the gem icons (off
            -- unless turned on).
            if not CUI._prebuilding then
                CUI.BuildInlineCog(socketRow._leftRegion, {
                    disabled = function() return CludesUIDB and CludesUIDB.charSheetSocketPanel == false end,
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
                                if CUI._refreshCharSheetSocketPanel then
                                    CUI._refreshCharSheetSocketPanel()
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
            statsRow, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Item Stats",
                tooltip = "Show each item's main and secondary stat (or its armor) and each weapon's damage per second beside its slot.",
                getValue = function() return CludesUIDB and CludesUIDB.showUpgradeTrack ~= false end,
                setValue = function(val)
                    Account().showUpgradeTrack = val
                    if CUI._refreshUpgradeTrackVisibility then
                        CUI._refreshUpgradeTrackVisibility()
                    end
                end,
            }, iconZoomCfg)
            cursorY = cursorY - height
            AddDisabledCover(statsRow)
        end

        -- Enchants (this sheet and the inspect sheet): a view over the
        -- sheet's shown key (on unless false) and its names key; None leaves
        -- the names key as it was. WoW Forever's enchants carry no icon, so
        -- the middle mode is the plain name there and Text the colored one.
        -- The Text Size cog shows only while the enchants show as text.
        local function EnchantValues()
            if CUI.IS_FOREVER then return { none = "None", icons = "Text", text = "Colored Text" } end
            return { none = "None", icons = "Icons + Hover", text = "Text" }
        end
        local function EnchantMode(showKey, namesKey)
            if CludesUIDB and CludesUIDB[showKey] == false then return "none" end
            if CludesUIDB and CludesUIDB[namesKey] then return "text" end
            return "icons"
        end
        local function SetEnchantMode(showKey, namesKey, val)
            Account()[showKey] = val ~= "none"
            if val ~= "none" then CludesUIDB[namesKey] = val == "text" end
        end
        local function EnchantTextShown(showKey, namesKey)
            local mode = EnchantMode(showKey, namesKey)
            return mode == "text" or (CUI.IS_FOREVER and mode == "icons")
        end

        local enchGemRow
        enchGemRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Enchants",
            tooltip = "How enchants show beside each item.",
            values = EnchantValues(),
            order = { "none", "icons", "text" },
            getValue = function() return EnchantMode("showEnchants", "charSheetEnchantNames") end,
            setValue = function(val)
                SetEnchantMode("showEnchants", "charSheetEnchantNames", val)
                if CUI._refreshEnchantsVisibility then CUI._refreshEnchantsVisibility() end
                if CUI._refreshCharSheetSlotLabels then CUI._refreshCharSheetSlotLabels() end
                -- Shows or hides the Text Size cog
                CUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Show PvP Item Level",
            tooltip = "Display your PvP item level above the Mythic+ rating on the character sheet.",
            getValue = function() return CludesUIDB and CludesUIDB.showPvpItemLevel or false end,
            setValue = function(val)
                Account().showPvpItemLevel = val
                if CUI._updatePvpIlvlDisplay then CUI._updatePvpIlvlDisplay() end
            end,
        })
        cursorY = cursorY - height
        AddDisabledCover(enchGemRow)

        if not CUI._prebuilding then
            local cogBtn = CUI.BuildInlineCog(enchGemRow._leftRegion, {
                title = "Enchant Text",
                rows = {
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.charSheetEnchantSize) or 9 end,
                        set = function(val)
                            Account().charSheetEnchantSize = val
                            if CUI._refreshCharSheetSlotLabels then
                                CUI._refreshCharSheetSlotLabels()
                            end
                        end,
                    },
                },
            })
            local function SyncEnchantCog()
                cogBtn:SetShown(EnchantTextShown("showEnchants", "charSheetEnchantNames"))
            end
            CUI.RegisterWidgetRefresh(SyncEnchantCog)
            SyncEnchantCog()
        end

        -- Durability | Season Panel. The panel greys out with the sheet off;
        -- durability stays live either way. The panel is retail only.
        local seasonCfg
        if not CUI.IS_FOREVER then
            seasonCfg = {
                type = "toggle",
                text = "Season Panel",
                tooltip = "Show an Omnium Folio shortcut to the right of the socket panel during Midnight seasons. The cog adds a Great Vault shortcut.",
                disabled = themeOff,
                disabledTooltip = "Character Sheet",
                getValue = function() return not (CludesUIDB and CludesUIDB.charSheetSeasonPanel == false) end,
                setValue = function(val)
                    Account().charSheetSeasonPanel = val
                    if CUI._refreshCharSheetSocketPanel then CUI._refreshCharSheetSocketPanel() end
                    CUI:RefreshPage()
                end,
            }
        end
        local durSeasonRow
        durSeasonRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Item Durability",
            tooltip = "Show total equipped durability above the character model, colored from green to red.",
            getValue = function() return CludesUIDB and CludesUIDB.showCharSheetDurability or false end,
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
                if CUI._updateCharSheetDurability then CUI._updateCharSheetDurability() end
                if CUI._updateScrollHeaderOffset then CUI._updateScrollHeaderOffset() end
                CUI:RefreshPage()
            end,
        }, seasonCfg or CUI.BlankRowCfg())
        cursorY = cursorY - height

        if not CUI._prebuilding then
            CUI.BuildInlineCog(durSeasonRow._leftRegion, {
                disabled = function() return not (CludesUIDB and CludesUIDB.showCharSheetDurability) end,
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
                            if CUI._updateCharSheetDurability then
                                CUI._updateCharSheetDurability()
                            end
                            if CUI._updateScrollHeaderOffset then
                                CUI._updateScrollHeaderOffset()
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
                            if CUI._updateCharSheetDurability then
                                CUI._updateCharSheetDurability()
                            end
                        end,
                    },
                },
            })

            -- Inline cog on Season Panel: the Great Vault shortcut is its own opt-in.
            if seasonCfg then
                CUI.BuildInlineCog(durSeasonRow._rightRegion, {
                    disabled = function()
                        return themeOff() or (CludesUIDB and CludesUIDB.charSheetSeasonPanel == false)
                    end,
                    disabledTooltip = function() return themeOff() and "Character Sheet" or "Season Panel" end,
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
                                if CUI._refreshCharSheetSocketPanel then
                                    CUI._refreshCharSheetSocketPanel()
                                end
                            end,
                        },
                    },
                })
            end
        end

        _, height = Widg:Spacer(hostFrame, cursorY, 10)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  GEAR FLYOUT
        ---------------------------------------------------------------------------
        -- The popup of same-slot items from an equipped slot. Item levels and
        -- stat letters enhance Blizzard's own flyout, so they stay live with the
        -- sheet off; the slot arrows belong to the sheet and grey out with it.
        -- The sheet's own slot letters live under Item Details (Stat Letters,
        -- Tertiary Stats). All off unless turned on.
        _, height = WSCardSection(hostFrame, "GEAR FLYOUT", cursorY)
        cursorY = cursorY - height

        local flyoutStatsCfg
        if not CUI.IS_FOREVER then
            flyoutStatsCfg = {
                type = "toggle",
                text = "Show Item Stats",
                tooltip = "Shows each item's secondary stats as letters in the gear flyout, largest first (C Crit, H Haste, M Mastery, V Versatility), so items with the same icon are told apart.",
                getValue = function() return CludesUIDB and CludesUIDB.flyoutItemStats or false end,
                setValue = function(val)
                    Account().flyoutItemStats = val
                    CUI:RefreshPage()
                end,
            }
        end
        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Item Levels",
            tooltip = "Shows the item level on each item in the character sheet gear flyout (the popup of same-slot bag items that appears when hovering an equipped slot), colored by quality.",
            getValue = function() return CludesUIDB and CludesUIDB.flyoutItemLevels or false end,
            setValue = AccountField("flyoutItemLevels"),
        }, flyoutStatsCfg or CUI.BlankRowCfg())
        cursorY = cursorY - height

        if not CUI.IS_FOREVER then
            _, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Tertiary Stat Letters",
                tooltip = "Adds Leech, Avoidance and Speed (L, A, S) in smaller letters behind the secondary stats in the gear flyout.",
                disabled = function() return not (CludesUIDB and CludesUIDB.flyoutItemStats) end,
                disabledTooltip = "Show Item Stats",
                getValue = function()
                    return CludesUIDB and CludesUIDB.flyoutItemStatsTertiary == true or false
                end,
                setValue = AccountField("flyoutItemStatsTertiary"),
            }, {
                type = "toggle",
                text = "Hide Slot Flyout Arrows",
                tooltip = "Hide the arrows beside equipment slots on the Equipment tab. The slot flyouts remain usable.",
                disabled = themeOff,
                disabledTooltip = "Character Sheet",
                getValue = function() return CludesUIDB and CludesUIDB.charSheetHideSlotFlyoutArrows == true end,
                setValue = function(val)
                    Account().charSheetHideSlotFlyoutArrows = val
                    if CUI._refreshCharSheetSlotFlyoutArrows then
                        CUI._refreshCharSheetSlotFlyoutArrows()
                    end
                end,
            })
            cursorY = cursorY - height
        end

        _, height = Widg:Spacer(hostFrame, cursorY, 10)
        cursorY = cursorY - height

        ---------------------------------------------------------------------------
        --  STAT DISPLAY
        ---------------------------------------------------------------------------
        _, height = WSCardSection(hostFrame, "STAT DISPLAY", cursorY)
        cursorY = cursorY - height

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
        local function SectionShown(settingKey)
            return not (CludesUIDB and CludesUIDB["showStatCategory_" .. settingKey] == false)
        end
        local function SecOrTerShown() return SectionShown("SecondaryStats") or SectionShown("Tertiary") end

        -- Stat Sections (checkbox dropdown + cog) | Show Diminishing Returns
        local sectionsRow
        sectionsRow, height = Widg:DualRow(hostFrame, cursorY, { type = "label", text = "Stat Sections" }, {
            type = "toggle",
            text = "Show Diminishing Returns",
            tooltip = "Adds diminishing returns info to Secondary and Tertiary stat tooltips.",
            getValue = function() return CludesUIDB and CludesUIDB.showAdjustedStats or false end,
            setValue = AccountField("showAdjustedStats"),
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            local leftRegion = sectionsRow._leftRegion
            -- Each section's colour swatch sits on its row of the dropdown; dimmed while
            -- Blizzard UI Color applies or the section is unchecked.
            local itemList = {}
            for idx, sec in ipairs(STAT_SECTIONS) do
                local settingKey, labelText, colorKey, def = sec.key, sec.label, sec.color, sec.def
                itemList[idx] = {
                    key = settingKey,
                    label = labelText,
                    swatch = {
                        get = function()
                            local color = CludesUIDB
                                and CludesUIDB.statCategoryColors
                                and CludesUIDB.statCategoryColors[colorKey]
                            if color then return color.r, color.g, color.b, 1 end
                            return def.r, def.g, def.b, 1
                        end,
                        set = function(red, green, blue)
                            if not CludesUIDB then CludesUIDB = {} end
                            if not CludesUIDB.statCategoryColors then CludesUIDB.statCategoryColors = {} end
                            if not CludesUIDB.statCategoryUseColor then
                                CludesUIDB.statCategoryUseColor = {}
                            end
                            CludesUIDB.statCategoryColors[colorKey] = { r = red, g = green, b = blue }
                            CludesUIDB.statCategoryUseColor[colorKey] = true
                            if CUI._refreshCharacterSheetColors then
                                CUI._refreshCharacterSheetColors()
                            end
                        end,
                        disabled = function() return blizzColorsOn() or not SectionShown(settingKey) end,
                        -- Two requirements with opposite wording: pre-wrapped, so raw.
                        disabledTooltip = function()
                            if blizzColorsOn() then
                                return not CUI.IS_FOREVER
                                        and CUI.DisabledTooltip("Blizzard UI Color", "disabled")
                                    or nil
                            end
                            return CUI.DisabledTooltip(labelText)
                        end,
                        rawTooltip = true,
                    },
                }
            end
            local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                leftRegion,
                210,
                leftRegion:GetFrameLevel() + 2,
                itemList,
                SectionShown,
                function(settingKey, val)
                    Account()["showStatCategory_" .. settingKey] = val
                    if CUI._updateStatCategoryVisibility then
                        CUI._updateStatCategoryVisibility()
                    end
                    local sf = CharacterFrame and CUI._GetFFD(CharacterFrame).scrollFrame
                    if sf then sf:SetVerticalScroll(0) end
                    CUI:RefreshPage()
                end
            )
            Pix.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
            leftRegion._control = checkDrop
            leftRegion._lastInline = nil
            CUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Cog: the per-section extras the old per-section rows held
            local rowList = {
                {
                    type = "toggle",
                    label = "Show Mana",
                    tooltip = "Adds Mana to the Attributes section.",
                    disabled = function() return not SectionShown("Attributes") end,
                    disabledTooltip = "Attributes",
                    get = function() return CludesUIDB and CludesUIDB.showManaStat == true end,
                    set = function(val)
                        Account().showManaStat = val
                        if CUI._refreshStatsVisibility then CUI._refreshStatsVisibility() end
                    end,
                },
                {
                    type = "reordercheck",
                    label = "Crests",
                    ddWidth = 150,
                    disabled = function() return not SectionShown("Crests") end,
                    disabledTooltip = "Crests",
                    items = {
                        { key = "Myth", label = "Myth", fixed = true },
                        { key = "Hero", label = "Hero", fixed = true },
                        { key = "Champion", label = "Champion", fixed = true },
                        { key = "Veteran", label = "Veteran", fixed = true },
                        { key = "Adventurer", label = "Adventurer", fixed = true },
                    },
                    get = function(settingKey)
                        return not (CludesUIDB and CludesUIDB["showCrest_" .. settingKey] == false)
                    end,
                    set = function(settingKey, val)
                        Account()["showCrest_" .. settingKey] = val
                        if CUI._refreshStatsVisibility then CUI._refreshStatsVisibility() end
                    end,
                },
            }
            -- Blizz Default only (not WoW Forever, whose sheet has no
            -- CludesUI stats section): on unless turned off.
            if stock and not CUI.IS_FOREVER then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Blizzard UI Color",
                    tooltip = "Shows the item level and stat titles in Blizzard's yellow.",
                    get = function() return not (CludesUIDB and CludesUIDB.charSheetBlizzColors == false) end,
                    set = function(val)
                        Account().charSheetBlizzColors = val
                        if CUI._refreshCharacterSheetColors then
                            CUI._refreshCharacterSheetColors()
                        end
                        CUI:RefreshPage()
                    end,
                }
            end
            CUI.BuildInlineCog(leftRegion, {
                title = "Stat Section Settings",
                rows = rowList,
                disabled = themeOff,
                disabledTooltip = "Character Sheet",
            })
        end
        AddDisabledCover(sectionsRow)

        -- Secondary/Tertiary Text | Secondary/Tertiary Highlights (both write
        -- the Secondary and the Tertiary keys; the Secondary pair is shown)
        local stRow
        stRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Secondary/Tertiary Text",
            tooltip = "How Secondary and Tertiary stat values are shown.",
            values = { pct = "Percent", value = "Value", both = "Value (Percent)" },
            order = { "pct", "value", "both" },
            disabled = function() return not SecOrTerShown() end,
            disabledTooltip = "Secondary Stats or Tertiary Stats",
            getValue = function()
                -- Both wins over Raw, as on the sheet
                if CludesUIDB and CludesUIDB.showSecondaryBoth then return "both" end
                if CludesUIDB and CludesUIDB.showSecondaryRaw then return "value" end
                return "pct"
            end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                local raw, both = val == "value", val == "both"
                CludesUIDB.showSecondaryRaw, CludesUIDB.showSecondaryBoth = raw, both
                CludesUIDB.showTertiaryRaw, CludesUIDB.showTertiaryBoth = raw, both
                if CUI._refreshStatFormats then CUI._refreshStatFormats() end
            end,
        }, {
            type = "toggle",
            text = "Secondary/Tertiary Highlights",
            tooltip = "Hovering a Secondary or Tertiary stat highlights the gear that has it.",
            disabled = function() return not SecOrTerShown() end,
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
        cursorY = cursorY - height
        AddDisabledCover(stRow)

        ---------------------------------------------------------------------------
        --  INSPECT SHEET
        ---------------------------------------------------------------------------
        _, height = WSCardSection(hostFrame, "INSPECT SHEET", cursorY)
        cursorY = cursorY - height

        local themedInspectSheetRow
        themedInspectSheetRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Inspect Sheet",
            tooltip = "Applies CludesUI theme styling to the inspect sheet window.",
            getValue = function() return not CludesUIDB or CludesUIDB.themedInspectSheet ~= false end,
            setValue = function(val)
                Account().themedInspectSheet = val
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Inspect Sheet theme setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Enchants",
            tooltip = "How enchants show beside each item.",
            values = EnchantValues(),
            order = { "none", "icons", "text" },
            disabled = function() return CludesUIDB and CludesUIDB.themedInspectSheet == false end,
            disabledTooltip = "Inspect Sheet",
            getValue = function() return EnchantMode("inspectShowEnchants", "inspectEnchantNames") end,
            setValue = function(val)
                SetEnchantMode("inspectShowEnchants", "inspectEnchantNames", val)
                if CUI._refreshInspectSlotLabels then CUI._refreshInspectSlotLabels() end
                -- Shows or hides the Text Size cog
                CUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Text Size (unset follows the character sheet's), shown only while
        -- the enchants show as text.
        if not CUI._prebuilding then
            local cogBtn = CUI.BuildInlineCog(themedInspectSheetRow._rightRegion, {
                title = "Enchant Text",
                disabled = function() return CludesUIDB and CludesUIDB.themedInspectSheet == false end,
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
                            if CUI._refreshInspectSlotLabels then
                                CUI._refreshInspectSlotLabels()
                            end
                        end,
                    },
                },
            })
            local function SyncEnchantCog()
                cogBtn:SetShown(EnchantTextShown("inspectShowEnchants", "inspectEnchantNames"))
            end
            CUI.RegisterWidgetRefresh(SyncEnchantCog)
            SyncEnchantCog()
        end

        local inspectRow
        inspectRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Item Level",
            tooltip = "Toggle visibility of item level text on the inspect sheet.",
            getValue = function() return CludesUIDB and CludesUIDB.inspectShowItemLevel ~= false end,
            setValue = function(val)
                Account().inspectShowItemLevel = val
                if CUI._refreshInspectItemLevelVisibility then
                    CUI._refreshInspectItemLevelVisibility()
                end
            end,
        }, {
            type = "toggle",
            text = "Upgrade Track",
            tooltip = "Toggle visibility of upgrade track text on the inspect sheet.",
            getValue = function() return CludesUIDB and CludesUIDB.inspectShowUpgradeTrack ~= false end,
            setValue = function(val)
                Account().inspectShowUpgradeTrack = val
                if CUI._refreshInspectUpgradeTrackVisibility then
                    CUI._refreshInspectUpgradeTrackVisibility()
                end
            end,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            local function themeOff() return not (CludesUIDB and CludesUIDB.themedInspectSheet) end

            local inspectCover = CreateFrame("Frame", nil, inspectRow)
            inspectCover:SetAllPoints(inspectRow)
            inspectCover:SetFrameLevel(inspectRow:GetFrameLevel() + 10)
            inspectCover:EnableMouse(true)
            local itemLevelInspectBg = CUI.SolidTex(inspectCover, "BACKGROUND", 0, 0, 0, 0)
            itemLevelInspectBg:SetAllPoints()
            inspectCover:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(inspectCover, CUI.DisabledTooltip("Inspect Sheet")) end
            )
            inspectCover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

            CUI.RegisterWidgetRefresh(function()
                if themeOff() then
                    inspectCover:Show()
                    inspectRow:SetAlpha(0.3)
                else
                    inspectCover:Hide()
                    inspectRow:SetAlpha(1)
                end
            end)
            if themeOff() then
                inspectCover:Show()
                inspectRow:SetAlpha(0.3)
            else
                inspectCover:Hide()
                inspectRow:SetAlpha(1)
            end
        end

        return cursorY
    end

    ---------------------------------------------------------------------------
    --  LFG Menu card content
    ---------------------------------------------------------------------------
    local function BuildLFGMenuContent(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local _, height

        _, height = WSCardSection(hostFrame, "QUALITY OF LIFE", cursorY)
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Remember Sign-Up Roles",
            tooltip = "Remembers the Tank/Healer/DPS roles you last applied with and restores them the next time you sign up to a premade group (limited to roles your current spec can fill). Works with or without the reskin.",
            getValue = function() return CludesUIDB and CludesUIDB.lfgRememberRoles == true end,
            setValue = function(val)
                Account().lfgRememberRoles = val
                if CUI._GroupFinder_RefreshQoL then CUI._GroupFinder_RefreshQoL() end
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        return cursorY
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
    local function BuildFriendsCardContent(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local _, row, height
        local Kit = CUI.FriendsKit

        local CUSTOM = "Custom Friends List Tiles"
        local function customOff() return mod.FriendsCardGet("customTiles") ~= true end
        -- Blizz Default keeps Blizzard's cards, so only the custom list draws tiles there
        local function tilesOff() return CUI.GetBlizzWindowStyle("socialui") == "off" and customOff() end
        local function tileGate(rowConf, off)
            rowConf.disabled = off or tilesOff
            rowConf.disabledTooltip = CUSTOM
            return rowConf
        end

        _, height = WSCardSection(hostFrame, "DISPLAY", cursorY)
        cursorY = cursorY - height

        -- Custom Friends List Tiles | Tile Height: the custom friends list
        -- (CludesUI_FriendsList.lua) and its own height
        local tileMin, tileMax = CUI.FriendsList.TileRange()
        row, height = Widg:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = CUSTOM,
                tooltip = "CludesUI's own friends list, with a tile height you choose and friend groups. Right click a friend to set its group.",
                getValue = function() return not customOff() end,
                setValue = function(val)
                    mod.FriendsCardSet("customTiles", val and true or false)
                    CUI:RefreshPage() -- the tile settings' disabled state
                end,
            },
            tileGate({
                type = "slider",
                text = "Tile Height",
                min = tileMin,
                max = tileMax,
                step = 1,
                tooltip = "The height of each friend in the custom friends list. Shorter tiles show fewer lines.",
                getValue = function() return mod.FriendsCardGet("tileHeight") end,
                setValue = function(val) mod.FriendsCardSet("tileHeight", val) end,
            }, customOff)
        )
        cursorY = cursorY - height

        -- Tile Features | Class Icon Theme
        row, height = Widg:DualRow(
            hostFrame,
            cursorY,
            tileGate({
                type = "dropdown",
                text = "Tile Features",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            }),
            tileGate({
                type = "dropdown",
                text = "Class Icon Theme",
                values = Kit.ICON_STYLE_VALUES,
                order = Kit.ICON_STYLE_ORDER,
                getValue = function() return mod.FriendsCardGet("iconStyle") end,
                setValue = function(val) mod.FriendsCardSet("iconStyle", val) end,
            })
        )
        cursorY = cursorY - height

        -- Tile Features: one checkbox dropdown over the three tile switches,
        -- each still its own key, in place of the row's placeholder.
        if not CUI._prebuilding then
            local region = row._leftRegion
            if region._control then region._control:Hide() end
            local dropdown, refreshFn = CUI.BuildVisOptsCBDropdown(
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
                function(settingKey) return mod.FriendsCardGet(settingKey) == true end,
                function(settingKey, val) mod.FriendsCardSet(settingKey, val and true or false) end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = tilesOff, disabledTooltip = CUSTOM }
            )
            CUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(refreshFn)
        end

        -- Auto-Accept Friend Invites
        row, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto-Accept Friend Invites",
            tooltip = "Auto-accepts all group invites from people on your friends list",
            getValue = function() return mod.FriendsCardGet("autoAcceptFriendInvites") == true end,
            setValue = function(val)
                mod.FriendsCardSet("autoAcceptFriendInvites", val)
                CUI:RefreshPage() -- the guildmate cog's disabled state
            end,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height

        -- Guildmates in a cog on Auto-Accept Friend Invites: it only extends
        -- that feature, so the cog blocks while the toggle is off.
        if not CUI._prebuilding then
            CUI.BuildInlineCog(row._leftRegion, {
                title = "Auto Accept Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Accept Invites from Guildmates",
                        get = function() return mod.FriendsCardGet("autoAcceptGuildInvites") == true end,
                        set = function(val) mod.FriendsCardSet("autoAcceptGuildInvites", val) end,
                    },
                },
                disabled = function() return mod.FriendsCardGet("autoAcceptFriendInvites") ~= true end,
                disabledTooltip = "Auto-Accept Friend Invites",
            })
        end

        return cursorY
    end

    local function BuildMerchantContent(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local _, height

        local function themeOff() return CludesUIDB and CludesUIDB.reskinMerchant == false end

        local function AddDisabledCover(goal)
            local cover = CreateFrame("Frame", nil, goal)
            cover:SetAllPoints(goal)
            cover:SetFrameLevel(goal:GetFrameLevel() + 10)
            cover:EnableMouse(true)
            local backdrop = CUI.SolidTex(cover, "BACKGROUND", 0, 0, 0, 0)
            backdrop:SetAllPoints()
            cover:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(cover, CUI.DisabledTooltip("Merchant")) end
            )
            cover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function refreshFn()
                if themeOff() then
                    cover:Show()
                    goal:SetAlpha(0.3)
                else
                    cover:Hide()
                    goal:SetAlpha(1)
                end
            end
            CUI.RegisterWidgetRefresh(refreshFn)
            refreshFn()
        end

        _, height = WSCardSection(hostFrame, "MERCHANT OPTIONS", cursorY)
        cursorY = cursorY - height

        local function merchantShowAsListOff() return CludesUIDB and CludesUIDB.merchantShowAsList == false end

        local row
        row, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show As List",
            tooltip = "Shows the items as a list instead of pages.",
            getValue = function() return CludesUIDB and CludesUIDB.merchantShowAsList == true end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                local previousValue = CludesUIDB.merchantShowAsList
                CludesUIDB.merchantShowAsList = val

                -- Enabling the setting breaks the UI immediately, a reload is required
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Merchant Show As List setting requires a UI reload to fully apply.",
                    confirmText = "Reload Now",
                    cancelText = "Cancel",
                    reload = true,
                    onCancel = function()
                        CludesUIDB.merchantShowAsList = previousValue
                        CUI:RefreshPage()
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
            getValue = function() return (CludesUIDB and CludesUIDB.merchantListRowHeight) or 32 end,
            setValue = function(val)
                Account().merchantListRowHeight = val
                if CUI._Merchant_RefreshRowHeight then CUI._Merchant_RefreshRowHeight() end
            end,
        })
        cursorY = cursorY - height
        AddDisabledCover(row)

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Item Level",
            tooltip = "Shows the item level on weapons and armor a vendor sells.",
            getValue = function() return CludesUIDB and CludesUIDB.merchantShowItemLevel == true end,
            setValue = function(val)
                Account().merchantShowItemLevel = val
                if CUI._Merchant_RefreshItemLevels then CUI._Merchant_RefreshItemLevels() end
            end,
        }, {
            type = "toggle",
            text = "Bulk Buy",
            tooltip = "Shift-click a vendor item to buy more than one stack at a time.",
            disabled = function() return CUI.PadGamepadUI() end,
            disabledTooltip = "This option does not work with the Gamepad interface style.",
            getValue = function() return CludesUIDB and CludesUIDB.merchantBulkBuy == true end,
            setValue = function(val)
                Account().merchantBulkBuy = val
                if CUI._Merchant_RefreshBulkBuy then CUI._Merchant_RefreshBulkBuy() end
            end,
        })
        cursorY = cursorY - height

        -- Expand Vendor UI: a bigger grid in the vendor window. The cog sets its
        -- size; 2 x 5 is Blizzard's own layout. Needs the Merchant skin (the
        -- card overlay) and is not used with Show As List.
        local function merchantShowAsListOn() return CludesUIDB and CludesUIDB.merchantShowAsList == true end
        local function BuildExpandCog(region)
            if CUI._prebuilding then return end
            local function setSize(settingKey, val)
                Account()[settingKey] = val
                if CUI._Merchant_RefreshExpand then CUI._Merchant_RefreshExpand() end
            end
            CUI.BuildInlineCog(region, {
                title = "Expand Vendor UI Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Vendor Columns",
                        min = 2,
                        max = 6,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.merchantCols) or 2 end,
                        set = function(val) setSize("merchantCols", val) end,
                    },
                    {
                        type = "slider",
                        label = "Vendor Rows",
                        min = 5,
                        max = 10,
                        step = 1,
                        get = function() return (CludesUIDB and CludesUIDB.merchantRows) or 5 end,
                        set = function(val) setSize("merchantRows", val) end,
                    },
                },
                gap = 9,
                disabled = function()
                    return merchantShowAsListOn() or not (CludesUIDB and CludesUIDB.merchantExpand)
                end,
                disabledTooltip = function()
                    if merchantShowAsListOn() then return "This option does not work with Show As List." end
                    return "Expand Vendor UI"
                end,
            })
        end

        row, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Expand Vendor UI",
            tooltip = "Shows more vendor items at once, in the columns and rows set in the cog.",
            disabled = merchantShowAsListOn,
            disabledTooltip = "This option does not work with Show As List.",
            getValue = function() return CludesUIDB and CludesUIDB.merchantExpand == true end,
            setValue = function(val)
                Account().merchantExpand = val
                if CUI._Merchant_RefreshExpand then CUI._Merchant_RefreshExpand() end
                CUI:RefreshPage()
            end,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height
        BuildExpandCog(row._leftRegion)
        AddDisabledCover(row)

        return cursorY
    end

    ---------------------------------------------------------------------------
    --  Loot Window card: BORDER, an optional border in place of the window
    --  border (ApplyLootBorder, CludesUIBlizzardSkin_WindowPacks.lua; Default
    --  leaves the setting unset), and ICON BORDER, the item icons' border in a
    --  picked style. The Tooltips page's border rows (the shared helpers above,
    --  under the "lootWindow" and "lootIcon" prefixes), plus a Quality color mode.
    ---------------------------------------------------------------------------
    local function BuildLootContent(hostFrame, cursorY)
        if not CludesUIDB then CludesUIDB = {} end
        local Widg = CUI.Widgets
        local _, height
        local prefixText = "lootWindow"
        local iconPrefix = "lootIcon"

        local function lootOff() return CUI.GetBlizzWindowStyle("loot") == "off" end
        local function iconOff() return lootOff() or not CludesUIDB.lootIconBorder end
        local function refreshFn()
            if CUI._Loot_RefreshBorder then CUI._Loot_RefreshBorder() end
        end

        _, height = WSCardSection(hostFrame, "BORDER", cursorY)
        cursorY = cursorY - height

        local texValues, texOrder = CUI.GetBorderTextureDropdown()
        texValues.default = "Default"
        table.insert(texOrder, 1, "default")

        local row
        row, height = Widg:DualRow(hostFrame, cursorY, {
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
                if not CludesUIDB then CludesUIDB = {} end
                local saved = CludesUIDB
                if val == "default" then
                    saved[prefixText .. "BorderTexture"] = nil
                else
                    local c, b = CUI.GetBorderStyleSelectDefaults(val)
                    saved[prefixText .. "BorderTexture"] = val
                    saved[prefixText .. "BorderBehind"] = b
                    saved[prefixText .. "BorderColor"] = c
                    -- Full opacity and the style's own size: the 18% default leaves textured art faded
                    saved[prefixText .. "BorderOpacity"] = 1
                    local size = CUI.GetBorderDefaultSize(nil, val)
                    if size then
                        saved[prefixText .. "BorderThickness"] = CUI.BORDER_LABEL_OF_STEP[size]
                    end
                end
                saved[prefixText .. "BorderOffsetX"] = nil
                saved[prefixText .. "BorderOffsetY"] = nil
                if saved[prefixText .. "BorderThicknessPx"] then
                    saved[prefixText .. "BorderThicknessPx"] = false
                end
                refreshFn()
                CUI:RefreshPage(true)
            end,
        }, BorderSizeSlider(prefixText, "Border Size", lootOff, refreshFn, "Loot Window"))
        cursorY = cursorY - height

        -- Accent | Class | Custom | Quality swatches beside Border Size, as on the Tooltips page.
        AttachBorderControls(row, prefixText, lootOff, false, {
            apply = refreshFn,
            quality = {
                key = prefixText .. "BorderQualityColor",
                tip = "Quality Color: the best item's, or this color for Poor and Common",
            },
        })

        -- Width | Height Offset, only for a textured style (art with built-in padding needs fitting).
        local ocfgL, ocfgR = BorderOffsetCfgs(prefixText, lootOff, refreshFn, "Loot Window")
        if ocfgL then
            _, height = Widg:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
            cursorY = cursorY - height
        end

        -- ICON BORDER: the item icons' quality border in a picked style and size (color stays the item quality).
        _, height = WSCardSection(hostFrame, "ICON BORDER", cursorY)
        cursorY = cursorY - height

        local iconValues, iconOrder = CUI.GetBorderTextureDropdown()
        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Icon Borders",
            tooltip = "Draws the item icons' quality border in the style and size below.",
            disabled = lootOff,
            disabledTooltip = "Loot Window",
            getValue = function() return CludesUIDB.lootIconBorder == true end,
            setValue = function(val)
                CludesUIDB.lootIconBorder = val
                refreshFn()
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Icon Border Style",
            disabled = iconOff,
            disabledTooltip = "Icon Borders",
            values = iconValues,
            order = iconOrder,
            getValue = function() return CludesUIDB[iconPrefix .. "BorderTexture"] or "solid" end,
            setValue = function(val)
                local saved = CludesUIDB
                saved[iconPrefix .. "BorderTexture"] = val
                saved[iconPrefix .. "BorderOffsetX"] = nil
                saved[iconPrefix .. "BorderOffsetY"] = nil
                if saved[iconPrefix .. "BorderThicknessPx"] then
                    saved[iconPrefix .. "BorderThicknessPx"] = false
                end
                refreshFn()
                CUI:RefreshPage(true)
            end,
        })
        cursorY = cursorY - height

        local iconSize = BorderSizeSlider(iconPrefix, "Icon Border Size", iconOff, refreshFn, "Icon Borders")
        iconSize.trackWidth = nil -- no swatches beside it: the full track
        -- Textured styles add the two offsets: Size | Width Offset, then Height Offset | blank.
        local icL, icR = BorderOffsetCfgs(iconPrefix, iconOff, refreshFn, "Icon Borders")
        if icL then
            _, height = Widg:DualRow(hostFrame, cursorY, iconSize, icL)
            cursorY = cursorY - height
            _, height = Widg:DualRow(hostFrame, cursorY, icR, CUI.BlankRowCfg())
            cursorY = cursorY - height
        else
            _, height = Widg:DualRow(hostFrame, cursorY, iconSize, CUI.BlankRowCfg())
            cursorY = cursorY - height
        end

        return cursorY
    end

    local function BuildLootToastContent(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local _, height

        _, height = WSCardSection(hostFrame, "QUALITY OF LIFE", cursorY)
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quality Strip",
            tooltip = "Adds a strip down the left edge of a loot toast in the item's quality color. The flat skin drops Blizzard's quality ring around the icon, so this puts that rarity cue back.",
            getValue = function() return not CludesUIDB or CludesUIDB.lootToastQualityStrip ~= false end,
            setValue = AccountFieldThen("lootToastQualityStrip"),
        }, {
            type = "toggle",
            text = "Gold Toast Strip",
            tooltip = "Also show the strip on gold toasts, in the header's gold color. Gold has no rarity to signal, so this is off by default.",
            getValue = function() return CludesUIDB and CludesUIDB.lootToastQualityStripMoney == true end,
            setValue = AccountFieldThen("lootToastQualityStripMoney"),
        })
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Toast Scale",
            tooltip = "Scales the loot and gold toasts.",
            min = 0.5,
            max = 1.5,
            step = 0.05,
            format = "%.0f%%",
            displayMul = 100,
            getValue = function() return CludesUIDB and CludesUIDB.lootToastScale or 1.0 end,
            setValue = AccountFieldThen("lootToastScale"),
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        return cursorY
    end

    ---------------------------------------------------------------------------
    --  Mail card, ALT LIST section (retail): the Alt List beside Send Mail
    --  (CludesUIBlizzardSkin_MailAlts.lua, ns.MailAlts), whatever the card's
    --  style. Sort, cap and minimum level ride the toggle's cog; Shown
    --  Characters lists every recorded character under its realm.
    ---------------------------------------------------------------------------
    local function BuildMailAltList(hostFrame, cursorY)
        local MA = mod.MailAlts
        if not MA then return cursorY end
        local Widg = CUI.Widgets
        local _, row, height
        local REQ = "Show Alt List"
        local function On() return CludesUIDB and CludesUIDB.mailAltList == true end
        local function SkinsOff() return not On() end
        local function Get(settingKey, default)
            local val = CludesUIDB and CludesUIDB[settingKey]
            if val == nil then return default end
            return val
        end
        local function Set(settingKey, val)
            Account()[settingKey] = val
            MA.Refresh()
        end
        -- Every recorded character, a header per realm (rebuilt on each open).
        local function Items()
            local itemList, lastRealm = {}, nil
            for _, entry in ipairs(MA.Entries()) do
                if entry.realm ~= lastRealm then
                    lastRealm = entry.realm
                    itemList[#itemList + 1] = { isHeader = true, label = entry.realm }
                end
                local color = CUI.GetClassColor(entry.class)
                itemList[#itemList + 1] = {
                    key = entry.guid,
                    label = CUI.HexColor(color.r, color.g, color.b) .. entry.name .. "|r",
                    tooltip = MA.Describe(entry),
                }
            end
            return itemList
        end

        _, height = WSCardSection(hostFrame, "ALT LIST", cursorY)
        cursorY = cursorY - height

        row, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Alt List",
            tooltip = "Lists your alts beside Send Mail.",
            getValue = On,
            setValue = function(val)
                Set("mailAltList", val)
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Shown Characters",
            tooltip = "Untick a character to leave it off the list.",
            disabled = SkinsOff,
            disabledTooltip = REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function() return "__placeholder" end,
            setValue = function() end,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            CUI.BuildInlineCog(row._leftRegion, {
                title = "Alt List",
                disabled = SkinsOff,
                disabledTooltip = REQ,
                rows = {
                    {
                        type = "dropdown",
                        label = "Sort By",
                        values = { recent = "Last Played", level = "Level", name = "Name" },
                        order = { "recent", "level", "name" },
                        get = function() return Get("mailAltListSort", MA.DEFAULT_SORT) end,
                        set = function(val) Set("mailAltListSort", val) end,
                    },
                    {
                        type = "slider",
                        label = "Max Characters Shown",
                        min = 1,
                        max = MA.MAX_ROWS,
                        step = 1,
                        get = function() return Get("mailAltListMax", MA.DEFAULT_MAX) end,
                        set = function(val) Set("mailAltListMax", val) end,
                    },
                    {
                        type = "slider",
                        label = "Minimum Level",
                        min = 1,
                        max = GetMaxLevelForLatestExpansion(),
                        step = 1,
                        get = function() return Get("mailAltListMinLevel", MA.DEFAULT_MIN_LEVEL) end,
                        set = function(val) Set("mailAltListMinLevel", val) end,
                    },
                },
            })
            -- Shown Characters: the checkbox dropdown in place of the row's
            -- placeholder; a long roster gets the search box.
            local region = row._rightRegion
            if region._control then region._control:Hide() end
            local dropdown, refreshFn = CUI.BuildVisOptsCBDropdown(
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
                { disabled = SkinsOff, disabledTooltip = REQ, countLabel = true }
            )
            CUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(refreshFn)
        end

        return cursorY
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

    local function AskSkinReload(message)
        CUI:ShowConfirmPopup({
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
        if mod.WSkin and mod.WSkin.GetModernBG then return mod.WSkin.GetModernBG() end
        return 0.067, 0.067, 0.067, 0.97
    end
    local function WSModernSet(red, green, blue, a)
        Account().blizzWindowModernDefault = { r = red, g = green, b = blue, a = a }
        if CUI._WSkinRefreshStyles then CUI._WSkinRefreshStyles() end
    end

    -- Single Modern color swatch left of the set-all dropdown, greyed and
    -- blocked while isOff() (that dropdown is not on Modern). The picker
    -- carries the opacity slider; edits write the Modern preset directly, so
    -- windows already on Modern recolor immediately (no Apply to All).
    local function AttachModernSwatch(owner, anchorTo, isOff)
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            owner,
            owner:GetFrameLevel() + 5,
            function() return WSModernGet() end,
            function(red, green, blue, a) WSModernSet(red, green, blue, a) end,
            true,
            20
        )
        CUI.PanelPP.Point(colorSwatch, "RIGHT", anchorTo, "LEFT", -8, 0)
        colorSwatch:HookScript(
            "OnEnter",
            function(s) CUI.ShowWidgetTooltip(s, "Background color for the Modern style.") end
        )
        colorSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local cover = CUI.NewSwatchBlocker(colorSwatch)
        cover:SetScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    colorSwatch,
                    CUI.DisabledTooltip("This option requires the Modern style.")
                )
            end
        )
        cover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function Refresh()
            updateSwatch()
            local off = isOff()
            colorSwatch:SetAlpha(off and 0.3 or 1)
            cover:SetShown(off)
        end
        CUI.RegisterWidgetRefresh(Refresh)
        Refresh()
    end

    -- Global look settings (Global Options section): central tables, nil =
    -- defaults, resolved by the window-skin engine and applied live.
    local function SkinSetting(settingKey) return CludesUIDB and CludesUIDB[settingKey] end
    local function WSLookSet(settingKey, field, val)
        if not CludesUIDB then CludesUIDB = {} end
        local tbl = CludesUIDB[settingKey]
        if not tbl then
            tbl = {}
            CludesUIDB[settingKey] = tbl
        end
        tbl[field] = val
        if CUI._WSkinRefreshLooks then CUI._WSkinRefreshLooks() end
    end

    -- Inline accent|custom swatch pair on a DualRow region (the standard
    -- dual-swatch treatment): custom sits nearest the control, accent left of
    -- it; the active mode renders bright, the other dimmed.
    local function AttachLookSwatches(region, row, settingKey)
        local Pix = CUI.PanelPP
        local control = region._control

        local customSwatch, updateCustom = CUI.BuildColorSwatch(
            region,
            row:GetFrameLevel() + 3,
            function()
                local c = SkinSetting(settingKey)
                local col = c and c.color
                if col then return col.r or 1, col.g or 1, col.b or 1 end
                return 1, 1, 1
            end,
            function(red, green, blue)
                WSLookSet(settingKey, "color", { r = red, g = green, b = blue })
                WSLookSet(settingKey, "useCustom", true)
                CUI:RefreshPage()
            end,
            false,
            20
        )
        Pix.Point(customSwatch, "RIGHT", control, "LEFT", -8, 0)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            local c = SkinSetting(settingKey)
            if not (c and c.useCustom) then
                WSLookSet(settingKey, "useCustom", true)
                CUI:RefreshPage()
                return
            end
            if origClick then origClick(self, ...) end
        end)
        CUI.HoverTip(customSwatch, "Custom Color")

        local accentSwatch, updateAccent = CUI.BuildColorSwatch(
            region,
            row:GetFrameLevel() + 3,
            function() return CUI.ResolveActiveAccent() end,
            function()
                WSLookSet(settingKey, "useCustom", false)
                CUI:RefreshPage()
            end,
            false,
            20
        )
        Pix.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        accentSwatch:SetScript("OnClick", function()
            WSLookSet(settingKey, "useCustom", false)
            CUI:RefreshPage()
        end)
        CUI.HoverTip(accentSwatch, "Accent Color")
        region._lastInline = accentSwatch

        local function refreshPair()
            updateCustom()
            updateAccent()
            local c = SkinSetting(settingKey)
            local useCustom = c and c.useCustom
            customSwatch:SetAlpha(useCustom and 1 or 0.3)
            accentSwatch:SetAlpha(useCustom and 0.3 or 1)
        end
        CUI.RegisterWidgetRefresh(refreshPair)
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
            title = CUI.IS_FOREVER and "Looking For Group (LFG)" or "LFG Menu",
            desc = CUI.IS_FOREVER
                    and "Looking For Group window: group listing, group browser and who list, plus the group tooltip."
                or "Group Finder and Premade Groups window, plus browsing quality-of-life extras.",
            reloadMsg = "Changing the Group Finder reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLFGMenu = val end,
            -- Its one extra (Remember Sign-Up Roles) hooks retail's premade sign-up
            -- dialog, which Forever does not have.
            buildContent = not CUI.IS_FOREVER and BuildLFGMenuContent or nil,
        },
        {
            key = "legacysystem",
            title = "Progress Legacy",
            desc = "Restyles the Progress Legacy window (reward track, challenges and the legacy tree) in the CludesUI style.",
            reloadMsg = "Changing the Progress Legacy reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLegacySystem = val end,
        },
        {
            key = "greatvault",
            title = "Great Vault",
            desc = "Weekly rewards window with custom tile backgrounds, progress colors, and completion states.",
            reloadMsg = "Changing the Great Vault reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinGreatVault = val end,
        },
        {
            key = "adventureguide",
            title = "Adventure Guide",
            desc = "Encounter Journal: instance select, boss details, loot lists, and the bottom nav tabs.",
            reloadMsg = "Changing the Adventure Guide reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinAdventureGuide = val end,
        },
        {
            key = "collections",
            title = "Collections",
            desc = "Mounts, pets, toys, heirlooms, appearances, and campsites.",
            reloadMsg = "Changing the Collections reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinCollections = val end,
        },
        {
            key = "playerspells",
            title = "Talents & Spellbook",
            desc = "The Player Spells window: talents, spec selection, and the spellbook.",
            reloadMsg = "Changing the Talents & Spellbook reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinPlayerSpells = val end,
        },
        {
            key = "professionsbook",
            title = "Professions",
            desc = "The professions overview book with squared icons and flat progress bars.",
            reloadMsg = "Changing the Professions reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinProfessionsBook = val end,
        },
        {
            key = "professions",
            title = "Profession Crafting",
            desc = "The profession crafting window: recipe list, schematic, specializations, and crafting orders.",
            reloadMsg = "Changing the Profession Crafting reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinProfessions = val end,
        },
        {
            key = "worldmap",
            title = "Map & Quest Log",
            desc = "The world map window chrome and the quest log side panel.",
            reloadMsg = "Changing the Map & Quest Log reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinWorldMap = val end,
        },
        {
            key = "guild",
            title = "Guild & Communities",
            desc = "The Guild & Communities window: roster, chat, and the community list.",
            reloadMsg = "Changing the Guild & Communities reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinGuild = val end,
        },
        {
            key = "calendar",
            title = "Calendar",
            desc = "The monthly calendar grid, event dialogs, and navigation arrows.",
            reloadMsg = "Changing the Calendar reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinCalendar = val end,
        },
        {
            key = "achievements",
            title = "Achievements",
            desc = "The achievement window: categories, rows, progress bars, and search.",
            reloadMsg = "Changing the Achievements reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinAchievements = val end,
        },
        {
            key = "mail",
            title = "Mail",
            desc = "The mailbox: inbox rows, send mail, open mail, and attachment slots.",
            reloadMsg = "Changing the Mail reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinMail = val end,
            buildContent = not CUI.IS_FOREVER and BuildMailAltList or nil,
            searchText = not CUI.IS_FOREVER and { "Show Alt List", "Shown Characters" } or nil,
        },
        {
            key = "catalyst",
            title = "Catalyst",
            desc = "The item conversion window (catalyst and similar kiosks).",
            reloadMsg = "Changing the Catalyst reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinCatalyst = val end,
        },
        {
            key = "socket",
            title = "Gem Socketing",
            desc = "The gem socketing window with squared gem slots.",
            reloadMsg = "Changing the Gem Socketing reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinSocket = val end,
        },
        {
            key = "itemupgrade",
            title = "Item Upgrades",
            desc = "The item upgrade window: upgrade slot, track selector, cost, and the currency strip.",
            reloadMsg = "Changing the Item Upgrades reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinItemUpgrade = val end,
        },
        {
            key = "loot",
            title = "Loot Window",
            desc = "The loot window: item rows with squared icons, kept item quality colors.",
            reloadMsg = "Changing the Loot Window reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLoot = val end,
            buildContent = BuildLootContent,
        },
        {
            key = "loottoast",
            title = "Loot Toasts",
            desc = 'The "You received" popups for loot, currency, and upgrades.',
            reloadMsg = "Changing the Loot Toasts reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLootToast = val end,
            buildContent = BuildLootToastContent,
        },
        {
            key = "bnettoast",
            title = "Friend Notifications",
            desc = "The Battle.net popup when a friend comes online or goes offline, plus broadcasts and invites.",
            reloadMsg = "Changing the Friend Notifications reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinBNetToast = val end,
        },
        {
            key = "lootroll",
            title = "Loot Roll Popups",
            desc = "The need / greed / pass roll popups, with a squared icon and a flat roll timer.",
            reloadMsg = "Changing the Loot Roll Popups reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLootRoll = val end,
        },
        {
            key = "loothistory",
            title = "Loot Rolls Window",
            desc = "The pending-rolls window: encounter picker, roll timer, and the result rows.",
            reloadMsg = "Changing the Loot Rolls Window reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinLootHistory = val end,
        },
        {
            key = "groupinvite",
            title = "Group Invite Popup",
            desc = 'The "you have been invited to a group" dialogs, with your role and Accept / Decline.',
            reloadMsg = "Changing the Group Invite Popup reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinGroupInvite = val end,
        },
        {
            key = "readycheck",
            title = "Ready Check",
            desc = "The ready check prompt with its Yes / No buttons.",
            reloadMsg = "Changing the Ready Check reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinReadyCheck = val end,
        },
        {
            key = "housing",
            title = "Housing Dashboard",
            desc = "The housing dashboard window background, border, and title bar.",
            reloadMsg = "Changing the Housing Dashboard reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinHousing = val end,
        },
        {
            key = "micromenu",
            title = "Micro Menu",
            desc = "Flattens the micro menu buttons into the CludesUI style.",
            reloadMsg = "Changing the Micro Menu reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinMicroMenu = val end,
        },
        {
            key = "bagbar",
            title = "Bag Bar",
            desc = "Flattens the bag bar slot buttons into the CludesUI style.",
            reloadMsg = "Changing the Bag Bar reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinBagBar = val end,
        },
        {
            key = "dressup",
            title = "Dressing Room",
            desc = "The item preview / transmog dressing room window.",
            reloadMsg = "Changing the Dressing Room reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinDressUp = val end,
        },
        {
            key = "transmog",
            title = "Transmogrifier",
            desc = "The transmogrification window at the transmogrifier.",
            reloadMsg = "Changing the Transmogrifier reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinTransmog = val end,
        },
        {
            key = "merchant",
            title = "Merchant",
            desc = "The vendor window: item list, buyback, and bottom money bar.",
            reloadMsg = "Changing the Merchant reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinMerchant = val end,
            buildContent = BuildMerchantContent,
        },
        {
            key = "auctionhouse",
            title = "Auction House",
            desc = "The auction house: browse, sell, and my auctions views.",
            reloadMsg = "Changing the Auction House reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinAuctionHouse = val end,
        },
        {
            key = "macros",
            title = "Macros",
            desc = "The macro editor: tabs, icon grid, text well, and buttons.",
            reloadMsg = "Changing the Macros reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinMacros = val end,
        },
        {
            key = "settings",
            title = "Options Panel",
            desc = "Blizzard's options window chrome: frame, tabs, search, and category rail.",
            reloadMsg = "Changing the Options Panel reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinSettings = val end,
        },
        {
            key = "addonlist",
            title = "AddOn List",
            desc = "The addon manager: list rows, checkboxes, and buttons.",
            reloadMsg = "Changing the AddOn List reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinAddonList = val end,
        },
        {
            key = "craftorders",
            title = "Crafting Orders",
            desc = "The customer crafting orders window: browse, order form, and my orders.",
            reloadMsg = "Changing the Crafting Orders reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinCraftOrders = val end,
        },
        {
            key = "trainer",
            title = "Trainer",
            desc = "The class and profession trainer window: skill list, train button, and cost display.",
            reloadMsg = "Changing the Trainer reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinTrainer = val end,
        },
        {
            key = "gossip",
            title = "Gossip",
            desc = "The NPC dialog window: greeting text, gossip and quest options, and goodbye button.",
            reloadMsg = "Changing the Gossip reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinGossip = val end,
        },
        {
            key = "quest",
            title = "Quest",
            desc = "The NPC quest window: quest detail, progress, and reward panels plus the multi-quest greeting list.",
            reloadMsg = "Changing the Quest reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinQuest = val end,
        },
        {
            key = "inspectrecipe",
            title = "Inspect Recipe",
            desc = "The recipe preview window shown from a linked recipe or an inspected crafter.",
            reloadMsg = "Changing the Inspect Recipe reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinInspectRecipe = val end,
        },
        {
            key = "delves",
            title = "Delves Companion",
            desc = "Brann's configuration window: role and trinket slots, abilities, and the ability list.",
            reloadMsg = "Changing the Delves Companion reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinDelves = val end,
        },
        {
            key = "socialui",
            title = "Friends List",
            -- Retail: the Friends List module repaints its window to this card
            -- live. WoW Forever: the card drives that client's friends packs
            -- and hosts the friend tiles and auto-accept the module gives retail.
            desc = CUI.IS_FOREVER
                    and "The Social window frame, border, title bar, Battle.net bar, search boxes, filter dropdowns and buttons, and the friend tiles with class icons, class-colored names and region icons. The side tab icons stay untouched."
                or "The friends window backdrop, frame border, tabs, search boxes, bottom buttons and close button. Friend entries stay untouched; Blizz Default keeps the Friends List module's own flat look.",
            reloadMsg = CUI.IS_FOREVER
                    and "Changing the Friends List reskin requires a UI reload to fully swap between Blizzard and Cludes styles."
                or nil,
            setEnabled = function(val) Account().reskinSocialUI = val end,
            buildContent = CUI.IS_FOREVER and BuildFriendsCardContent or nil,
            searchText = CUI.IS_FOREVER
                    and { "Custom Friends List Tiles", "Tile Height", "Tile Features" }
                or nil,
        },
        {
            key = "queuestatus",
            title = "Queue Status",
            desc = "The panel the minimap Group Finder eye shows on hover: queue titles, role icons and counts, and time in queue.",
            reloadMsg = "Changing the Queue Status reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinQueueStatus = val end,
        },
        {
            key = "delvepicker",
            title = "Delve Tier Picker",
            desc = "The delve difficulty window: tier dropdown, reward list and Enter button. The Map Properties row is left stock -- it is a Blizzard widget display and is not safe to restyle.",
            reloadMsg = "Changing the Delve Tier Picker reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinDelvePicker = val end,
        },
        {
            key = "playerchoice",
            title = "Choice Windows",
            desc = 'Weekly and event choice windows such as Abundance harvests and "how will you aid..." pickers: option plates, headers, reward icons and buttons. Option artwork stays.',
            reloadMsg = "Changing the Choice Windows reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinPlayerChoice = val end,
        },
        {
            key = "trade",
            title = "Trade",
            desc = "The player-to-player trade window: frame, both item columns, the enchant slots, money rows and buttons. Item icons are squared and carry a rarity border. Both portraits are removed, as on every other window.",
            reloadMsg = "Changing the Trade reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinTrade = val end,
        },
        {
            key = "flagcarrier",
            title = "Flag Carriers",
            desc = "The battleground flag and orb carrier frames, dressed like CludesUI unit frames: health in the carrier's class color and power in its power color inside a thin black border, a square spec icon, a bordered trinket and cast bar, and the carrier's pet. The faction icon and the cast bar's fill stay as Blizzard draws them. To move them, turn on Move Flag Carriers in Edit Layout on the Quality of Life Window Mover page.",
            reloadMsg = "Changing the Flag Carriers reskin requires a UI reload to fully swap between Blizzard and Cludes styles.",
            setEnabled = function(val) Account().reskinFlagCarriers = val end,
        },
    }

    -- WoW Forever drops the cards for windows it does not skin or has no use
    -- for: the Delve Tier Picker and Housing Dashboard never load on that
    -- client, and the Great Vault has no content there. Retail drops the Bag
    -- Bar card (a Forever-only skin). Saved enable keys stay untouched.
    if CUI.IS_FOREVER then
        local foreverDropped = {
            greatvault = true,
            delvepicker = true,
            housing = true,
        }
        for idx = #WINDOWS, 1, -1 do
            if foreverDropped[WINDOWS[idx].key] then table.remove(WINDOWS, idx) end
        end
    else
        -- The Bag Bar and Progress Legacy skins exist only on Forever; drop
        -- their cards on retail.
        for idx = #WINDOWS, 1, -1 do
            local settingKey = WINDOWS[idx].key
            if settingKey == "bagbar" or settingKey == "legacysystem" then table.remove(WINDOWS, idx) end
        end
    end

    local function WSGetStyle(window) return CUI.GetBlizzWindowStyle(window.key) end

    -- Window skins a module's Style page choice overrides: while that module
    -- renders a stock style its pack stands down, so the card's style
    -- dropdown is blocked and Apply to All leaves the card alone.
    local WS_STYLE_OWNERS = { socialui = "friends" }
    local function WSStyleOwned(window)
        local ownerFrame = WS_STYLE_OWNERS[window.key]
        return ownerFrame and CUI.BlizzStyle and CUI.BlizzStyle.Get(ownerFrame) or false
    end

    -- Applies a style to one window. Returns true when the change crosses the
    -- on/off boundary, or the character sheet's Blizz Default one (= needs a
    -- reload). suppressPopup lets Apply to All show one popup for the whole
    -- batch instead of one per window.
    local function WSSetStyle(window, style, suppressPopup)
        local old = WSGetStyle(window)
        if old == style then return false end
        if not CludesUIDB then CludesUIDB = {} end
        -- A pick here belongs to the whole UI's current look: the Style
        -- page's Apply to All saves it into that look's window slot when
        -- the look changes (CludesUI.SwapWindowSkinStyle).
        window.setEnabled(style ~= "off")
        if style ~= "off" then
            -- Remember which skin set this window uses; kept while "off" so
            -- re-enabling restores the same pick.
            if not CludesUIDB.blizzWindowSkinStyles then CludesUIDB.blizzWindowSkinStyles = {} end
            CludesUIDB.blizzWindowSkinStyles[window.key] = style
        end
        -- A card with no reloadMsg swaps live both ways (retail Friends List).
        local oldClass = (old == "off" and 0) or (old == "blizzard" and 1) or 2
        local newClass = (style == "off" and 0) or (style == "blizzard" and 1) or 2
        local crossed = window.reloadMsg ~= nil and oldClass ~= newClass
        -- cui<->modern applies live (shell backdrops swap in place).
        if CUI._WSkinRefreshStyles then CUI._WSkinRefreshStyles() end
        if crossed and not suppressPopup then AskSkinReload(window.reloadMsg) end
        return crossed
    end

    -- A card's style as a dropdown row on another page (Action Bars' Menu,
    -- Bags & Rep Bars mirrors the Micro Menu and Bag Bar cards): the card's
    -- own list, read and write, reload popup included, greyed while window
    -- skins are off for the profile. nil for a card this client does not
    -- offer (the Bag Bar off WoW Forever).
    function CUI.WindowSkinStyleCfg(winKey, textValue, tooltip)
        local window
        for idx = 1, #WINDOWS do
            if WINDOWS[idx].key == winKey then
                window = WINDOWS[idx]
                break
            end
        end
        if not window then return nil end
        return {
            type = "dropdown",
            text = textValue,
            tooltip = tooltip,
            values = window.styleValues or WS_STYLE_VALUES,
            order = window.styleOrder or WS_STYLE_ORDER,
            disabled = CUI.BlizzWindowSkinsKilled,
            disabledTooltip = "Window Skins",
            getValue = function() return WSGetStyle(window) end,
            setValue = function(val)
                WSSetStyle(window, val)
                CUI:RefreshPage()
            end,
        }
    end

    -- One expandable card: custom header (mini-window glyph + title + style
    -- dropdown + chevron) over a shared card background, with the window's
    -- rows below when expanded. Returns the new y cursor.
    local function BuildWindowCard(hostFrame, cursorY, window)
        local Pix = CUI.PanelPP
        local ACC = CUI.CLUDES_GREEN
        local Loc = CUI.L
        local hasSettings = window.buildContent ~= nil
        local expanded = hasSettings and _wsExpanded[window.key]
        local cardTop = cursorY
        local brd -- whole-card border, created with the bg below (hover closure)

        -- Explicit size + single TOPLEFT anchor (the widget contract): inline
        -- search re-anchors and restores direct children through their FIRST
        -- point only, so a frame that gets its width from a second point
        -- collapses to zero width the first time a search is cleared.
        local cardW = hostFrame:GetWidth() - (CUI.CONTENT_PAD - WS_CARD_INSET) * 2
        local heading = CreateFrame("Button", nil, hostFrame)
        Pix.Size(heading, cardW, WS_HEADER_H)
        Pix.Point(heading, "TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD - WS_CARD_INSET, cursorY)
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
                extraLoc = extraLoc .. " " .. Loc(labelText)
            end
        end
        local searchName = window.title .. " " .. (window.desc or "") .. extra
        heading._isSectionHeader = true
        heading._sectionName = searchName
        local searchNameLoc = Loc(window.title) .. " " .. Loc(window.desc or "") .. extraLoc
        if searchNameLoc ~= searchName then heading._sectionNameLoc = searchNameLoc end

        -- Global (sidebar) search: the card header never goes through
        -- SectionHeader, so the index would otherwise have no entry for it --
        -- searching a window's title/description found it inline but not in
        -- the sidebar results. Register it with the same title + description
        -- keywords the inline pseudo-section matches (title as the display
        -- label, description via the tooltip field, which the fuzzy scorer
        -- also searches). section = the exact joined string stamped above, so
        -- a jump scrolls to and glows this header; the page's
        -- NavigateToElementSettings pre-hook expands the cards first.
        if CUI._RegisterSearchEntry then
            local titleLoc = Loc(window.title)
            local descSearch = window.desc or ""
            local descLoc = Loc(window.desc or "")
            if descLoc ~= descSearch then descSearch = descSearch .. " " .. descLoc end
            descSearch = descSearch .. extra
            if extraLoc ~= extra then descSearch = descSearch .. extraLoc end
            CUI._RegisterSearchEntry(
                window.title,
                titleLoc ~= window.title and titleLoc or nil,
                descSearch,
                CUI._buildingModule,
                CUI._buildingPage,
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
        local glyphBrd = CUI.MakeBorder(icon, 1, 1, 1, 0.35, Pix)
        local glyphBar = icon:CreateTexture(nil, "ARTWORK")
        glyphBar:SetHeight(4)
        Pix.Point(glyphBar, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        Pix.Point(glyphBar, "TOPRIGHT", icon, "TOPRIGHT", -1, -1)
        if glyphBar.SetSnapToPixelGrid then
            glyphBar:SetSnapToPixelGrid(false)
            glyphBar:SetTexelSnappingBias(0)
        end

        local title = CUI.MakeFont(heading, 14, nil, 1, 1, 1, 0.9)
        Pix.Point(title, "TOPLEFT", heading, "TOPLEFT", 50, -12)
        title:SetText(Loc(window.title))

        local description = CUI.MakeFont(heading, 11, nil, 1, 1, 1, 0.42)
        Pix.Point(description, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        description:SetWidth(590)
        description:SetJustifyH("LEFT")
        description:SetWordWrap(false)
        description:SetText(Loc(window.desc))

        -- Expand chevron only on cards that actually have settings; cards
        -- without any are not expandable at all.
        local chev
        if hasSettings then
            chev = heading:CreateTexture(nil, "OVERLAY")
            Pix.Size(chev, 16, 16)
            Pix.Point(chev, "RIGHT", heading, "RIGHT", -16, 0)
            chev:SetTexture(expanded and WS_ARROW_UP or WS_ARROW_DOWN)
            chev:SetAlpha(0.45)
            if expanded then chev:SetVertexColor(ACC.r, ACC.g, ACC.b) end
        end

        -- Style dropdown: pick CludesUI / Modern / Blizz Default for this
        -- window without expanding the card (the card's own list, when it
        -- has one).
        local dropdown = CUI.BuildDropdownControl(
            heading,
            148,
            heading:GetFrameLevel() + 2,
            window.styleValues or WS_STYLE_VALUES,
            window.styleOrder or WS_STYLE_ORDER,
            function() return WSGetStyle(window) end,
            function(val)
                WSSetStyle(window, val)
                CUI:RefreshPage()
            end
        )
        Pix.Point(dropdown, "RIGHT", heading, "RIGHT", -44, 0)
        local ownerFrame = WS_STYLE_OWNERS[window.key]
        if ownerFrame and CUI.BlizzStyle then CUI.BlizzStyle.BlockInline(ownerFrame, dropdown) end

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
            if dropdown._refreshLabel then dropdown._refreshLabel() end
        end

        local function ApplyHeaderHover()
            hbg:SetColorTexture(1, 1, 1, 0.05)
            title:SetAlpha(1)
            chev:SetAlpha(0.85)
            if brd then brd:SetColor(1, 1, 1, 0.22) end
        end
        local function ClearHeaderHover()
            -- Moving between the header and its dropdown fires OnLeave first;
            -- keep the row highlight while the pointer is still inside the header.
            if heading:IsMouseOver() then return end
            hbg:SetColorTexture(0, 0, 0, 0)
            title:SetAlpha(0.9)
            chev:SetAlpha(0.45)
            if brd then brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12) end
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
                CUI:RefreshPage(true)
            end)
        end

        cursorY = cursorY - WS_HEADER_H

        if expanded then
            -- Divider between the header and the card's settings
            local div = heading:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.07)
            div:SetHeight(1)
            Pix.Point(div, "BOTTOMLEFT", heading, "BOTTOMLEFT", 1, 0)
            Pix.Point(div, "BOTTOMRIGHT", heading, "BOTTOMRIGHT", -1, 0)
            Pix.DisablePixelSnap(div)

            cursorY = cursorY - 8
            cursorY = window.buildContent(hostFrame, cursorY)
            cursorY = cursorY - 8
        end

        -- Card background + border spanning the header and any expanded content. Child
        -- of the header, NOT the page wrapper: the inline search walks direct wrapper
        -- children, and as a header child the bg is never collected as a row, follows
        -- the header wherever the search re-flows it, and hides/shows with it for free.
        -- Explicitly sized because the header's own rect is the only anchor left.
        local backdrop = CreateFrame("Frame", nil, heading)
        backdrop:SetFrameLevel(hostFrame:GetFrameLevel())
        Pix.Size(backdrop, cardW, cardTop - cursorY)
        Pix.Point(backdrop, "TOPLEFT", heading, "TOPLEFT", 0, 0)
        brd = CUI.MakeRoundedCard(backdrop, expanded and 0.16 or 0.12)
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

        CUI.RegisterWidgetRefresh(RefreshCardState)
        RefreshCardState()

        return cursorY - WS_CARD_GAP
    end

    -- Per-profile master kill switch (the ONLY per-profile setting in this
    -- section): profile-root key disableWindowSkins, resolved live by
    -- CludesUI.BlizzWindowSkinsKilled(). Skins install at load, so every
    -- toggle shows the reload popup.
    local function WSKillSwitchSet(disabled)
        local prof = CUI.GetActiveProfileData()
        if not prof then return end
        prof.disableWindowSkins = disabled and true or nil
        -- Structural change (settings <-> hero takeover): force a rebuild,
        -- a plain refresh only re-reads widget values on the cached page.
        CUI:RefreshPage(true)
        AskSkinReload(
            disabled
                    and "Window skins are now disabled for this profile. A UI reload is required to restore the stock Blizzard windows."
                or "Window skins are now enabled for this profile. A UI reload is required to apply them."
        )
    end

    -- Feature hero shown INSTEAD of the page content while window skins are
    -- disabled for this profile: the intro popup's art (three mini windows,
    -- eyebrow, bullets) rebuilt inline, with one big Enable button.
    local function BuildWindowSkinsDisabledHero(hostFrame, yOffset)
        local Pix = CUI.PanelPP
        local ACC = CUI.CLUDES_GREEN
        local Loc = CUI.L
        local MakeBorder = CUI.MakeBorder
        local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

        local HERO_H = 470
        local owner = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(owner, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, HERO_H)
        Pix.Point(owner, "TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, yOffset - 24)

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
            local cardFrame = CreateFrame("Frame", nil, owner)
            cardFrame:SetFrameLevel(owner:GetFrameLevel() + 1)
            Pix.Size(cardFrame, wid, ch)
            Pix.Point(cardFrame, "CENTER", owner, "TOP", (idx - 2) * (CARD_W + CARD_GAP), -64)
            local cbg = cardFrame:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.121, 0.113, 0.106, 1)
            local color = titleColors[idx]
            local bar = cardFrame:CreateTexture(nil, "ARTWORK")
            bar:SetColorTexture(color[1], color[2], color[3], isCenter and 0.95 or 0.75)
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

        local eyebrow = owner:CreateFontString(nil, "OVERLAY")
        eyebrow:SetFont(FONT, 13, "")
        eyebrow:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        Pix.Point(eyebrow, "TOP", owner, "TOP", 0, -122)
        eyebrow:SetText(Loc("CLUDESUI FEATURE"))

        local title = owner:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 25, "")
        title:SetTextColor(1, 1, 1, 1)
        Pix.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
        title:SetText(Loc("Blizzard Window Skinning"))

        local description = owner:CreateFontString(nil, "OVERLAY")
        description:SetFont(FONT, 15, "")
        description:SetTextColor(1, 1, 1, 0.5)
        description:SetWidth(430)
        description:SetJustifyH("CENTER")
        description:SetWordWrap(true)
        Pix.Point(description, "TOP", title, "BOTTOM", 0, -12)
        description:SetText(
            Loc(
                "Blizzard's windows match the CludesUI theme with a WoW 2.0 Dark Theme, from the Dungeon Journal to the Auction House and beyond."
            )
        )

        local BULLETS = {
            "Every major Blizzard window themed to match CludesUI",
            "Recolor the theme to any color and opacity you like",
            "Scale any window larger or smaller with Shifter",
        }
        local prev
        for idx, textValue in ipairs(BULLETS) do
            local bl = owner:CreateFontString(nil, "OVERLAY")
            bl:SetFont(FONT, 14, "")
            bl:SetTextColor(1, 1, 1, 0.72)
            bl:SetJustifyH("LEFT")
            if idx == 1 then
                Pix.Point(bl, "TOP", owner, "TOP", -20, -252)
                bl:SetPoint("LEFT", owner, "CENTER", -160, 0)
            else
                Pix.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
            end
            bl:SetText(Loc(textValue))
            local bdot = owner:CreateTexture(nil, "OVERLAY")
            bdot:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
            Pix.Size(bdot, 5, 5)
            Pix.Point(bdot, "RIGHT", bl, "LEFT", -10, 0)
            prev = bl
        end

        local enableBtn = CreateFrame("Button", nil, owner)
        Pix.Size(enableBtn, 220, 40)
        Pix.Point(enableBtn, "TOP", owner, "TOP", 0, -344)
        enableBtn:SetFrameLevel(owner:GetFrameLevel() + 2)
        CUI.MakeStyledButton(
            enableBtn,
            "Enable Window Skins",
            15,
            CUI.WB_COLOURS,
            function() WSKillSwitchSet(false) end
        )

        local footnote = owner:CreateFontString(nil, "OVERLAY")
        footnote:SetFont(FONT, 12, "")
        footnote:SetTextColor(1, 1, 1, 0.35)
        Pix.Point(footnote, "TOP", enableBtn, "BOTTOM", 0, -12)
        footnote:SetText(Loc("Window skins are currently disabled for this profile."))

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
    local function BuildThirdPartySection(hostFrame, cursorY)
        local Widg = CUI.Widgets
        local entries = mod.GetThirdPartySkinList and mod.GetThirdPartySkinList()
        if not entries or #entries == 0 then return cursorY end

        local _, height
        _, height = Widg:Spacer(hostFrame, cursorY, 10)
        cursorY = cursorY - height
        _, height = Widg:SectionHeader(hostFrame, "THIRD-PARTY ADDONS", cursorY)
        cursorY = cursorY - height

        local function MasterOff() return (CludesUIDB and CludesUIDB.thirdPartySkinsOff) and true or false end
        local function TurnedOn()
            -- Live-apply any skins that can install right now; only removal
            -- needs the reload.
            local fired = mod.TryDispatchThirdPartySkins and mod.TryDispatchThirdPartySkins()
            CUI:RefreshPage()
            if not fired then
                AskSkinReload("Some addon skins could not apply live. A UI reload will fully apply them.")
            end
        end

        local itemList = {}
        itemList[1] = {
            type = "toggle",
            text = "Skin Third-Party Addons",
            tooltip = "Master switch for skinning other addons that support the CludesUI skinning API.",
            getValue = function() return not MasterOff() end,
            setValue = function(val)
                Account().thirdPartySkinsOff = (not val) and true or nil
                if val then
                    TurnedOn()
                else
                    CUI:RefreshPage()
                    AskSkinReload("Removing third-party addon skins requires a UI reload.")
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
                    local tbl = CludesUIDB and CludesUIDB.thirdPartySkinAddons
                    return not (tbl and tbl[name] == false)
                end,
                setValue = function(val)
                    if not CludesUIDB then CludesUIDB = {} end
                    local tbl = CludesUIDB.thirdPartySkinAddons
                    if not tbl then
                        tbl = {}
                        CludesUIDB.thirdPartySkinAddons = tbl
                    end
                    if val then
                        tbl[name] = nil
                    else
                        tbl[name] = false
                    end
                    if val then
                        TurnedOn()
                    else
                        AskSkinReload("Removing " .. name .. "'s skin requires a UI reload.")
                    end
                end,
            }
        end
        local h2
        for idx = 1, #itemList, 2 do
            _, h2 = Widg:DualRow(
                hostFrame,
                cursorY,
                itemList[idx],
                itemList[idx + 1] or { type = "label", text = "" }
            )
            cursorY = cursorY - h2
        end
        return cursorY
    end

    local function BuildWindowSkinsPage(pageTitle, hostFrame, yOffset)
        local Widg = CUI.Widgets
        local Pix = CUI.PanelPP
        local Loc = CUI.L
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true

        -- Per-profile kill switch takeover: while window skins are disabled
        -- for this profile, hide every setting and show the feature hero.
        -- Third-party skinning is decoupled from the kill switch, so its
        -- section stays reachable below the hero.
        if CUI.BlizzWindowSkinsKilled and CUI.BlizzWindowSkinsKilled() then
            local heroH = BuildWindowSkinsDisabledHero(hostFrame, yOffset)
            local y2 = BuildThirdPartySection(hostFrame, -heroH)
            return math.abs(y2)
        end

        _, height = Widg:Spacer(hostFrame, cursorY, 14)
        cursorY = cursorY - height

        -- Hosted on a sized frame (not a raw region on the wrapper) so the
        -- inline search hides it while filtering and restores it on clear;
        -- regions are invisible to the search and would float over results.
        local introHost = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(introHost, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, 20)
        Pix.Point(introHost, "TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY)
        local intro = CUI.MakeFont(introHost, 13, nil, 1, 1, 1, 0.5)
        Pix.Point(intro, "TOP", introHost, "TOP", 0, 0)
        intro:SetText(Loc("Pick a style for all reskinned Blizzard windows."))

        -- Per-profile master switch (top right; the only per-profile setting
        -- in this section). One step below Blizz Default: no-ops the whole
        -- window engine + CharacterSheet/Inspect + LFG skinning. Reload-bound.
        local disBtn = CreateFrame("Button", nil, introHost)
        Pix.Size(disBtn, 160, 24)
        Pix.Point(disBtn, "RIGHT", introHost, "RIGHT", 0, 0)
        disBtn:SetFrameLevel(introHost:GetFrameLevel() + 3)
        CUI.MakeStyledButton(
            disBtn,
            "Disable Window Skins",
            11,
            CUI.WB_COLOURS,
            function() WSKillSwitchSet(true) end
        )
        disBtn:HookScript(
            "OnEnter",
            function(s)
                CUI.ShowWidgetTooltip(
                    s,
                    Loc("Turns off ALL window skinning for this profile. Requires a reload.")
                )
            end
        )
        disBtn:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)

        cursorY = cursorY - 28

        -- Set-all row: pick a style, then push it to every window below. The
        -- swatch + cog edit the GLOBAL Modern background (windows without a
        -- per-window override follow it).
        local allDD = CUI.BuildDropdownControl(
            hostFrame,
            170,
            hostFrame:GetFrameLevel() + 3,
            WS_STYLE_VALUES,
            WS_STYLE_ORDER,
            function() return _wsApplyAllStyle end,
            function(val)
                _wsApplyAllStyle = val
                CUI:RefreshPage()
            end
        )
        Pix.Point(allDD, "TOPLEFT", hostFrame, "TOP", -115, cursorY)
        allDD._ttText = "Style to apply to every window below."
        AttachModernSwatch(hostFrame, allDD, function() return _wsApplyAllStyle ~= "modern" end)

        local applyBtn = CreateFrame("Button", nil, hostFrame)
        Pix.Size(applyBtn, 110, 30)
        Pix.Point(applyBtn, "LEFT", allDD, "RIGHT", 10, 0)
        applyBtn:SetFrameLevel(hostFrame:GetFrameLevel() + 3)
        CUI.MakeStyledButton(applyBtn, "Apply to All", 12, CUI.WB_COLOURS, function()
            local crossed = false
            for _, window in ipairs(WINDOWS) do
                local style = (_wsApplyAllStyle == "off" and window.blizzDefault) or _wsApplyAllStyle
                if not WSStyleOwned(window) and WSSetStyle(window, style, true) then crossed = true end
            end
            CUI:RefreshPage()
            if crossed then
                AskSkinReload("Changing window skin styles requires a UI reload to fully apply.")
            end
        end)
        cursorY = cursorY - 30 - 26

        -- GLOBAL OPTIONS: look settings shared by every reskinned window.
        _, height = Widg:SectionHeader(hostFrame, "GLOBAL OPTIONS", cursorY)
        cursorY = cursorY - height

        local gRow1
        gRow1, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Accent Bar",
            tooltip = "Accent bar on the active tab of reskinned windows.",
            getValue = function()
                local c = SkinSetting("blizzWinAccentBar")
                return not (c and c.enabled == false)
            end,
            setValue = function(val) WSLookSet("blizzWinAccentBar", "enabled", val and true or false) end,
        }, {
            type = "slider",
            text = "Bar Fill Opacity",
            min = 10,
            max = 100,
            step = 1,
            getValue = function()
                local c = SkinSetting("blizzWinBarFill")
                return math.floor(((c and c.alpha) or 0.95) * 100 + 0.5)
            end,
            setValue = function(val) WSLookSet("blizzWinBarFill", "alpha", val / 100) end,
        })
        if not CUI._prebuilding then
            AttachLookSwatches(gRow1._leftRegion, gRow1, "blizzWinAccentBar")
            AttachLookSwatches(gRow1._rightRegion, gRow1, "blizzWinBarFill")
        end
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "multiSwatch",
            text = "Link Color",
            swatches = {
                {
                    tooltip = "Accent Color",
                    getValue = function() return CUI.ResolveActiveAccent() end,
                    setValue = function() end,
                    onClick = function()
                        WSLookSet("blizzWinLinks", "useCustom", false)
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = SkinSetting("blizzWinLinks")
                        return (c and c.useCustom) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Custom Color",
                    getValue = function()
                        local c = SkinSetting("blizzWinLinks")
                        local col = c and c.color
                        if col then return col.r or 1, col.g or 1, col.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(red, green, blue)
                        WSLookSet("blizzWinLinks", "color", { r = red, g = green, b = blue })
                        WSLookSet("blizzWinLinks", "useCustom", true)
                        CUI:RefreshPage()
                    end,
                    onClick = function(self)
                        local c = SkinSetting("blizzWinLinks")
                        if not (c and c.useCustom) then
                            WSLookSet("blizzWinLinks", "useCustom", true)
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local c = SkinSetting("blizzWinLinks")
                        return (c and c.useCustom) and 1 or 0.3
                    end,
                },
            },
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        -- Breathing room between the global settings and the window cards.
        cursorY = cursorY - 30

        -- Cards with their own settings content (buildContent) sit at the top of the
        -- list, keeping their relative order; plain style-only cards follow in theirs.
        -- WINDOWS itself stays in its defined order -- the apply-all and reset loops
        -- don't care, and new entries keep being added by category there.
        local ordered = {}
        for _, window in ipairs(WINDOWS) do
            if window.buildContent then ordered[#ordered + 1] = window end
        end
        for _, window in ipairs(WINDOWS) do
            if not window.buildContent then ordered[#ordered + 1] = window end
        end
        for _, window in ipairs(ordered) do
            cursorY = BuildWindowCard(hostFrame, cursorY, window)
        end

        cursorY = BuildThirdPartySection(hostFrame, cursorY)

        _, height = Widg:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Dragon Riding page
    ---------------------------------------------------------------------------
    local function EDR_DB() return mod.edrDB and mod.edrDB.profile end
    local function DragonRidingCfg(key)
        local p = EDR_DB()
        return p and p[key]
    end
    local function EDR_Set(key, val)
        local p = EDR_DB()
        if p then p[key] = val end
    end
    local function EDR_SetField(key, field, val)
        local tbl = DragonRidingCfg(key)
        if tbl then tbl[field] = val end
    end
    local function RebuildDragonRiding()
        if mod.edrRebuild then mod.edrRebuild() end
        CUI:RefreshPage()
    end
    -- Row setters over EDR_Set: the key written with the row's value, then EDR_Rebuild() for the Then form.
    local function EDR_SetRow(settingKey)
        return function(value) EDR_Set(settingKey, value) end
    end
    local function EDR_SetRowThen(settingKey)
        return function(value)
            EDR_Set(settingKey, value)
            RebuildDragonRiding()
        end
    end
    local function EDR_Redraw()
        if mod.edrRedraw then mod.edrRedraw() end
    end

    -------------------------------------------------------------------
    --  Bar texture dropdown tables (shared media path, same as ERB)
    -------------------------------------------------------------------
    local EDR_BAR_TEXTURES = mod.EDR_BAR_TEXTURES
    local _, EDR_BAR_TEXTURE_NAMES, EDR_BAR_TEXTURE_ORDER = CUI.BuildBarTextureTables()

    -- Live sample bubble in the content header; sized to the bubble plus margin.
    local function ChatBubblesHeaderBuilder(headerText)
        local building = true
        local function HeightFor(bubbleH) return math.max(80, math.floor(bubbleH + 40)) end
        local bubble = CUI.ChatBubbles.ShowPreview(headerText, function(bubbleH)
            local wanted = HeightFor(bubbleH)
            if not building and headerText:IsVisible() and math.abs(headerText:GetHeight() - wanted) > 1 then
                CUI:SetContentHeaderHeightSilent(wanted)
            end
        end)
        building = false
        return HeightFor(bubble:GetHeight())
    end

    -- Sample Skyriding HUD in the content header, painted by the HUD's own
    -- passes (ns.EDR_ShowSample).
    local SkyridingHeaderBuilder = SampleHeaderBuilder({
        {
            show = function(headerText, place)
                if mod.EDR_ShowSample then mod.EDR_ShowSample(headerText, place) end
            end,
        },
    })

    local function BuildChatBubblesPage(pageTitle, hostFrame, yOffset)
        local Widg = CUI.Widgets
        local Pix = CUI.PP
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true
        if not CUI._prebuilding then
            CUI:SetContentHeader(ChatBubblesHeaderBuilder)
        elseif CUI.ClearContentHeader then
            CUI:ClearContentHeader()
        end

        local CBM = CUI.ChatBubbles
        -- Reads never create the profile table; writes do.
        local function BBDB() return CBM.DB(true) end
        -- Same defaults table the renderer reads, so a widget can never offer a value the
        -- bubble would not actually draw.
        local function CBVal(settingKey)
            local saved = CBM.DB(false)
            local val = saved and saved[settingKey]
            if val ~= nil then return val end
            return CBM.Defaults()[settingKey]
        end
        -- Structural write: can change whether we draw at all, or which of Blizzard's
        -- CVars we hold down, so it runs the renderer's full pass.
        local function CBSet(settingKey, val)
            local saved = BBDB()
            if not saved then return end
            saved[settingKey] = val
            CBM.Refresh()
        end
        -- Appearance write: nothing here can move a channel or one of Blizzard's CVars, so
        -- it only re-styles what is already on screen. Worth the split because a slider
        -- fires this per STEP while it is dragged, and the full pass re-diffs every event
        -- registration and round-trips Blizzard's three switches every time.
        local function CBSetStyle(settingKey, val)
            local saved = BBDB()
            if not saved then return end
            saved[settingKey] = val
            CBM.RefreshStyle()
        end
        -- A cog or row control on one style key: reads it through CBVal, writes
        -- it through CBSetStyle.
        local function CBGetter(settingKey)
            return function() return CBVal(settingKey) end
        end
        local function CBSetter(settingKey)
            return function(val) CBSetStyle(settingKey, val) end
        end
        local function CBColor(settingKey)
            local color = CBVal(settingKey)
            if not color then return 1, 1, 1, 1 end
            return color.r, color.g, color.b, color.a or 1
        end
        local function SkinsOff() return CBVal("enabled") ~= true end
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
        if not CUI._prebuilding then
            local warnFrame = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(warnFrame, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, 30)
            Pix.Point(warnFrame, "TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY)
            local warnLabel = CUI.MakeFont(warnFrame, 14, "", 1, 0.25, 0.25, 1)
            warnLabel:SetPoint("LEFT", warnFrame, "LEFT", 0, 0)
            warnLabel:SetText(CUI.L("Only works outside of Instances"))
        end
        cursorY = cursorY - 30

        _, height = Widg:SectionHeader(hostFrame, "DISPLAY", cursorY)
        cursorY = cursorY - height

        local channelsRow
        channelsRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = GATE,
            getValue = function() return CBVal("enabled") == true end,
            setValue = function(val)
                if not val then
                    CBSet("enabled", false)
                    CUI:RefreshPage()
                    return
                end
                local message =
                    "CludesUI restyles Blizzard's chat bubbles and turns on the switches it needs. Party and Raid keep your current setting, and everything is put back when you turn this off."
                CUI:ShowConfirmPopup({
                    title = GATE,
                    message = message,
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = function()
                        CBSet("enabled", true)
                        CUI:RefreshPage()
                    end,
                    onCancel = function() CUI:RefreshPage() end,
                })
            end,
        }, {
            type = "dropdown",
            text = "Channels",
            tooltip = "Choose which channels get a bubble.",
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function() return "__placeholder" end,
            setValue = function() end,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            local region = channelsRow._rightRegion
            if region._control then region._control:Hide() end
            local channelItems = {
                { key = "say", label = "Say" },
                { key = "yell", label = "Yell" },
                { key = "party", label = "Party", tooltip = "Includes instance chat." },
                { key = "raid", label = "Raid" },
                { key = "npc", label = "NPCs" },
                { key = "emote", label = "Emotes" },
            }
            local chDD, chDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                240,
                region:GetFrameLevel() + 2,
                channelItems,
                function(key) return CBVal(key) == true end,
                function(key, val) CBSet(key, val) end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = SkinsOff, disabledTooltip = GATE_REQ }
            )
            CUI.PanelPP.Point(chDD, "RIGHT", region, "RIGHT", -20, 0)
            region._control = chDD
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(chDDRefresh)
        end

        -- Structural, not appearance: it decides which of Blizzard's switches we hold and at
        -- what value, so it takes the full pass. Half-empty right slot is allowed here because
        -- this is the last row of its section.
        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide Chat Bubbles in Instances",
            getValue = function() return CBVal("hideInInstances") == true end,
            setValue = function(val) CBSet("hideInInstances", val) end,
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = Widg:SectionHeader(hostFrame, "APPEARANCE", cursorY)
        cursorY = cursorY - height

        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Padding",
            min = 2,
            max = 24,
            step = 1,
            tooltip = "Space between the text and the edge of the bubble.",
            getValue = CBGetter("padding"),
            setValue = CBSetter("padding"),
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        }, {
            type = "slider",
            text = "Maximum Width",
            min = 120,
            max = 500,
            step = 10,
            getValue = CBGetter("maxWidth"),
            setValue = CBSetter("maxWidth"),
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        })
        cursorY = cursorY - height

        local fontValues, fontOrder = CUI.BuildFontDropdownData()
        local fontBorderRow
        fontBorderRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Font",
            values = fontValues,
            order = fontOrder,
            getValue = CBGetter("font"),
            setValue = CBSetter("font"),
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        }, {
            type = "slider",
            text = "Border",
            min = 0,
            max = 4,
            step = 1,
            getValue = CBGetter("borderSize"),
            setValue = CBSetter("borderSize"),
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        })
        cursorY = cursorY - height

        if not CUI._prebuilding then
            -- Built BEFORE the swatch on purpose: the cog sits beside the control, and
            -- BuildInlineSwatches chains _lastInline, so the swatch lands to its left.
            CUI.BuildInlineCog(fontBorderRow._leftRegion, {
                disabled = SkinsOff,
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
                        get = function() return CBVal("followBlizzardColor") == true end,
                        set = function(val)
                            CBSetStyle("followBlizzardColor", val)
                            CUI:RefreshPage()
                        end,
                    },
                },
            })

            -- BuildInlineSwatches, not a hand-rolled BuildColorSwatch: it is the house form for
            -- a swatch riding on a control half. It anchors through PP.Point, registers the
            -- swatch's refresh so a profile switch repaints it, and builds the greyed-out block
            -- plus tooltip from opts.disabled.
            CUI.BuildInlineSwatches(fontBorderRow._leftRegion, {
                {
                    getValue = function()
                        local red, green, b = CBColor("textColor")
                        return red, green, b, 1
                    end,
                    setValue = function(red, green, blue)
                        CBSetStyle("textColor", { r = red, g = green, b = blue })
                    end,
                    -- Two reasons this swatch can be dead, so the tip is resolved per reason.
                    disabled = function() return SkinsOff() or CBVal("followBlizzardColor") == true end,
                    disabledTooltip = function()
                        return SkinsOff() and GATE_REQ or "Follow Blizzard Default Color"
                    end,
                    requireState = function() return SkinsOff() and "enabled" or "disabled" end,
                },
            }, { disabled = SkinsOff, disabledTooltip = GATE_REQ })

            CUI.BuildInlineSwatches(fontBorderRow._rightRegion, {
                {
                    getValue = function() return CBColor("borderColor") end,
                    setValue = function(red, green, blue, a)
                        CBSetStyle("borderColor", { r = red, g = green, b = blue, a = a })
                    end,
                    hasAlpha = true,
                },
            }, { disabled = SkinsOff, disabledTooltip = GATE_REQ })
        end

        local nameRow
        nameRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Show Speaker Name",
            tooltip = "Choose which channels show the speaker.",
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function() return "__placeholder" end,
            setValue = function() end,
        }, {
            type = "slider",
            text = "Vertical Offset",
            min = -80,
            max = 80,
            step = 2,
            getValue = CBGetter("offsetY"),
            setValue = CBSetter("offsetY"),
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        })
        cursorY = cursorY - height

        -- Same build as the Channels dropdown above.
        if not CUI._prebuilding then
            local region = nameRow._leftRegion
            if region._control then region._control:Hide() end
            local nameItems = {
                { key = "say", label = "Say" },
                { key = "yell", label = "Yell" },
                { key = "party", label = "Party" },
                { key = "raid", label = "Raid" },
                { key = "npc", label = "NPCs" },
                { key = "emote", label = "Emotes" },
            }
            local nmDD, nmDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                240,
                region:GetFrameLevel() + 2,
                nameItems,
                function(key)
                    local tbl = CBVal("showName")
                    return type(tbl) == "table" and tbl[key] == true
                end,
                function(key, val)
                    local saved = BBDB()
                    if not saved then return end
                    if type(saved.showName) ~= "table" then saved.showName = {} end
                    saved.showName[key] = val or nil
                    CBM.RefreshStyle()
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = SkinsOff, disabledTooltip = GATE_REQ }
            )
            CUI.PanelPP.Point(nmDD, "RIGHT", region, "RIGHT", -20, 0)
            region._control = nmDD
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(nmDDRefresh)

            CUI.BuildInlineCog(region, {
                disabled = SkinsOff,
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
        bgRow, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Background",
            getValue = function() return CBVal("background") ~= false end,
            setValue = function(val)
                CBSetStyle("background", val)
                CUI:RefreshPage()
            end,
            disabled = SkinsOff,
            disabledTooltip = GATE_REQ,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        -- Colour and opacity are one swatch but two stored keys, so the write goes straight
        -- to the DB rather than through CBSetStyle.
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(bgRow._leftRegion, {
                {
                    getValue = function()
                        local red, green, b = CBColor("bgColor")
                        return red, green, b, CBVal("bgAlpha")
                    end,
                    setValue = function(red, green, blue, a)
                        local saved = BBDB()
                        if not saved then return end
                        saved.bgColor = { r = red, g = green, b = blue }
                        saved.bgAlpha = a
                        CBM.RefreshStyle()
                    end,
                    hasAlpha = true,
                    disabled = function() return SkinsOff() or CBVal("background") == false end,
                    disabledTooltip = function() return SkinsOff() and GATE_REQ or "Background" end,
                },
            })
        end

        return math.abs(cursorY)
    end

    local function BuildDragonRidingPage(pageTitle, hostFrame, yOffset)
        local Widg = CUI.Widgets
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true

        -- Append SharedMedia textures (safe to call multiple times)
        CUI.AppendSharedMediaTextures(
            EDR_BAR_TEXTURE_NAMES,
            EDR_BAR_TEXTURE_ORDER,
            nil,
            EDR_BAR_TEXTURES
        )
        local edrTexValues = {}
        local edrTexOrder = {}
        for _, settingKey in ipairs(EDR_BAR_TEXTURE_ORDER) do
            if settingKey ~= "---" then
                edrTexValues[settingKey] = EDR_BAR_TEXTURE_NAMES[settingKey] or settingKey
                edrTexOrder[#edrTexOrder + 1] = settingKey
            end
        end
        edrTexValues._menuOpts = {
            itemHeight = 28,
            background = function(settingKey) return EDR_BAR_TEXTURES[settingKey] end,
        }

        local justifyValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local justifyOrder = { "LEFT", "CENTER", "RIGHT" }

        -- The bar art is chosen on Global Settings > Style ("Skyriding HUD")
        -- and latched for the session like every other module's style, so
        -- the rows below are laid out for the look the HUD renders.
        local BS = CUI.BlizzStyle
        local edrStyle = BS.Active("dragonriding")

        -- The sample HUD heads the page while the bar is on; off, the page
        -- hides everything below its first row and shows no header either.
        if not CUI._prebuilding and DragonRidingCfg("enabled") == true then
            CUI:SetContentHeader(SkyridingHeaderBuilder)
        elseif CUI.ClearContentHeader then
            CUI:ClearContentHeader()
        end

        -- The Move in Unlock Mode button on the bar's first section, built
        -- whatever Enable Skyriding Bar says: its disabled state explains itself.
        local heading
        heading, height = Widg:SectionHeader(hostFrame, "GENERAL", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "EDR_Cluster",
            disabled = function() return DragonRidingCfg("enabled") ~= true end,
            disabledTooltip = "Skyriding Bar",
        })
        cursorY = BS.Note(hostFrame, cursorY, "dragonriding")
        _, height = Widg:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Skyriding Bar",
            getValue = function() return DragonRidingCfg("enabled") == true end,
            -- DependentSetValue: everything below Row 1 is hidden while the
            -- bar is off; the flip forces the full rebuild.
            setValue = CUI.DependentSetValue(
                function() return DragonRidingCfg("enabled") == true end,
                function(val)
                    EDR_Set("enabled", val)
                    RebuildDragonRiding()
                end
            ),
        }, {
            type = "toggle",
            text = "Hide in Combat",
            disabled = function() return DragonRidingCfg("enabled") ~= true end,
            disabledTooltip = "Skyriding Bar",
            getValue = function() return DragonRidingCfg("hideInCombat") == true end,
            setValue = EDR_SetRowThen("hideInCombat"),
        })
        cursorY = cursorY - height

        -- Everything below Row 1 (the rest of GENERAL plus the LAYOUT and
        -- SPEED BAR sections) is HIDDEN entirely while the bar is off.
        if DragonRidingCfg("enabled") == true then
            local function EDR_IsGems() return DragonRidingCfg("vigorStyle") == "gems" end
            local function EDR_ShowSpeed() return DragonRidingCfg("showSpeed") ~= false end
            local function EDR_ShowSW() return DragonRidingCfg("showSecondWind") ~= false end
            local function EDR_WSOff() return DragonRidingCfg("showWhirlingSurge") == false end
            -- The icon's automatic size, in the Icon Size slider's range.
            local function EDR_AutoIconSize()
                local val = math.floor(((mod.edrIconSize and mod.edrIconSize()) or 34) + 0.5)
                return math.max(16, math.min(80, val))
            end

            -- The parts the HUD shows. The speed bar's and Second Wind's own
            -- rows exist only while they are shown, so those two rebuild the page.
            _, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Speed Bar",
                getValue = EDR_ShowSpeed,
                setValue = CUI.DependentSetValue(EDR_ShowSpeed, function(val)
                    EDR_Set("showSpeed", val)
                    RebuildDragonRiding()
                end),
            }, {
                type = "toggle",
                text = "Show Second Wind",
                getValue = EDR_ShowSW,
                setValue = CUI.DependentSetValue(EDR_ShowSW, function(val)
                    EDR_Set("showSecondWind", val)
                    RebuildDragonRiding()
                end),
            })
            cursorY = cursorY - height
            local wsRow
            wsRow, height = Widg:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Whirling Surge",
                getValue = function() return not EDR_WSOff() end,
                setValue = EDR_SetRowThen("showWhirlingSurge"),
            }, {
                type = "toggle",
                text = "Show Icon Cooldown Text",
                disabled = EDR_WSOff,
                disabledTooltip = "Show Whirling Surge",
                getValue = function()
                    return DragonRidingCfg("whirlingSurgeText") and DragonRidingCfg("whirlingSurgeText").enabled ~= false
                end,
                setValue = function(val)
                    EDR_SetField("whirlingSurgeText", "enabled", val)
                    EDR_Redraw()
                end,
            })
            cursorY = cursorY - height
            -- Icon size: automatic (as tall as the bars) while Auto Size is on;
            -- turning it off hands the slider the current automatic size.
            if not CUI._prebuilding then
                CUI.BuildInlineCog(wsRow._leftRegion, {
                    title = "Whirling Surge Icon",
                    disabled = EDR_WSOff,
                    disabledTooltip = "Show Whirling Surge",
                    rows = {
                        {
                            type = "toggle",
                            label = "Auto Size",
                            tooltip = "Keeps the icon as tall as the bars.",
                            get = function() return DragonRidingCfg("iconSize") == nil end,
                            set = function(val)
                                if val then
                                    EDR_Set("iconSize", nil)
                                else
                                    EDR_Set("iconSize", EDR_AutoIconSize())
                                end
                                RebuildDragonRiding()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Icon Size",
                            min = 16,
                            max = 80,
                            step = 1,
                            disabled = function() return DragonRidingCfg("iconSize") == nil end,
                            disabledTooltip = "Auto Size",
                            requireState = "disabled",
                            get = function() return DragonRidingCfg("iconSize") or EDR_AutoIconSize() end,
                            set = EDR_SetRowThen("iconSize"),
                        },
                    },
                })
            end
            -- Classic Gems replaces the charge row with Blizzard's original gems
            -- (the page rebuilds: the Charge row and the gem scale follow it).
            -- The cog holds the full-charge chime and, for the gems, their scale.
            local vigorRow
            vigorRow, height = Widg:DualRow(hostFrame, cursorY, {
                type = "segmented",
                text = "Vigor Style",
                values = { bars = "Bars", gems = "Classic Gems" },
                order = { "bars", "gems" },
                tooltip = "Classic Gems brings back Blizzard's original vigor display above the bars.",
                getValue = function() return DragonRidingCfg("vigorStyle") or "bars" end,
                setValue = CUI.DependentSetValue(EDR_IsGems, function(val)
                    EDR_Set("vigorStyle", val)
                    RebuildDragonRiding()
                end),
            }, {
                type = "slider",
                pixel = true,
                text = "Stack Spacing",
                min = 0,
                max = 10,
                step = 1,
                -- The gap between pips: nothing to space with no pip row shown.
                disabled = function() return EDR_IsGems() and not EDR_ShowSW() end,
                disabledTooltip = "This option requires the Bars vigor style or Show Second Wind",
                getValue = function() return DragonRidingCfg("stackSpacing") end,
                setValue = EDR_SetRowThen("stackSpacing"),
            })
            cursorY = cursorY - height
            if not CUI._prebuilding then
                local vigorRows = {
                    {
                        type = "toggle",
                        label = "Play Sound on Full Charge",
                        tooltip = "Plays Blizzard's vigor chime each time a skyriding charge fills.",
                        get = function() return DragonRidingCfg("chargeSound") == true end,
                        set = EDR_SetRow("chargeSound"),
                    },
                }
                if EDR_IsGems() then
                    vigorRows[2] = {
                        type = "slider",
                        label = "Gem Scale",
                        min = 0.5,
                        max = 2.0,
                        step = 0.05,
                        get = function() return DragonRidingCfg("classicScale") or 1 end,
                        set = EDR_SetRowThen("classicScale"),
                    }
                end
                CUI.BuildInlineCog(vigorRow._leftRegion, { title = "Vigor", rows = vigorRows })
            end
            _, height = Widg:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Width",
                min = 80,
                max = 600,
                step = 1,
                getValue = function() return DragonRidingCfg("width") end,
                setValue = EDR_SetRowThen("width"),
            }, {
                type = "slider",
                pixel = true,
                text = "Element Spacing",
                min = 0,
                max = 12,
                step = 1,
                getValue = function() return DragonRidingCfg("gap") end,
                setValue = EDR_SetRowThen("gap"),
            })
            cursorY = cursorY - height
            -- Border Size: the CludesUI border and its colour on the
            -- CludesUI look; under Classic WoW UI the slot sizes the vanilla
            -- frame, as the Resource Bars' Border Size does; Blizzard Style's
            -- panel has no size to set.
            local borderCfg
            if edrStyle == "classic" then
                borderCfg = BS.ClassicBorderSizeCfg(
                    function() return DragonRidingCfg("classicFrameSize") end,
                    function(val)
                        EDR_Set("classicFrameSize", val)
                        RebuildDragonRiding()
                    end
                )
            else
                borderCfg = BS.Gate("dragonriding", {
                    type = "slider",
                    text = "Border Size",
                    min = 0,
                    max = 4,
                    step = 1,
                    getValue = function() return DragonRidingCfg("borderThickness") or 0 end,
                    setValue = function(val)
                        EDR_Set("borderThickness", val)
                        EDR_Redraw()
                        CUI:RefreshPage()
                    end,
                })
            end
            local borderRow
            borderRow, height = Widg:DualRow(hostFrame, cursorY, borderCfg, {
                type = "dropdown",
                text = "Bar Texture",
                values = edrTexValues,
                order = edrTexOrder,
                getValue = function() return DragonRidingCfg("barTexture") or "none" end,
                setValue = function(val)
                    EDR_Set("barTexture", val)
                    EDR_Redraw()
                end,
            })
            cursorY = cursorY - height
            if not CUI._prebuilding and edrStyle == "cui" then
                local region = borderRow._leftRegion
                local control = region._control
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    borderRow:GetFrameLevel() + 3,
                    function()
                        local color = DragonRidingCfg("borderColor")
                        return color.r, color.g, color.b, color.a
                    end,
                    function(red, green, blue, a)
                        local p = DragonRidingCfg("borderColor")
                        p.r, p.g, p.b, p.a = red, green, blue, a
                        EDR_Redraw()
                    end,
                    true,
                    20
                )
                CUI.PanelPP.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
                region._lastInline = colorSwatch
                -- No border to colour at size 0: dimmed and blocked.
                local cover = CUI.NewSwatchBlocker(colorSwatch)
                cover:SetScript(
                    "OnEnter",
                    function()
                        CUI.ShowWidgetTooltip(
                            colorSwatch,
                            CUI.DisabledTooltip("This option requires a Border Size above 0.")
                        )
                    end
                )
                cover:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                local function UpdateSwatchState()
                    if (DragonRidingCfg("borderThickness") or 0) == 0 then
                        colorSwatch:SetAlpha(0.3)
                        cover:Show()
                    else
                        colorSwatch:SetAlpha(1)
                        cover:Hide()
                    end
                end
                CUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    UpdateSwatchState()
                end)
                UpdateSwatchState()
            end
            _, height = Widg:Spacer(hostFrame, cursorY, 20)
            cursorY = cursorY - height

            -- Charge and Second Wind rows, each only while its part is shown
            -- (Classic Gems replaces the charge row); no section without either.
            local showCharges, showSW = not EDR_IsGems(), EDR_ShowSW()
            if showCharges or showSW then
                _, height = Widg:SectionHeader(hostFrame, "LAYOUT", cursorY)
                cursorY = cursorY - height
                if showCharges then
                    _, height = Widg:DualRow(hostFrame, cursorY, {
                        type = "slider",
                        text = "Charge Height",
                        min = 2,
                        max = 24,
                        step = 1,
                        getValue = function() return DragonRidingCfg("skyridingHeight") end,
                        setValue = EDR_SetRowThen("skyridingHeight"),
                    }, {
                        type = "multiSwatch",
                        text = "Charge Color",
                        swatches = {
                            {
                                text = "Background",
                                getValue = function()
                                    local color = DragonRidingCfg("skyridingBg")
                                    return color.r, color.g, color.b, color.a
                                end,
                                setValue = function(red, green, blue, a)
                                    local p = DragonRidingCfg("skyridingBg")
                                    p.r, p.g, p.b, p.a = red, green, blue, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Background",
                            },
                            {
                                text = "Stacks",
                                getValue = function()
                                    local color = DragonRidingCfg("skyridingFilled")
                                    return color.r, color.g, color.b, color.a
                                end,
                                setValue = function(red, green, blue, a)
                                    local p = DragonRidingCfg("skyridingFilled")
                                    p.r, p.g, p.b, p.a = red, green, blue, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Charges",
                            },
                        },
                    })
                    cursorY = cursorY - height
                end
                if showSW then
                    _, height = Widg:DualRow(hostFrame, cursorY, {
                        type = "slider",
                        text = "Second Wind Height",
                        min = 2,
                        max = 24,
                        step = 1,
                        getValue = function() return DragonRidingCfg("secondWindHeight") end,
                        setValue = EDR_SetRowThen("secondWindHeight"),
                    }, {
                        type = "multiSwatch",
                        text = "Second Wind Color",
                        swatches = {
                            {
                                text = "Background",
                                getValue = function()
                                    local color = DragonRidingCfg("secondWindBg")
                                    return color.r, color.g, color.b, color.a
                                end,
                                setValue = function(red, green, blue, a)
                                    local p = DragonRidingCfg("secondWindBg")
                                    p.r, p.g, p.b, p.a = red, green, blue, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Background",
                            },
                            {
                                text = "Second Wind",
                                getValue = function()
                                    local color = DragonRidingCfg("secondWindFilled")
                                    return color.r, color.g, color.b, color.a
                                end,
                                setValue = function(red, green, blue, a)
                                    local p = DragonRidingCfg("secondWindFilled")
                                    p.r, p.g, p.b, p.a = red, green, blue, a
                                    EDR_Redraw()
                                end,
                                hasAlpha = true,
                                tooltip = "Second Wind",
                            },
                        },
                    })
                    cursorY = cursorY - height
                end
                _, height = Widg:Spacer(hostFrame, cursorY, 20)
                cursorY = cursorY - height
            end

            -- The speed bar's own section only while the bar is shown.
            if EDR_ShowSpeed() then
                _, height = Widg:SectionHeader(hostFrame, "SPEED BAR", cursorY)
                cursorY = cursorY - height
                _, height = Widg:DualRow(hostFrame, cursorY, {
                    type = "slider",
                    text = "Height",
                    min = 4,
                    max = 40,
                    step = 1,
                    getValue = function() return DragonRidingCfg("speedHeight") end,
                    setValue = EDR_SetRowThen("speedHeight"),
                }, {
                    type = "toggle",
                    text = "Thrill Color Change",
                    getValue = function() return DragonRidingCfg("thrillColorToggle") == true end,
                    setValue = function(val)
                        EDR_Set("thrillColorToggle", val)
                        EDR_Redraw()
                    end,
                })
                cursorY = cursorY - height
                _, height = Widg:DualRow(hostFrame, cursorY, {
                    type = "multiSwatch",
                    text = "Speed Color",
                    swatches = {
                        {
                            text = "Background",
                            getValue = function()
                                local color = DragonRidingCfg("speedBarBg")
                                return color.r, color.g, color.b, color.a
                            end,
                            setValue = function(red, green, blue, a)
                                local p = DragonRidingCfg("speedBarBg")
                                p.r, p.g, p.b, p.a = red, green, blue, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Background",
                        },
                        {
                            text = "Speed",
                            getValue = function()
                                local color = DragonRidingCfg("normalColor")
                                return color.r, color.g, color.b, color.a
                            end,
                            setValue = function(red, green, blue, a)
                                local p = DragonRidingCfg("normalColor")
                                p.r, p.g, p.b, p.a = red, green, blue, a
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
                                local color = DragonRidingCfg("tickColor")
                                return color.r, color.g, color.b, color.a
                            end,
                            setValue = function(red, green, blue, a)
                                local p = DragonRidingCfg("tickColor")
                                p.r, p.g, p.b, p.a = red, green, blue, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Hash Marker",
                        },
                        {
                            text = "Thrill",
                            getValue = function()
                                local color = DragonRidingCfg("thrillColor")
                                return color.r, color.g, color.b, color.a
                            end,
                            setValue = function(red, green, blue, a)
                                local p = DragonRidingCfg("thrillColor")
                                p.r, p.g, p.b, p.a = red, green, blue, a
                                EDR_Redraw()
                            end,
                            hasAlpha = true,
                            tooltip = "Thrill",
                        },
                    },
                })
                cursorY = cursorY - height
                local speedTextRow
                speedTextRow, height = Widg:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Show Speed Text",
                    getValue = function()
                        return DragonRidingCfg("speedText") and DragonRidingCfg("speedText").enabled ~= false
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
                    getValue = function() return (DragonRidingCfg("speedText") or {}).justify or "CENTER" end,
                    setValue = function(val)
                        EDR_SetField("speedText", "justify", val)
                        EDR_Redraw()
                    end,
                })
                if not CUI._prebuilding then
                    CUI.BuildInlineCog(speedTextRow._rightRegion, {
                        title = "Speed Text Position",
                        rows = {
                            {
                                type = "slider",
                                label = "Size",
                                min = 6,
                                max = 32,
                                step = 1,
                                get = function() return (DragonRidingCfg("speedText") or {}).size or 12 end,
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
                                get = function() return (DragonRidingCfg("speedText") or {}).offsetX or 0 end,
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
                                get = function() return (DragonRidingCfg("speedText") or {}).offsetY or 0 end,
                                set = function(val)
                                    EDR_SetField("speedText", "offsetY", val)
                                    EDR_Redraw()
                                end,
                            },
                        },
                    })
                end
                cursorY = cursorY - height
                _, height = Widg:Spacer(hostFrame, cursorY, 20)
                cursorY = cursorY - height
            end -- Show Speed Bar
        end -- close Dragon Riding hidden-while-disabled gate

        -- The wrapper is SetAllPoints-anchored, so SetHeight on it is inert;
        -- return the measured height so the scroll range is correct.
        return math.abs(cursorY)
    end

    -- WoW Forever has no skyriding: the Dragon Riding tab is not registered there
    -- (its resident file returns at load, so the page would have no DB to read).
    local pages = CUI.IS_FOREVER and { PAGE_WINDOWSKINS, PAGE_TOOLTIPS, PAGE_CHATBUBBLES }
        or { PAGE_WINDOWSKINS, PAGE_TOOLTIPS, PAGE_CHATBUBBLES, PAGE_DRAGONRIDING }
    -- Panel shown, or unfolded from its mini window (no page callback runs then): a shown
    -- sample catches up on writes it skipped while hidden (Unlock Mode, other pages). Each
    -- repaint checks that its own sample is the one on screen.
    local function CatchUpPreviews()
        RepaintTooltipPreview()
        RepaintPopupPreview()
        if mod.EDR_RepaintSample then mod.EDR_RepaintSample() end
    end
    CUI:RegisterOnShow(CatchUpPreviews)
    CUI:RegisterOnCollapse(function(on)
        if not on then CatchUpPreviews() end
    end)
    CUI:RegisterModule("CludesUIBlizzardSkin", {
        title = "Window Skins",
        description = CUI.IS_FOREVER
                and "Themed Blizzard frames: window skins, tooltips, menus, popups, chat bubbles."
            or "Themed Blizzard frames: window skins, tooltips, menus, popups, chat bubbles, Dragon Riding HUD.",
        searchTerms = "blizzard skin character sheet tooltip menu popup dragon riding skyriding window skins lfg group finder premade queue pause game menu great vault inspect collections mounts pets toys spellbook talents adventure guide encounter journal professions guild communities calendar achievements mail catalyst gem socket item upgrade upgrades crest loot window loot toast you received popup micro menu modern delves companion brann loot roll need greed pass disenchant loot rolls pending rolls group invite invited to a group role chat bubbles bubble speech balloon",
        pages = pages,
        buildPage = function(pageTitle, hostFrame, yOffset)
            if pageTitle == PAGE_WINDOWSKINS then
                return BuildWindowSkinsPage(pageTitle, hostFrame, yOffset)
            end
            if pageTitle == PAGE_TOOLTIPS then return BuildTooltipsPage(pageTitle, hostFrame, yOffset) end
            if pageTitle == PAGE_CHATBUBBLES then
                return BuildChatBubblesPage(pageTitle, hostFrame, yOffset)
            end
            if pageTitle == PAGE_DRAGONRIDING then
                return BuildDragonRidingPage(pageTitle, hostFrame, yOffset)
            end
        end,
        -- The Tooltips, Chat Bubbles and Skyriding previews live in the content header; a
        -- cached page whose header was dropped rebuilds with it.
        getHeaderBuilder = function(pageTitle)
            if pageTitle == PAGE_TOOLTIPS then return TooltipHeaderBuilder end
            if pageTitle == PAGE_CHATBUBBLES then return ChatBubblesHeaderBuilder end
            if pageTitle == PAGE_DRAGONRIDING and DragonRidingCfg("enabled") == true then
                return SkyridingHeaderBuilder
            end
        end,
        -- A kept page shown again: its preview paints again (the Fonts and Textures pages,
        -- Unlock Mode and a profile switch write its keys from elsewhere).
        onPageCacheRestore = function(pageTitle)
            if pageTitle == PAGE_TOOLTIPS then
                RepaintTooltipPreview()
                RepaintPopupPreview()
            end
            if pageTitle == PAGE_DRAGONRIDING and mod.EDR_RepaintSample then mod.EDR_RepaintSample() end
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
                local prof = CUI.GetActiveProfileData()
                if prof then prof.disableWindowSkins = nil end
                -- Per-profile Chat Bubbles; Refresh hands back any CVars it held.
                if prof then prof.chatBubbles = nil end
                if CUI.ChatBubbles then CUI.ChatBubbles.Refresh() end
            end
            if CludesUIDB then
                -- Every setting on the two tabs: the export bundle's own list
                -- (CludesUI_Profiles.lua), so a setting added there resets too.
                for _, k in ipairs(CUI.BLIZZ_SKIN_GLOBAL_KEYS) do
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
                local prof = CUI.GetActiveProfileData()
                if prof then prof.tooltipFixedPos = nil end
                if CUI._applyTooltipBuffs then CUI._applyTooltipBuffs() end
                -- Any glow on a popup on screen goes (the hooks stay, inert).
                if CUI._EnsureResurrectGlow then CUI._EnsureResurrectGlow() end
                if CUI.SyncAuraTooltipSkin then CUI.SyncAuraTooltipSkin() end
            end
            if CUI._applyTooltipCursorAnchor then CUI._applyTooltipCursorAnchor() end
            if CUI._applyTooltipFixedAnchor then CUI._applyTooltipFixedAnchor() end
            if CUI._applyTooltipHealthStrip then CUI._applyTooltipHealthStrip() end
            if CUI._applyTooltipHealthStripStyle then CUI._applyTooltipHealthStripStyle() end
            if CUI._refreshCharSheetSocketPanel then CUI._refreshCharSheetSocketPanel() end
            if CUI._refreshCharSheetSlotFlyoutArrows then
                CUI._refreshCharSheetSlotFlyoutArrows()
            end
            if CUI._refreshStatFormats then CUI._refreshStatFormats() end
            if CUI._refreshCharSheetSlotLabels then CUI._refreshCharSheetSlotLabels() end
            if CUI._refreshInspectSlotLabels then CUI._refreshInspectSlotLabels() end
            -- WoW Forever's Friends List card (auto-accept and the tiles)
            if mod.FriendsCardRefresh then mod.FriendsCardRefresh() end
            -- The Mail card's Alt List (retail)
            if mod.MailAlts then mod.MailAlts.Refresh() end
        end,
    })

    -- Deep links (What's New, search) into the Window Skins page target rows
    -- that only exist while a card is expanded. Pre-hook: expand every card and
    -- drop the page cache so the nav's SelectPage cold-builds with all rows
    -- present before it resolves the section/highlight.
    local origNav = CUI.NavigateToElementSettings
    if origNav then
        function CUI:NavigateToElementSettings(
            moduleName,
            pageTitle,
            sectionName,
            preSelectFn,
            highlightText
        )
            -- The original refuses in combat: no page state changes then.
            if InCombatLockdown() then
                return origNav(self, moduleName, pageTitle, sectionName, preSelectFn, highlightText)
            end
            if
                moduleName == "CludesUIBlizzardSkin"
                and pageTitle == PAGE_WINDOWSKINS
                and (sectionName or highlightText)
            then
                local changed = false
                for _, window in ipairs(WINDOWS) do
                    if not _wsExpanded[window.key] then
                        _wsExpanded[window.key] = true
                        changed = true
                    end
                end
                if changed and CUI.InvalidatePageCache then CUI:InvalidatePageCache() end
            end
            return origNav(self, moduleName, pageTitle, sectionName, preSelectFn, highlightText)
        end
    end

    SLASH_EBSK1 = "/cbsk"
    SlashCmdList.EBSK = function()
        if InCombatLockdown and InCombatLockdown() then return end
        CUI:ShowModule("CludesUIBlizzardSkin")
    end
end)
