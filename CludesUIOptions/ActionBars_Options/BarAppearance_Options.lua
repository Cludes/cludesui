if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\BarAppearance_Options.lua
--  Action Bars options: the Appearance, Effects, Behavior (and Paging) and
--  Text sections of the Bar Display page. Called by BuildSharedBarSettings
--  for bars that are not visibility-only; returns y and the rows its click
--  navigation maps to. Shared helpers come from ns._ABO_OptEnv, the
--  per-build helpers from ctx.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIActionBars"]
if not mod then
    return
end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function BuildBarAppearance(hostFrame, posY, context)
    local environ = mod._ABO_OptEnv
    local ABAR, EndCapsCtl, GROUP_BAR_ORDER, InCombatLockdown, Pix =
        environ.EAB, environ.EndCapsCtl, environ.GROUP_BAR_ORDER, environ.InCombatLockdown, environ.PP
    local SB, SECTION_ICON_APPEARANCE, SECTION_TEXT, SelectedKey =
        environ.SB, environ.SECTION_ICON_APPEARANCE, environ.SECTION_TEXT, environ.SelectedKey
    local SHORT_LABELS, ShownBorderDefaults, TEXT_ANCHOR_DROPDOWN_ORDER, TEXT_ANCHOR_LABELS =
        environ.SHORT_LABELS,
        environ.ShownBorderDefaults,
        environ.TEXT_ANCHOR_DROPDOWN_ORDER,
        environ.TEXT_ANCHOR_LABELS
    local BgDisabled, SGet, SSeedTextOffsets, SSet =
        context.BgDisabled, context.SGet, context.SSeedTextOffsets, context.SSet
    local SSetColor, SUpdatePreview, SUpdatePreviewAndResize, SVal =
        context.SSetColor, context.SUpdatePreview, context.SUpdatePreviewAndResize, context.SVal
    local W = context.W
    local _, hgt
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
    local function BarSync(rgn, tooltip, read, copy, same, after)
        local function CopyTo(keys)
            local v = read()
            for _, key in ipairs(keys) do
                copy(ABAR.db.profile.bars[key], v, key)
            end
            if after then
                after()
            end
            CludesUI:RefreshPage()
        end
        CludesUI.BuildSyncIcon({
            region = rgn,
            tooltip = tooltip,
            onClick = function()
                CopyTo(GROUP_BAR_ORDER)
            end,
            isSynced = function()
                local v = read()
                for _, key in ipairs(GROUP_BAR_ORDER) do
                    if not same(ABAR.db.profile.bars[key], v, key) then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { rgn }
            end,
            multiApply = {
                elementKeys = GROUP_BAR_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function()
                    return SelectedKey()
                end,
                onApply = CopyTo,
            },
        })
    end

    -- The sync icon of a button text (prefix keybind, count or macro): its
    -- colour, size, X and Y offsets and anchor. A colour is copied only when
    -- the selected bar has one; an unset anchor is stored as false.
    local function TextSync(rgn, tooltip, prefix)
        local COLOR, SIZE = prefix .. "FontColor", prefix .. "FontSize"
        local OX, OY, ANCHOR = prefix .. "OffsetX", prefix .. "OffsetY", prefix .. "Anchor"
        BarSync(rgn, tooltip, function()
            local s = SB()
            return { c = s[COLOR], sz = s[SIZE] or 12, ox = s[OX] or 0, oy = s[OY] or 0, an = s[ANCHOR] }
        end, function(bar, v, key)
            local c = v.c
            if c then
                bar[COLOR] = { r = c.r, g = c.g, b = c.b }
            end
            bar[SIZE] = v.sz
            bar[OX] = v.ox
            bar[OY] = v.oy
            bar[ANCHOR] = v.an or false
            ABAR:ApplyFontsForBar(key)
        end, function(bar, v)
            if (bar[SIZE] or 12) ~= v.sz or (bar[OX] or 0) ~= v.ox or (bar[OY] or 0) ~= v.oy then
                return false
            end
            if (bar[ANCHOR] or nil) ~= (v.an or nil) then
                return false
            end
            local c, bc = v.c, bar[COLOR]
            return not c or (bc and bc.r == c.r and bc.g == c.g and bc.b == c.b) and true or false
        end)
    end

    -- A row whose items or cog hold settings with labels of their own (a
    -- checklist, a dropdown with a settings cog) registers its search entry
    -- right before the row, as the index keeps the first entry of a label:
    -- those labels, and the labels of the rows it stands in for, are the
    -- entry's search text. barKey (optional) is the bar a hit opens, in place
    -- of the bar being built.
    local function RowSearch(labelText, words, barId)
        if not CludesUI._RegisterSearchEntry then
            return
        end
        local textValue = {}
        for idx = 1, #words do
            local s = words[idx]
            textValue[#textValue + 1] = s
            local loc = CludesUI.L(s)
            if loc ~= s then
                textValue[#textValue + 1] = loc
            end
        end
        local labelLoc = CludesUI.L(labelText)
        local section = hostFrame._currentSection and hostFrame._currentSection._sectionName
        if type(section) ~= "string" then
            section = nil
        end
        local sel = CludesUI._buildingSelector
        local setter, selKey = sel and sel.setter, sel and sel.key
        if barId then
            setter, selKey = CludesUI._setActionBarKey, barId
        end
        CludesUI._RegisterSearchEntry(
            labelText,
            labelLoc ~= labelText and labelLoc or nil,
            table.concat(textValue, " "),
            CludesUI._buildingModule,
            CludesUI._buildingPage,
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
                if reads then
                    reads()
                end
                return "__placeholder"
            end,
            setValue = function() end,
        }
    end
    -- The checklist in `rgn` (a half built from ChecklistCfg). Spec Overrides
    -- see each click as it happens (the slot's capture); onMenuClosed runs
    -- each time its open menu hides. The search prebuild builds none.
    local function BuildChecklist(rgn, itemList, get, set, onMenuClosed)
        if CludesUI._prebuilding then
            return
        end
        if rgn._control then
            rgn._control:Hide()
        end
        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            170,
            rgn:GetFrameLevel() + 2,
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
        Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -------------------------------------------------------------------
    --  APPEARANCE
    -------------------------------------------------------------------
    iconsSectionHeader, hgt = W:SectionHeader(hostFrame, SECTION_ICON_APPEARANCE, posY)
    posY = posY - hgt
    posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "actionbars")

    -- Stock mode (Blizzard Style or Classic WoW UI): the shared gate.
    local function BlizzStyleOn()
        return CludesUI.BlizzStyle.Get("actionbars")
    end

    -- "No custom shape" also covers "cropped" and unset.
    local function ShapeIsNone()
        local v = SGet("buttonShape")
        return v == "none" or v == "cropped" or v == nil
    end
    local function ShapeIsCustom()
        return not ShapeIsNone()
    end

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
        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        -- Border Size: a custom shape's ring is on/off, so it keeps the None/Strong
        -- dropdown; every other shape gets the pixel slider over the same key and
        -- its borderThicknessPx companion. The shape setter rebuilds the page so the
        -- slot follows the shape; a bar switch already rebuilds.
        local sizeCfg
        if ShapeIsCustom() then
            sizeCfg = {
                type = "dropdown",
                text = "Border Size",
                disabled = BlizzStyleOn,
                disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
                requireState = "disabled",
                values = mod.BORDER_THICKNESS_LABELS,
                order = mod.BORDER_THICKNESS_ORDER,
                itemDisabled = function(val)
                    if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then
                        return true
                    end
                    return false
                end,
                itemDisabledTooltip = function(val)
                    if ShapeIsCustom() and (val == "thin" or val == "normal" or val == "heavy") then
                        return "This option requires a non-custom shape to be selected"
                    end
                end,
                getValue = function()
                    local v = SGet("borderThickness")
                    return v or "thin"
                end,
                setValue = function(v)
                    SSet("borderThickness", v, function(k)
                        local record = mod.BORDER_THICKNESS[v]
                        if record then
                            local shape = ABAR.db.profile.bars[k].buttonShape or "none"
                            if shape ~= "none" and shape ~= "cropped" then
                                ABAR.db.profile.bars[k].shapeBorderSize = record.shape
                                ABAR.db.profile.bars[k].shapeBorderEnabled = record.shape > 0
                            else
                                ABAR.db.profile.bars[k].borderSize = record.regular
                                ABAR.db.profile.bars[k].borderEnabled = record.regular > 0
                            end
                        end
                        ABAR:ApplyBordersForBar(k)
                        ABAR:ApplyShapesForBar(k)
                    end)
                    SUpdatePreview()
                end,
            }
        else
            sizeCfg = CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = BlizzStyleOn,
                disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
                requireState = "disabled",
                -- The step the buttons render with (ResolveBorderThickness's regular
                -- column): an unknown or numeric thickness is thin.
                getStep = function()
                    local record = mod.BORDER_THICKNESS[SGet("borderThickness") or "thin"]
                        or mod.BORDER_THICKNESS.thin
                    return record.regular
                end,
                -- Exactly what the dropdown wrote for a non-custom shape: the label and its mirrors.
                setStep = function(step)
                    local s = SB()
                    local labelText = CludesUI.BORDER_LABEL_OF_STEP[step]
                    s.borderThickness = labelText
                    local record = mod.BORDER_THICKNESS[labelText]
                    if record then
                        s.borderSize = record.regular
                        s.borderEnabled = record.regular > 0
                    end
                end,
                getTex = function()
                    return SGet("borderTexture") or "solid"
                end,
                getPx = function()
                    return SGet("borderThicknessPx")
                end,
                setPx = function(v)
                    SB().borderThicknessPx = v
                end,
                apply = function()
                    local k = SelectedKey()
                    ABAR:ApplyBordersForBar(k)
                    ABAR:ApplyShapesForBar(k)
                    CludesUI:RefreshPage()
                    SUpdatePreview()
                end,
            })
        end
        abBsRow, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("actionbars", {
                type = "dropdown",
                text = "Border Style",
                disabled = function()
                    return BlizzStyleOn() or ShapeIsCustom()
                end,
                disabledTooltip = function()
                    if ShapeIsCustom() then
                        return "This option requires a non-custom button shape"
                    end
                    return CludesUI.DisabledTooltip(CludesUI.BlizzStyle.Label("actionbars"), "disabled")
                end,
                rawTooltip = true,
                values = texValues,
                order = texOrder,
                getValue = function()
                    return SGet("borderTexture") or "solid"
                end,
                setValue = function(v)
                    local defTh = CludesUI.GetBorderDefaultSize("actionbars", v)
                    -- An unregistered SharedMedia border answers the NUMBER 1; this key stores labels.
                    if type(defTh) == "number" then
                        defTh = CludesUI.BORDER_LABEL_OF_STEP[defTh] or "thin"
                    end
                    SSet("borderTexture", v, function(k)
                        ABAR.db.profile.bars[k].borderTextureOffset = nil
                        ABAR.db.profile.bars[k].borderTextureOffsetY = nil
                        ABAR.db.profile.bars[k].borderTextureShiftX = nil
                        ABAR.db.profile.bars[k].borderTextureShiftY = nil
                        -- A style pick resets the size to the style's default: a set exact size goes with it (false travels, nil would not).
                        if ABAR.db.profile.bars[k].borderThicknessPx then
                            ABAR.db.profile.bars[k].borderThicknessPx = false
                        end
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(v)
                        ABAR.db.profile.bars[k].borderColor = { r = _bcol.r, g = _bcol.g, b = _bcol.b, a = 1 }
                        ABAR.db.profile.bars[k].borderClassColor = false
                        ABAR.db.profile.bars[k].borderBehind = _bbehind
                        if defTh then
                            ABAR.db.profile.bars[k].borderThickness = defTh
                            local record = mod.BORDER_THICKNESS[defTh]
                            if record then
                                local shape = ABAR.db.profile.bars[k].buttonShape or "none"
                                if shape ~= "none" and shape ~= "cropped" then
                                    ABAR.db.profile.bars[k].shapeBorderSize = record.shape
                                    ABAR.db.profile.bars[k].shapeBorderEnabled = record.shape > 0
                                else
                                    ABAR.db.profile.bars[k].borderSize = record.regular
                                    ABAR.db.profile.bars[k].borderEnabled = record.regular > 0
                                end
                            end
                        end
                        ABAR:ApplyBordersForBar(k)
                        ABAR:ApplyShapesForBar(k)
                    end)
                    SUpdatePreview()
                    -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                    CludesUI:RefreshPage(true)
                end,
            }),
            CludesUI.BlizzStyle.Gate("actionbars", sizeCfg)
        )
        posY = posY - hgt
        -- Width Offset | Height Offset: the textured border's outward offsets, their
        -- own row while a textured style is selected (Solid has none; the style
        -- setter rebuilds the page). Shown = the override, else the "actionbars"
        -- registry default for the step and thickness key ApplyBordersForBar and the
        -- shape repaint pass (ResolveBorderThickness), scaled to an exact size as drawn.
        do
            local btnTex = SGet("borderTexture") or "solid"
            if btnTex ~= "" and btnTex ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "actionbars",
                    disabled = BlizzStyleOn,
                    disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
                    requireState = "disabled",
                    getTex = function()
                        return SGet("borderTexture") or "solid"
                    end,
                    getStep = function()
                        return (mod.ResolveBorderThickness(SB()))
                    end,
                    getSizeKey = function()
                        return SGet("borderThickness") or "thin"
                    end,
                    getPx = function()
                        return SGet("borderThicknessPx")
                    end,
                    getX = function()
                        return SGet("borderTextureOffset")
                    end,
                    setX = function(v)
                        SB().borderTextureOffset = v
                    end,
                    getY = function()
                        return SGet("borderTextureOffsetY")
                    end,
                    setY = function(v)
                        SB().borderTextureOffsetY = v
                    end,
                    apply = function()
                        ABAR:ApplyBordersForBar(SelectedKey())
                        CludesUI:RefreshPage()
                        SUpdatePreview()
                    end,
                })
                _, hgt = W:DualRow(
                    hostFrame,
                    posY,
                    CludesUI.BlizzStyle.Gate("actionbars", ocfgL),
                    CludesUI.BlizzStyle.Gate("actionbars", ocfgR)
                )
                posY = posY - hgt
            end
        end
        do
            local rgn = abBsRow._leftRegion
            -- The offsets/shifts the buttons render with when none is set: the
            -- step's registry defaults (looked up as before), scaled to an exact
            -- size when one is set, as ApplyButtonBorders draws them.
            local function ButtonBorderDefaults()
                local tex = SGet("borderTexture") or "solid"
                local th = SGet("borderThickness") or "thin"
                local step, px = mod.ResolveBorderThickness(SB())
                return ShownBorderDefaults(tex, th, step, px)
            end
            local cogBtn = CludesUI.BuildInlineCog(rgn, {
                anchorTo = rgn._control,
                title = "Border Options",
                captureRegion = rgn,
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local v = SGet("borderTextureShiftX")
                            if v then
                                return v
                            end
                            local _, _, dsx = ButtonBorderDefaults()
                            return dsx
                        end,
                        set = function(v)
                            -- The shift shown by default stores nil (follow the style again).
                            local _, _, dsx = ButtonBorderDefaults()
                            if v == math.floor(dsx + 0.5) then
                                v = nil
                            end
                            SSet("borderTextureShiftX", v, function(k)
                                ABAR:ApplyBordersForBar(k)
                            end)
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
                            local v = SGet("borderTextureShiftY")
                            if v then
                                return v
                            end
                            local _, _, _, dsy = ButtonBorderDefaults()
                            return dsy
                        end,
                        set = function(v)
                            local _, _, _, dsy = ButtonBorderDefaults()
                            if v == math.floor(dsy + 0.5) then
                                v = nil
                            end
                            SSet("borderTextureShiftY", v, function(k)
                                ABAR:ApplyBordersForBar(k)
                            end)
                            SUpdatePreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            return SGet("borderBehind") or false
                        end,
                        set = function(v)
                            SSet("borderBehind", v == false and nil or v, function(k)
                                ABAR:ApplyBordersForBar(k)
                            end)
                            SUpdatePreview()
                            CludesUI:RefreshPage()
                        end,
                    },
                    -- The inverse of Show Behind, which wins: the runtime
                    -- ignores this flag while Show Behind is on.
                    {
                        type = "toggle",
                        label = "Border Above Effects",
                        tooltip = "Draws this bar's button borders over proc glows, the assisted highlight and the cooldown swipe.",
                        disabled = function()
                            return BlizzStyleOn()
                                or ShapeIsCustom()
                                or (SGet("borderBehind") and true or false)
                        end,
                        disabledTooltip = function()
                            if BlizzStyleOn() then
                                return CludesUI.DisabledTooltip(
                                    CludesUI.BlizzStyle.Label("actionbars"),
                                    "disabled"
                                )
                            end
                            if ShapeIsCustom() then
                                return "This option requires a non-custom button shape"
                            end
                            return CludesUI.DisabledTooltip("Show Behind", "disabled")
                        end,
                        rawTooltip = true,
                        get = function()
                            return SGet("borderAboveEffects") or false
                        end,
                        set = function(v)
                            SSet("borderAboveEffects", v and true or false, function(k)
                                ABAR:ApplyBordersForBar(k)
                            end)
                            SUpdatePreview()
                        end,
                    },
                },
            })
            if cogBtn then
                local function UpdateCogVis()
                    cogBtn:SetShown((SGet("borderTexture") or "solid") ~= "solid")
                end
                CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end
        local bsLeftRgn = abBsRow._leftRegion
        BarSync(bsLeftRgn, "Apply Border Style to all Bars", function()
            local s = SB()
            return {
                texture = s.borderTexture,
                ox = s.borderTextureOffset,
                oy = s.borderTextureOffsetY,
                sx = s.borderTextureShiftX,
                sy = s.borderTextureShiftY,
                behind = s.borderBehind,
                above = s.borderAboveEffects,
                color = s.borderColor,
                classColor = s.borderClassColor,
            }
        end, function(bar, v, key)
            bar.borderTexture = v.texture or "solid"
            bar.borderTextureOffset = v.ox
            bar.borderTextureOffsetY = v.oy
            bar.borderTextureShiftX = v.sx
            bar.borderTextureShiftY = v.sy
            bar.borderBehind = v.behind
            bar.borderAboveEffects = v.above
            local bc = v.color
            if bc then
                bar.borderColor = { r = bc.r, g = bc.g, b = bc.b, a = bc.a }
            end
            bar.borderClassColor = v.classColor
            ABAR:ApplyBordersForBar(key)
        end, function(bar, v)
            return (bar.borderTexture or "solid") == (v.texture or "solid")
                and bar.borderTextureOffset == v.ox
                and bar.borderTextureOffsetY == v.oy
                and bar.borderTextureShiftX == v.sx
                and bar.borderTextureShiftY == v.sy
                and (bar.borderBehind or false) == (v.behind or false)
                and (bar.borderAboveEffects or false) == (v.above or false)
        end)
    end

    do
        local rightRgn = abBsRow._rightRegion
        local ctrl = rightRgn._control

        local classBorderSwatch, updateClassBorderSwatch = CludesUI.BuildColorSwatch(
            rightRgn,
            abBsRow:GetFrameLevel() + 3,
            function()
                local _, ct = UnitClass("player")
                local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                if cc then
                    return cc.r, cc.g, cc.b
                end
                return 1, 1, 1
            end,
            function() end,
            false,
            20
        )
        Pix.Point(classBorderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        classBorderSwatch:SetScript("OnClick", function()
            SSet("borderClassColor", true, function(k)
                ABAR:ApplyBordersForBar(k)
                ABAR:ApplyShapesForBar(k)
            end)
            SUpdatePreview()
            CludesUI:RefreshPage()
        end)
        CludesUI.HoverTip(classBorderSwatch, "Class Colored")

        local customSwatch, updateCustomSwatch = CludesUI.BuildColorSwatch(
            rightRgn,
            abBsRow:GetFrameLevel() + 3,
            function()
                local c = SGet("borderColor")
                if not c then
                    return 0, 0, 0
                end
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                SSetColor("borderColor", r, g, b, nil, function(k)
                    ABAR:ApplyBordersForBar(k)
                    ABAR:ApplyShapesForBar(k)
                end)
                SSetColor("shapeBorderColor", r, g, b, nil, function(k)
                    ABAR:ApplyShapesForBar(k)
                end)
                SUpdatePreview()
            end,
            false,
            20
        )
        Pix.Point(customSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
        CludesUI.HoverTip(customSwatch, "Custom Color")

        -- Click the dimmed custom swatch to switch back from class color (no block overlay)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if SGet("borderClassColor") then
                SSet("borderClassColor", false, function(k)
                    ABAR:ApplyBordersForBar(k)
                    ABAR:ApplyShapesForBar(k)
                end)
                SUpdatePreview()
                CludesUI:RefreshPage()
                return
            end
            -- No border selected: allow swapping boxes but do not open the color picker
            if (SGet("borderThickness") or "thin") == "none" then
                return
            end
            if origClick then
                origClick(self, ...)
            end
        end)

        local function UpdateBorderSwatchState()
            local isClassColored = SGet("borderClassColor")
            local isNone = (SGet("borderThickness") or "thin") == "none"
            customSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
            classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
        end
        CludesUI.RegisterWidgetRefresh(function()
            updateCustomSwatch()
            updateClassBorderSwatch()
            UpdateBorderSwatchState()
        end)
        UpdateBorderSwatchState()
    end

    do
        local rgn = abBsRow._rightRegion
        BarSync(rgn, "Apply Border Size and Color to all Bars", function()
            local s = SB()
            -- borderThicknessPx is copied as is (string, false or nil).
            return {
                th = s.borderThickness,
                px = s.borderThicknessPx,
                c = s.borderColor,
                cc = s.borderClassColor,
            }
        end, function(bar, v, key)
            bar.borderThickness = v.th
            local px = v.px
            if px == nil and bar.borderThicknessPx ~= nil then
                px = false
            end
            bar.borderThicknessPx = px
            local record = mod.BORDER_THICKNESS[v.th]
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
            local c = v.c
            if c then
                bar.borderColor = { r = c.r, g = c.g, b = c.b, a = c.a }
                bar.shapeBorderColor = { r = c.r, g = c.g, b = c.b, a = c.a }
            end
            bar.borderClassColor = v.cc
            ABAR:ApplyBordersForBar(key)
            ABAR:ApplyShapesForBar(key)
        end, function(bar, v)
            -- nil and false render alike.
            if
                (bar.borderThickness or "thin") ~= (v.th or "thin")
                or (bar.borderThicknessPx or false) ~= (v.px or false)
            then
                return false
            end
            if (bar.borderClassColor or false) ~= (v.cc or false) then
                return false
            end
            local c, bc = v.c, bar.borderColor
            return (bc and bc.r or 0) == (c and c.r or 0)
                and (bc and bc.g or 0) == (c and c.g or 0)
                and (bc and bc.b or 0) == (c and c.b or 0)
                and (bc and bc.a or 1) == (c and c.a or 1)
        end)
    end

    local classColorBorderRow
    classColorBorderRow, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("actionbars", {
            type = "dropdown",
            text = "Custom Button Shape",
            disabled = BlizzStyleOn,
            disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            itemDisabled = function(val)
                if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then
                    return true
                end
                return false
            end,
            itemDisabledTooltip = function(val)
                if val ~= "none" and val ~= "cropped" and (SGet("borderTexture") or "solid") ~= "solid" then
                    return "This option requires the Border Style to be set to Solid"
                end
            end,
            getValue = function()
                local v = SGet("buttonShape")
                return v or "none"
            end,
            setValue = function(v)
                -- Set icon zoom BEFORE shapes: ApplyShapesForBar -> ApplyShapeToButton reads the new value.
                SSet("iconZoom", mod.SHAPE_ZOOM_DEFAULTS[v] or 5.5)
                SSet("buttonShape", v, function(k)
                    -- Reset border thickness to the default for the new shape mode
                    if v ~= "none" and v ~= "cropped" then
                        ABAR.db.profile.bars[k].borderThickness = mod.BORDER_THICKNESS_DEFAULT_SHAPE
                        local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_SHAPE]
                        ABAR.db.profile.bars[k].shapeBorderSize = record.shape
                        ABAR.db.profile.bars[k].shapeBorderEnabled = true
                    else
                        ABAR.db.profile.bars[k].borderThickness = mod.BORDER_THICKNESS_DEFAULT_REGULAR
                        local record = mod.BORDER_THICKNESS[mod.BORDER_THICKNESS_DEFAULT_REGULAR]
                        ABAR.db.profile.bars[k].borderSize = record.regular
                        ABAR.db.profile.bars[k].borderEnabled = true
                    end
                    -- Default keybind/count text for cropped vs normal (offsets keep a
                    -- positioned text's corner spacing)
                    if v == "cropped" then
                        ABAR.db.profile.bars[k].keybindFontSize = 11
                        ABAR.db.profile.bars[k].countFontSize = 11
                        ABAR.ApplyShapeTextOffsets(ABAR.db.profile.bars[k], 0, 1, 0, -1)
                    else
                        ABAR.db.profile.bars[k].keybindFontSize = 12
                        ABAR.db.profile.bars[k].countFontSize = 12
                        ABAR.ApplyShapeTextOffsets(ABAR.db.profile.bars[k], 0, 0, 0, 0)
                    end
                    ABAR:ApplyShapesForBar(k)
                    ABAR:ApplyPaddingForBar(k)
                    ABAR:ApplyBordersForBar(k)
                    ABAR:ApplyFontsForBar(k)
                    ABAR:ApplyIconBackgroundForBar(k)
                end)
                ABAR:RefreshProcGlows()
                SUpdatePreview()
                -- Full rebuild: the Border Size slot is a dropdown for a custom shape
                -- and the pixel slider otherwise, and only a rebuild swaps it.
                CludesUI:RefreshPage(true)
            end,
        }),
        CludesUI.BlizzStyle.Gate("actionbars", {
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 10,
            step = 0.5,
            disabled = BlizzStyleOn,
            disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            getValue = function()
                return SVal("iconZoom", ABAR.db.profile.iconZoom or 5.5)
            end,
            setValue = function(v)
                SSet("iconZoom", v, function(k)
                    ABAR:ApplyBordersForBar(k)
                    ABAR:ApplyShapesForBar(k)
                end)
                SUpdatePreview()
            end,
        })
    )
    posY = posY - hgt
    do
        local rgn = classColorBorderRow._leftRegion
        BarSync(rgn, "Apply Custom Button Shape to all Bars", function()
            return SGet("buttonShape") or "none"
        end, function(bs, v, key)
            bs.iconZoom = mod.SHAPE_ZOOM_DEFAULTS[v] or 5.5
            bs.buttonShape = v
            if v ~= "none" and v ~= "cropped" then
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
            if v == "cropped" then
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
        end, function(bar, v)
            return (bar.buttonShape or "none") == v
        end, function()
            ABAR:RefreshProcGlows()
            SUpdatePreview()
        end)
    end

    do
        local rgn = classColorBorderRow._rightRegion
        BarSync(rgn, "Apply Icon Zoom to all Bars", function()
            return SB().iconZoom or ABAR.db.profile.iconZoom or 5.5
        end, function(bar, v, key)
            bar.iconZoom = v
            ABAR:ApplyBordersForBar(key)
            ABAR:ApplyShapesForBar(key)
        end, function(bar, v)
            return (bar.iconZoom or ABAR.db.profile.iconZoom or 5.5) == v
        end)
    end

    -- Icon Background | Blizzard Icon Background
    local slotBgRow
    slotBgRow, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("actionbars", {
            type = "slider",
            text = "Icon Background",
            min = 0,
            max = 100,
            step = 1,
            disabled = BlizzStyleOn,
            disabledTooltip = CludesUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            getValue = function()
                local v = ABAR.db.profile.slotBgOpacity
                if v == nil then
                    v = 50
                end
                return v
            end,
            setValue = function(v)
                ABAR.db.profile.slotBgOpacity = v
                ABAR:ApplySlotBackgroundColor()
            end,
        }),
        {
            type = "toggle",
            text = "Blizzard Icon Background",
            tooltip = "Shows Blizzard's slot art on empty slots.",
            getValue = function()
                return ABAR.db.profile.showBlizzIconBg or false
            end,
            setValue = function(v)
                ABAR.db.profile.showBlizzIconBg = v
                for _, details in ipairs(mod.BAR_CONFIG or {}) do
                    ABAR:ApplyIconBackgroundForBar(details.key)
                end
                CludesUI:RefreshPage()
            end,
        }
    )
    posY = posY - hgt
    do
        local rgn = slotBgRow._rightRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Icon Background",
            anchorTo = rgn._control,
            disabled = function()
                return not (ABAR.db.profile.showBlizzIconBg or false)
            end,
            disabledTooltip = "Blizzard Icon Background",
            rows = {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    tooltip = "Controls the opacity of the Blizzard icon slot background texture.",
                    get = function()
                        return math.floor((ABAR.db.profile.blizzIconBgAlpha or 1) * 100 + 0.5)
                    end,
                    set = function(v)
                        ABAR.db.profile.blizzIconBgAlpha = v / 100
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
        local rgn = slotBgRow._leftRegion
        local function SbgOff()
            if BlizzStyleOn() then
                return true
            end
            local v = ABAR.db.profile.slotBgOpacity
            if v == nil then
                v = 50
            end
            return v == 0
        end
        local sbgSwatch, sbgUpdateSwatch = CludesUI.BuildColorSwatch(
            rgn,
            slotBgRow:GetFrameLevel() + 3,
            function()
                local c = ABAR.db.profile.slotBgColor or { r = 0.15, g = 0.15, b = 0.15 }
                return c.r, c.g, c.b, 1
            end,
            function(r, g, b)
                ABAR.db.profile.slotBgColor = { r = r, g = g, b = b }
                ABAR:ApplySlotBackgroundColor()
            end,
            false,
            20
        )
        Pix.Point(sbgSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
        rgn._lastInline = sbgSwatch
        sbgSwatch:SetAlpha(SbgOff() and 0.15 or 1)
        local sbgOrigClick = sbgSwatch:GetScript("OnClick")
        sbgSwatch:SetScript("OnClick", function(self, ...)
            if SbgOff() then
                return
            end
            if sbgOrigClick then
                sbgOrigClick(self, ...)
            end
        end)
        sbgSwatch:SetScript("OnEnter", function(self)
            if SbgOff() then
                if BlizzStyleOn() then
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.DisabledTooltip(CludesUI.BlizzStyle.Label("actionbars"), "disabled")
                    )
                else
                    CludesUI.ShowWidgetTooltip(self, CludesUI.DisabledTooltip("Set Icon Background above 0"))
                end
            end
        end)
        sbgSwatch:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        CludesUI.RegisterWidgetRefresh(function()
            sbgSwatch:SetAlpha(SbgOff() and 0.15 or 1)
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
                local v = SGet("bgPadding")
                if v ~= nil then
                    return v
                end
                return math.max(SVal("bgPadX", 0), SVal("bgPadY", 0))
            end,
            setValue = function(v)
                SB().bgPadX, SB().bgPadY = nil, nil
                SSet("bgPadding", v, function(k)
                    ABAR:ApplyBackgroundForBar(k)
                end)
                SUpdatePreview()
            end,
        }
    end
    local function BarBgSpacingSync(regionFrame)
        local function CurrentSpacing(prefs)
            if prefs.bgPadding ~= nil then
                return prefs.bgPadding
            end
            return math.max(prefs.bgPadX or 0, prefs.bgPadY or 0)
        end
        local function ApplySpacingTo(key)
            local target = ABAR.db.profile.bars[key]
            target.bgPadding = CurrentSpacing(SB())
            target.bgPadX = nil
            target.bgPadY = nil
            ABAR:ApplyBackgroundForBar(key)
        end
        BarSync(regionFrame, "Apply Bar Background Spacing to all Bars", function()
            return CurrentSpacing(SB())
        end, function(_, _, key)
            ApplySpacingTo(key)
        end, function(bar, spacing)
            return CurrentSpacing(bar) == spacing
        end)
    end

    -- Bar Background's other rows: Spacing last, unless it sits beside Bar
    -- Background (the WoW Forever look).
    local function BuildBarBackgroundRows(capsForever)
        local function BackgroundOpacity(prefs)
            if prefs.bgOpacity ~= nil then
                return prefs.bgOpacity
            end
            local color = prefs.bgColor
            return ((color and color.a) or 0.5) * 100
        end

        -- Section gate: these rows are built only while Bar Background is on for
        -- the selected bar (its SectionToggleSetValue rebuilds the page on a flip).
        if SVal("bgEnabled", false) then
            local bgColorRow
            bgColorRow, hgt = W:DualRow(hostFrame, posY, {
                type = "colorpicker",
                text = "Background Color",
                hasAlpha = false,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function()
                    local c = SGet("bgColor") or { r = 0, g = 0, b = 0, a = 0.5 }
                    return c.r, c.g, c.b, 1
                end,
                setValue = function(r, g, b)
                    local old = SGet("bgColor") or { a = 0.5 }
                    SSetColor("bgColor", r, g, b, old.a or 0.5, function(k)
                        ABAR:ApplyBackgroundForBar(k)
                    end)
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
                getValue = function()
                    return BackgroundOpacity(SB())
                end,
                setValue = function(v)
                    SSet("bgOpacity", v, function(k)
                        ABAR:ApplyBackgroundForBar(k)
                    end)
                    SUpdatePreview()
                end,
            })
            posY = posY - hgt

            do
                local regionFrame = bgColorRow._leftRegion
                local function ApplyColorTo(key)
                    local source = SGet("bgColor") or { r = 0, g = 0, b = 0, a = 0.5 }
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
                BarSync(regionFrame, "Apply Background Color to all Bars", function()
                    return SGet("bgColor") or { r = 0, g = 0, b = 0 }
                end, function(_, _, key)
                    ApplyColorTo(key)
                end, function(bar, color)
                    local target = bar.bgColor or { r = 0, g = 0, b = 0 }
                    return target.r == color.r and target.g == color.g and target.b == color.b
                end)
            end

            do
                local regionFrame = bgColorRow._rightRegion
                local function ApplyOpacityTo(key)
                    local target = ABAR.db.profile.bars[key]
                    target.bgOpacity = BackgroundOpacity(SB())
                    ABAR:ApplyBackgroundForBar(key)
                end
                BarSync(regionFrame, "Apply Background Opacity to all Bars", function()
                    return BackgroundOpacity(SB())
                end, function(_, _, key)
                    ApplyOpacityTo(key)
                end, function(bar, opacity)
                    return BackgroundOpacity(bar) == opacity
                end)
            end

            do
                local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
                local bgBorderRow
                bgBorderRow, hgt = W:DualRow(
                    hostFrame,
                    posY,
                    {
                        type = "dropdown",
                        text = "Background Border Style",
                        disabled = BgDisabled,
                        disabledTooltip = "Bar Background Border",
                        values = texValues,
                        order = texOrder,
                        getValue = function()
                            return SVal("bgBorderTexture", "solid")
                        end,
                        setValue = function(v)
                            local color, behind = CludesUI.GetBorderStyleSelectDefaults(v)
                            SSet("bgBorderTexture", v, function(k)
                                local prefs = ABAR.db.profile.bars[k]
                                prefs.bgBorderOffsetX = nil
                                prefs.bgBorderOffsetY = nil
                                prefs.bgBorderShiftX = nil
                                prefs.bgBorderShiftY = nil
                                -- A style pick resets the border: a set exact size goes with it (false travels, nil would not).
                                if prefs.bgBorderThicknessPx then
                                    prefs.bgBorderThicknessPx = false
                                end
                                prefs.bgBorderBehind = behind
                                prefs.bgBorderColor = { r = color.r, g = color.g, b = color.b, a = 1 }
                                ABAR:ApplyBackgroundForBar(k)
                            end)
                            SUpdatePreview()
                            -- Full rebuild: the Width/Height Offset row exists only for a textured style.
                            CludesUI:RefreshPage(true)
                        end,
                    },
                    CludesUI.BorderPxSliderCfg({
                        text = "Background Border Size",
                        disabled = BgDisabled,
                        disabledTooltip = "Bar Background Border",
                        -- The step ApplyBackgroundForBar renders with: a thickness with no
                        -- entry (unknown, or the number an old SharedMedia pick stored) is 0, hidden.
                        getStep = function()
                            local record = mod.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                            return record and record.regular or 0
                        end,
                        setStep = function(step)
                            SB().bgBorderThickness = CludesUI.BORDER_LABEL_OF_STEP[step]
                        end,
                        getTex = function()
                            return SVal("bgBorderTexture", "solid")
                        end,
                        getPx = function()
                            return SGet("bgBorderThicknessPx")
                        end,
                        setPx = function(v)
                            SB().bgBorderThicknessPx = v
                        end,
                        apply = function()
                            ABAR:ApplyBackgroundForBar(SelectedKey())
                            CludesUI:RefreshPage()
                            SUpdatePreview()
                        end,
                    })
                )
                posY = posY - hgt

                -- Background Border Width Offset | Height Offset: the textured border's
                -- outward offsets, their own row while a textured style is selected
                -- (Solid has none; the style setter rebuilds the page). Shown = the
                -- override, else the "actionbars" registry default for the thickness
                -- key ApplyBackgroundForBar passes.
                do
                    local bgTex = SVal("bgBorderTexture", "solid")
                    if bgTex ~= "" and bgTex ~= "solid" then
                        local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                            addonKey = "actionbars",
                            disabled = BgDisabled,
                            disabledTooltip = "Bar Background Border",
                            getTex = function()
                                return SVal("bgBorderTexture", "solid")
                            end,
                            getStep = function()
                                local record = mod.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                                return record and record.regular or 0
                            end,
                            getSizeKey = function()
                                return SVal("bgBorderThickness", "none")
                            end,
                            getPx = function()
                                return SGet("bgBorderThicknessPx")
                            end,
                            getX = function()
                                return SGet("bgBorderOffsetX")
                            end,
                            setX = function(v)
                                SB().bgBorderOffsetX = v
                            end,
                            getY = function()
                                return SGet("bgBorderOffsetY")
                            end,
                            setY = function(v)
                                SB().bgBorderOffsetY = v
                            end,
                            apply = function()
                                ABAR:ApplyBackgroundForBar(SelectedKey())
                                CludesUI:RefreshPage()
                                SUpdatePreview()
                            end,
                        })
                        ocfgL.text = "Background Border Width Offset"
                        ocfgR.text = "Background Border Height Offset"
                        _, hgt = W:DualRow(hostFrame, posY, ocfgL, ocfgR)
                        posY = posY - hgt
                    end
                end

                do
                    local regionFrame = bgBorderRow._rightRegion
                    local borderSwatch, refreshBorder = CludesUI.BuildColorSwatch(
                        regionFrame,
                        regionFrame:GetFrameLevel() + 5,
                        function()
                            local c = SGet("bgBorderColor") or { r = 0, g = 0, b = 0, a = 1 }
                            return c.r, c.g, c.b, c.a
                        end,
                        function(r, g, b, a)
                            SSetColor("bgBorderColor", r, g, b, a, function(k)
                                ABAR:ApplyBackgroundForBar(k)
                            end)
                            SUpdatePreview()
                        end,
                        true,
                        20
                    )
                    Pix.Point(borderSwatch, "RIGHT", regionFrame._control, "LEFT", -12, 0)
                    regionFrame._lastInline = borderSwatch
                    CludesUI.RegisterWidgetRefresh(function()
                        local disabled = BgDisabled() or SVal("bgBorderThickness", "none") == "none"
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
                            local v = source.bgBorderThicknessPx
                            if v == nil and target.bgBorderThicknessPx ~= nil then
                                v = false
                            end
                            target.bgBorderThicknessPx = v
                        end
                        local color = source.bgBorderColor
                        if color then
                            target.bgBorderColor = { r = color.r, g = color.g, b = color.b, a = color.a }
                        end
                        ABAR:ApplyBackgroundForBar(key)
                    end
                    BarSync(regionFrame, "Apply Background Border Size and Color to all Bars", function()
                        return {
                            th = SVal("bgBorderThickness", "none"),
                            px = SGet("bgBorderThicknessPx") or false, -- nil and false render alike
                            color = SGet("bgBorderColor") or { r = 0, g = 0, b = 0, a = 1 },
                        }
                    end, function(_, _, key)
                        ApplySizeTo(key)
                    end, function(target, v)
                        if
                            (target.bgBorderThickness or "none") ~= v.th
                            or (target.bgBorderThicknessPx or false) ~= v.px
                        then
                            return false
                        end
                        local tc, c = target.bgBorderColor or { r = 0, g = 0, b = 0, a = 1 }, v.color
                        return tc.r == c.r and tc.g == c.g and tc.b == c.b and tc.a == c.a
                    end)
                end

                do
                    local regionFrame = bgBorderRow._leftRegion
                    -- The offsets/shifts the background border renders with when none is
                    -- set: its registry defaults (looked up as before), scaled to an exact
                    -- size when one is set, as ApplyBackgroundForBar draws them.
                    local function BgBorderDefaults()
                        local texture = SVal("bgBorderTexture", "solid")
                        local thickness = SVal("bgBorderThickness", "thin")
                        local record = mod.BORDER_THICKNESS[SVal("bgBorderThickness", "none")]
                        local step = record and record.regular or 0
                        local px = CludesUI.BorderPx(SGet("bgBorderThicknessPx"), step, texture)
                        return ShownBorderDefaults(texture, thickness, step, px)
                    end
                    local offsetButton = CludesUI.BuildInlineCog(regionFrame, {
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
                                    local value = SGet("bgBorderShiftX")
                                    if value ~= nil then
                                        return value
                                    end
                                    local _, _, defaultX = BgBorderDefaults()
                                    return defaultX
                                end,
                                set = function(v)
                                    -- The shift shown by default stores nil (follow the style again).
                                    local _, _, defaultX = BgBorderDefaults()
                                    if v == math.floor(defaultX + 0.5) then
                                        v = nil
                                    end
                                    SSet("bgBorderShiftX", v, function(k)
                                        ABAR:ApplyBackgroundForBar(k)
                                    end)
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
                                    local value = SGet("bgBorderShiftY")
                                    if value ~= nil then
                                        return value
                                    end
                                    local _, _, _, defaultY = BgBorderDefaults()
                                    return defaultY
                                end,
                                set = function(v)
                                    local _, _, _, defaultY = BgBorderDefaults()
                                    if v == math.floor(defaultY + 0.5) then
                                        v = nil
                                    end
                                    SSet("bgBorderShiftY", v, function(k)
                                        ABAR:ApplyBackgroundForBar(k)
                                    end)
                                    SUpdatePreview()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show Behind",
                                get = function()
                                    return SVal("bgBorderBehind", false)
                                end,
                                set = function(v)
                                    SSet("bgBorderBehind", v, function(k)
                                        ABAR:ApplyBackgroundForBar(k)
                                    end)
                                    SUpdatePreview()
                                end,
                            },
                        },
                    })
                    if offsetButton then
                        local function UpdateOffsetButton()
                            offsetButton:SetShown(not BgDisabled())
                        end
                        CludesUI.RegisterWidgetRefresh(UpdateOffsetButton)
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
                    BarSync(regionFrame, "Apply Background Border Style to all Bars", SB, function(_, _, key)
                        ApplyStyleTo(key)
                    end, function(target, source)
                        return (target.bgBorderTexture or "solid") == (source.bgBorderTexture or "solid")
                            and target.bgBorderOffsetX == source.bgBorderOffsetX
                            and target.bgBorderOffsetY == source.bgBorderOffsetY
                            and target.bgBorderShiftX == source.bgBorderShiftX
                            and target.bgBorderShiftY == source.bgBorderShiftY
                            and (target.bgBorderBehind or false) == (source.bgBorderBehind or false)
                    end)
                end
            end

            local bgMultiplierRow
            bgMultiplierRow, hgt = W:DualRow(hostFrame, posY, {
                type = "slider",
                text = "Multiplier X",
                min = 1,
                max = 4,
                step = 1,
                disabled = BgDisabled,
                disabledTooltip = "Bar Background",
                getValue = function()
                    return SVal("bgMultiplierX", 1)
                end,
                setValue = function(v)
                    SSet("bgMultiplierX", v, function(k)
                        ABAR:ApplyBackgroundForBar(k)
                    end)
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
                getValue = function()
                    return SVal("bgMultiplierY", 1)
                end,
                setValue = function(v)
                    SSet("bgMultiplierY", v, function(k)
                        ABAR:ApplyBackgroundForBar(k)
                    end)
                    SUpdatePreviewAndResize()
                end,
            })
            posY = posY - hgt

            do
                local regionFrame = bgMultiplierRow._leftRegion
                CludesUI.BuildInlineCog(regionFrame, {
                    anchorTo = regionFrame._control,
                    title = "Multiplier X Settings",
                    captureRegion = regionFrame,
                    rows = {
                        {
                            type = "dropdown",
                            label = "Growth Direction",
                            values = { left = "Left", right = "Right" },
                            order = { "left", "right" },
                            get = function()
                                return SVal("bgExpandDirectionX", "right")
                            end,
                            set = function(v)
                                SSet("bgExpandDirectionX", v, function(k)
                                    ABAR:ApplyBackgroundForBar(k)
                                end)
                                SUpdatePreviewAndResize()
                            end,
                        },
                    },
                })
            end

            do
                local regionFrame = bgMultiplierRow._rightRegion
                CludesUI.BuildInlineCog(regionFrame, {
                    anchorTo = regionFrame._control,
                    title = "Multiplier Y Settings",
                    captureRegion = regionFrame,
                    rows = {
                        {
                            type = "dropdown",
                            label = "Growth Direction",
                            values = { up = "Up", down = "Down" },
                            order = { "up", "down" },
                            get = function()
                                return SVal("bgExpandDirectionY", "up")
                            end,
                            set = function(v)
                                SSet("bgExpandDirectionY", v, function(k)
                                    ABAR:ApplyBackgroundForBar(k)
                                end)
                                SUpdatePreviewAndResize()
                            end,
                        },
                    },
                })
            end

            if not capsForever then
                local spacingRow
                spacingRow, hgt = W:DualRow(hostFrame, posY, BarBgSpacingCfg(), CludesUI.BlankRowCfg())
                posY = posY - hgt
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
            vertical = function()
                return not ABAR:GetOrientationForBar(SelectedKey())
            end,
            write = function(k, v)
                if k then
                    SSet(k, v, function(bk)
                        ABAR:ApplyPaddingForBar(bk)
                    end)
                    SUpdatePreviewAndResize()
                else
                    ABAR:ApplyPaddingForBar(SelectedKey())
                    SUpdatePreviewAndResize()
                    CludesUI:RefreshPage()
                end
                if SelectedKey() == "MainBar" then
                    mod.AB_CapsSpanApply()
                end
            end,
            copyApply = function(key)
                ABAR:ApplyPaddingForBar(key)
                if key == "MainBar" then
                    mod.AB_CapsSpanApply()
                end
            end,
            syncKeys = GROUP_BAR_ORDER,
            syncLabels = SHORT_LABELS,
        })
        local bgCfg = {
            type = "toggle",
            text = "Bar Background",
            getValue = function()
                return SVal("bgEnabled", false)
            end,
            -- Section gate: its other rows are hidden (not grayed) while off; the wrapper forces the page rebuild.
            setValue = CludesUI.SectionToggleSetValue(function(v)
                SSet("bgEnabled", v, function(k)
                    ABAR:ApplyBackgroundForBar(k)
                end)
                SUpdatePreview()
            end),
        }
        local capsRow, bgRgn
        RowSearch("Bar Background", { "Enable Bar Background" })
        if CAPS.forever then
            RowSearch(
                "Bar Frame",
                { "Show the frame and dividers behind the bar's buttons.", "Show Bar Background" }
            )
            capsRow, hgt = W:DualRow(hostFrame, posY, CAPS.Cfg(), {
                type = "toggle",
                text = "Bar Frame",
                tooltip = "Show the frame and dividers behind the bar's buttons.",
                getValue = function()
                    return mod.AB_ForeverBg(SelectedKey())
                end,
                setValue = function(v)
                    SSet("foreverBarBg", v and true or false, function(k)
                        ABAR:ApplyPaddingForBar(k)
                    end)
                    SUpdatePreviewAndResize()
                end,
            })
            posY = posY - hgt
            CAPS.Build(capsRow._leftRegion)
            do
                local rgn = capsRow._rightRegion
                local function BgTo(key, v)
                    local d = ABAR.db.profile.bars[key]
                    if d then
                        d.foreverBarBg = v
                        ABAR:ApplyPaddingForBar(key)
                    end
                end
                BarSync(rgn, "Apply Bar Frame to all Bars", function()
                    return mod.AB_ForeverBg(SelectedKey())
                end, function(_, v, key)
                    BgTo(key, v)
                end, function(_, v, key)
                    return mod.AB_ForeverBg(key) == v
                end)
            end
            local bgOn = SVal("bgEnabled", false)
            local bgRow
            bgRow, hgt =
                W:DualRow(hostFrame, posY, bgCfg, bgOn and BarBgSpacingCfg() or CludesUI.BlankRowCfg())
            posY = posY - hgt
            bgRgn = bgRow._leftRegion
            if bgOn then
                BarBgSpacingSync(bgRow._rightRegion)
            end
        else
            capsRow, hgt = W:DualRow(hostFrame, posY, CAPS.Cfg(), bgCfg)
            posY = posY - hgt
            CAPS.Build(capsRow._leftRegion)
            bgRgn = capsRow._rightRegion
        end
        do
            local regionFrame = bgRgn
            BarSync(regionFrame, "Apply Bar Background Enable to all Bars", function()
                return SVal("bgEnabled", false)
            end, function(bar, enabled, key)
                bar.bgEnabled = enabled
                ABAR:ApplyBackgroundForBar(key)
            end, function(bar, enabled)
                return (bar.bgEnabled or false) == enabled
            end)
        end
        BuildBarBackgroundRows(CAPS.forever)
    end

    -------------------------------------------------------------------
    --  EFFECTS
    -------------------------------------------------------------------
    _, hgt = W:SectionHeader(hostFrame, "EFFECTS", posY)
    posY = posY - hgt

    -- Desaturate on Cooldown | Alpha on Cooldown
    RowSearch("Alpha on Cooldown", {
        "Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
        "Alpha when on CD",
    })
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Desaturate on Cooldown",
        -- setValue runs a one-shot catch-up sweep: cooldown repaints happen on edges only, so an icon grey at uncheck time would stay grey.
        tooltip = "Desaturates (grays out) action button icons while the ability is on cooldown. GCD-only cooldowns are excluded.",
        getValue = function()
            return ABAR.db.profile.desaturateOnCooldown or false
        end,
        setValue = function(v)
            local p = ABAR.db.profile
            local was = p.desaturateOnCooldown or false
            p.desaturateOnCooldown = v
            if was ~= (v or false) and ABAR._DesatSettingChanged then
                ABAR._DesatSettingChanged(v and true or false)
            end
        end,
    }, {
        type = "slider",
        text = "Alpha on Cooldown",
        min = 0,
        max = 100,
        step = 5,
        tooltip = "Dims action button icons to this opacity while on cooldown (100 = off), using the same detection as Desaturate on Cooldown.",
        getValue = function()
            return ABAR.db.profile.alphaWhenOnCD or 100
        end,
        setValue = function(v)
            ABAR.db.profile.alphaWhenOnCD = v
            if ABAR.ApplyCDAlphaAll then
                ABAR:ApplyCDAlphaAll()
            end
        end,
    })
    posY = posY - hgt

    -- Out of Range Coloring | Cooldown Swipe Opacity
    RowSearch("Cooldown Swipe Opacity", {
        "Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
        "CD Swipe Opacity",
    })
    local rangeSwipeRow
    rangeSwipeRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Out of Range Coloring",
        getValue = function()
            return SGet("outOfRangeColoring") or false
        end,
        setValue = function(v)
            SSet("outOfRangeColoring", v, function()
                ABAR:ApplyRangeColoring()
            end)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Cooldown Swipe Opacity",
        min = 0,
        max = 100,
        step = 5,
        trackWidth = 120,
        tooltip = "Opacity of the cooldown swipe (the dark radial sweep); use the swatch to set its colour.",
        getValue = function()
            return ABAR.db.profile.cdSwipeAlpha or 80
        end,
        setValue = function(v)
            ABAR.db.profile.cdSwipeAlpha = v
            if ABAR.ApplyCooldownSwipeColor then
                ABAR:ApplyCooldownSwipeColor()
            end
        end,
    })
    posY = posY - hgt
    do
        local rgn = rangeSwipeRow._leftRegion
        BarSync(rgn, "Apply Range Coloring to all Bars", function()
            local s = SB()
            return { on = s.outOfRangeColoring or false, color = s.outOfRangeColor }
        end, function(bar, v)
            bar.outOfRangeColoring = v.on
            local c = v.color
            if c then
                bar.outOfRangeColor = { r = c.r, g = c.g, b = c.b }
            end
        end, function(bar, v)
            return (bar.outOfRangeColoring or false) == v.on
        end, function()
            ABAR:ApplyRangeColoring()
        end)
    end
    do
        local leftRgn = rangeSwipeRow._leftRegion
        local rangeColorGet = function()
            local c = SGet("outOfRangeColor")
            if not c then
                return 0.7, 0.2, 0.2
            end
            return c.r, c.g, c.b
        end
        local rangeColorSet = function(r, g, b)
            SSetColor("outOfRangeColor", r, g, b, nil, function()
                ABAR:ApplyRangeColoring()
            end)
        end
        local rangeSwatch, rangeUpdateSwatch = CludesUI.BuildColorSwatch(
            leftRgn,
            leftRgn:GetFrameLevel() + 5,
            rangeColorGet,
            rangeColorSet,
            false,
            20
        )
        Pix.Point(rangeSwatch, "RIGHT", leftRgn._control, "LEFT", -12, 0)
        leftRgn._lastInline = rangeSwatch

        local function RangeDisabled()
            return not SGet("outOfRangeColoring")
        end

        CludesUI.RegisterWidgetRefresh(function()
            local off = RangeDisabled()
            rangeSwatch:SetAlpha(off and 0.3 or 1)
            rangeUpdateSwatch()
        end)
        rangeSwatch:SetAlpha(RangeDisabled() and 0.3 or 1)

        local rangeBlock = CreateFrame("Frame", nil, rangeSwatch)
        rangeBlock:SetAllPoints()
        rangeBlock:SetFrameLevel(rangeSwatch:GetFrameLevel() + 10)
        rangeBlock:EnableMouse(true)
        rangeBlock:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(rangeSwatch, CludesUI.DisabledTooltip("Out of Range Coloring"))
        end)
        rangeBlock:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        CludesUI.RegisterWidgetRefresh(function()
            rangeBlock:SetShown(RangeDisabled())
        end)
        rangeBlock:SetShown(RangeDisabled())
    end
    -- Inline swatch for Cooldown Swipe Opacity (right): colour-only (hasAlpha=false), since alpha lives on the slider.
    do
        local rgn = rangeSwipeRow._rightRegion
        local ctrl = rgn._control
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            rgn,
            rangeSwipeRow:GetFrameLevel() + 5,
            function()
                local c = ABAR.db.profile.cdSwipeColor or {}
                return c.r or 0, c.g or 0, c.b or 0
            end,
            function(r, g, b)
                ABAR.db.profile.cdSwipeColor = { r = r, g = g, b = b }
                if ABAR.ApplyCooldownSwipeColor then
                    ABAR:ApplyCooldownSwipeColor()
                end
            end,
            false,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        rgn._lastInline = colorSwatch
        -- Canonical inline-swatch pattern: auto-disable at 0 opacity (invisible swipe has no visible colour).
        local function SwipeDisabled()
            return (ABAR.db.profile.cdSwipeAlpha or 80) == 0
        end
        local block = CreateFrame("Frame", nil, colorSwatch)
        block:SetAllPoints()
        block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(
                colorSwatch,
                CludesUI.DisabledTooltip("Set Cooldown Swipe Opacity above 0")
            )
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        CludesUI.RegisterWidgetRefresh(function()
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
        RowSearch("Item Information", {
            "Item details shown on action buttons.",
            "Item Rank",
            "Equipped Item Color",
            "Show Item Rank",
            "Show Equipped Item Color",
        })
        local itemRow
        itemRow, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "toggle",
                text = "Hide Charge Count at 0",
                tooltip = "Hide the charge number on action buttons when it reaches 0, instead of showing a 0. The number returns as soon as a charge or item comes back.",
                getValue = function()
                    return ABAR.db.profile.hideZeroCount or false
                end,
                setValue = function(v)
                    ABAR.db.profile.hideZeroCount = v or nil
                    if ABAR.RefreshAllCounts then
                        ABAR:RefreshAllCounts()
                    end
                end,
            },
            ChecklistCfg("Item Information", "Item details shown on action buttons.", function()
                local _ = SB().showRankIcon
                _ = ABAR.db.profile.showEquippedBorder
            end)
        )
        posY = posY - hgt
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
                lockedFn = BlizzStyleOn,
                lockedTooltip = function()
                    return CludesUI.DisabledTooltip(CludesUI.BlizzStyle.Label("actionbars"), "disabled")
                end,
            },
        }, function(k)
            if k == "rank" then
                return SGet("showRankIcon") or false
            end
            return ABAR.db.profile.showEquippedBorder or false
        end, function(k, v)
            if k == "rank" then
                SSet("showRankIcon", v)
                if _G._CUAB_Apply then
                    _G._CUAB_Apply()
                end
            else
                ABAR.db.profile.showEquippedBorder = v and true or false
                ABAR:ApplyEquippedBorder()
            end
        end)
        -- The Apply link copies Item Rank alone: Equipped Item Color is one
        -- setting for every bar.
        do
            local rgn = itemRow._rightRegion
            BarSync(rgn, "Apply Item Rank to all Bars", function()
                return SB().showRankIcon or false
            end, function(bar, v)
                bar.showRankIcon = v
            end, function(bar, v)
                return (bar.showRankIcon or false) == v
            end, function()
                if _G._CUAB_Apply then
                    _G._CUAB_Apply()
                end
            end)
        end
    end

    -- One Button Assist Icon | blank
    local obaRow
    obaRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "One Button Assist Icon",
        getValue = function()
            return ABAR.db.profile.obaIconEnabled ~= false
        end,
        setValue = function(v)
            ABAR.db.profile.obaIconEnabled = v
            if mod.RefreshAssistSpinners then
                mod.RefreshAssistSpinners()
            end
        end,
    }, CludesUI.BlankRowCfg())
    posY = posY - hgt
    do
        local rgn = obaRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            anchorTo = rgn._control,
            title = "One Button Assist Icon",
            rows = {
                {
                    type = "slider",
                    label = "Icon Outset",
                    min = 0,
                    max = 30,
                    step = 1,
                    get = function()
                        return ABAR.db.profile.obaIconOutset or 9
                    end,
                    set = function(v)
                        ABAR.db.profile.obaIconOutset = v
                        if mod.RefreshAssistSpinners then
                            mod.RefreshAssistSpinners()
                        end
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
            _, hgt = W:SectionHeader(hostFrame, "BEHAVIOR & PAGING", posY)
            posY = posY - hgt
        else
            _, hgt = W:SectionHeader(hostFrame, "BEHAVIOR", posY)
            posY = posY - hgt
        end

        -- Click Through | Disable Tooltips
        local behaviorRow
        behaviorRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Click Through",
            getValue = function()
                return SGet("clickThrough")
            end,
            setValue = function(v)
                SSet("clickThrough", v, function(k)
                    ABAR:ApplyClickThroughForBar(k)
                end)
                -- Its Apply link compares this toggle.
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Disable Tooltips",
            getValue = function()
                return SGet("disableTooltips") or false
            end,
            setValue = function(v)
                SSet("disableTooltips", v)
            end,
        })
        posY = posY - hgt
        do
            local rgn = behaviorRow._leftRegion
            BarSync(rgn, "Apply Click Through to all Bars", function()
                return SB().clickThrough or false
            end, function(bar, v, key)
                bar.clickThrough = v
                ABAR:ApplyClickThroughForBar(key)
            end, function(bar, v)
                return (bar.clickThrough or false) == v
            end)
        end
        do
            local rgn = behaviorRow._rightRegion
            BarSync(rgn, "Apply Disable Tooltips to all Bars", function()
                return SB().disableTooltips or false
            end, function(bar, v)
                bar.disableTooltips = v
            end, function(bar, v)
                return (bar.disableTooltips or false) == v
            end)
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
                local paging = SGet("paging")
                local v = paging and paging[stateId]
                return v and tostring(v) or "none"
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
                for _, v in pairs(bar.paging) do
                    if v then
                        anySet = true
                        break
                    end
                end
                if not anySet then
                    bar.paging = {}
                end
                if mod.RebuildBarPaging then
                    mod.RebuildBarPaging(selKey)
                end
            end

            local isMain = selKey == "MainBar"
            local function RebuildPaging(k)
                if mod.RebuildBarPaging then
                    mod.RebuildBarPaging(k)
                end
            end

            local function PagingDropdown(stateId, textValue)
                return {
                    type = "dropdown",
                    text = textValue,
                    values = pagingValues,
                    order = pagingOrder,
                    getValue = function()
                        return GetPagingVal(stateId)
                    end,
                    setValue = function(v)
                        SetPagingVal(stateId, v)
                    end,
                }
            end
            -- modTargetPaging, the switch both groups below follow while their
            -- own key is unset: until set, on while any of the five states
            -- holds a page.
            local function ModTargetOn()
                local v = SGet("modTargetPaging")
                if v ~= nil then
                    return v
                end
                local paging = SGet("paging")
                if paging then
                    for stateId in pairs(EAB_VT.MOD_TARGET_PAGING) do
                        if paging[stateId] then
                            return true
                        end
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
                if SGet("modTargetPaging") == false then
                    return false
                end
                local v = SGet(key)
                if v == nil then
                    v = ModTargetOn()
                end
                return v and true or false
            end
            local function ModifierOn()
                return GroupOn("modifierPaging")
            end
            local function TargetOn()
                return GroupOn("targetPaging")
            end
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
                if not CludesUI.IS_FOREVER then
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
                form = function()
                    return not SGet("disableFormPaging")
                end,
                skyriding = function()
                    return not SGet("disableSkyridingPaging")
                end,
                modifier = ModifierOn,
                target = TargetOn,
            }
            local function PagingGet(k)
                return (PAGING_GET[k] or TargetOn)()
            end
            -- Writing one group's key first settles the other group's key to
            -- what it shows. Under modTargetPaging false (both held off),
            -- ticking a group clears it and the other group keeps its off.
            -- While both the other key and modTargetPaging are unset, the other
            -- group falls back to the five states' pages, so a page picked for
            -- one group would otherwise check the other: it is pinned. The
            -- runtime pages that group exactly as before (the pin reads false
            -- only while none of the five states holds a page).
            local function PagingSet(k, v)
                if k == "form" then
                    SSet("disableFormPaging", not v, RebuildPaging)
                elseif k == "skyriding" then
                    SSet("disableSkyridingPaging", not v, RebuildPaging)
                else
                    local s = SB()
                    local mine = (k == "modifier") and "modifierPaging" or "targetPaging"
                    local other = (k == "modifier") and "targetPaging" or "modifierPaging"
                    if s.modTargetPaging == false then
                        if v then
                            s.modTargetPaging = nil
                            s[other] = false
                        end
                    elseif s[other] == nil and s.modTargetPaging == nil then
                        if k == "modifier" then
                            s[other] = TargetOn()
                        else
                            s[other] = ModifierOn()
                        end
                    end
                    SSet(mine, v and true or false, RebuildPaging)
                end
            end
            -- A group's dropdowns exist only while it is on: the page is built
            -- again once the menu closed, never while it is open.
            local function PagingMenuClosed()
                if ModifierOn() ~= modOn or TargetOn() ~= targetOn then
                    CludesUI:RefreshPage(true)
                end
            end

            -- Paging Arrows (Action Bar 1): a view over showPagingArrows
            -- (Always) and pagingArrowsWhilePaged (While Paged, the default;
            -- false with the arrows off is Never).
            local function ArrowsMode()
                if SGet("showPagingArrows") then
                    return "always"
                end
                if SGet("pagingArrowsWhilePaged") == false then
                    return "never"
                end
                return "paged"
            end

            -- The section's paging slots in order, paired into rows.
            local slots = {}
            slots[#slots + 1] = ChecklistCfg(
                "Paging Options",
                "What switches this bar to another page.",
                function()
                    local s = SB()
                    local _ = s.disableFormPaging
                    _ = s.disableSkyridingPaging
                    _ = s.modifierPaging
                    _ = s.targetPaging
                    _ = s.modTargetPaging
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
                    setValue = function(v)
                        local s = SB()
                        if v == "always" then
                            s.showPagingArrows = true
                        else
                            s.showPagingArrows = false
                            s.pagingArrowsWhilePaged = (v == "paged")
                        end
                        if mod.LayoutPagingFrame then
                            mod.LayoutPagingFrame()
                        end
                        SUpdatePreviewAndResize()
                        CludesUI:RefreshPage()
                    end,
                }
            end
            if modOn then
                slots[#slots + 1] = PagingDropdown("shift", "Shift Modifier")
                slots[#slots + 1] = PagingDropdown("ctrl", "Ctrl Modifier")
                slots[#slots + 1] = PagingDropdown("alt", "Alt Modifier")
            end
            if targetOn then
                slots[#slots + 1] = PagingDropdown("help", "Friendly Target")
                slots[#slots + 1] = PagingDropdown("harm", "Hostile Target")
            end
            -- Class form dropdowns
            local classStatesLocal = PG_STATES.class and PG_STATES.class[playerClass]
            if classStatesLocal then
                for _, st in ipairs(classStatesLocal) do
                    slots[#slots + 1] = PagingDropdown(st.id, st.label)
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
                if not CludesUI.IS_FOREVER then
                    words[#words + 1] = "Skyriding Paging"
                    words[#words + 1] = "Disable Skyriding Paging"
                end
                words[#words + 1] = "Modifier Paging"
                words[#words + 1] = "Target Paging"
                words[#words + 1] = "Modifier/Target Paging"
                RowSearch("Paging Options", words, "MainBar")
                RowSearch("Paging Arrows", {
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
                r, hgt = W:DualRow(hostFrame, posY, slots[idx], slots[idx + 1] or CludesUI.BlankRowCfg())
                posY = posY - hgt
                pagingRow = pagingRow or r
            end
            BuildChecklist(pagingRow._leftRegion, pagingItems, PagingGet, PagingSet, PagingMenuClosed)

            if isMain then
                local rRgn = pagingRow._rightRegion
                local function RelayoutArrows()
                    if mod.LayoutPagingFrame then
                        mod.LayoutPagingFrame()
                    end
                end
                -- The cog's settings join the slot's capture, so the Spec
                -- Overrides gold walk marks the slot while one is overridden.
                CludesUI.BuildInlineCog(rRgn, {
                    title = "Paging Arrow Settings",
                    anchorTo = rRgn._control,
                    captureRegion = rRgn,
                    rows = {
                        {
                            type = "toggle",
                            label = "Show Arrows on Right",
                            get = function()
                                return SGet("pagingArrowsRight") or false
                            end,
                            set = function(v)
                                SSet("pagingArrowsRight", v, RelayoutArrows)
                                SUpdatePreviewAndResize()
                            end,
                            disabled = function()
                                return ArrowsMode() == "never"
                            end,
                            disabledTooltip = "Paging Arrows",
                        },
                        -- Never greyed: it also steers the next and previous
                        -- page keybinds.
                        {
                            type = "toggle",
                            label = "Skip Visible Bars When Paging",
                            tooltip = "Next and previous page, from the keybinds or the paging arrows, skip the pages your other enabled bars use.",
                            get = function()
                                return SGet("skipVisiblePagingBars") or false
                            end,
                            set = function(v)
                                SSet("skipVisiblePagingBars", v, function()
                                    mod.RefreshPagingCycleMacros()
                                end)
                            end,
                        },
                    },
                })
            end
        end
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    -------------------------------------------------------------------
    --  TEXT
    -------------------------------------------------------------------
    textSectionHeader, hgt = W:SectionHeader(hostFrame, SECTION_TEXT, posY)
    posY = posY - hgt

    -- Each row's left control turns its text on or off. While it is off, the
    -- right half greys out: the size slider, its offsets cog and its colour.
    local TextOff = {
        cooldown = function()
            return not GetCVarBool("countdownForCooldowns")
        end,
        -- Charge Numbers with nothing ticked.
        charges = function()
            local s = SB()
            return (s.hideChargeCount and s.hideStackCount and s.hideItemCount) and true or false
        end,
        keybind = function()
            return SGet("hideKeybind") and true or false
        end,
        macro = function()
            return SGet("hideMacroText") and true or false
        end,
    }

    -- A text's re-apply: the cooldown countdown has its own.
    local function ApplyFonts(k)
        ABAR:ApplyFontsForBar(k)
    end
    local function ApplyCooldownFonts(k)
        ABAR:ApplyCooldownFontsForBar(k)
    end
    -- A text cog's offset slider over key (-150 to 150).
    local function OffsetRow(label, key, apply)
        return {
            type = "slider",
            label = label,
            min = -150,
            max = 150,
            step = 1,
            get = function()
                return SVal(key, 0)
            end,
            set = function(v)
                SSet(key, v, apply)
                SUpdatePreview()
            end,
        }
    end
    -- A text's colour swatch beside its size slider (white until set).
    local function TextColorSwatch(rgn, key, apply, off, offTip)
        CludesUI.BuildInlineSwatches(rgn, {
            {
                getValue = function()
                    local c = SGet(key)
                    if not c then
                        return 1, 1, 1
                    end
                    return c.r, c.g, c.b
                end,
                setValue = function(r, g, b)
                    SSetColor(key, r, g, b, nil, apply)
                    SUpdatePreview()
                end,
            },
        }, { disabled = off, disabledTooltip = offTip })
    end
    -- The offsets cog and colour of a button text (prefix count, keybind or
    -- macro): Position (the anchor; Default stored false, not nil, as profile
    -- sync copies only keys that exist; a new anchor seeds its offsets), then
    -- X and Y offsets, greyed with the text.
    local function TextCog(rgn, prefix, title, off, offTip)
        local ANCHOR, OX, OY = prefix .. "Anchor", prefix .. "OffsetX", prefix .. "OffsetY"
        CludesUI.BuildInlineCog(rgn, {
            title = title,
            disabled = off,
            disabledTooltip = offTip,
            rows = {
                {
                    type = "dropdown",
                    label = "Position",
                    values = TEXT_ANCHOR_LABELS,
                    order = TEXT_ANCHOR_DROPDOWN_ORDER,
                    get = function()
                        return SVal(ANCHOR, "default")
                    end,
                    set = function(v)
                        local anchor = v ~= "default" and v or nil
                        SSeedTextOffsets(prefix, ANCHOR, OX, OY, anchor)
                        SSet(ANCHOR, anchor or false, ApplyFonts)
                        SUpdatePreview()
                    end,
                },
                OffsetRow("X Offset", OX, ApplyFonts),
                OffsetRow("Y Offset", OY, ApplyFonts),
            },
        })
        TextColorSwatch(rgn, prefix .. "FontColor", ApplyFonts, off, offTip)
    end

    -- Cooldown Numbers | Cooldown Text Size. Cooldown Numbers LIVE-toggles
    -- Blizzard's countdownForCooldowns CVar and is never stored in our DB;
    -- the CVar is written only on an actual user flip.
    local cdTextRow
    cdTextRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Cooldown Numbers",
        tooltip = "Toggles Blizzard's cooldown numbers setting.",
        getValue = function()
            return GetCVarBool("countdownForCooldowns")
        end,
        setValue = function(v)
            if InCombatLockdown() then
                return
            end
            CludesUI.SetCVar("countdownForCooldowns", v and "1" or "0", "CludesUIActionBars")
            -- Refresh so the cogs and the right half dim/undim with the CVar state.
            CludesUI:RefreshPage()
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
        getValue = function()
            return SVal("cooldownFontSize", 12)
        end,
        setValue = function(v)
            SSet("cooldownFontSize", v, function(k)
                ABAR:ApplyCooldownFontsForBar(k)
            end)
            SUpdatePreview()
        end,
    })
    posY = posY - hgt
    -- Inline cog: Cooldown Numbers (left). Holds the charge-spell recharge toggle
    -- (our feature, DB-saved); dimmed when the CVar is off, since no numbers show then.
    do
        local rgn = cdTextRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Cooldown Numbers",
            anchorTo = rgn._control,
            disabled = TextOff.cooldown,
            disabledTooltip = "Cooldown Numbers",
            rows = {
                {
                    type = "toggle",
                    label = "Charge Recharge Numbers",
                    tooltip = "Show the recharge countdown on charge spells while a charge is still banked. When off, the recharge timer only appears at 0 charges (Blizzard default).",
                    get = function()
                        return ABAR.db.profile.showChargeRechargeNumbers ~= false
                    end,
                    set = function(v)
                        ABAR.db.profile.showChargeRechargeNumbers = v
                        ABAR:RefreshChargeRechargeNumbers()
                    end,
                },
            },
        })
    end

    do
        local rgn = cdTextRow._rightRegion
        BarSync(rgn, "Apply Cooldown Text Settings to all Bars", function()
            local s = SB()
            return {
                c = s.cooldownTextColor,
                sz = s.cooldownFontSize or 12,
                ox = s.cooldownTextXOffset or 0,
                oy = s.cooldownTextYOffset or 0,
                fit = s.cooldownFontFit or false,
            }
        end, function(bar, v, key)
            local c = v.c
            if c then
                bar.cooldownTextColor = { r = c.r, g = c.g, b = c.b }
            end
            bar.cooldownFontSize = v.sz
            bar.cooldownTextXOffset = v.ox
            bar.cooldownTextYOffset = v.oy
            bar.cooldownFontFit = v.fit
            ABAR:ApplyCooldownFontsForBar(key)
        end, function(bar, v)
            if (bar.cooldownFontSize or 12) ~= v.sz or (bar.cooldownTextXOffset or 0) ~= v.ox then
                return false
            end
            if (bar.cooldownTextYOffset or 0) ~= v.oy or (bar.cooldownFontFit or false) ~= v.fit then
                return false
            end
            local c, bc = v.c, bar.cooldownTextColor
            return not c or (bc and bc.r == c.r and bc.g == c.g and bc.b == c.b) and true or false
        end)
    end

    do
        local rgn = cdTextRow._rightRegion
        CludesUI.BuildInlineCog(rgn, {
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
                    get = function()
                        return SVal("cooldownFontFit", false)
                    end,
                    set = function(v)
                        SSet("cooldownFontFit", v and true or false, function(k)
                            ABAR:ApplyCooldownFontsForBar(k)
                        end)
                    end,
                },
            },
        })

        TextColorSwatch(rgn, "cooldownTextColor", ApplyCooldownFonts, TextOff.cooldown, "Cooldown Numbers")
    end

    -- Charge Numbers | Charge Text Size. Charge Numbers: which counts this
    -- bar's buttons show, each its own key (true hides that count; unset,
    -- the default, shows it).
    RowSearch(
        "Charge Numbers",
        { "Which counts show on this bar's buttons.", "Charges", "Stacks", "Item Count" }
    )
    RowSearch("Charge Text Size", { "Charges Text Size" })
    chargesRow, hgt = W:DualRow(
        hostFrame,
        posY,
        ChecklistCfg("Charge Numbers", "Which counts show on this bar's buttons.", function()
            local s = SB()
            local _ = s.hideChargeCount
            _ = s.hideStackCount
            _ = s.hideItemCount
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
            getValue = function()
                return SVal("countFontSize", 12)
            end,
            setValue = function(v)
                SSet("countFontSize", v, function(k)
                    ABAR:ApplyFontsForBar(k)
                end)
                SUpdatePreview()
            end,
        }
    )
    posY = posY - hgt
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
    }, function(k)
        return not SGet(k)
    end, function(k, v)
        SSet(k, (not v) and true or nil, function(bk)
            ABAR:RefreshCountVisibility(bk)
        end)
        SUpdatePreview()
    end)
    do
        local rgn = chargesRow._rightRegion
        TextSync(rgn, "Apply Charges Text Settings to all Bars", "count")
    end

    do
        local rgn = chargesRow._rightRegion
        TextCog(rgn, "count", "Charges Text Offsets", TextOff.charges, "Charge Numbers")
    end

    -- Keybind Text | Keybind Text Size
    RowSearch("Keybind Text", { "Hide Keybind Text" })
    row, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Keybind Text",
        -- Shows the inverse of hideKeybind, the stored setting.
        getValue = function()
            return not SGet("hideKeybind")
        end,
        setValue = function(v)
            SSet("hideKeybind", not v, function(k)
                ABAR:ApplyFontsForBar(k)
            end)
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
        getValue = function()
            return SVal("keybindFontSize", 12)
        end,
        setValue = function(v)
            SSet("keybindFontSize", v, function(k)
                ABAR:ApplyFontsForBar(k)
            end)
            SUpdatePreview()
        end,
    })
    posY = posY - hgt
    keybindRow = row
    do
        local rgn = row._leftRegion
        BarSync(rgn, "Apply Keybind Visibility to all Bars", function()
            return SB().hideKeybind
        end, function(bar, v, key)
            bar.hideKeybind = v
            ABAR:ApplyFontsForBar(key)
        end, function(bar, v)
            return (bar.hideKeybind or false) == (v or false)
        end)
    end
    do
        local rgn = keybindRow._rightRegion
        TextSync(rgn, "Apply Keybind Text Settings to all Bars", "keybind")
    end

    do
        local rgn = keybindRow._rightRegion
        TextCog(rgn, "keybind", "Keybind Text Offsets", TextOff.keybind, "Keybind Text")
    end

    -- Macro Text | Macro Text Size
    RowSearch("Macro Text", { "Hide Macro Text" })
    local macroRow
    macroRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Macro Text",
        -- Shows the inverse of hideMacroText, the stored setting.
        getValue = function()
            return not SGet("hideMacroText")
        end,
        setValue = function(v)
            SSet("hideMacroText", not v, function(k)
                ABAR:ApplyFontsForBar(k)
            end)
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
        getValue = function()
            return SVal("macroFontSize", 12)
        end,
        setValue = function(v)
            SSet("macroFontSize", v, function(k)
                ABAR:ApplyFontsForBar(k)
            end)
            SUpdatePreview()
        end,
    })
    posY = posY - hgt
    do
        local rgn = macroRow._leftRegion
        BarSync(rgn, "Apply Macro Text Visibility to all Bars", function()
            return SB().hideMacroText
        end, function(bar, v, key)
            bar.hideMacroText = v
            ABAR:ApplyFontsForBar(key)
        end, function(bar, v)
            return (bar.hideMacroText or false) == (v or false)
        end)
    end
    do
        local rgn = macroRow._rightRegion
        TextSync(rgn, "Apply Macro Text Settings to all Bars", "macro")
    end

    do
        local rgn = macroRow._rightRegion
        TextCog(rgn, "macro", "Macro Text Offsets", TextOff.macro, "Macro Text")
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt

    return posY, iconsSectionHeader, textSectionHeader, keybindRow, chargesRow, classColorBorderRow
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildBarAppearance = BuildBarAppearance
