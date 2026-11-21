if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ActionBars_Options\BarAppearance_Options.lua
--  Action Bars options: the Appearance, Effects, Behavior (and Paging) and
--  Text sections of the Bar Display page. Called by BuildSharedBarSettings
--  for bars that are not visibility-only; returns y and the rows its click
--  navigation maps to. Shared helpers come from ns._ABO_OptEnv, the
--  per-build helpers from ctx.
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIActionBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

local function BuildBarAppearance(hostFrame, cursorY, context)
    local environ = mod._ABO_OptEnv
    local ABAR, EndCapsCtl, GROUP_BAR_ORDER, InCombatLockdown, Pix =
        environ.EAB, environ.EndCapsCtl, environ.GROUP_BAR_ORDER, environ.InCombatLockdown, environ.PP
    local SB, SECTION_ICON_APPEARANCE, SECTION_TEXT, SelectedKey =
        environ.SB, environ.SECTION_ICON_APPEARANCE, environ.SECTION_TEXT, environ.SelectedKey
    local SHORT_NAMES, ShownBorderDefaults, TEXT_ANCHOR_DROPDOWN_ORDER, TEXT_ANCHOR_LABELS =
        environ.SHORT_LABELS,
        environ.ShownBorderDefaults,
        environ.TEXT_ANCHOR_DROPDOWN_ORDER,
        environ.TEXT_ANCHOR_LABELS
    local BgDisabled, ReadSetting, SSeedTextOffsets, WriteSetting =
        context.BgDisabled, context.SGet, context.SSeedTextOffsets, context.SSet
    local SSetColor, SUpdatePreview, SUpdatePreviewAndResize, SettingOr =
        context.SSetColor, context.SUpdatePreview, context.SUpdatePreviewAndResize, context.SVal
    local W = context.W
    local _, height
    local row
    -- Row / section references for click-navigation (returned to BuildSharedBarSettings)
    local iconsSectionHeader, textSectionHeader
    local keybindRow, chargesRow

    -- A sync icon on rgn for one group of settings: read() takes the selected
    -- bar's values once, copy(bar, v, key) writes them into another bar and
    -- re-applies it, same(bar, v, key) says whether a bar already matches, and
    -- after() (optional) re-applies what every bar shares once the copies are
    -- done. All copies to every action bar, Multiple to the ticked ones, and
    -- the page repaints after either; it reads synced while every bar matches.
    local function BarSync(region, tooltip, read, copy, same, after)
        local function CopyTo(keys)
            local value = read()
            for _, key in ipairs(keys) do
                copy(ABAR.db.profile.bars[key], value, key)
            end
            if after then after() end
            CUI:RefreshPage()
        end
        CUI.BuildSyncIcon({
            region = region,
            tooltip = tooltip,
            onClick = function() CopyTo(GROUP_BAR_ORDER) end,
            isSynced = function()
                local value = read()
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if not same(ABAR.db.profile.bars[key], value, key) then return false end
                end
                return true
            end,
            flashTargets = function() return { region } end,
            multiApply = {
                elementKeys = GROUP_BAR_ORDER,
                elementLabels = SHORT_NAMES,
                getCurrentKey = function() return SelectedKey() end,
                onApply = CopyTo,
            },
        })
    end

    -- The sync icon of a button text (prefix keybind, count or macro): its
    -- colour, size, X and Y offsets and anchor. A colour is copied only when
    -- the selected bar has one; an unset anchor is stored as false.
    local function TextSync(region, tooltip, prefix)
        local COLOR, SIZE = prefix .. "FontColor", prefix .. "FontSize"
        local OX, OY, ANCHOR = prefix .. "OffsetX", prefix .. "OffsetY", prefix .. "Anchor"
        BarSync(region, tooltip, function()
            local barCfg = SB()
            return {
                c = barCfg[COLOR],
                sz = barCfg[SIZE] or 12,
                ox = barCfg[OX] or 0,
                oy = barCfg[OY] or 0,
                an = barCfg[ANCHOR],
            }
        end, function(bar, value, key)
            local color = value.c
            if color then bar[COLOR] = { r = color.r, g = color.g, b = color.b } end
            bar[SIZE] = value.sz
            bar[OX] = value.ox
            bar[OY] = value.oy
            bar[ANCHOR] = value.an or false
            ABAR:ApplyFontsForBar(key)
        end, function(bar, value)
            if (bar[SIZE] or 12) ~= value.sz or (bar[OX] or 0) ~= value.ox or (bar[OY] or 0) ~= value.oy then
                return false
            end
            if (bar[ANCHOR] or nil) ~= (value.an or nil) then return false end
            local c, bc = value.c, bar[COLOR]
            return not c or (bc and bc.r == c.r and bc.g == c.g and bc.b == c.b) and true or false
        end)
    end

    -- A row whose items or cog hold settings with labels of their own (a
    -- checklist, a dropdown with a settings cog) registers its search entry
    -- right before the row, as the index keeps the first entry of a label:
    -- those labels, and the labels of the rows it stands in for, are the
    -- entry's search text. barKey (optional) is the bar a hit opens, in place
    -- of the bar being built.
    local function AddRowSearch(labelText, words, barId)
        if not CUI._RegisterSearchEntry then return end
        local textValue = {}
        for idx = 1, #words do
            local s = words[idx]
            textValue[#textValue + 1] = s
            local loc = CUI.L(s)
            if loc ~= s then textValue[#textValue + 1] = loc end
        end
        local labelLoc = CUI.L(labelText)
        local section = hostFrame._currentSection and hostFrame._currentSection._sectionName
        if type(section) ~= "string" then section = nil end
        local sel = CUI._buildingSelector
        local setter, selKey = sel and sel.setter, sel and sel.key
        if barId then
            setter, selKey = CUI._setActionBarKey, barId
        end
        CUI._RegisterSearchEntry(
            labelText,
            labelLoc ~= labelText and labelLoc or nil,
            table.concat(textValue, " "),
            CUI._buildingModule,
            CUI._buildingPage,
            section,
            setter,
            selKey
        )
    end
    -- The DualRow half a checklist takes: a stand-in dropdown whose label
    -- carries the row text and its tooltip. Its getter runs `reads`, which
    -- reads every key the checklist writes, so the Spec Overrides gold walk
    -- marks the slot while one of them is overridden.
    local function ChecklistCfg(textValue, tooltip, reads)
        return {
            type = "dropdown",
            text = textValue,
            tooltip = tooltip,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                if reads then reads() end
                return "__placeholder"
            end,
            setValue = function() end,
        }
    end
    -- The checklist in `rgn` (a half built from ChecklistCfg). Spec Overrides
    -- see each click as it happens (the slot's capture); onMenuClosed runs
    -- each time its open menu hides. The search prebuild builds none.
    local function BuildChecklist(region, itemList, get, set, onMenuClosed)
        if CUI._prebuilding then return end
        if region._control then region._control:Hide() end
        local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            170,
            region:GetFrameLevel() + 2,
            itemList,
            get,
            set,
            nil,
            nil,
            nil,
            nil,
            onMenuClosed,
            { notifyWrites = true, dimLocked = true }
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -------------------------------------------------------------------
    --  APPEARANCE
    -------------------------------------------------------------------
    iconsSectionHeader, height = W:SectionHeader(hostFrame, SECTION_ICON_APPEARANCE, cursorY)
    cursorY = cursorY - height
    cursorY = CUI.BlizzStyle.Note(hostFrame, cursorY, "actionbars")

    -- Stock mode (Blizzard Style or Classic WoW UI): the shared gate.
    local function BlizzLookOn() return CUI.BlizzStyle.Get("actionbars") end

    -- "No custom shape" also covers "cropped" and unset.
    local function ShapeIsNone()
        local value = ReadSetting("buttonShape")
        return value == "none" or value == "cropped" or value == nil
    end
    local function HasCustomShape() return not ShapeIsNone() end

    local SHAPE_VALUES = {
        none = "None",
        cropped = "Cropped",
        square = "Square",
        circle = "Circle",
        csquare = "Curved Square",
        diamond = "Diamond",
        hexagon = "Hexagon",
        portrait = "Portrait",
        shield = "Shield",
    }
    local SHAPE_ORDER = {
        "none",
        "cropped",
        "---",
        "square",
        "circle",
        "csquare",
        "diamond",
        "hexagon",
        "portrait",
        "shield",
    }

    local abBsRow
    do
        local texValues, texOrder = CUI.GetBorderTextureDropdown()
        -- Border Size: a custom shape's ring is on/off, so it keeps the None/Strong
        -- dropdown; every other shape gets the pixel slider over the same key and
        -- its borderThicknessPx companion. The shape setter rebuilds the page so the
        -- slot follows the shape; a bar switch already rebuilds.
        local sizeCfg
        if HasCustomShape() then
            sizeCfg = {
                type = "dropdown",
                text = "Border Size",
                disabled = BlizzLookOn,
                disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
                requireState = "disabled",
                values = mod.BORDER_THICKNESS_LABELS,
                order = mod.BORDER_THICKNESS_ORDER,
                itemDisabled = function(val)
                    if HasCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then
                        return true
                    end
                    return false
                end,
                itemDisabledTooltip = function(val)
                    if HasCustomShape() and (val == "thin" or val == "normal" or val == "heavy") then
                        return "This option requires a non-custom shape to be selected"
                    end
                end,
                getValue = function()
                    local value = ReadSetting("borderThickness")
                    return value or "thin"
                end,
                setValue = function(value)
                    WriteSetting("borderThickness", value, function(keyName)
                        local record = mod.BORDER_THICKNESS[value]
                        if record then
                            local shape = ABAR.db.profile.bars[keyName].buttonShape or "none"
                            if shape ~= "none" and shape ~= "cropped" then
                                ABAR.db.profile.bars[keyName].shapeBorderSize = record.shape
                                ABAR.db.profile.bars[keyName].shapeBorderEnabled = record.shape > 0
                            else
                                ABAR.db.profile.bars[keyName].borderSize = record.regular
                                ABAR.db.profile.bars[keyName].borderEnabled = record.regular > 0
                            end
                        end
                        ABAR:ApplyBordersForBar(keyName)
                        ABAR:ApplyShapesForBar(keyName)
                    end)
                    SUpdatePreview()
                end,
            }
        else
            sizeCfg = CUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = BlizzLookOn,
                disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
                requireState = "disabled",
                -- The step the buttons render with (ResolveBorderThickness's regular
                -- column): an unknown or numeric thickness is thin.
                getStep = function()
                    local record = mod.BORDER_THICKNESS[ReadSetting("borderThickness") or "thin"]
                        or mod.BORDER_THICKNESS.thin
                    return record.regular
                end,
                -- Exactly what the dropdown wrote for a non-custom shape: the label and its mirrors.
                setStep = function(step)
                    local barCfg = SB()
                    local labelText = CUI.BORDER_LABEL_OF_STEP[step]
                    barCfg.borderThickness = labelText
                    local record = mod.BORDER_THICKNESS[labelText]
                    if record then
                        barCfg.borderSize = record.regular
                        barCfg.borderEnabled = record.regular > 0
                    end
                end,
                getTex = function() return ReadSetting("borderTexture") or "solid" end,
                getPx = function() return ReadSetting("borderThicknessPx") end,
                setPx = function(value) SB().borderThicknessPx = value end,
                apply = function()
                    local keyName = SelectedKey()
                    ABAR:ApplyBordersForBar(keyName)
                    ABAR:ApplyShapesForBar(keyName)
                    CUI:RefreshPage()
                    SUpdatePreview()
                end,
            })
        end
        abBsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CUI.BlizzStyle.Gate("actionbars", {
                type = "dropdown",
                text = "Border Style",
                disabled = function() return BlizzLookOn() or HasCustomShape() end,
                disabledTooltip = function()
                    if HasCustomShape() then return "This option requires a non-custom button shape" end
                    return CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
                end,
                rawTooltip = true,
                values = texValues,
                order = texOrder,
                getValue = function() return ReadSetting("borderTexture") or "solid" end,
                setValue = function(value)
                    local defTh = CUI.GetBorderDefaultSize("actionbars", value)
                    -- An unregistered SharedMedia border answers the NUMBER 1; this key stores labels.
                    if type(defTh) == "number" then defTh = CUI.BORDER_LABEL_OF_STEP[defTh] or "thin" end
                    WriteSetting("borderTexture", value, function(keyName)
                        ABAR.db.profile.bars[keyName].borderTextureOffset = nil
                        ABAR.db.profile.bars[keyName].borderTextureOffsetY = nil
                        ABAR.db.profile.bars[keyName].borderTextureShiftX = nil
                        ABAR.db.profile.bars[keyName].borderTextureShiftY = nil
                        -- A style pick resets the size to the style's default: a set exact size goes with it (false travels, nil would not).
                        if ABAR.db.profile.bars[keyName].borderThicknessPx then
                            ABAR.db.profile.bars[keyName].borderThicknessPx = false
                        end
                        local _bcol, _bbehind = CUI.GetBorderStyleSelectDefaults(value)
                        ABAR.db.profile.bars[keyName].borderColor =
                            { r = _bcol.r, g = _bcol.g, b = _bcol.b, a = 1 }
                        ABAR.db.profile.bars[keyName].borderClassColor = false
                        ABAR.db.profile.bars[keyName].borderBehind = _bbehind
                        if defTh then
                            ABAR.db.profile.bars[keyName].borderThickness = defTh
                            local record = mod.BORDER_THICKNESS[defTh]
                            if record then
                                local shape = ABAR.db.profile.bars[keyName].buttonShape or "none"
                                if shape ~= "none" and shape ~= "cropped" then
                                    ABAR.db.profile.bars[keyName].shapeBorderSize = record.shape
                                    ABAR.db.profile.bars[keyName].shapeBorderEnabled = record.shape > 0
                                else
                                    ABAR.db.profile.bars[keyName].borderSize = record.regular
                                    ABAR.db.profile.bars[keyName].borderEnabled = record.regular > 0
                                end
                            end
                        end
                        ABAR:ApplyBordersForBar(keyName)
                        ABAR:ApplyShapesForBar(keyName)
                    end)
                    SUpdatePreview()
                    -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                    CUI:RefreshPage(true)
                end,
            }),
            CUI.BlizzStyle.Gate("actionbars", sizeCfg)
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: the textured border's outward offsets, their
        -- own row while a textured style is selected (Solid has none; the style
        -- setter rebuilds the page). Shown = the override, else the "actionbars"
        -- registry default for the step and thickness key ApplyBordersForBar and the
        -- shape repaint pass (ResolveBorderThickness), scaled to an exact size as drawn.
        do
            local btnTex = ReadSetting("borderTexture") or "solid"
            if btnTex ~= "" and btnTex ~= "solid" then
                local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                    addonKey = "actionbars",
                    disabled = BlizzLookOn,
                    disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
                    requireState = "disabled",
                    getTex = function() return ReadSetting("borderTexture") or "solid" end,
                    getStep = function() return (mod.ResolveBorderThickness(SB())) end,
                    getSizeKey = function() return ReadSetting("borderThickness") or "thin" end,
                    getPx = function() return ReadSetting("borderThicknessPx") end,
                    getX = function() return ReadSetting("borderTextureOffset") end,
                    setX = function(value) SB().borderTextureOffset = value end,
                    getY = function() return ReadSetting("borderTextureOffsetY") end,
                    setY = function(value) SB().borderTextureOffsetY = value end,
                    apply = function()
                        ABAR:ApplyBordersForBar(SelectedKey())
                        CUI:RefreshPage()
                        SUpdatePreview()
                    end,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CUI.BlizzStyle.Gate("actionbars", ocfgL),
                    CUI.BlizzStyle.Gate("actionbars", ocfgR)
                )
                cursorY = cursorY - height
            end
        end
        do
            local region = abBsRow._leftRegion
            -- The offsets/shifts the buttons render with when none is set: the
            -- step's registry defaults (looked up as before), scaled to an exact
            -- size when one is set, as ApplyButtonBorders draws them.
            local function BtnBorderDefaults()
                local texture = ReadSetting("borderTexture") or "solid"
                local th = ReadSetting("borderThickness") or "thin"
                local step, px = mod.ResolveBorderThickness(SB())
                return ShownBorderDefaults(texture, th, step, px)
            end
            local cogBtn = CUI.BuildInlineCog(region, {
                anchorTo = region._control,
                title = "Border Options",
                captureRegion = region,
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local value = ReadSetting("borderTextureShiftX")
                            if value then return value end
                            local _, _, dsx = BtnBorderDefaults()
                            return dsx
                        end,
                        set = function(value)
                            -- The shift shown by default stores nil (follow the style again).
                            local _, _, dsx = BtnBorderDefaults()
                            if value == math.floor(dsx + 0.5) then value = nil end
                            WriteSetting(
                                "borderTextureShiftX",
                                value,
                                function(keyName) ABAR:ApplyBordersForBar(keyName) end
                            )
                            SUpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shift Y",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local value = ReadSetting("borderTextureShiftY")
                            if value then return value end
                            local _, _, _, dsy = BtnBorderDefaults()
                            return dsy
                        end,
                        set = function(value)
                            local _, _, _, dsy = BtnBorderDefaults()
                            if value == math.floor(dsy + 0.5) then value = nil end
                            WriteSetting(
                                "borderTextureShiftY",
                                value,
                                function(keyName) ABAR:ApplyBordersForBar(keyName) end
                            )
                            SUpdatePreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function() return ReadSetting("borderBehind") or false end,
                        set = function(value)
                            WriteSetting(
                                "borderBehind",
                                value == false and nil or value,
                                function(keyName) ABAR:ApplyBordersForBar(keyName) end
                            )
                            SUpdatePreview()
                            CUI:RefreshPage()
                        end,
                    },
                    -- The inverse of Show Behind, which wins: the runtime
                    -- ignores this flag while Show Behind is on.
                    {
                        type = "toggle",
                        label = "Border Above Effects",
                        tooltip = "Draws this bar's button borders over proc glows, the assisted highlight and the cooldown swipe.",
                        disabled = function()
                            return BlizzLookOn()
                                or HasCustomShape()
                                or (ReadSetting("borderBehind") and true or false)
                        end,
                        disabledTooltip = function()
                            if BlizzLookOn() then
                                return CUI.DisabledTooltip(
                                    CUI.BlizzStyle.Label("actionbars"),
                                    "disabled"
                                )
                            end
                            if HasCustomShape() then
                                return "This option requires a non-custom button shape"
                            end
                            return CUI.DisabledTooltip("Show Behind", "disabled")
                        end,
                        rawTooltip = true,
                        get = function() return ReadSetting("borderAboveEffects") or false end,
                        set = function(value)
                            WriteSetting(
                                "borderAboveEffects",
                                value and true or false,
                                function(keyName) ABAR:ApplyBordersForBar(keyName) end
                            )
                            SUpdatePreview()
                        end,
                    },
                },
            })
            if cogBtn then
                local function UpdateCogVis() cogBtn:SetShown((ReadSetting("borderTexture") or "solid") ~= "solid") end
                CUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end
        local bsLeftRgn = abBsRow._leftRegion
        BarSync(
            bsLeftRgn,
            "Apply Border Style to all Bars",
            function()
                local barCfg = SB()
                return {
                    texture = barCfg.borderTexture,
                    ox = barCfg.borderTextureOffset,
                    oy = barCfg.borderTextureOffsetY,
                    sx = barCfg.borderTextureShiftX,
                    sy = barCfg.borderTextureShiftY,
                    behind = barCfg.borderBehind,
                    above = barCfg.borderAboveEffects,
                    color = barCfg.borderColor,
                    classColor = barCfg.borderClassColor,
                }
            end,
            function(bar, value, key)
                bar.borderTexture = value.texture or "solid"
                bar.borderTextureOffset = value.ox
                bar.borderTextureOffsetY = value.oy
                bar.borderTextureShiftX = value.sx
                bar.borderTextureShiftY = value.sy
                bar.borderBehind = value.behind
                bar.borderAboveEffects = value.above
                local bc = value.color
                if bc then bar.borderColor = { r = bc.r, g = bc.g, b = bc.b, a = bc.a } end
                bar.borderClassColor = value.classColor
                ABAR:ApplyBordersForBar(key)
            end,
            function(bar, value)
                return (bar.borderTexture or "solid") == (value.texture or "solid")
                    and bar.borderTextureOffset == value.ox
                    and bar.borderTextureOffsetY == value.oy
                    and bar.borderTextureShiftX == value.sx
                    and bar.borderTextureShiftY == value.sy
                    and (bar.borderBehind or false) == (value.behind or false)
                    and (bar.borderAboveEffects or false) == (value.above or false)
            end
        )
    end

    do
        local rightRegion = abBsRow._rightRegion
        local control = rightRegion._control

        local classBorderSwatch, updateClassBorderSwatch = CUI.BuildColorSwatch(
            rightRegion,
            abBsRow:GetFrameLevel() + 3,
            function()
                local _, classTok = UnitClass("player")
                local classColor = classTok and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classTok]
                if classColor then return classColor.r, classColor.g, classColor.b end
                return 1, 1, 1
            end,
            function() end,
            false,
            20
        )
        Pix.Point(classBorderSwatch, "RIGHT", control, "LEFT", -8, 0)
        classBorderSwatch:SetScript("OnClick", function()
            WriteSetting("borderClassColor", true, function(keyName)
                ABAR:ApplyBordersForBar(keyName)
                ABAR:ApplyShapesForBar(keyName)
            end)
            SUpdatePreview()
            CUI:RefreshPage()
        end)
        CUI.HoverTip(classBorderSwatch, "Class Colored")

        local customSwatch, updateCustomSwatch = CUI.BuildColorSwatch(
            rightRegion,
            abBsRow:GetFrameLevel() + 3,
            function()
                local color = ReadSetting("borderColor")
                if not color then return 0, 0, 0 end
                return color.r, color.g, color.b
            end,
            function(red, green, blue)
                SSetColor("borderColor", red, green, blue, nil, function(keyName)
                    ABAR:ApplyBordersForBar(keyName)
                    ABAR:ApplyShapesForBar(keyName)
                end)
                SSetColor(
                    "shapeBorderColor",
                    red,
                    green,
                    blue,
                    nil,
                    function(keyName) ABAR:ApplyShapesForBar(keyName) end
                )
                SUpdatePreview()
            end,
            false,
            20
        )
        Pix.Point(customSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
        CUI.HoverTip(customSwatch, "Custom Color")

        -- Click the dimmed custom swatch to switch back from class color (no block overlay)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if ReadSetting("borderClassColor") then
                WriteSetting("borderClassColor", false, function(keyName)
                    ABAR:ApplyBordersForBar(keyName)
                    ABAR:ApplyShapesForBar(keyName)
                end)
                SUpdatePreview()
                CUI:RefreshPage()
                return
            end
            -- No border selected: allow swapping boxes but do not open the color picker
            if (ReadSetting("borderThickness") or "thin") == "none" then return end
            if origClick then origClick(self, ...) end
        end)

        local function UpdateBorderSwatchState()
            local isClassColored = ReadSetting("borderClassColor")
            local isNone = (ReadSetting("borderThickness") or "thin") == "none"
            customSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
            classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
        end
        CUI.RegisterWidgetRefresh(function()
            updateCustomSwatch()
            updateClassBorderSwatch()
            UpdateBorderSwatchState()
        end)
        UpdateBorderSwatchState()
    end

    do
        local region = abBsRow._rightRegion
        BarSync(region, "Apply Border Size and Color to all Bars", function()
            local barCfg = SB()
            -- borderThicknessPx is copied as is (string, false or nil).
            return {
                th = barCfg.borderThickness,
                px = barCfg.borderThicknessPx,
                c = barCfg.borderColor,
                cc = barCfg.borderClassColor,
            }
        end, function(bar, value, key)
            bar.borderThickness = value.th
            local px = value.px
            if px == nil and bar.borderThicknessPx ~= nil then px = false end
            bar.borderThicknessPx = px
            local record = mod.BORDER_THICKNESS[value.th]
            if record then
                local shape = bar.buttonShape or "none"
                if shape ~= "none" and shape ~= "cropped" then
                    bar.shapeBorderSize = record.shape
                    bar.shapeBorderEnabled = record.shape > 0
                else
                    bar.borderSize = record.regular
                    bar.borderEnabled = record.regular > 0
                end
            end
            local color = value.c
            if color then
                bar.borderColor = { r = color.r, g = color.g, b = color.b, a = color.a }
                bar.shapeBorderColor = { r = color.r, g = color.g, b = color.b, a = color.a }
            end
            bar.borderClassColor = value.cc
            ABAR:ApplyBordersForBar(key)
            ABAR:ApplyShapesForBar(key)
        end, function(bar, value)
            -- nil and false render alike.
            if
                (bar.borderThickness or "thin") ~= (value.th or "thin")
                or (bar.borderThicknessPx or false) ~= (value.px or false)
            then
                return false
            end
            if (bar.borderClassColor or false) ~= (value.cc or false) then return false end
            local color, bc = value.c, bar.borderColor
            return (bc and bc.r or 0) == (color and color.r or 0)
                and (bc and bc.g or 0) == (color and color.g or 0)
                and (bc and bc.b or 0) == (color and color.b or 0)
                and (bc and bc.a or 1) == (color and color.a or 1)
        end)
    end

    local classColorBorderRow
    classColorBorderRow, height = W:DualRow(
        hostFrame,
        cursorY,
        CUI.BlizzStyle.Gate("actionbars", {
            type = "dropdown",
            text = "Custom Button Shape",
            disabled = BlizzLookOn,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            itemDisabled = function(val)
                if val ~= "none" and val ~= "cropped" and (ReadSetting("borderTexture") or "solid") ~= "solid" then
                    return true
                end
                return false
            end,
            itemDisabledTooltip = function(val)
                if val ~= "none" and val ~= "cropped" and (ReadSetting("borderTexture") or "solid") ~= "solid" then
                    return "This option requires the Border Style to be set to Solid"
                end
            end,
            getValue = function()
                local value = ReadSetting("buttonShape")
                return value or "none"
            end,
            setValue = function(value)
                -- Set icon zoom BEFORE shapes: ApplyShapesForBar -> ApplyShapeToButton reads the new value.
                WriteSetting("iconZoom", mod.SHAPE_ZOOM_DEFAULTS[value] or 5.5)
                WriteSetting("buttonShape", value, function(keyName)
                    -- Reset border thickness to the default for the new shape mode
                    if value ~= "none" and value ~= "cropped" then
                        ABAR.db.profile.bars[keyName].borderThickness = mod.BORDER_THICKNESS_DEFAULT_SHAPE
                        local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_SHAPE]
                        ABAR.db.profile.bars[keyName].shapeBorderSize = record.shape
                        ABAR.db.profile.bars[keyName].shapeBorderEnabled = true
                    else
                        ABAR.db.profile.bars[keyName].borderThickness = mod.BORDER_THICKNESS_DEFAULT_REGULAR
                        local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_REGULAR]
                        ABAR.db.profile.bars[keyName].borderSize = record.regular
                        ABAR.db.profile.bars[keyName].borderEnabled = true
                    end
                    -- Default keybind/count text for cropped vs normal (offsets keep a
                    -- positioned text's corner spacing)
                    if value == "cropped" then
                        ABAR.db.profile.bars[keyName].keybindFontSize = 11
                        ABAR.db.profile.bars[keyName].countFontSize = 11
                        ABAR.ApplyShapeTextOffsets(ABAR.db.profile.bars[keyName], 0, 1, 0, -1)
                    else
                        ABAR.db.profile.bars[keyName].keybindFontSize = 12
                        ABAR.db.profile.bars[keyName].countFontSize = 12
                        ABAR.ApplyShapeTextOffsets(ABAR.db.profile.bars[keyName], 0, 0, 0, 0)
                    end
                    ABAR:ApplyShapesForBar(keyName)
                    ABAR:ApplyPaddingForBar(keyName)
                    ABAR:ApplyBordersForBar(keyName)
                    ABAR:ApplyFontsForBar(keyName)
                    ABAR:ApplyIconBackgroundForBar(keyName)
                end)
                ABAR:RefreshProcGlows()
                SUpdatePreview()
                -- Full rebuild: the Border Size slot is a dropdown for a custom shape
                -- and the pixel slider otherwise, and only a rebuild swaps it.
                CUI:RefreshPage(true)
            end,
        }),
        CUI.BlizzStyle.Gate("actionbars", {
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 10,
            step = 0.5,
            disabled = BlizzLookOn,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            getValue = function() return SettingOr("iconZoom", ABAR.db.profile.iconZoom or 5.5) end,
            setValue = function(value)
                WriteSetting("iconZoom", value, function(keyName)
                    ABAR:ApplyBordersForBar(keyName)
                    ABAR:ApplyShapesForBar(keyName)
                end)
                SUpdatePreview()
            end,
        })
    )
    cursorY = cursorY - height
    do
        local region = classColorBorderRow._leftRegion
        BarSync(
            region,
            "Apply Custom Button Shape to all Bars",
            function() return ReadSetting("buttonShape") or "none" end,
            function(bs, value, key)
                bs.iconZoom = mod.SHAPE_ZOOM_DEFAULTS[value] or 5.5
                bs.buttonShape = value
                if value ~= "none" and value ~= "cropped" then
                    bs.borderThickness = mod.BORDER_THICKNESS_DEFAULT_SHAPE
                    local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_SHAPE]
                    bs.shapeBorderSize = record.shape
                    bs.shapeBorderEnabled = true
                else
                    bs.borderThickness = mod.BORDER_THICKNESS_DEFAULT_REGULAR
                    local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_REGULAR]
                    bs.borderSize = record.regular
                    bs.borderEnabled = true
                end
                if value == "cropped" then
                    bs.keybindFontSize = 11
                    bs.countFontSize = 11
                    ABAR.ApplyShapeTextOffsets(bs, 0, 1, 0, -1)
                else
                    bs.keybindFontSize = 12
                    bs.countFontSize = 12
                    ABAR.ApplyShapeTextOffsets(bs, 0, 0, 0, 0)
                end
                ABAR:ApplyShapesForBar(key)
                ABAR:ApplyPaddingForBar(key)
                ABAR:ApplyBordersForBar(key)
                ABAR:ApplyFontsForBar(key)
            end,
            function(bar, value) return (bar.buttonShape or "none") == value end,
            function()
                ABAR:RefreshProcGlows()
                SUpdatePreview()
            end
        )
    end

    do
        local region = classColorBorderRow._rightRegion
        BarSync(
            region,
            "Apply Icon Zoom to all Bars",
            function() return SB().iconZoom or ABAR.db.profile.iconZoom or 5.5 end,
            function(bar, value, key)
                bar.iconZoom = value
                ABAR:ApplyBordersForBar(key)
                ABAR:ApplyShapesForBar(key)
            end,
            function(bar, value) return (bar.iconZoom or ABAR.db.profile.iconZoom or 5.5) == value end
        )
    end

    -- Icon Background | Blizzard Icon Background
    local slotBgRow
    slotBgRow, height = W:DualRow(
        hostFrame,
        cursorY,
        CUI.BlizzStyle.Gate("actionbars", {
            type = "slider",
            text = "Icon Background",
            min = 0,
            max = 100,
            step = 1,
            disabled = BlizzLookOn,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            getValue = function()
                local value = ABAR.db.profile.slotBgOpacity
                if value == nil then value = 50 end
                return value
            end,
            setValue = function(value)
                ABAR.db.profile.slotBgOpacity = value
                ABAR:ApplySlotBackgroundColor()
            end,
        }),
        {
            type = "toggle",
            text = "Blizzard Icon Background",
            tooltip = "Shows Blizzard's slot art on empty slots.",
            getValue = function() return ABAR.db.profile.showBlizzIconBg or false end,
            setValue = function(value)
                ABAR.db.profile.showBlizzIconBg = value
                for _, details in ipairs(mod.BAR_CONFIG or {}) do
                    ABAR:ApplyIconBackgroundForBar(details.key)
                end
                CUI:RefreshPage()
            end,
        }
    )
    cursorY = cursorY - height
    do
        local region = slotBgRow._rightRegion
        CUI.BuildInlineCog(region, {
            title = "Icon Background",
            anchorTo = region._control,
            disabled = function() return not (ABAR.db.profile.showBlizzIconBg or false) end,
            disabledTooltip = "Blizzard Icon Background",
            rows = {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    tooltip = "Controls the opacity of the Blizzard icon slot background texture.",
                    get = function() return math.floor((ABAR.db.profile.blizzIconBgAlpha or 1) * 100 + 0.5) end,
                    set = function(value)
                        ABAR.db.profile.blizzIconBgAlpha = value / 100
                        for _, details in ipairs(mod.BAR_CONFIG or {}) do
                            ABAR:ApplyIconBackgroundForBar(details.key)
                        end
                    end,
                },
            },
        })
    end
    -- Inline swatch: icon background color (left). Dimmed while a stock style is on (no slot background exists) or at 0 opacity.
    do
        local region = slotBgRow._leftRegion
        local function SlotBgOff()
            if BlizzLookOn() then return true end
            local value = ABAR.db.profile.slotBgOpacity
            if value == nil then value = 50 end
            return value == 0
        end
        local sbgSwatch, sbgUpdateSwatch = CUI.BuildColorSwatch(
            region,
            slotBgRow:GetFrameLevel() + 3,
            function()
                local color = ABAR.db.profile.slotBgColor or { r = 0.15, g = 0.15, b = 0.15 }
                return color.r, color.g, color.b, 1
            end,
            function(red, green, blue)
                ABAR.db.profile.slotBgColor = { r = red, g = green, b = blue }
                ABAR:ApplySlotBackgroundColor()
            end,
            false,
            20
        )
        Pix.Point(sbgSwatch, "RIGHT", region._control, "LEFT", -8, 0)
        region._lastInline = sbgSwatch
        sbgSwatch:SetAlpha(SlotBgOff() and 0.15 or 1)
        local sbgOrigClick = sbgSwatch:GetScript("OnClick")
        sbgSwatch:SetScript("OnClick", function(self, ...)
            if SlotBgOff() then return end
            if sbgOrigClick then sbgOrigClick(self, ...) end
        end)
        sbgSwatch:SetScript("OnEnter", function(self)
            if SlotBgOff() then
                if BlizzLookOn() then
                    CUI.ShowWidgetTooltip(
                        self,
                        CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
                    )
                else
                    CUI.ShowWidgetTooltip(self, CUI.DisabledTooltip("Set Icon Background above 0"))
                end
            end
        end)
        sbgSwatch:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        CUI.RegisterWidgetRefresh(function()
            sbgSwatch:SetAlpha(SlotBgOff() and 0.15 or 1)
            sbgUpdateSwatch()
        end)
    end

    -------------------------------------------------------------------
    --  End Caps | Bar Background close the section, Bar Background's
    --  other rows following it while it is on. Under the WoW Forever look
    --  End Caps sits beside Bar Frame (the frame and dividers behind the
    --  bar's buttons; both on by default on Action Bar 1 only) and Bar
    --  Background starts the next row, beside its Spacing.
    -------------------------------------------------------------------
    local function BarBgSpacingCfg()
        return {
            type = "slider",
            text = "Spacing",
            min = 0,
            max = 20,
            step = 1,
            disabled = BgDisabled,
            disabledTooltip = "Bar Background",
            getValue = function()
                local value = ReadSetting("bgPadding")
                if value ~= nil then return value end
                return math.max(SettingOr("bgPadX", 0), SettingOr("bgPadY", 0))
            end,
            setValue = function(value)
                SB().bgPadX, SB().bgPadY = nil, nil
                WriteSetting("bgPadding", value, function(keyName) ABAR:ApplyBackgroundForBar(keyName) end)
                SUpdatePreview()
            end,
        }
    end
    local function BarBgSpacingSync(regionFrame)
        local function CurrentSpacing(prefs)
            if prefs.bgPadding ~= nil then return prefs.bgPadding end
            return math.max(prefs.bgPadX or 0, prefs.bgPadY or 0)
        end
        local function ApplySpacingTo(key)
            local target = ABAR.db.profile.bars[key]
            target.bgPadding = CurrentSpacing(SB())
            target.bgPadX = nil
            target.bgPadY = nil
            ABAR:ApplyBackgroundForBar(key)
        end
        BarSync(
            regionFrame,
            "Apply Bar Background Spacing to all Bars",
            function() return CurrentSpacing(SB()) end,
            function(_, _, key) ApplySpacingTo(key) end,
            function(bar, spacing) return CurrentSpacing(bar) == spacing end
        )
    end

    -- Bar Background's other rows: Spacing last, unless it sits beside Bar
    -- Background (the WoW Forever look).
    local function BuildBarBackgroundRows(capsForever)
        local function BackgroundOpacity(prefs)
            if prefs.bgOpacity ~= nil then return prefs.bgOpacity end
            local color = prefs.bgColor
            return ((color and color.a) or 0.5) * 100
        end

        -- Section gate: these rows are built only while Bar Background is on for
        -- the selected bar (its SectionToggleSetValue rebuilds the page on a flip).
        if SettingOr("bgEnabled", false) then
            local bgColorRow
            bgColorRow, height = W:DualRow(hostFrame, cursorY, {
                type = "colorpicker",
                text = "Background Color",
                hasAlpha = false,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function()
                    local color = ReadSetting("bgColor") or { r = 0, g = 0, b = 0, a = 0.5 }
                    return color.r, color.g, color.b, 1
                end,
                setValue = function(red, green, blue)
                    local old = ReadSetting("bgColor") or { a = 0.5 }
                    SSetColor(
                        "bgColor",
                        red,
                        green,
                        blue,
                        old.a or 0.5,
                        function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                    )
                    SUpdatePreview()
                end,
            }, {
                type = "slider",
                text = "Background Opacity",
                min = 0,
                max = 100,
                step = 1,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function() return BackgroundOpacity(SB()) end,
                setValue = function(value)
                    WriteSetting("bgOpacity", value, function(keyName) ABAR:ApplyBackgroundForBar(keyName) end)
                    SUpdatePreview()
                end,
            })
            cursorY = cursorY - height

            do
                local regionFrame = bgColorRow._leftRegion
                local function ApplyColorTo(key)
                    local source = ReadSetting("bgColor") or { r = 0, g = 0, b = 0, a = 0.5 }
                    local target = ABAR.db.profile.bars[key]
                    local old = target.bgColor
                    target.bgColor = {
                        r = source.r,
                        g = source.g,
                        b = source.b,
                        a = (old and old.a) or source.a or 0.5,
                    }
                    ABAR:ApplyBackgroundForBar(key)
                end
                BarSync(
                    regionFrame,
                    "Apply Background Color to all Bars",
                    function() return ReadSetting("bgColor") or { r = 0, g = 0, b = 0 } end,
                    function(_, _, key) ApplyColorTo(key) end,
                    function(bar, color)
                        local target = bar.bgColor or { r = 0, g = 0, b = 0 }
                        return target.r == color.r and target.g == color.g and target.b == color.b
                    end
                )
            end

            do
                local regionFrame = bgColorRow._rightRegion
                local function ApplyOpacityTo(key)
                    local target = ABAR.db.profile.bars[key]
                    target.bgOpacity = BackgroundOpacity(SB())
                    ABAR:ApplyBackgroundForBar(key)
                end
                BarSync(
                    regionFrame,
                    "Apply Background Opacity to all Bars",
                    function() return BackgroundOpacity(SB()) end,
                    function(_, _, key) ApplyOpacityTo(key) end,
                    function(bar, opacity) return BackgroundOpacity(bar) == opacity end
                )
            end

            do
                local texValues, texOrder = CUI.GetBorderTextureDropdown()
                local bgBorderRow
                bgBorderRow, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    {
                        type = "dropdown",
                        text = "Background Border Style",
                        disabled = BgDisabled,
                        disabledTooltip = "Bar Background Border",
                        values = texValues,
                        order = texOrder,
                        getValue = function() return SettingOr("bgBorderTexture", "solid") end,
                        setValue = function(value)
                            local color, behind = CUI.GetBorderStyleSelectDefaults(value)
                            WriteSetting("bgBorderTexture", value, function(keyName)
                                local prefs = ABAR.db.profile.bars[keyName]
                                prefs.bgBorderOffsetX = nil
                                prefs.bgBorderOffsetY = nil
                                prefs.bgBorderShiftX = nil
                                prefs.bgBorderShiftY = nil
                                -- A style pick resets the border: a set exact size goes with it (false travels, nil would not).
                                if prefs.bgBorderThicknessPx then prefs.bgBorderThicknessPx = false end
                                prefs.bgBorderBehind = behind
                                prefs.bgBorderColor = { r = color.r, g = color.g, b = color.b, a = 1 }
                                ABAR:ApplyBackgroundForBar(keyName)
                            end)
                            SUpdatePreview()
                            -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                            CUI:RefreshPage(true)
                        end,
                    },
                    CUI.BorderPxSliderCfg({
                        text = "Background Border Size",
                        disabled = BgDisabled,
                        disabledTooltip = "Bar Background Border",
                        -- The step ApplyBackgroundForBar renders with: a thickness with no
                        -- entry (unknown, or the number an old SharedMedia pick stored) is 0, hidden.
                        getStep = function()
                            local record = mod.BORDER_THICKNESS[SettingOr("bgBorderThickness", "none")]
                            return record and record.regular or 0
                        end,
                        setStep = function(step) SB().bgBorderThickness = CUI.BORDER_LABEL_OF_STEP[step] end,
                        getTex = function() return SettingOr("bgBorderTexture", "solid") end,
                        getPx = function() return ReadSetting("bgBorderThicknessPx") end,
                        setPx = function(value) SB().bgBorderThicknessPx = value end,
                        apply = function()
                            ABAR:ApplyBackgroundForBar(SelectedKey())
                            CUI:RefreshPage()
                            SUpdatePreview()
                        end,
                    })
                )
                cursorY = cursorY - height

                -- Background Border Width Offset | Height Offset: the textured border's
                -- outward offsets, their own row while a textured style is selected
                -- (Solid has none; the style setter rebuilds the page). Shown = the
                -- override, else the "actionbars" registry default for the thickness
                -- key ApplyBackgroundForBar passes.
                do
                    local bgTex = SettingOr("bgBorderTexture", "solid")
                    if bgTex ~= "" and bgTex ~= "solid" then
                        local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                            addonKey = "actionbars",
                            disabled = BgDisabled,
                            disabledTooltip = "Bar Background Border",
                            getTex = function() return SettingOr("bgBorderTexture", "solid") end,
                            getStep = function()
                                local record = mod.BORDER_THICKNESS[SettingOr("bgBorderThickness", "none")]
                                return record and record.regular or 0
                            end,
                            getSizeKey = function() return SettingOr("bgBorderThickness", "none") end,
                            getPx = function() return ReadSetting("bgBorderThicknessPx") end,
                            getX = function() return ReadSetting("bgBorderOffsetX") end,
                            setX = function(value) SB().bgBorderOffsetX = value end,
                            getY = function() return ReadSetting("bgBorderOffsetY") end,
                            setY = function(value) SB().bgBorderOffsetY = value end,
                            apply = function()
                                ABAR:ApplyBackgroundForBar(SelectedKey())
                                CUI:RefreshPage()
                                SUpdatePreview()
                            end,
                        })
                        ocfgL.text = "Background Border Width Offset"
                        ocfgR.text = "Background Border Height Offset"
                        _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                        cursorY = cursorY - height
                    end
                end

                do
                    local regionFrame = bgBorderRow._rightRegion
                    local borderSwatch, refreshBorder = CUI.BuildColorSwatch(
                        regionFrame,
                        regionFrame:GetFrameLevel() + 5,
                        function()
                            local color = ReadSetting("bgBorderColor") or { r = 0, g = 0, b = 0, a = 1 }
                            return color.r, color.g, color.b, color.a
                        end,
                        function(red, green, blue, a)
                            SSetColor(
                                "bgBorderColor",
                                red,
                                green,
                                blue,
                                a,
                                function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                            )
                            SUpdatePreview()
                        end,
                        true,
                        20
                    )
                    Pix.Point(borderSwatch, "RIGHT", regionFrame._control, "LEFT", -12, 0)
                    regionFrame._lastInline = borderSwatch
                    CUI.RegisterWidgetRefresh(function()
                        local disabled = BgDisabled() or SettingOr("bgBorderThickness", "none") == "none"
                        borderSwatch:SetAlpha(disabled and 0.15 or 1)
                        refreshBorder()
                    end)
                end

                do
                    local regionFrame = bgBorderRow._rightRegion
                    local function ApplySizeTo(key)
                        local source = SB()
                        local target = ABAR.db.profile.bars[key]
                        target.bgBorderThickness = source.bgBorderThickness
                        do
                            local value = source.bgBorderThicknessPx
                            if value == nil and target.bgBorderThicknessPx ~= nil then value = false end
                            target.bgBorderThicknessPx = value
                        end
                        local color = source.bgBorderColor
                        if color then
                            target.bgBorderColor = { r = color.r, g = color.g, b = color.b, a = color.a }
                        end
                        ABAR:ApplyBackgroundForBar(key)
                    end
                    BarSync(regionFrame, "Apply Background Border Size and Color to all Bars", function()
                        return {
                            th = SettingOr("bgBorderThickness", "none"),
                            px = ReadSetting("bgBorderThicknessPx") or false, -- nil and false render alike
                            color = ReadSetting("bgBorderColor") or { r = 0, g = 0, b = 0, a = 1 },
                        }
                    end, function(_, _, key) ApplySizeTo(key) end, function(target, value)
                        if
                            (target.bgBorderThickness or "none") ~= value.th
                            or (target.bgBorderThicknessPx or false) ~= value.px
                        then
                            return false
                        end
                        local tc, color = target.bgBorderColor or { r = 0, g = 0, b = 0, a = 1 }, value.color
                        return tc.r == color.r and tc.g == color.g and tc.b == color.b and tc.a == color.a
                    end)
                end

                do
                    local regionFrame = bgBorderRow._leftRegion
                    -- The offsets/shifts the background border renders with when none is
                    -- set: its registry defaults (looked up as before), scaled to an exact
                    -- size when one is set, as ApplyBackgroundForBar draws them.
                    local function BackBorderDefaults()
                        local texture = SettingOr("bgBorderTexture", "solid")
                        local thickness = SettingOr("bgBorderThickness", "thin")
                        local record = mod.BORDER_THICKNESS[SettingOr("bgBorderThickness", "none")]
                        local step = record and record.regular or 0
                        local px = CUI.BorderPx(ReadSetting("bgBorderThicknessPx"), step, texture)
                        return ShownBorderDefaults(texture, thickness, step, px)
                    end
                    local offsetButton = CUI.BuildInlineCog(regionFrame, {
                        anchorTo = regionFrame._control,
                        title = "Border Options",
                        captureRegion = regionFrame,
                        rows = {
                            {
                                type = "slider",
                                label = "Shift X",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local value = ReadSetting("bgBorderShiftX")
                                    if value ~= nil then return value end
                                    local _, _, defaultX = BackBorderDefaults()
                                    return defaultX
                                end,
                                set = function(value)
                                    -- The shift shown by default stores nil (follow the style again).
                                    local _, _, defaultX = BackBorderDefaults()
                                    if value == math.floor(defaultX + 0.5) then value = nil end
                                    WriteSetting(
                                        "bgBorderShiftX",
                                        value,
                                        function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                                    )
                                    SUpdatePreview()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Shift Y",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local value = ReadSetting("bgBorderShiftY")
                                    if value ~= nil then return value end
                                    local _, _, _, defaultY = BackBorderDefaults()
                                    return defaultY
                                end,
                                set = function(value)
                                    local _, _, _, defaultY = BackBorderDefaults()
                                    if value == math.floor(defaultY + 0.5) then value = nil end
                                    WriteSetting(
                                        "bgBorderShiftY",
                                        value,
                                        function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                                    )
                                    SUpdatePreview()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show Behind",
                                get = function() return SettingOr("bgBorderBehind", false) end,
                                set = function(value)
                                    WriteSetting(
                                        "bgBorderBehind",
                                        value,
                                        function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                                    )
                                    SUpdatePreview()
                                end,
                            },
                        },
                    })
                    if offsetButton then
                        local function UpdateOffsetButton() offsetButton:SetShown(not BgDisabled()) end
                        CUI.RegisterWidgetRefresh(UpdateOffsetButton)
                        UpdateOffsetButton()
                    end
                end

                do
                    local regionFrame = bgBorderRow._leftRegion
                    local function ApplyStyleTo(key)
                        local source = SB()
                        local target = ABAR.db.profile.bars[key]
                        target.bgBorderTexture = source.bgBorderTexture
                        target.bgBorderOffsetX = source.bgBorderOffsetX
                        target.bgBorderOffsetY = source.bgBorderOffsetY
                        target.bgBorderShiftX = source.bgBorderShiftX
                        target.bgBorderShiftY = source.bgBorderShiftY
                        target.bgBorderBehind = source.bgBorderBehind
                        ABAR:ApplyBackgroundForBar(key)
                    end
                    BarSync(
                        regionFrame,
                        "Apply Background Border Style to all Bars",
                        SB,
                        function(_, _, key) ApplyStyleTo(key) end,
                        function(target, source)
                            return (target.bgBorderTexture or "solid") == (source.bgBorderTexture or "solid")
                                and target.bgBorderOffsetX == source.bgBorderOffsetX
                                and target.bgBorderOffsetY == source.bgBorderOffsetY
                                and target.bgBorderShiftX == source.bgBorderShiftX
                                and target.bgBorderShiftY == source.bgBorderShiftY
                                and (target.bgBorderBehind or false) == (source.bgBorderBehind or false)
                        end
                    )
                end
            end

            local bgMultiplierRow
            bgMultiplierRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Multiplier X",
                min = 1,
                max = 4,
                step = 1,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function() return SettingOr("bgMultiplierX", 1) end,
                setValue = function(value)
                    WriteSetting("bgMultiplierX", value, function(keyName) ABAR:ApplyBackgroundForBar(keyName) end)
                    SUpdatePreviewAndResize()
                end,
            }, {
                type = "slider",
                text = "Multiplier Y",
                min = 1,
                max = 4,
                step = 1,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function() return SettingOr("bgMultiplierY", 1) end,
                setValue = function(value)
                    WriteSetting("bgMultiplierY", value, function(keyName) ABAR:ApplyBackgroundForBar(keyName) end)
                    SUpdatePreviewAndResize()
                end,
            })
            cursorY = cursorY - height

            do
                local regionFrame = bgMultiplierRow._leftRegion
                CUI.BuildInlineCog(regionFrame, {
                    anchorTo = regionFrame._control,
                    title = "Multiplier X Settings",
                    captureRegion = regionFrame,
                    rows = {
                        {
                            type = "dropdown",
                            label = "Growth Direction",
                            values = { left = "Left", right = "Right" },
                            order = { "left", "right" },
                            get = function() return SettingOr("bgExpandDirectionX", "right") end,
                            set = function(value)
                                WriteSetting(
                                    "bgExpandDirectionX",
                                    value,
                                    function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                                )
                                SUpdatePreviewAndResize()
                            end,
                        },
                    },
                })
            end

            do
                local regionFrame = bgMultiplierRow._rightRegion
                CUI.BuildInlineCog(regionFrame, {
                    anchorTo = regionFrame._control,
                    title = "Multiplier Y Settings",
                    captureRegion = regionFrame,
                    rows = {
                        {
                            type = "dropdown",
                            label = "Growth Direction",
                            values = { up = "Up", down = "Down" },
                            order = { "up", "down" },
                            get = function() return SettingOr("bgExpandDirectionY", "up") end,
                            set = function(value)
                                WriteSetting(
                                    "bgExpandDirectionY",
                                    value,
                                    function(keyName) ABAR:ApplyBackgroundForBar(keyName) end
                                )
                                SUpdatePreviewAndResize()
                            end,
                        },
                    },
                })
            end

            if not capsForever then
                local spacingRow
                spacingRow, height = W:DualRow(hostFrame, cursorY, BarBgSpacingCfg(), CUI.BlankRowCfg())
                cursorY = cursorY - height
                BarBgSpacingSync(spacingRow._leftRegion)
            end
        end -- bgEnabled section gate
    end

    do
        -- A change to Action Bar 1's caps also repaints a bar carrying one
        -- of them (the first-install span).
        local CAPS = EndCapsCtl({
            key = SelectedKey,
            store = SB,
            label = "End Caps",
            vertical = function() return not ABAR:GetOrientationForBar(SelectedKey()) end,
            write = function(keyName, value)
                if keyName then
                    WriteSetting(keyName, value, function(bk) ABAR:ApplyPaddingForBar(bk) end)
                    SUpdatePreviewAndResize()
                else
                    ABAR:ApplyPaddingForBar(SelectedKey())
                    SUpdatePreviewAndResize()
                    CUI:RefreshPage()
                end
                if SelectedKey() == "MainBar" then mod.AB_CapsSpanApply() end
            end,
            copyApply = function(key)
                ABAR:ApplyPaddingForBar(key)
                if key == "MainBar" then mod.AB_CapsSpanApply() end
            end,
            syncKeys = GROUP_BAR_ORDER,
            syncLabels = SHORT_NAMES,
        })
        local bgCfg = {
            type = "toggle",
            text = "Bar Background",
            getValue = function() return SettingOr("bgEnabled", false) end,
            -- Section gate: its other rows are hidden (not grayed) while off; the wrapper forces the page rebuild.
            setValue = CUI.SectionToggleSetValue(function(value)
                WriteSetting("bgEnabled", value, function(keyName) ABAR:ApplyBackgroundForBar(keyName) end)
                SUpdatePreview()
            end),
        }
        local capsRow, bgRgn
        AddRowSearch("Bar Background", { "Enable Bar Background" })
        if CAPS.forever then
            AddRowSearch(
                "Bar Frame",
                { "Show the frame and dividers behind the bar's buttons.", "Show Bar Background" }
            )
            capsRow, height = W:DualRow(hostFrame, cursorY, CAPS.Cfg(), {
                type = "toggle",
                text = "Bar Frame",
                tooltip = "Show the frame and dividers behind the bar's buttons.",
                getValue = function() return mod.AB_ForeverBg(SelectedKey()) end,
                setValue = function(value)
                    WriteSetting(
                        "foreverBarBg",
                        value and true or false,
                        function(keyName) ABAR:ApplyPaddingForBar(keyName) end
                    )
                    SUpdatePreviewAndResize()
                end,
            })
            cursorY = cursorY - height
            CAPS.Build(capsRow._leftRegion)
            do
                local region = capsRow._rightRegion
                local function BgTo(key, value)
                    local d = ABAR.db.profile.bars[key]
                    if d then
                        d.foreverBarBg = value
                        ABAR:ApplyPaddingForBar(key)
                    end
                end
                BarSync(
                    region,
                    "Apply Bar Frame to all Bars",
                    function() return mod.AB_ForeverBg(SelectedKey()) end,
                    function(_, value, key) BgTo(key, value) end,
                    function(_, value, key) return mod.AB_ForeverBg(key) == value end
                )
            end
            local bgOn = SettingOr("bgEnabled", false)
            local bgRow
            bgRow, height =
                W:DualRow(hostFrame, cursorY, bgCfg, bgOn and BarBgSpacingCfg() or CUI.BlankRowCfg())
            cursorY = cursorY - height
            bgRgn = bgRow._leftRegion
            if bgOn then BarBgSpacingSync(bgRow._rightRegion) end
        else
            capsRow, height = W:DualRow(hostFrame, cursorY, CAPS.Cfg(), bgCfg)
            cursorY = cursorY - height
            CAPS.Build(capsRow._leftRegion)
            bgRgn = capsRow._rightRegion
        end
        do
            local regionFrame = bgRgn
            BarSync(
                regionFrame,
                "Apply Bar Background Enable to all Bars",
                function() return SettingOr("bgEnabled", false) end,
                function(bar, enabled, key)
                    bar.bgEnabled = enabled
                    ABAR:ApplyBackgroundForBar(key)
                end,
                function(bar, enabled) return (bar.bgEnabled or false) == enabled end
            )
        end
        BuildBarBackgroundRows(CAPS.forever)
    end

    -------------------------------------------------------------------
    --  EFFECTS
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "EFFECTS", cursorY)
    cursorY = cursorY - height

    -- Desaturate on Cooldown | Alpha on Cooldown
    AddRowSearch("Alpha on Cooldown", {
        "Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
        "Alpha when on CD",
    })
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Desaturate on Cooldown",
        -- setValue runs a one-shot catch-up sweep: cooldown repaints happen on edges only, so an icon grey at uncheck time would stay grey.
        tooltip = "Desaturates (grays out) action button icons while the ability is on cooldown. GCD-only cooldowns are excluded.",
        getValue = function() return ABAR.db.profile.desaturateOnCooldown or false end,
        setValue = function(value)
            local profile = ABAR.db.profile
            local was = profile.desaturateOnCooldown or false
            profile.desaturateOnCooldown = value
            if was ~= (value or false) and ABAR._DesatSettingChanged then
                ABAR._DesatSettingChanged(value and true or false)
            end
        end,
    }, {
        type = "slider",
        text = "Alpha on Cooldown",
        min = 0,
        max = 100,
        step = 5,
        tooltip = "Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
        getValue = function() return ABAR.db.profile.alphaWhenOnCD or 100 end,
        setValue = function(value)
            ABAR.db.profile.alphaWhenOnCD = value
            if ABAR.ApplyCDAlphaAll then ABAR:ApplyCDAlphaAll() end
        end,
    })
    cursorY = cursorY - height

    -- Out of Range Coloring | Cooldown Swipe Opacity
    AddRowSearch("Cooldown Swipe Opacity", {
        "Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
        "CD Swipe Opacity",
    })
    local rangeSwipeRow
    rangeSwipeRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Out of Range Coloring",
        getValue = function() return ReadSetting("outOfRangeColoring") or false end,
        setValue = function(value)
            WriteSetting("outOfRangeColoring", value, function() ABAR:ApplyRangeColoring() end)
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Cooldown Swipe Opacity",
        min = 0,
        max = 100,
        step = 5,
        trackWidth = 120,
        tooltip = "Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
        getValue = function() return ABAR.db.profile.cdSwipeAlpha or 80 end,
        setValue = function(value)
            ABAR.db.profile.cdSwipeAlpha = value
            if ABAR.ApplyCooldownSwipeColor then ABAR:ApplyCooldownSwipeColor() end
        end,
    })
    cursorY = cursorY - height
    do
        local region = rangeSwipeRow._leftRegion
        BarSync(
            region,
            "Apply Range Coloring to all Bars",
            function()
                local barCfg = SB()
                return { on = barCfg.outOfRangeColoring or false, color = barCfg.outOfRangeColor }
            end,
            function(bar, value)
                bar.outOfRangeColoring = value.on
                local color = value.color
                if color then bar.outOfRangeColor = { r = color.r, g = color.g, b = color.b } end
            end,
            function(bar, value) return (bar.outOfRangeColoring or false) == value.on end,
            function() ABAR:ApplyRangeColoring() end
        )
    end
    do
        local leftRegion = rangeSwipeRow._leftRegion
        local rangeColorGet = function()
            local color = ReadSetting("outOfRangeColor")
            if not color then return 0.7, 0.2, 0.2 end
            return color.r, color.g, color.b
        end
        local rangeColorSet = function(red, green, blue)
            SSetColor("outOfRangeColor", red, green, blue, nil, function() ABAR:ApplyRangeColoring() end)
        end
        local rangeSwatch, rangeUpdateSwatch = CUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            rangeColorGet,
            rangeColorSet,
            false,
            20
        )
        Pix.Point(rangeSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
        leftRegion._lastInline = rangeSwatch

        local function RangeColorOff() return not ReadSetting("outOfRangeColoring") end

        CUI.RegisterWidgetRefresh(function()
            local off = RangeColorOff()
            rangeSwatch:SetAlpha(off and 0.3 or 1)
            rangeUpdateSwatch()
        end)
        rangeSwatch:SetAlpha(RangeColorOff() and 0.3 or 1)

        local rangeBlock = CUI.NewSwatchBlocker(rangeSwatch)
        rangeBlock:SetScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(rangeSwatch, CUI.DisabledTooltip("Out of Range Coloring"))
            end
        )
        rangeBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        CUI.RegisterWidgetRefresh(function() rangeBlock:SetShown(RangeColorOff()) end)
        rangeBlock:SetShown(RangeColorOff())
    end
    -- Inline swatch for Cooldown Swipe Opacity (right): colour-only (hasAlpha=false), since alpha lives on the slider.
    do
        local region = rangeSwipeRow._rightRegion
        local control = region._control
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            region,
            rangeSwipeRow:GetFrameLevel() + 5,
            function()
                local color = ABAR.db.profile.cdSwipeColor or {}
                return color.r or 0, color.g or 0, color.b or 0
            end,
            function(red, green, blue)
                ABAR.db.profile.cdSwipeColor = { r = red, g = green, b = blue }
                if ABAR.ApplyCooldownSwipeColor then ABAR:ApplyCooldownSwipeColor() end
            end,
            false,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        -- Canonical inline-swatch pattern: auto-disable at 0 opacity (invisible swipe has no visible colour).
        local function SwipeDisabled() return (ABAR.db.profile.cdSwipeAlpha or 80) == 0 end
        local block = CUI.NewSwatchBlocker(colorSwatch)
        block:SetScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    colorSwatch,
                    CUI.DisabledTooltip("Set Cooldown Swipe Opacity above 0")
                )
            end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        CUI.RegisterWidgetRefresh(function()
            updateSwatch()
            local off = SwipeDisabled()
            colorSwatch:SetAlpha(off and 0.3 or 1)
            block:SetShown(off)
        end)
        local off0 = SwipeDisabled()
        colorSwatch:SetAlpha(off0 and 0.3 or 1)
        block:SetShown(off0)
    end

    -- Hide Charge Count at 0 | Item Information: Item Rank (this bar's) and
    -- Equipped Item Color (Blizzard's equipped-item border, kept in our
    -- square art and the item's rarity color; one setting for every bar,
    -- saved false, not nil, as WoW Forever defaults it on; the Blizzard and
    -- Classic styles draw their own, so it locks under them).
    do
        AddRowSearch("Item Information", {
            "Item details shown on action buttons.",
            "Item Rank",
            "Equipped Item Color",
            "Show Item Rank",
            "Show Equipped Item Color",
        })
        local itemRow
        itemRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = "Hide Charge Count at 0",
                tooltip = "Hide the charge number on action buttons when it reaches 0, instead of showing a 0. The number returns as soon as a charge or item comes back.",
                getValue = function() return ABAR.db.profile.hideZeroCount or false end,
                setValue = function(value)
                    ABAR.db.profile.hideZeroCount = value or nil
                    if ABAR.RefreshAllCounts then ABAR:RefreshAllCounts() end
                end,
            },
            ChecklistCfg("Item Information", "Item details shown on action buttons.", function()
                local _ = SB().showRankIcon
                _ = ABAR.db.profile.showEquippedBorder
            end)
        )
        cursorY = cursorY - height
        BuildChecklist(itemRow._rightRegion, {
            {
                key = "rank",
                label = "Item Rank",
                tooltip = "Shows the consumable rank (quality) diamond icon on action buttons.",
            },
            {
                key = "equipped",
                label = "Equipped Item Color",
                tooltip = "Equipped items get a rarity color border.",
                lockedFn = BlizzLookOn,
                lockedTooltip = function()
                    return CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
                end,
            },
        }, function(keyName)
            if keyName == "rank" then return ReadSetting("showRankIcon") or false end
            return ABAR.db.profile.showEquippedBorder or false
        end, function(keyName, value)
            if keyName == "rank" then
                WriteSetting("showRankIcon", value)
                if _G._CUAB_Apply then _G._CUAB_Apply() end
            else
                ABAR.db.profile.showEquippedBorder = value and true or false
                ABAR:ApplyEquippedBorder()
            end
        end)
        -- The Apply link copies Item Rank alone: Equipped Item Color is one
        -- setting for every bar.
        do
            local region = itemRow._rightRegion
            BarSync(
                region,
                "Apply Item Rank to all Bars",
                function() return SB().showRankIcon or false end,
                function(bar, value) bar.showRankIcon = value end,
                function(bar, value) return (bar.showRankIcon or false) == value end,
                function()
                    if _G._CUAB_Apply then _G._CUAB_Apply() end
                end
            )
        end
    end

    -- One Button Assist Icon | blank
    local obaRow
    obaRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "One Button Assist Icon",
        getValue = function() return ABAR.db.profile.obaIconEnabled ~= false end,
        setValue = function(value)
            ABAR.db.profile.obaIconEnabled = value
            if mod.RefreshAssistSpinners then mod.RefreshAssistSpinners() end
        end,
    }, CUI.BlankRowCfg())
    cursorY = cursorY - height
    do
        local region = obaRow._leftRegion
        CUI.BuildInlineCog(region, {
            anchorTo = region._control,
            title = "One Button Assist Icon",
            rows = {
                {
                    type = "slider",
                    label = "Icon Outset",
                    min = 0,
                    max = 30,
                    step = 1,
                    get = function() return ABAR.db.profile.obaIconOutset or 9 end,
                    set = function(value)
                        ABAR.db.profile.obaIconOutset = value
                        if mod.RefreshAssistSpinners then mod.RefreshAssistSpinners() end
                    end,
                },
            },
        })
    end

    -------------------------------------------------------------------
    --  BEHAVIOR & PAGING (MainBar and Bars 2-10); BEHAVIOR on the bars
    --  that do not page (Stance Bar, Pet Bar)
    -------------------------------------------------------------------
    do
        local selKey = SelectedKey()
        local _bkp = mod.EAB_VTABLE and mod.EAB_VTABLE.BAR_KEY_TO_PAGE
        local showPaging = selKey and _bkp and _bkp[selKey]
        if showPaging then
            _, height = W:SectionHeader(hostFrame, "BEHAVIOR & PAGING", cursorY)
            cursorY = cursorY - height
        else
            _, height = W:SectionHeader(hostFrame, "BEHAVIOR", cursorY)
            cursorY = cursorY - height
        end

        -- Click Through | Disable Tooltips
        local behaviorRow
        behaviorRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Click Through",
            getValue = function() return ReadSetting("clickThrough") end,
            setValue = function(value)
                WriteSetting("clickThrough", value, function(keyName) ABAR:ApplyClickThroughForBar(keyName) end)
                -- Its Apply link compares this toggle.
                CUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Disable Tooltips",
            getValue = function() return ReadSetting("disableTooltips") or false end,
            setValue = function(value) WriteSetting("disableTooltips", value) end,
        })
        cursorY = cursorY - height
        do
            local region = behaviorRow._leftRegion
            BarSync(
                region,
                "Apply Click Through to all Bars",
                function() return SB().clickThrough or false end,
                function(bar, value, key)
                    bar.clickThrough = value
                    ABAR:ApplyClickThroughForBar(key)
                end,
                function(bar, value) return (bar.clickThrough or false) == value end
            )
        end
        do
            local region = behaviorRow._rightRegion
            BarSync(
                region,
                "Apply Disable Tooltips to all Bars",
                function() return SB().disableTooltips or false end,
                function(bar, value) bar.disableTooltips = value end,
                function(bar, value) return (bar.disableTooltips or false) == value end
            )
        end

        if showPaging then
            local _, playerClass = UnitClass("player")
            local EAB_VT = mod.EAB_VTABLE or {}
            local PG_STATES = EAB_VT.PAGING_STATES or {}
            local BKP = EAB_VT.BAR_KEY_TO_PAGE or {}

            -- The pages a state can switch this bar to: Default, then the page
            -- of every other action bar (a bar cannot page to itself).
            local pagingValues = { none = "Default" }
            local pagingOrder = { "none" }
            for idx = 1, 10 do
                local key = idx == 1 and "MainBar" or ("Bar" .. idx)
                local pg = key ~= selKey and BKP[key]
                if pg then
                    pagingValues[tostring(pg)] = idx == 1 and "Action Bar 1 (Main)" or ("Action Bar " .. idx)
                    pagingOrder[#pagingOrder + 1] = tostring(pg)
                end
            end

            local function GetPagingVal(stateId)
                local paging = ReadSetting("paging")
                local value = paging and paging[stateId]
                return value and tostring(value) or "none"
            end
            local function SetPagingVal(stateId, val)
                local bar = ABAR.db.profile.bars[selKey]
                bar.paging = bar.paging or {}
                -- Default stores nil, not false: the driver builder reads nil as
                -- unconfigured (the form's own bonus bar swap still applies),
                -- while false would suppress it.
                bar.paging[stateId] = val ~= "none" and tonumber(val) or nil
                -- Nothing paged any more: an empty table again.
                local anySet = false
                for _, value in pairs(bar.paging) do
                    if value then
                        anySet = true
                        break
                    end
                end
                if not anySet then bar.paging = {} end
                if mod.RebuildBarPaging then mod.RebuildBarPaging(selKey) end
            end

            local isMain = selKey == "MainBar"
            local function RebuildPaging(keyName)
                if mod.RebuildBarPaging then mod.RebuildBarPaging(keyName) end
            end

            local function PagingRow(stateId, textValue)
                return {
                    type = "dropdown",
                    text = textValue,
                    values = pagingValues,
                    order = pagingOrder,
                    getValue = function() return GetPagingVal(stateId) end,
                    setValue = function(value) SetPagingVal(stateId, value) end,
                }
            end
            -- modTargetPaging, the switch both groups below follow while their
            -- own key is unset: until set, on while any of the five states
            -- holds a page.
            local function ModTargetOn()
                local value = ReadSetting("modTargetPaging")
                if value ~= nil then return value end
                local paging = ReadSetting("paging")
                if paging then
                    for stateId in pairs(EAB_VT.MOD_TARGET_PAGING) do
                        if paging[stateId] then return true end
                    end
                end
                return false
            end
            -- Modifier Paging (Shift, Ctrl, Alt) and Target Paging (friendly,
            -- hostile target): each its own key, read through ModTargetOn
            -- while unset; modTargetPaging false holds both off whatever they
            -- say (the runtime's rule too). Off hides the group's dropdowns
            -- and the bar stops paging on its states; their picks are kept for
            -- when it is turned back on.
            local function GroupOn(key)
                if ReadSetting("modTargetPaging") == false then return false end
                local value = ReadSetting(key)
                if value == nil then value = ModTargetOn() end
                return value and true or false
            end
            local function ModifierOn() return GroupOn("modifierPaging") end
            local function TargetOn() return GroupOn("targetPaging") end
            local modOn, targetOn = ModifierOn(), TargetOn()

            -- Paging Options. Form Paging and Skyriding Paging are Action Bar
            -- 1's (the only bar the engine pages off its bonus bar), each the
            -- inverse of its disable key: unchecked suppresses the implicit
            -- swap only, so an explicit page below still applies. No
            -- skyriding on WoW Forever.
            local pagingItems = {}
            if isMain then
                pagingItems[#pagingItems + 1] = {
                    key = "form",
                    label = "Form Paging",
                    tooltip = "While unchecked, this bar keeps its page in any form.",
                }
                if not CUI.IS_FOREVER then
                    pagingItems[#pagingItems + 1] = {
                        key = "skyriding",
                        label = "Skyriding Paging",
                        tooltip = "While unchecked, this bar keeps its page while skyriding.",
                    }
                end
            end
            pagingItems[#pagingItems + 1] = {
                key = "modifier",
                label = "Modifier Paging",
                tooltip = "Pages this bar while Shift, Ctrl or Alt is held.",
            }
            pagingItems[#pagingItems + 1] = {
                key = "target",
                label = "Target Paging",
                tooltip = "Pages this bar while you have a friendly or hostile target.",
            }
            local PAGING_GET = {
                form = function() return not ReadSetting("disableFormPaging") end,
                skyriding = function() return not ReadSetting("disableSkyridingPaging") end,
                modifier = ModifierOn,
                target = TargetOn,
            }
            local function PagingGet(keyName) return (PAGING_GET[keyName] or TargetOn)() end
            -- Writing one group's key first settles the other group's key to
            -- what it shows. Under modTargetPaging false (both held off),
            -- ticking a group clears it and the other group keeps its off.
            -- While both the other key and modTargetPaging are unset, the other
            -- group falls back to the five states' pages, so a page picked for
            -- one group would otherwise check the other: it is pinned. The
            -- runtime pages that group exactly as before (the pin reads false
            -- only while none of the five states holds a page).
            local function PagingSet(keyName, value)
                if keyName == "form" then
                    WriteSetting("disableFormPaging", not value, RebuildPaging)
                elseif keyName == "skyriding" then
                    WriteSetting("disableSkyridingPaging", not value, RebuildPaging)
                else
                    local barCfg = SB()
                    local mine = (keyName == "modifier") and "modifierPaging" or "targetPaging"
                    local other = (keyName == "modifier") and "targetPaging" or "modifierPaging"
                    if barCfg.modTargetPaging == false then
                        if value then
                            barCfg.modTargetPaging = nil
                            barCfg[other] = false
                        end
                    elseif barCfg[other] == nil and barCfg.modTargetPaging == nil then
                        if keyName == "modifier" then
                            barCfg[other] = TargetOn()
                        else
                            barCfg[other] = ModifierOn()
                        end
                    end
                    WriteSetting(mine, value and true or false, RebuildPaging)
                end
            end
            -- A group's dropdowns exist only while it is on: the page is built
            -- again once the menu closed, never while it is open.
            local function PagingMenuClosed()
                if ModifierOn() ~= modOn or TargetOn() ~= targetOn then CUI:RefreshPage(true) end
            end

            -- Paging Arrows (Action Bar 1): a view over showPagingArrows
            -- (Always) and pagingArrowsWhilePaged (While Paged, the default;
            -- false with the arrows off is Never).
            local function ArrowsMode()
                if ReadSetting("showPagingArrows") then return "always" end
                if ReadSetting("pagingArrowsWhilePaged") == false then return "never" end
                return "paged"
            end

            -- The section's paging slots in order, paired into rows.
            local slots = {}
            slots[#slots + 1] = ChecklistCfg(
                "Paging Options",
                "What switches this bar to another page.",
                function()
                    local barCfg = SB()
                    local _ = barCfg.disableFormPaging
                    _ = barCfg.disableSkyridingPaging
                    _ = barCfg.modifierPaging
                    _ = barCfg.targetPaging
                    _ = barCfg.modTargetPaging
                end
            )
            if isMain then
                slots[#slots + 1] = {
                    type = "dropdown",
                    text = "Paging Arrows",
                    tooltip = "When Action Bar 1's paging arrows show.",
                    values = { never = "Never", always = "Always", paged = "While Paged" },
                    order = { "never", "always", "paged" },
                    getValue = ArrowsMode,
                    setValue = function(value)
                        local barCfg = SB()
                        if value == "always" then
                            barCfg.showPagingArrows = true
                        else
                            barCfg.showPagingArrows = false
                            barCfg.pagingArrowsWhilePaged = (value == "paged")
                        end
                        if mod.LayoutPagingFrame then mod.LayoutPagingFrame() end
                        SUpdatePreviewAndResize()
                        CUI:RefreshPage()
                    end,
                }
            end
            if modOn then
                slots[#slots + 1] = PagingRow("shift", "Shift Modifier")
                slots[#slots + 1] = PagingRow("ctrl", "Ctrl Modifier")
                slots[#slots + 1] = PagingRow("alt", "Alt Modifier")
            end
            if targetOn then
                slots[#slots + 1] = PagingRow("help", "Friendly Target")
                slots[#slots + 1] = PagingRow("harm", "Hostile Target")
            end
            -- Class form dropdowns
            local classStatesLocal = PG_STATES.class and PG_STATES.class[playerClass]
            if classStatesLocal then
                for _, st in ipairs(classStatesLocal) do
                    slots[#slots + 1] = PagingRow(st.id, st.label)
                end
            end
            -- Both entries open Action Bar 1, whichever bar is built first:
            -- only its Paging Options lists Form and Skyriding Paging, and
            -- only it has Paging Arrows.
            do
                local words = {
                    "What switches this bar to another page.",
                    "Form Paging",
                    "Disable Form Paging",
                }
                if not CUI.IS_FOREVER then
                    words[#words + 1] = "Skyriding Paging"
                    words[#words + 1] = "Disable Skyriding Paging"
                end
                words[#words + 1] = "Modifier Paging"
                words[#words + 1] = "Target Paging"
                words[#words + 1] = "Modifier/Target Paging"
                AddRowSearch("Paging Options", words, "MainBar")
                AddRowSearch("Paging Arrows", {
                    "When Action Bar 1's paging arrows show.",
                    "Never",
                    "Always",
                    "While Paged",
                    "Show Arrows on Right",
                    "Skip Visible Bars When Paging",
                    "Show While Paged",
                }, "MainBar")
            end
            local pagingRow
            for idx = 1, #slots, 2 do
                local r
                r, height =
                    W:DualRow(hostFrame, cursorY, slots[idx], slots[idx + 1] or CUI.BlankRowCfg())
                cursorY = cursorY - height
                pagingRow = pagingRow or r
            end
            BuildChecklist(pagingRow._leftRegion, pagingItems, PagingGet, PagingSet, PagingMenuClosed)

            if isMain then
                local rRgn = pagingRow._rightRegion
                local function RelayoutArrows()
                    if mod.LayoutPagingFrame then mod.LayoutPagingFrame() end
                end
                -- The cog's settings join the slot's capture, so the Spec
                -- Overrides gold walk marks the slot while one is overridden.
                CUI.BuildInlineCog(rRgn, {
                    title = "Paging Arrow Settings",
                    anchorTo = rRgn._control,
                    captureRegion = rRgn,
                    rows = {
                        {
                            type = "toggle",
                            label = "Show Arrows on Right",
                            get = function() return ReadSetting("pagingArrowsRight") or false end,
                            set = function(value)
                                WriteSetting("pagingArrowsRight", value, RelayoutArrows)
                                SUpdatePreviewAndResize()
                            end,
                            disabled = function() return ArrowsMode() == "never" end,
                            disabledTooltip = "Paging Arrows",
                        },
                        -- Never greyed: it also steers the next and previous
                        -- page keybinds.
                        {
                            type = "toggle",
                            label = "Skip Visible Bars When Paging",
                            tooltip = "Next and previous page, from the keybinds or the paging arrows, skip the pages your other enabled bars use.",
                            get = function() return ReadSetting("skipVisiblePagingBars") or false end,
                            set = function(value)
                                WriteSetting(
                                    "skipVisiblePagingBars",
                                    value,
                                    function() mod.RefreshPagingCycleMacros() end
                                )
                            end,
                        },
                    },
                })
            end
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  TEXT
    -------------------------------------------------------------------
    textSectionHeader, height = W:SectionHeader(hostFrame, SECTION_TEXT, cursorY)
    cursorY = cursorY - height

    -- Each row's left control turns its text on or off. While it is off, the
    -- right half greys out: the size slider, its offsets cog and its colour.
    local TextOff = {
        cooldown = function() return not GetCVarBool("countdownForCooldowns") end,
        -- Charge Numbers with nothing ticked.
        charges = function()
            local barCfg = SB()
            return (barCfg.hideChargeCount and barCfg.hideStackCount and barCfg.hideItemCount) and true
                or false
        end,
        keybind = function() return ReadSetting("hideKeybind") and true or false end,
        macro = function() return ReadSetting("hideMacroText") and true or false end,
    }

    -- A text's re-apply: the cooldown countdown has its own.
    local function ApplyFonts(keyName) ABAR:ApplyFontsForBar(keyName) end
    local function ApplyCooldownFonts(keyName) ABAR:ApplyCooldownFontsForBar(keyName) end
    -- A text cog's offset slider over key (-150 to 150).
    local function OffsetRow(label, key, apply)
        return {
            type = "slider",
            label = label,
            min = -150,
            max = 150,
            step = 1,
            get = function() return SettingOr(key, 0) end,
            set = function(value)
                WriteSetting(key, value, apply)
                SUpdatePreview()
            end,
        }
    end
    -- A text's colour swatch beside its size slider (white until set).
    local function TextColorSwatch(region, key, apply, off, offTip)
        CUI.BuildInlineSwatches(region, {
            {
                getValue = function()
                    local color = ReadSetting(key)
                    if not color then return 1, 1, 1 end
                    return color.r, color.g, color.b
                end,
                setValue = function(red, green, blue)
                    SSetColor(key, red, green, blue, nil, apply)
                    SUpdatePreview()
                end,
            },
        }, { disabled = off, disabledTooltip = offTip })
    end
    -- The offsets cog and colour of a button text (prefix count, keybind or
    -- macro): Position (the anchor; Default stored false, not nil, as profile
    -- sync copies only keys that exist; a new anchor seeds its offsets), then
    -- X and Y offsets, greyed with the text.
    local function TextCog(region, prefix, title, off, offTip)
        local ANCHOR, OX, OY = prefix .. "Anchor", prefix .. "OffsetX", prefix .. "OffsetY"
        CUI.BuildInlineCog(region, {
            title = title,
            disabled = off,
            disabledTooltip = offTip,
            rows = {
                {
                    type = "dropdown",
                    label = "Position",
                    values = TEXT_ANCHOR_LABELS,
                    order = TEXT_ANCHOR_DROPDOWN_ORDER,
                    get = function() return SettingOr(ANCHOR, "default") end,
                    set = function(value)
                        local anchor = value ~= "default" and value or nil
                        SSeedTextOffsets(prefix, ANCHOR, OX, OY, anchor)
                        WriteSetting(ANCHOR, anchor or false, ApplyFonts)
                        SUpdatePreview()
                    end,
                },
                OffsetRow("X Offset", OX, ApplyFonts),
                OffsetRow("Y Offset", OY, ApplyFonts),
            },
        })
        TextColorSwatch(region, prefix .. "FontColor", ApplyFonts, off, offTip)
    end

    -- Cooldown Numbers | Cooldown Text Size. Cooldown Numbers LIVE-toggles
    -- Blizzard's countdownForCooldowns CVar and is never stored in our DB;
    -- the CVar is written only on an actual user flip.
    local cdTextRow
    cdTextRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Cooldown Numbers",
        tooltip = "Toggles Blizzard's cooldown numbers setting.",
        getValue = function() return GetCVarBool("countdownForCooldowns") end,
        setValue = function(value)
            if InCombatLockdown() then return end
            CUI.SetCVar("countdownForCooldowns", value and "1" or "0", "CludesUIActionBars")
            -- Refresh so the cogs and the right half dim/undim with the CVar state.
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Cooldown Text Size",
        min = 6,
        max = 30,
        step = 1,
        trackWidth = 120,
        disabled = TextOff.cooldown,
        disabledTooltip = "Cooldown Numbers",
        getValue = function() return SettingOr("cooldownFontSize", 12) end,
        setValue = function(value)
            WriteSetting("cooldownFontSize", value, function(keyName) ABAR:ApplyCooldownFontsForBar(keyName) end)
            SUpdatePreview()
        end,
    })
    cursorY = cursorY - height
    -- Inline cog: Cooldown Numbers (left). Holds the charge-spell recharge toggle
    -- (our feature, DB-saved); dimmed when the CVar is off, since no numbers show then.
    do
        local region = cdTextRow._leftRegion
        CUI.BuildInlineCog(region, {
            title = "Cooldown Numbers",
            anchorTo = region._control,
            disabled = TextOff.cooldown,
            disabledTooltip = "Cooldown Numbers",
            rows = {
                {
                    type = "toggle",
                    label = "Charge Recharge Numbers",
                    tooltip = "Show the recharge countdown on charge spells while a charge is still banked. When off, the recharge timer only appears at 0 charges (Blizzard default).",
                    get = function() return ABAR.db.profile.showChargeRechargeNumbers ~= false end,
                    set = function(value)
                        ABAR.db.profile.showChargeRechargeNumbers = value
                        ABAR:RefreshChargeRechargeNumbers()
                    end,
                },
            },
        })
    end

    do
        local region = cdTextRow._rightRegion
        BarSync(region, "Apply Cooldown Text Settings to all Bars", function()
            local barCfg = SB()
            return {
                c = barCfg.cooldownTextColor,
                sz = barCfg.cooldownFontSize or 12,
                ox = barCfg.cooldownTextXOffset or 0,
                oy = barCfg.cooldownTextYOffset or 0,
                fit = barCfg.cooldownFontFit or false,
            }
        end, function(bar, value, key)
            local color = value.c
            if color then bar.cooldownTextColor = { r = color.r, g = color.g, b = color.b } end
            bar.cooldownFontSize = value.sz
            bar.cooldownTextXOffset = value.ox
            bar.cooldownTextYOffset = value.oy
            bar.cooldownFontFit = value.fit
            ABAR:ApplyCooldownFontsForBar(key)
        end, function(bar, value)
            if (bar.cooldownFontSize or 12) ~= value.sz or (bar.cooldownTextXOffset or 0) ~= value.ox then
                return false
            end
            if (bar.cooldownTextYOffset or 0) ~= value.oy or (bar.cooldownFontFit or false) ~= value.fit then
                return false
            end
            local color, bc = value.c, bar.cooldownTextColor
            return not color
                or (bc and bc.r == color.r and bc.g == color.g and bc.b == color.b) and true
                or false
        end)
    end

    do
        local region = cdTextRow._rightRegion
        CUI.BuildInlineCog(region, {
            title = "Cooldown Text",
            disabled = TextOff.cooldown,
            disabledTooltip = "Cooldown Numbers",
            rows = {
                OffsetRow("X Offset", "cooldownTextXOffset", ApplyCooldownFonts),
                OffsetRow("Y Offset", "cooldownTextYOffset", ApplyCooldownFonts),
                {
                    type = "toggle",
                    label = "Fit Size to Button",
                    tooltip = "Caps the countdown size so it cannot spill outside small buttons.",
                    get = function() return SettingOr("cooldownFontFit", false) end,
                    set = function(value)
                        WriteSetting(
                            "cooldownFontFit",
                            value and true or false,
                            function(keyName) ABAR:ApplyCooldownFontsForBar(keyName) end
                        )
                    end,
                },
            },
        })

        TextColorSwatch(region, "cooldownTextColor", ApplyCooldownFonts, TextOff.cooldown, "Cooldown Numbers")
    end

    -- Charge Numbers | Charge Text Size. Charge Numbers: which counts this
    -- bar's buttons show, each its own key (true hides that count; unset,
    -- the default, shows it).
    AddRowSearch(
        "Charge Numbers",
        { "Which counts show on this bar's buttons.", "Charges", "Stacks", "Item Count" }
    )
    AddRowSearch("Charge Text Size", { "Charges Text Size" })
    chargesRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ChecklistCfg("Charge Numbers", "Which counts show on this bar's buttons.", function()
            local barCfg = SB()
            local _ = barCfg.hideChargeCount
            _ = barCfg.hideStackCount
            _ = barCfg.hideItemCount
        end),
        {
            type = "slider",
            text = "Charge Text Size",
            min = 6,
            max = 30,
            step = 1,
            trackWidth = 120,
            disabled = TextOff.charges,
            disabledTooltip = "Charge Numbers",
            getValue = function() return SettingOr("countFontSize", 12) end,
            setValue = function(value)
                WriteSetting("countFontSize", value, function(keyName) ABAR:ApplyFontsForBar(keyName) end)
                SUpdatePreview()
            end,
        }
    )
    cursorY = cursorY - height
    BuildChecklist(chargesRow._leftRegion, {
        { key = "hideChargeCount", label = "Charges", tooltip = "The charges a spell has left." },
        {
            key = "hideStackCount",
            label = "Stacks",
            tooltip = "The count some spells show, such as stacks of a buff they spend.",
        },
        {
            key = "hideItemCount",
            label = "Item Count",
            tooltip = "How many of an item you carry, such as potions or a spell's reagent.",
        },
    }, function(keyName) return not ReadSetting(keyName) end, function(keyName, value)
        WriteSetting(keyName, (not value) and true or nil, function(bk) ABAR:RefreshCountVisibility(bk) end)
        SUpdatePreview()
    end)
    do
        local region = chargesRow._rightRegion
        TextSync(region, "Apply Charges Text Settings to all Bars", "count")
    end

    do
        local region = chargesRow._rightRegion
        TextCog(region, "count", "Charges Text Offsets", TextOff.charges, "Charge Numbers")
    end

    -- Keybind Text | Keybind Text Size
    AddRowSearch("Keybind Text", { "Hide Keybind Text" })
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Keybind Text",
        -- Shows the inverse of hideKeybind, the stored setting.
        getValue = function() return not ReadSetting("hideKeybind") end,
        setValue = function(value)
            WriteSetting("hideKeybind", not value, function(keyName) ABAR:ApplyFontsForBar(keyName) end)
            SUpdatePreview()
        end,
    }, {
        type = "slider",
        text = "Keybind Text Size",
        min = 6,
        max = 30,
        step = 1,
        trackWidth = 120,
        disabled = TextOff.keybind,
        disabledTooltip = "Keybind Text",
        getValue = function() return SettingOr("keybindFontSize", 12) end,
        setValue = function(value)
            WriteSetting("keybindFontSize", value, function(keyName) ABAR:ApplyFontsForBar(keyName) end)
            SUpdatePreview()
        end,
    })
    cursorY = cursorY - height
    keybindRow = row
    do
        local region = row._leftRegion
        BarSync(
            region,
            "Apply Keybind Visibility to all Bars",
            function() return SB().hideKeybind end,
            function(bar, value, key)
                bar.hideKeybind = value
                ABAR:ApplyFontsForBar(key)
            end,
            function(bar, value) return (bar.hideKeybind or false) == (value or false) end
        )
    end
    do
        local region = keybindRow._rightRegion
        TextSync(region, "Apply Keybind Text Settings to all Bars", "keybind")
    end

    do
        local region = keybindRow._rightRegion
        TextCog(region, "keybind", "Keybind Text Offsets", TextOff.keybind, "Keybind Text")
    end

    -- Macro Text | Macro Text Size
    AddRowSearch("Macro Text", { "Hide Macro Text" })
    local macroRow
    macroRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Macro Text",
        -- Shows the inverse of hideMacroText, the stored setting.
        getValue = function() return not ReadSetting("hideMacroText") end,
        setValue = function(value)
            WriteSetting("hideMacroText", not value, function(keyName) ABAR:ApplyFontsForBar(keyName) end)
            SUpdatePreview()
        end,
    }, {
        type = "slider",
        text = "Macro Text Size",
        min = 6,
        max = 30,
        step = 1,
        trackWidth = 120,
        disabled = TextOff.macro,
        disabledTooltip = "Macro Text",
        getValue = function() return SettingOr("macroFontSize", 12) end,
        setValue = function(value)
            WriteSetting("macroFontSize", value, function(keyName) ABAR:ApplyFontsForBar(keyName) end)
            SUpdatePreview()
        end,
    })
    cursorY = cursorY - height
    do
        local region = macroRow._leftRegion
        BarSync(
            region,
            "Apply Macro Text Visibility to all Bars",
            function() return SB().hideMacroText end,
            function(bar, value, key)
                bar.hideMacroText = value
                ABAR:ApplyFontsForBar(key)
            end,
            function(bar, value) return (bar.hideMacroText or false) == (value or false) end
        )
    end
    do
        local region = macroRow._rightRegion
        TextSync(region, "Apply Macro Text Settings to all Bars", "macro")
    end

    do
        local region = macroRow._rightRegion
        TextCog(region, "macro", "Macro Text Offsets", TextOff.macro, "Macro Text")
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildBarAppearance = BuildBarAppearance
