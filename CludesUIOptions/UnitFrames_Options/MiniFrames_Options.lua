if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  UnitFrames_Options\MiniFrames_Options.lua
--  Unit Frames options: Mini Frames and Boss Frames builders. Definitions
--  only; the shared helpers come from ns._UFO_OptEnv (filled by
--  CUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIUnitFrames"]
if not mod then return end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept page go through the
-- options frame pool (CludesUI_FramePool.lua), which hands the next build
-- the previous build's frames reset to new; on any other parent it is the
-- plain CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame
-- The pool's other calls this file makes, read once here as CreateFrame is:
-- the page path never calls the pool through its public slot, which
-- another addon could replace.
local PoolIsIdle = CUI._Pool.IsIdle

---------------------------------------------------------------------------
--  Mini frame donor settings helper
--  Returns the settings table unitKey copies its look from (its Copy Look
--  From pick, else focus, target, player). Routed through the runtime
--  resolver so the options preview and the live frames can never disagree
--  about which frame is on screen to inherit from.
---------------------------------------------------------------------------
local function GetMiniDonorSettings(unitName)
    local environ = mod._UFO_OptEnv
    local saved = environ.db
    return mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitName) or saved.profile.player
end

-- The label of each mini frame's enable toggle (the row that opens its DISPLAY
-- section): the requirement its Move in Unlock Mode button names while that
-- toggle is off.
local MINI_ENABLE_LABELS = {
    targettarget = "Enable Target of Target",
    focustarget = "Enable Focus Target",
    pet = "Enable Pet Frame",
    boss = "Enable Boss Frames",
}

---------------------------------------------------------------------------
--  Shared mini frame settings builder
---------------------------------------------------------------------------
local function BuildMiniTextAndSize(
    W,
    hostFrame,
    posY,
    unitSettings,
    unitName,
    enableRow,
    afterSizeRow,
    options
)
    local environ = mod._UFO_OptEnv
    local AddDarkModeBlock, BuildBarTexDropdown, BuildInactiveNotice, Pix =
        environ.AddDarkModeBlock, environ.BuildBarTexDropdown, environ.BuildInactiveNotice, environ.PP
    local RegisterWidgetRefresh, ReloadAndUpdate, saved, healthTextOrder =
        environ.RegisterWidgetRefresh, environ.ReloadAndUpdate, environ.db, environ.healthTextOrder
    local healthTextOrderBoss, healthTextValues = environ.healthTextOrderBoss, environ.healthTextValues
    local TexBgRowCfg = environ.TexBgRowCfg
    local _, height
    options = options or {}

    -- Shorthand accessors for this mini frame's settings
    local function MGet(settingKey) return unitSettings[settingKey] end
    local function MSet(settingKey, val)
        unitSettings[settingKey] = val
        ReloadAndUpdate()
    end
    -- Row setters over MSet: the key written with the row's value.
    local function MSetRow(settingKey)
        return function(value) MSet(settingKey, value) end
    end
    local function UnitVal(settingKey, default)
        local value = unitSettings[settingKey]
        if value ~= nil then return value end
        return default
    end
    -- A row getter over MVal: the key's value, or the default given.
    local function MValRow(settingKey, default)
        return function() return UnitVal(settingKey, default) end
    end

    -- DISPLAY
    local headerFrame
    headerFrame, height = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - height
    -- The Move in Unlock Mode button on the frame's first section: its mover
    -- exists only for the CludesUI frame source, so the button explains
    -- itself while the frame is hidden (its enable toggle) or on Blizzard's frame.
    CUI.BuildSectionUnlockJump(headerFrame, {
        key = unitName,
        disabled = function() return mod.GetUnitFrameSource(unitName) ~= "cui" end,
        disabledTooltip = function()
            if mod.VisUnitDisabled(saved.profile, unitName) then return MINI_ENABLE_LABELS[unitName] end
            return "This option requires the CludesUI Frame Source."
        end,
    })
    posY = CUI.BlizzStyle.Note(hostFrame, posY, "unitframes")

    -- Enable row (passed in from each builder)
    local enableRowFrame
    if enableRow then
        enableRowFrame, height = enableRow(W, hostFrame, posY)
        posY = posY - height
    end

    -- If this unit isn't on the CludesUI frame, skip the (inapplicable)
    -- settings below and show a short notice instead.
    if enableRow and mod.GetUnitFrameSource(unitName) ~= "cui" then
        posY = BuildInactiveNotice(hostFrame, posY, mod.GetUnitFrameSource(unitName))
        return posY, headerFrame, nil, nil, nil, enableRowFrame
    end

    -- Bar Texture override. Mini frames inherit the main frames' donor texture
    -- (Copy Look From) by default; a specific pick here overrides it for
    -- this frame only. Lands as the last DISPLAY row: Row 2 for ToT/Focus Target/Pet, Row 3 for Boss.
    do
        local mtVals, mtOrder = BuildBarTexDropdown()
        table.insert(mtOrder, 1, "inherit")
        mtVals["inherit"] = "Inherit (Main Frames)"
        -- Menu item preview background for "Inherit" shows the donor texture.
        local mo = mtVals._menuOpts
        if mo then
            local baseBg = mo.background
            mo.background = function(settingKey)
                if settingKey == "inherit" then
                    local sourceUnit = GetMiniDonorSettings(unitName)
                    local dk = sourceUnit and sourceUnit.healthBarTexture
                    if dk == "inherit" then dk = nil end
                    dk = dk or saved.profile.healthBarTexture
                    return dk and (mod.healthBarTextures or {})[dk] or nil
                end
                return baseBg and baseBg(settingKey) or nil
            end
        end
        -- Boss frames get a "Hover Borders" control in the right slot (mirrors
        -- Raid Frames); the other mini frames leave that slot empty.
        local bossUnit = (unitName == "boss")
        local rightSlot
        if bossUnit then
            rightSlot = {
                type = "dropdown",
                text = "Hover Borders",
                values = { __placeholder = "All" },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            }
        else
            -- ToT / Focus Target / Pet: per-frame Strata override (same options as
            -- main frames' Frame Strata); inherits the global value until set
            -- (getter falls back to db.profile.frameStrata).
            local miniStrataValues = CUI.FRAME_STRATA_LABELS
            local miniStrataOrder = CUI.FRAME_STRATA_ORDER_BASE
            rightSlot = {
                type = "dropdown",
                text = "Strata",
                tooltip = "Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
                values = miniStrataValues,
                order = miniStrataOrder,
                getValue = function()
                    return unitSettings.frameStrata or saved.profile.frameStrata or "MEDIUM"
                end,
                setValue = function(value)
                    unitSettings.frameStrata = value
                    ReloadAndUpdate()
                end,
            }
        end
        local barTexRow
        barTexRow, height = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Bar Texture",
            values = mtVals,
            order = mtOrder,
            getValue = function()
                local value = unitSettings.healthBarTexture
                if value == nil then return "inherit" end
                return value
            end,
            setValue = function(value)
                if value == "inherit" then
                    unitSettings.healthBarTexture = nil
                else
                    unitSettings.healthBarTexture = value
                end
                ReloadAndUpdate()
            end,
        }, rightSlot)
        posY = posY - height
        -- Textured Background cog: while Bar Texture is Inherit the toggle
        -- follows the main frame and shows its value, greyed.
        if not CUI._prebuilding then
            CUI.BuildInlineCog(barTexRow._leftRegion, {
                title = "Texture Settings",
                rows = {
                    TexBgRowCfg(function() return unitSettings end, ReloadAndUpdate, unitName),
                },
            })
        end

        -- Boss Hover Borders: checkbox dropdown (Hover Border / Target Border,
        -- both default off) with inline color swatches. Enabling one recolors
        -- the boss frame's existing border to that color (hover > target).
        if bossUnit and not CUI._prebuilding then
            local Pix = CUI.PP
            local rightRegion = barTexRow._rightRegion
            if rightRegion._control then rightRegion._control:Hide() end
            local hbKeyMap = { hover = "bossHoverBorderEnabled", target = "bossTargetBorderEnabled" }
            local hbItems = {
                { key = "hover", label = "Hover Border" },
                { key = "target", label = "Target Border" },
            }
            local UpdateHBSwatchVis -- forward declare; assigned after swatches
            local checkDrop = CUI.BuildVisOptsCBDropdown(
                rightRegion,
                170,
                rightRegion:GetFrameLevel() + 2,
                hbItems,
                function(keyName) return unitSettings[hbKeyMap[keyName]] and true or false end,
                function(keyName, value)
                    unitSettings[hbKeyMap[keyName]] = value
                    ReloadAndUpdate()
                    if UpdateHBSwatchVis then UpdateHBSwatchVis() end
                end
            )
            CUI.PanelPP.Point(checkDrop, "RIGHT", rightRegion, "RIGHT", -20, 0)
            rightRegion._control = checkDrop
            rightRegion._lastInline = nil

            -- Inline swatches: Hover (nearest the dropdown), then Target to its left.
            local lvl = barTexRow:GetFrameLevel() + 3
            local hoverSwatch, updHover = CUI.BuildColorSwatch(rightRegion, lvl, function()
                local color = unitSettings.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
                return color.r, color.g, color.b, unitSettings.bossHoverBorderAlpha or 1
            end, function(red, green, blue, a)
                unitSettings.bossHoverBorderColor = { r = red, g = green, b = blue }
                unitSettings.bossHoverBorderAlpha = a
                ReloadAndUpdate()
            end, true, 20)
            hoverSwatch:SetPoint("RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
            rightRegion._lastInline = hoverSwatch
            CUI.HoverTip(hoverSwatch, "Hover")

            local targetSwatch, updTarget = CUI.BuildColorSwatch(rightRegion, lvl, function()
                local color = unitSettings.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
                return color.r, color.g, color.b, unitSettings.bossTargetBorderAlpha or 1
            end, function(red, green, blue, a)
                unitSettings.bossTargetBorderColor = { r = red, g = green, b = blue }
                unitSettings.bossTargetBorderAlpha = a
                ReloadAndUpdate()
            end, true, 20)
            targetSwatch:SetPoint("RIGHT", rightRegion._lastInline, "LEFT", -8, 0)
            rightRegion._lastInline = targetSwatch
            CUI.HoverTip(targetSwatch, "Target")

            -- Gray a swatch when its border state is off (still clickable so the
            -- color can be pre-set), matching the Raid Frames Hover Borders row.
            UpdateHBSwatchVis = function()
                hoverSwatch:SetAlpha(unitSettings.bossHoverBorderEnabled and 1 or 0.3)
                targetSwatch:SetAlpha(unitSettings.bossTargetBorderEnabled and 1 or 0.3)
            end
            CUI.RegisterWidgetRefresh(function()
                updHover()
                updTarget()
                UpdateHBSwatchVis()
            end)
            UpdateHBSwatchVis()
        end
    end

    -- Boss Border Style | Border Size (+ Width Offset | Height Offset for a
    -- textured style): the boss frames' own border, or the main frames'
    -- while the style reads Inherit. Full pairs, so Strata | Dark Mode below
    -- stays the section's last row.
    if unitName == "boss" then
        posY = posY - mod.UF_BossFrameBorderRows(W, hostFrame, posY, unitSettings, ReloadAndUpdate)
    end

    -- Dark Mode for this frame alone, as on the Main Frames page (unset follows the
    -- profile's). It feeds the Dark Mode override condition, so it rechecks it and is
    -- locked while such an override is edited.
    local darkCfg = {
        type = "toggle",
        text = "Dark Mode",
        tooltip = "Dark Mode for this frame. Global Settings > Colors switches every frame.",
        getValue = function() return mod.UF_DarkThemeOn(unitSettings) end,
        setValue = function(value)
            MSet("darkTheme", value)
            CUI.Conditions_Recheck()
            CUI:RefreshPage()
        end,
    }
    local function LockDark(region)
        if CUI._prebuilding then return end
        CUI.SpecOverrides_AttachEditLock(
            region,
            "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
            CUI.SpecOverrides_DarkCondEditActive
        )
    end

    -- DISPLAY bottom row for boss: the mini frames carry their Strata
    -- override in the Bar Texture row's right slot, which boss spends on
    -- Hover Borders, so boss gets its own row here. Without it nothing in
    -- the UI writes a boss strata at all -- the main frames' dropdown is
    -- per-frame and the profile-wide value is only the fallback.
    if unitName == "boss" then
        local bossStrataValues = CUI.FRAME_STRATA_LABELS
        local bossStrataOrder = CUI.FRAME_STRATA_ORDER_BASE
        local strataRow
        strataRow, height = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Strata",
            tooltip = "Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
            values = bossStrataValues,
            order = bossStrataOrder,
            getValue = function() return unitSettings.frameStrata or saved.profile.frameStrata or "MEDIUM" end,
            setValue = function(value)
                unitSettings.frameStrata = value
                ReloadAndUpdate()
            end,
        }, darkCfg)
        posY = posY - height
        LockDark(strataRow._rightRegion)
    end

    -- DISPLAY: per-frame Border Size override for ToT/Focus Target/Pet.
    -- Size only, no color/texture (those still inherit from main frames);
    -- borderSizeOverride nil = inherit donor size until set. Boss frames use
    -- their own Border Style | Border Size row above instead.
    if unitName ~= "boss" then
        _, height = W:DualRow(
            hostFrame,
            posY,
            CUI.BlizzStyle.Gate("unitframes", {
                type = "slider",
                text = "Border Size",
                min = 0,
                max = 4,
                step = 1,
                tooltip = "Overrides the border size from the main frames for this frame only. Border color and texture still follow the main frames.",
                getValue = function()
                    local sourceUnit = GetMiniDonorSettings(unitName)
                    return unitSettings.borderSizeOverride or (sourceUnit and sourceUnit.borderSize) or 1
                end,
                setValue = function(value)
                    unitSettings.borderSizeOverride = value
                    ReloadAndUpdate()
                end,
            }),
            {
                type = "toggle",
                text = "Show Highlight Border",
                tooltip = "Show the main frames' hover highlight border on this frame. Turn off so this frame never recolors on mouseover. No effect when Highlight is off in the main frames' Hover Borders.",
                getValue = function() return unitSettings.showHighlightBorder ~= false end,
                setValue = function(value) unitSettings.showHighlightBorder = value end,
            }
        )
        posY = posY - height
        local darkRow
        darkRow, height = W:DualRow(hostFrame, posY, darkCfg, CUI.BlankRowCfg())
        posY = posY - height
        LockDark(darkRow._leftRegion)
    end

    -- Optional extra rows after enable (e.g. portrait, cast icon, indicators)
    if afterSizeRow then posY = afterSizeRow(W, hostFrame, posY) end

    -- HEALTH BAR section
    local textHeader
    textHeader, height = W:SectionHeader(hostFrame, "HEALTH BAR", posY)
    posY = posY - height

    -- Row 1: Bar Height + Bar Width
    local sizeRow
    local mhDis, mhTip, mhRaw = CUI.MatchGuard(unitName, "Height")
    local mwDis, mwTip, mwRaw = CUI.MatchGuard(unitName, "Width")
    local rightSlot
    -- Vertical Fill wants tall, narrow bars: the Vertical Fill toggle rebuilds the page.
    local vertFill = unitSettings.healthVerticalFill == true
    if CUI.BlizzStyle.Get("unitframes") then
        -- Blizzard Style: the stock size is fixed, so the whole frame scales
        -- instead; the slider takes the gated width's slot (no blank slot).
        rightSlot = {
            type = "slider",
            text = "Frame Scale",
            min = 50,
            max = 200,
            step = 5,
            tooltip = "Scales the whole frame. Blizzard Style frames are the stock size, so this stands in for Bar Width and Health Bar Height.",
            getValue = function() return math.floor((unitSettings.blizzScale or 1) * 100 + 0.5) end,
            setValue = function(value)
                unitSettings.blizzScale = value / 100
                ReloadAndUpdate()
            end,
        }
    elseif options.hideBarWidth then
        rightSlot = { type = "label", text = "" }
    else
        rightSlot = CUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Bar Width",
            min = vertFill and 20 or 60,
            max = 300,
            step = 1,
            disabled = mwDis,
            disabledTooltip = mwTip,
            rawTooltip = mwRaw,
            getValue = function() return unitSettings.frameWidth end,
            setValue = function(value)
                unitSettings.frameWidth = value
                ReloadAndUpdate()
            end,
        })
    end
    sizeRow, height = W:DualRow(
        hostFrame,
        posY,
        CUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Health Bar Height",
            min = 10,
            max = vertFill and 400 or 100,
            step = 1,
            disabled = mhDis,
            disabledTooltip = mhTip,
            rawTooltip = mhRaw,
            getValue = function() return unitSettings.healthHeight end,
            setValue = function(value)
                unitSettings.healthHeight = value
                ReloadAndUpdate()
            end,
        }),
        rightSlot
    )
    posY = posY - height

    -- Row 2: Fill Color + Bar Background/Opacity. Boss frames present each as an
    -- opacity slider with inline class/custom swatches (mirroring Main Frames' Bar
    -- Background); other mini units keep the combined "Bar Color" multiSwatch + "Bar Opacity" slider.
    do
        local bossUnit = (unitName == "boss")

        local leftSlot2, rightSlot2
        if bossUnit then
            -- Fill Color = the health fill opacity (formerly "Fill Opacity")
            -- with the fill color swatches moved inline below.
            leftSlot2 = {
                type = "slider",
                text = "Fill Color",
                min = 0,
                max = 100,
                step = 1,
                disabled = function() return mod.UF_DarkThemeOn(unitSettings) end,
                disabledTooltip = "Dark Mode",
                requireState = "disabled",
                getValue = MValRow("healthBarOpacity", 90),
                setValue = MSetRow("healthBarOpacity"),
            }
            rightSlot2 = {
                type = "slider",
                text = "Bar Background",
                min = 0,
                max = 100,
                step = 1,
                getValue = MValRow("customBgAlpha", 100),
                setValue = MSetRow("customBgAlpha"),
            }
        else
            -- "Fill Color" picker: Custom Colored Fill + Class Colored Fill.
            -- Bar Background was split out to its own slider + swatch row below
            -- (still the same customBgColor / customBgAlpha variables).
            local fillSwatches = {
                {
                    tooltip = "Custom Colored Fill",
                    hasAlpha = false,
                    getValue = function()
                        local color = MGet("customFillColor")
                        if color then return color.r, color.g, color.b end
                        return 37 / 255, 193 / 255, 29 / 255
                    end,
                    setValue = function(red, green, blue)
                        unitSettings.customFillColor = { r = red, g = green, b = blue }
                        ReloadAndUpdate()
                    end,
                    onClick = function(self)
                        if UnitVal("healthClassColored", false) then
                            if MGet("customFillColor") == nil then
                                unitSettings.customFillColor = { r = 37 / 255, g = 193 / 255, b = 29 / 255 }
                            end
                            unitSettings.healthClassColored = false
                            ReloadAndUpdate()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function() return UnitVal("healthClassColored", false) and 0.3 or 1 end,
                },
                {
                    tooltip = "Class Colored Fill",
                    hasAlpha = false,
                    getValue = function()
                        local _, ct = UnitClass("player")
                        if ct and RAID_CLASS_COLORS[ct] then
                            local classColor = RAID_CLASS_COLORS[ct]
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        unitSettings.healthClassColored = true
                        ReloadAndUpdate()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function() return UnitVal("healthClassColored", false) and 1 or 0.3 end,
                },
            }
            leftSlot2 = { type = "multiSwatch", text = "Fill Color", swatches = fillSwatches }
            rightSlot2 = {
                type = "slider",
                text = "Fill Opacity",
                min = 0,
                max = 100,
                step = 1,
                disabled = function() return mod.UF_DarkThemeOn(unitSettings) end,
                disabledTooltip = "Dark Mode",
                requireState = "disabled",
                getValue = MValRow("healthBarOpacity", 90),
                setValue = MSetRow("healthBarOpacity"),
            }
        end

        local colorRow
        colorRow, height = W:DualRow(hostFrame, posY, leftSlot2, rightSlot2)
        posY = posY - height

        if bossUnit then
            -- Inline Custom + Class fill swatches on the Fill Color slider (left
            -- region); both toggle healthClassColored, the inactive one dims to 0.3.
            if not CUI._prebuilding then
                local region = colorRow._leftRegion
                mod.UFO_SwatchPair(region, {
                    store = function() return unitSettings end,
                    flag = "healthClassColored",
                    flagDefault = false,
                    autoGet = function()
                        local _, ct = UnitClass("player")
                        local classColor = ct and RAID_CLASS_COLORS[ct]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    autoTip = "Class Colored Fill",
                    colorKey = "customFillColor",
                    colorDefault = { r = 37 / 255, g = 193 / 255, b = 29 / 255 },
                    customTip = "Custom Colored Fill",
                    seed = true,
                    apply = ReloadAndUpdate,
                })
            end

            -- Inline Custom + Class background swatches on the Bar Background
            -- slider (right region); both toggle bgClassColored, inactive dims to 0.3.
            if not CUI._prebuilding then
                local region = colorRow._rightRegion
                mod.UFO_SwatchPair(region, {
                    store = function() return unitSettings end,
                    flag = "bgClassColored",
                    flagDefault = false,
                    autoGet = function()
                        local _, ct = UnitClass("player")
                        local classColor = ct and RAID_CLASS_COLORS[ct]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    autoTip = "Class Colored Background",
                    colorKey = "customBgColor",
                    colorDefault = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
                    customTip = "Custom Background Color",
                    apply = ReloadAndUpdate,
                })
            end
        end

        -- Dark Mode disables Fill Color controls (flat dark health bar ignores
        -- fill/background colors). Boss also blocks Bar Background so its swatches
        -- gray out like Main Frames; other mini units' Bar Opacity has its own disable handler.
        if not CUI._prebuilding then
            AddDarkModeBlock(colorRow._leftRegion, function() return unitSettings end)
            if bossUnit then AddDarkModeBlock(colorRow._rightRegion, function() return unitSettings end) end
        end
    end

    -- Mini frames pair Smooth Health Bars with Vertical Fill below;
    -- boss frames keep it beside Reverse Fill.
    local smoothBarsWidget = {
        type = "toggle",
        text = "Smooth Health Bars",
        getValue = MValRow("smoothBars", false),
        setValue = MSetRow("smoothBars"),
    }
    local reverseFillWidget = {
        type = "toggle",
        text = "Reverse Fill",
        getValue = function() return unitSettings.healthReverseFill end,
        setValue = function(value)
            unitSettings.healthReverseFill = value
            ReloadAndUpdate()
        end,
    }
    if unitName == "boss" then
        _, height = W:DualRow(hostFrame, posY, smoothBarsWidget, reverseFillWidget)
        posY = posY - height
    else
        -- Bar Background (opacity slider + inline color swatch) | Reverse Fill.
        -- Reuses the existing customBgAlpha (opacity) + customBgColor (color)
        -- variables -- same as the Boss frames and the runtime health bg, so
        -- no saved option changes.
        local bgRow
        bgRow, height = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = MValRow("customBgAlpha", 100),
            setValue = MSetRow("customBgAlpha"),
        }, reverseFillWidget)
        posY = posY - height
        -- inline bg colors - custom swatch + class swatch
        -- tot/focus use class for player, reaction for npc
        -- pet resolves to player's class color
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(bgRow._leftRegion, {
                {
                    tooltip = "Custom Background Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = MGet("customBgColor")
                        if color then return color.r, color.g, color.b end
                        return 17 / 255, 17 / 255, 17 / 255
                    end,
                    setValue = function(red, green, blue)
                        unitSettings.customBgColor = { r = red, g = green, b = blue }
                        ReloadAndUpdate()
                    end,
                    onClick = function(self)
                        if UnitVal("bgClassColored", false) then
                            unitSettings.bgClassColored = false
                            ReloadAndUpdate()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function() return UnitVal("bgClassColored", false) and 0.3 or 1 end,
                },
                {
                    tooltip = "Class Colored Background",
                    hasAlpha = false,
                    getValue = function()
                        local _, ct = UnitClass("player")
                        local classColor = ct and RAID_CLASS_COLORS[ct]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        unitSettings.bgClassColored = true
                        ReloadAndUpdate()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function() return UnitVal("bgClassColored", false) and 1 or 0.3 end,
                },
            })
        end
    end

    -- Vertical Fill swaps the fill AXIS (Reverse Fill above flips direction within
    -- it, so vertical+reverse fills top-to-bottom); own row since Reverse Fill's row is already full on both layouts.
    _, height = W:DualRow(
        hostFrame,
        posY,
        CUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Vertical Fill",
            tooltip = "Fill the health bar bottom-to-top instead of left-to-right. Reverse Fill flips it to top-to-bottom.",
            getValue = function() return unitSettings.healthVerticalFill end,
            setValue = function(value)
                unitSettings.healthVerticalFill = value
                ReloadAndUpdate()
                CUI:RefreshPage(true)
            end,
        }),
        unitName ~= "boss" and smoothBarsWidget or CUI.BlankRowCfg()
    )
    posY = posY - height

    -- Blizzard Style: the stock level number in the boss art's level circle
    -- (the small frames' stock art carries none), with its size and
    -- offsets on a cog. The row is the preview level text's click target
    -- (stashed on the page: the boss targets table reads it).
    if unitName == "boss" and CUI.BlizzStyle.Get("unitframes") then
        hostFrame._ufLevelRow, height = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Level",
            tooltip = "Shows the unit's level in the frame's level circle, as the default UI does.",
            getValue = function() return unitSettings.blizzShowLevel ~= false end,
            setValue = function(value)
                unitSettings.blizzShowLevel = value
                ReloadAndUpdate()
                CUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        posY = posY - height
        if not CUI._prebuilding then
            CUI.BuildInlineCog(hostFrame._ufLevelRow._leftRegion, {
                disabled = function() return unitSettings.blizzShowLevel == false end,
                disabledTooltip = "This option requires Show Level.",
                title = "Level Text Settings",
                rows = {
                    -- The size follows the name text until set here.
                    {
                        type = "slider",
                        label = "Size",
                        min = 8,
                        max = 100,
                        step = 1,
                        get = function()
                            return UnitVal(
                                "blizzLevelSize",
                                UnitVal("leftTextSize", unitSettings.textSize or 12)
                            )
                        end,
                        set = MSetRow("blizzLevelSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = MValRow("blizzLevelX", 0),
                        set = MSetRow("blizzLevelX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = MValRow("blizzLevelY", 0),
                        set = MSetRow("blizzLevelY"),
                    },
                    {
                        type = "toggle",
                        label = "Difficulty Color",
                        tooltip = "Colors an attackable unit's level by difficulty, as the default UI does.",
                        get = MValRow("blizzLevelDifficultyColor", true),
                        set = MSetRow("blizzLevelDifficultyColor"),
                    },
                },
            })
        end
    end

    -- Active text slots share the Main Frames list workflow. One slot: its
    -- content dropdown, and (once it shows something) a settings cog and the
    -- Custom / Class colour swatch pair. o: key, name, shown (the dropdown's
    -- caption, default name), default, order, clears (slots a unique content
    -- leaves), align (the boss Extra Text's Alignment row), reach (the offset
    -- sliders' range, default 100 x 60).
    local function TextSlot(o)
        local settingKey, default = o.key, o.default
        local contentKey = settingKey .. "Content"
        local classKey = settingKey .. "ClassColor"
        local function Content() return UnitVal(contentKey, default) end
        local function Off() return Content() == "none" end
        local function Slider(label, suffix, lo, hi, step, def)
            return {
                type = "slider",
                label = label,
                min = lo,
                max = hi,
                step = step,
                get = function()
                    return UnitVal(settingKey .. suffix, type(def) == "function" and def() or def)
                end,
                set = function(value) MSet(settingKey .. suffix, value) end,
            }
        end
        -- Separator and Prefix: pipes and outer spaces stripped.
        local function Clean(value)
            return (tostring(value or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end
        local xReach = o.reach or 100
        local yReach = o.reach or 60
        local rows = {}
        if o.align then
            rows[#rows + 1] = {
                type = "dropdown",
                label = "Alignment",
                values = { ["left"] = "Left", ["right"] = "Right", ["center"] = "Center" },
                order = { "left", "right", "center" },
                get = function() return UnitVal(settingKey .. "Align", "left") end,
                set = function(value) MSet(settingKey .. "Align", value) end,
            }
        end
        rows[#rows + 1] = Slider("Size", "Size", 8, 100, 1, function() return unitSettings.textSize or 12 end)
        rows[#rows + 1] = Slider("X Offset", "X", -xReach, xReach, 1, 0)
        rows[#rows + 1] = Slider("Y Offset", "Y", -yReach, yReach, 1, 0)
        rows[#rows + 1] = Slider("Width %", "WidthPct", 20, 200, 5, 100)
        -- The colour of the Name > Target / Target indicator: custom or class.
        local sepKey, sepClassKey = settingKey .. "TargetSepColor", settingKey .. "TargetSepClassColor"
        rows[#rows + 1] = {
            type = "multiswatch",
            label = "Indicator Color",
            disabled = function()
                local c = Content()
                return c ~= "nametotarget" and c ~= "targetname"
            end,
            disabledTooltip = "This option only applies when Name > Target or Target is selected.",
            swatches = {
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local color = UnitVal(sepKey, nil)
                        if type(color) == "table" then return color.r or 1, color.g or 1, color.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(red, green, blue) MSet(sepKey, { r = red, g = green, b = blue }) end,
                    onClick = function(self)
                        if UnitVal(sepClassKey, false) then
                            MSet(sepClassKey, false)
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function() return UnitVal(sepClassKey, false) and 0.3 or 1 end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = CUI.PlayerClassRGB,
                    setValue = function() end,
                    onClick = function() MSet(sepClassKey, true) end,
                    refreshAlpha = function() return UnitVal(sepClassKey, false) and 1 or 0.3 end,
                },
            },
        }
        rows[#rows + 1] = {
            type = "input",
            label = "Separator",
            inputWidth = 60,
            get = function() return UnitVal(settingKey .. "TargetSep", ">") end,
            set = function(value)
                value = Clean(value)
                MSet(settingKey .. "TargetSep", value ~= "" and value or ">")
            end,
            disabled = function() return Content() ~= "nametotarget" end,
            disabledTooltip = "This option only applies when Name > Target is selected.",
        }
        rows[#rows + 1] = {
            type = "input",
            label = "Prefix",
            inputWidth = 60,
            tooltip = "Text shown before the target's name.",
            get = function() return UnitVal(settingKey .. "TargetPrefix", "T:") end,
            -- Unlike Separator, empty is kept: no prefix.
            set = function(value) MSet(settingKey .. "TargetPrefix", Clean(value)) end,
            disabled = function() return Content() ~= "targetname" end,
            disabledTooltip = "This option only applies when Target is selected.",
        }
        local shown = o.shown or o.name
        return {
            key = settingKey,
            position = shown,
            default = default,
            cfg = {
                type = "dropdown",
                text = shown,
                values = healthTextValues,
                order = o.order,
                getValue = Content,
                -- A content only one slot may show leaves the slots that held it.
                setValue = function(value)
                    unitSettings[contentKey] = value
                    if o.clears and mod.UF_IsUniqueContent(value) then
                        for _, other in ipairs(o.clears) do
                            if unitSettings[other .. "Content"] == value then
                                unitSettings[other .. "Content"] = "none"
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CUI:RefreshPage(true)
                end,
            },
            decorate = function(region)
                if CUI._prebuilding then return end
                CUI.BuildInlineCog(region, {
                    disabled = Off,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = o.name .. " Settings",
                    rows = mod.UF_CoreTextRows(settingKey, default, UnitVal, MSet, rows),
                })
                -- Class, then Custom, left of the cog. Both are dead while the slot
                -- shows nothing; the one not in use dims.
                local classSw, classSwUp = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and CUI.GetClassColor(class)
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(classSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                classSw:SetScript("OnClick", function()
                    if Off() then return end
                    MSet(classKey, true)
                    CUI:RefreshPage()
                end)
                CUI.HoverTip(classSw, "Class Colored")
                local swatch, swUp = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        return UnitVal(settingKey .. "ColorR", 1),
                            UnitVal(settingKey .. "ColorG", 1),
                            UnitVal(settingKey .. "ColorB", 1)
                    end,
                    function(red, green, blue)
                        unitSettings[settingKey .. "ColorR"] = red
                        unitSettings[settingKey .. "ColorG"] = green
                        unitSettings[settingKey .. "ColorB"] = blue
                        ReloadAndUpdate()
                    end,
                    nil,
                    20
                )
                Pix.Point(swatch, "RIGHT", classSw, "LEFT", -8, 0)
                region._lastInline = swatch
                local stockClick = swatch:GetScript("OnClick")
                swatch:SetScript("OnClick", function(self, ...)
                    if Off() then return end
                    if UnitVal(classKey, false) then
                        MSet(classKey, false)
                        CUI:RefreshPage()
                        return
                    end
                    if stockClick then stockClick(self, ...) end
                end)
                CUI.HoverTip(swatch, "Custom Colored")
                local function Dim()
                    local isNone, isClass = Off(), UnitVal(classKey, false)
                    swatch:SetAlpha((isClass or isNone) and 0.3 or 1)
                    classSw:SetAlpha((isClass and not isNone) and 1 or 0.3)
                end
                RegisterWidgetRefresh(function()
                    swUp()
                    classSwUp()
                    Dim()
                end)
                Dim()
            end,
        }
    end
    local slotOrder = (unitName == "boss") and healthTextOrderBoss or healthTextOrder
    local textSlots = {
        TextSlot({
            key = "leftText",
            name = "Left Text",
            default = "name",
            order = slotOrder,
            clears = { "rightText", "centerText" },
        }),
        TextSlot({
            key = "rightText",
            name = "Right Text",
            default = "none",
            order = slotOrder,
            clears = { "leftText", "centerText" },
        }),
        TextSlot({ key = "centerText", name = "Center Text", default = "none", order = slotOrder }),
    }
    -- Boss frames add a full-length Extra Text with an Alignment of its own.
    if unitName == "boss" then
        textSlots[4] = TextSlot({
            key = "extraText",
            name = "Extra Text",
            shown = "Extra Text (full length)",
            default = "none",
            order = healthTextOrderBoss,
            align = true,
            reach = 300,
        })
    end
    local textRow
    posY, textRow = mod.UFO_BuildTextSlots(W, hostFrame, posY, {
        slots = textSlots,
        values = healthTextValues,
        contentOrder = textSlots[1].cfg.order,
        unit = unitName,
        page = unitName == "boss" and "Boss Frames" or "Mini Frames",
        db = function() return unitSettings end,
        liveDB = function() return saved.profile[unitName] end,
        apply = ReloadAndUpdate,
    })

    -- POWER BAR section (mini units with a power bar: boss, and the pet on WoW Forever).
    -- Fill always uses the unit's power color (powerPercentPowerColor default on);
    -- a height of 0 effectively hides the bar.
    if options.hasPowerBar then
        local powerHeader
        powerHeader, height = W:SectionHeader(hostFrame, "POWER BAR", posY)
        posY = posY - height

        -- Row 1: Power Bar Height (+ Reverse Fill cog) | Above Health Bar toggle
        local pwrRow1
        pwrRow1, height = W:DualRow(
            hostFrame,
            posY,
            -- Blizzard Style: the stock track fixes height and spot; the
            -- Reverse Fill cog on this slot keeps working (keepRow).
            CUI.BlizzStyle.Gate("unitframes", {
                type = "slider",
                text = "Power Bar Height",
                min = 0,
                max = 100,
                step = 1,
                getValue = MValRow("powerHeight", 6),
                setValue = MSetRow("powerHeight"),
            }, true),
            CUI.BlizzStyle.Gate("unitframes", {
                type = "toggle",
                text = "Above Health Bar",
                getValue = function() return UnitVal("powerPosition", "below") == "above" end,
                setValue = function(value) MSet("powerPosition", value and "above" or "below") end,
            })
        )
        posY = posY - height
        -- Expose the Power Bar Height row + POWER BAR header so the boss
        -- preview's power-bar click overlay can scroll here.
        hostFrame._powerHeaderFrame = powerHeader
        hostFrame._powerHeightRow = pwrRow1
        -- Reverse Fill cog on Power Bar Height (left) -- mirrors Main Frames.
        if not CUI._prebuilding then
            local region = pwrRow1._leftRegion
            CUI.BuildInlineCog(region, {
                title = "Power Bar Fill",
                rows = {
                    {
                        type = "toggle",
                        label = "Reverse Fill",
                        get = MValRow("powerReverseFill", false),
                        set = MSetRow("powerReverseFill"),
                    },
                },
            })
        end

        -- Row 2: Bar Background (opacity slider + power/custom bg swatches) |
        -- Fill Color (opacity slider + power/custom fill swatches). Mirrors the
        -- Main Frames power bar; the opacity sliders replace the old plain ones.
        local pwrRow2
        pwrRow2, height = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = MValRow("customPowerBgAlpha", 100),
            setValue = MSetRow("customPowerBgAlpha"),
        }, {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            getValue = MValRow("powerBarOpacity", 100),
            setValue = MSetRow("powerBarOpacity"),
        })
        posY = posY - height
        -- Inline Power Colored + Custom background swatches on Bar Background
        -- (left region); both toggle powerBgPowerColored, the inactive one
        -- dims to 0.3 (mirrors the Main Frames power Bar Background).
        if not CUI._prebuilding then
            local region = pwrRow2._leftRegion
            mod.UFO_SwatchPair(region, {
                store = function() return unitSettings end,
                flag = "powerBgPowerColored",
                flagDefault = false,
                autoGet = function()
                    local _, pToken = UnitPowerType("player")
                    local details = CUI.GetPowerColor(pToken or "MANA")
                    local f = CUI.GetPowerBgDarkenFactor()
                    return details.r * f, details.g * f, details.b * f
                end,
                autoTip = "Power Colored Background. Power colors can be adjusted in Global Settings -> Colors.",
                colorKey = "customPowerBgColor",
                colorDefault = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
                customTip = "Custom Background Color",
                apply = ReloadAndUpdate,
            })
        end
        -- Inline Power Colored + Custom fill swatches on Fill Color (right
        -- region); both toggle powerPercentPowerColor (default on = power
        -- colored), the inactive one dims to 0.3.
        if not CUI._prebuilding then
            local region = pwrRow2._rightRegion
            local fPwrGet = function()
                local _, pToken = UnitPowerType("player")
                local details = CUI.GetPowerColor(pToken or "MANA")
                return details.r, details.g, details.b
            end
            local powerSwatch, powerSwatchUpdate = CUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                fPwrGet,
                function() end,
                false,
                20
            )
            powerSwatch._eabOrigClick = powerSwatch:GetScript("OnClick")
            powerSwatch:SetScript("OnClick", function()
                unitSettings.powerPercentPowerColor = true
                ReloadAndUpdate()
                CUI:RefreshPage()
            end)
            powerSwatch:HookScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(
                        powerSwatch,
                        "Power Colored Fill. Power colors can be adjusted in Global Settings -> Colors."
                    )
                end
            )
            powerSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            Pix.Point(powerSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = powerSwatch
            RegisterWidgetRefresh(function()
                powerSwatchUpdate()
                powerSwatch:SetAlpha((UnitVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)
            end)
            powerSwatch:SetAlpha((UnitVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)

            local fGet = function()
                local color = MGet("customPowerFillColor")
                if color then return color.r, color.g, color.b end
                return 0, 0, 1
            end
            local fSet = function(red, green, blue)
                unitSettings.customPowerFillColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
            end
            local fillSwatch, fillSwatchUpdate =
                CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, fGet, fSet, false, 20)
            fillSwatch._eabOrigClick = fillSwatch:GetScript("OnClick")
            fillSwatch:SetScript("OnClick", function(self)
                if UnitVal("powerPercentPowerColor", true) ~= false then
                    unitSettings.powerPercentPowerColor = false
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end)
            fillSwatch:HookScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(fillSwatch, "Custom Colored Fill") end
            )
            fillSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            Pix.Point(fillSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = fillSwatch
            RegisterWidgetRefresh(function()
                fillSwatchUpdate()
                fillSwatch:SetAlpha((UnitVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
            end)
            fillSwatch:SetAlpha((UnitVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
        end

        -- Row 3: Power Text (format) + Text Position -- ported from Main Frames.
        -- Reads/writes the same per-unit keys; MSet -> ReloadAndUpdate live-updates
        -- the real boss frames AND the preview (runtime already supports boss).
        local pwrTextRow
        local function SetPowerTextFormat(value)
            unitSettings.powerTextFormat = value
            if value ~= "none" and UnitVal("powerPercentText", "none") == "none" then
                unitSettings.powerPercentText = "center"
            end
            if value == "none" then unitSettings.powerPercentText = "none" end
            ReloadAndUpdate()
            CUI:RefreshPage()
            -- The page stays, so the menu is rebuilt for Custom's pencil.
            mod.UFO_RefreshMenus(pwrTextRow and pwrTextRow._leftRegion)
        end
        pwrTextRow, height = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Power Text",
            values = mod.UFO_CustomTextValues({
                ["none"] = "None",
                ["smart"] = "Smart Text",
                ["curpp"] = "Power Value",
                ["perpp"] = "Power %",
                ["both"] = "Value | %",
            }, function() return UnitVal("powerTextFormat", "perpp") end, function()
                mod.UFO_EditCustomText(
                    "powerText",
                    unitSettings,
                    unitName,
                    function() SetPowerTextFormat("custom") end
                )
            end),
            -- WoW Forever lists no Smart Text (CludesUI.PowerTextFormat).
            order = CUI.PowerTextFormatOrder({
                "none",
                "---",
                "custom",
                "---",
                "smart",
                "curpp",
                "perpp",
                "both",
            }),
            getValue = function() return CUI.PowerTextFormat(UnitVal("powerTextFormat", "perpp")) end,
            setValue = SetPowerTextFormat,
        }, {
            type = "dropdown",
            text = "Text Position",
            values = { ["none"] = "None", ["left"] = "Left", ["right"] = "Right", ["center"] = "Center" },
            order = { "none", "---", "left", "right", "center" },
            getValue = MValRow("powerPercentText", "none"),
            setValue = function(value)
                MSet("powerPercentText", value)
                CUI:RefreshPage()
            end,
        })
        posY = posY - height
        -- Expose the power-text row so the preview's power-text click overlay
        -- can scroll here (mirrors parent._powerHeightRow / _powerHeaderFrame).
        hostFrame._powerTextRow = pwrTextRow
        if not CUI._prebuilding then
            mod.UFO_AddCustomFormatAccessor(
                pwrTextRow._leftRegion,
                "Power Text",
                "powerText",
                UnitVal("powerTextFormat", "perpp"),
                function() return unitSettings end,
                ReloadAndUpdate
            )
        end
        -- Show % cog on Power Text (left)
        if not CUI._prebuilding then
            local region = pwrTextRow._leftRegion
            CUI.BuildInlineCog(
                region,
                mod.UFO_PowerTextCog(
                    UnitVal,
                    MSet,
                    { none = true, curpp = true },
                    function(value) MSet("powerShowPercent", value) end
                )
            )
        end
        -- Inline Text Color swatches on Power Text (left): Custom + Power Colored,
        -- mutually exclusive (mirrors Main Frames' Text Color multiSwatch). Custom
        -- click: first clears power-colored (selecting custom), second opens the
        -- picker. Power-colored click: selects power-colored + clears custom.
        if not CUI._prebuilding then
            local region = pwrTextRow._leftRegion
            local customSw, customSwUp = CUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local color = MGet("powerTextColor")
                    if color then return color.r, color.g, color.b end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    unitSettings.powerTextColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                end,
                false,
                20
            )
            Pix.Point(customSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = customSw
            local customOrigClick = customSw:GetScript("OnClick")
            customSw:SetScript("OnClick", function(self, ...)
                if UnitVal("powerPercentTextPowerColor", false) then
                    unitSettings.powerPercentTextPowerColor = false
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                    return
                end
                if customOrigClick then customOrigClick(self, ...) end
            end)
            CUI.HoverTip(customSw, "Custom Text Color")
            local powerSw, powerSwUp = CUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local details = CUI.GetPowerColor(pToken or "MANA")
                    if details then return details.r, details.g, details.b end
                    return 1, 1, 1
                end,
                function() end,
                false,
                20
            )
            Pix.Point(powerSw, "RIGHT", customSw, "LEFT", -8, 0)
            region._lastInline = powerSw
            powerSw:SetScript("OnClick", function()
                unitSettings.powerPercentTextPowerColor = true
                unitSettings.powerTextColor = nil
                ReloadAndUpdate()
                CUI:RefreshPage()
            end)
            CUI.HoverTip(powerSw, "Power Colored Text")
            local function UpdSwatches()
                local isPower = UnitVal("powerPercentTextPowerColor", false)
                customSw:SetAlpha(isPower and 0.3 or 1)
                powerSw:SetAlpha(isPower and 1 or 0.3)
            end
            RegisterWidgetRefresh(function()
                customSwUp()
                powerSwUp()
                UpdSwatches()
            end)
            UpdSwatches()
        end
        -- Size + X/Y offsets cog on Text Position (right)
        if not CUI._prebuilding then
            local region = pwrTextRow._rightRegion
            CUI.BuildInlineCog(region, {
                disabled = function() return UnitVal("powerPercentText", "none") == "none" end,
                disabledTooltip = "This option requires a text position other than none.",
                title = "Text Position",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 100,
                        step = 1,
                        get = MValRow("powerPercentSize", 9),
                        set = MSetRow("powerPercentSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = MValRow("powerPercentX", 0),
                        set = MSetRow("powerPercentX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = MValRow("powerPercentY", 0),
                        set = MSetRow("powerPercentY"),
                    },
                },
            })
        end

        -- Power bar border size and color, matching Player/Target/Focus.
        local pwrBorderRow
        pwrBorderRow, height = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 4,
            step = 1,
            trackWidth = 120,
            getValue = MValRow("powerBorderSize", 0),
            setValue = MSetRow("powerBorderSize"),
        }, { type = "label", text = "" })
        posY = posY - height
        if not CUI._prebuilding then
            local region = pwrBorderRow._leftRegion
            local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                region,
                pwrBorderRow:GetFrameLevel() + 3,
                function()
                    local color = MGet("powerBorderColor") or { r = 0, g = 0, b = 0 }
                    return color.r, color.g, color.b, UnitVal("powerBorderAlpha", 1)
                end,
                function(red, green, blue, a)
                    unitSettings.powerBorderColor = { r = red, g = green, b = blue }
                    unitSettings.powerBorderAlpha = a
                    ReloadAndUpdate()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
            CUI.HoverTip(colorSwatch, "Border Color")
            region._lastInline = colorSwatch
            RegisterWidgetRefresh(updateSwatch)
        end
    end

    -- Extra section rendered at the very bottom, below the Power Bar (boss "Indicators").
    if options.afterPowerRow then posY = options.afterPowerRow(W, hostFrame, posY) end

    return posY, headerFrame, sizeRow, textHeader, textRow, enableRowFrame
end

-- Inline "Portrait on Right" cog attached to a Show Portrait toggle
-- region. Clicking the cog opens a popup with a toggle that swaps
-- settings.portraitSide between "left" and "right" live; withArtStyle
-- (Target of Target / Focus Target) adds the 2D / Class art choice.
local function AttachPortraitSideCog(region, unitSettings, withArtStyle, unitName)
    local environ = mod._UFO_OptEnv
    local ReloadAndUpdate, UpdatePreview, classThemeSubOrder, classThemeSubValues =
        environ.ReloadAndUpdate,
        environ.UpdatePreview,
        environ.classThemeSubOrder,
        environ.classThemeSubValues
    local _, portraitShow
    local rowList = {
        {
            type = "toggle",
            label = "Portrait on Right",
            get = function() return (unitSettings.portraitSide or "left") == "right" end,
            set = function(value)
                unitSettings.portraitSide = value and "right" or "left"
                ReloadAndUpdate()
                UpdatePreview()
            end,
        },
    }
    if withArtStyle then
        rowList[#rowList + 1] = {
            type = "dropdown",
            label = "Art Style",
            values = { ["2d"] = "2D Portrait", ["class"] = "Class" },
            order = { "2d", "class" },
            get = function() return unitSettings.portraitMode == "class" and "class" or "2d" end,
            set = function(value)
                local function ApplyArt()
                    unitSettings.portraitMode = value
                    ReloadAndUpdate()
                    UpdatePreview()
                end
                if
                    value == "2d"
                    and unitSettings.portraitMode == "class"
                    and unitSettings.portraitMirror
                    and not CUI.BlizzStyle.Get("unitframes")
                    and mod.UF_Ask2DMirroredPortraits(function()
                        ApplyArt()
                        CUI:RefreshPage()
                    end)
                then
                    if portraitShow and portraitShow._popupFrame then portraitShow._popupFrame:Hide() end
                    return
                end
                ApplyArt()
            end,
        }
        rowList[#rowList + 1] = {
            type = "dropdown",
            label = "Class Style",
            values = classThemeSubValues,
            order = classThemeSubOrder,
            get = function() return unitSettings.classThemeStyle or "modern" end,
            set = function(value)
                unitSettings.classThemeStyle = value
                ReloadAndUpdate()
                UpdatePreview()
            end,
            disabled = function() return unitSettings.portraitMode ~= "class" end,
            disabledTooltip = "This option requires Art Style to be set to Class",
            rawTooltip = true,
        }
        -- The Non-Player Portrait opt-in and its choice, as on the main frames.
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Custom Non-Player Portrait",
            tooltip = "Pick what NPCs show in Class art instead of their 2D portrait.",
            get = function() return unitSettings.portraitNonPlayerOn == true end,
            set = function(value)
                unitSettings.portraitNonPlayerOn = value or nil
                ReloadAndUpdate()
            end,
        }
        -- No 3D here: a mini frame's fade never reaches a model (the
        -- runtime resolves a saved "3d" to 2D the same way).
        rowList[#rowList + 1] = {
            type = "dropdown",
            label = "Non-Player Portrait",
            values = { ["2d"] = "2D Portrait", ["none"] = "Nothing" },
            order = { "2d", "none" },
            get = function() return unitSettings.portraitNonPlayer == "none" and "none" or "2d" end,
            set = function(value)
                unitSettings.portraitNonPlayer = value
                ReloadAndUpdate()
            end,
            disabled = function()
                return unitSettings.portraitMode ~= "class" or not unitSettings.portraitNonPlayerOn
            end,
            disabledTooltip = function()
                if unitSettings.portraitMode ~= "class" then
                    return "This option requires Art Style to be set to Class"
                end
                return "Custom Non-Player Portrait"
            end,
        }
    end
    if unitName == "targettarget" or unitName == "boss" then
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Mirror Portrait",
            tooltip = "Mirrors playable-race portraits in 2D. Always flips class art horizontally.",
            disabled = function() return CUI.BlizzStyle.Get("unitframes") end,
            disabledTooltip = function() return CUI.BlizzStyle.Label("unitframes") end,
            requireState = "disabled",
            get = function() return unitSettings.portraitMirror == true end,
            set = function(value)
                local function ApplyMirror()
                    unitSettings.portraitMirror = value or nil
                    mod.UF_RefreshPortraitMirror(unitName)
                    UpdatePreview()
                end
                if
                    value
                    and not unitSettings.portraitMirror
                    and unitSettings.portraitMode ~= "3d"
                    and unitSettings.portraitMode ~= "class"
                    and mod.UF_Ask2DMirroredPortraits(function()
                        ApplyMirror()
                        CUI:RefreshPage()
                    end)
                then
                    if portraitShow and portraitShow._popupFrame then portraitShow._popupFrame:Hide() end
                    return
                end
                ApplyMirror()
            end,
        }
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Vertical Border Separator",
            tooltip = "Draws the selected border style between the attached portrait and the bars.",
            disabled = function()
                local sourceUnit = unitName == "boss" and mod.UF_BossBorderSettings()
                    or GetMiniDonorSettings(unitName)
                return CUI.BlizzStyle.Get("unitframes")
                    or (unitSettings.borderSizeOverride or sourceUnit.borderSize or 1) <= 0
                    or not CUI.GetBorderCompanion(sourceUnit.borderTexture or "solid", "sepV")
            end,
            disabledTooltip = function()
                if CUI.BlizzStyle.Get("unitframes") then
                    return CUI.BlizzStyle.Label("unitframes")
                end
                return "This option requires a border style with divider art and a Border Size above 0."
            end,
            rawTooltip = true,
            get = function() return unitSettings.portraitSeparator == true end,
            set = function(value)
                unitSettings.portraitSeparator = value or nil
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }
    end
    _, portraitShow = CUI.BuildInlineCog(region, {
        gap = 9,
        title = "Portrait Settings",
        -- Side and art only show on a shown portrait (the stock styles
        -- always show one); the Show Portrait setters refresh this state.
        disabled = function()
            return unitSettings.showPortrait == false and not CUI.BlizzStyle.Get("unitframes")
        end,
        disabledTooltip = "Show Portrait",
        rows = rowList,
    })
end

-- Shared builder for the two independent mini frames (Target of Target,
-- Focus Target). settingsTable/unitKey select which one; each renders its
-- own single enable toggle + Show Portrait (right slot), Pet-style.
function mod.UFO_BuildFoTToTOptions(W, hostFrame, posY, unitSettings, unitName)
    local environ = mod._UFO_OptEnv
    local AttachFrameSourceCog, BuildApplyAllRow, MINI_GROUP_ORDER, PromptReloadIfUnspawned =
        environ.AttachFrameSourceCog,
        environ.BuildApplyAllRow,
        environ.MINI_GROUP_ORDER,
        environ.PromptReloadIfUnspawned
    local ReloadAndUpdate, abs, saved = environ.ReloadAndUpdate, environ.abs, environ.db
    unitSettings = unitSettings or saved.profile.targettarget
    unitName = unitName or "targettarget"
    local enableText = (unitName == "focustarget") and "Enable Focus Target" or "Enable Target of Target"
    local _, height

    _, height = BuildApplyAllRow(hostFrame, posY, MINI_GROUP_ORDER, unitName, true)
    posY = posY - height

    local portraitLine
    local function enableRow(Ww, profile, rowY)
        local ownFrames = mod.GetUnitFrameSource(unitName) == "cui"
        -- The Frame Source cog's "Blizzard Default" only makes sense when the
        -- parent target/focus frame is itself on Blizzard's frame (its native
        -- child target-of-target is then alive; see ns.GetUnitFrameSource);
        -- the cog's dropdown is blocked otherwise with an explanation.
        local parentLabel = (unitName == "focustarget") and "Focus" or "Target"
        local parentKey = (unitName == "focustarget") and "focus" or "target"
        local childName = (unitName == "focustarget") and "focus-target" or "target-of-target"
        portraitLine, height = Ww:DualRow(profile, rowY, {
            type = "toggle",
            text = enableText,
            getValue = function() return saved.profile.enabledFrames[unitName] ~= false end,
            setValue = function(value)
                saved.profile.enabledFrames[unitName] = value
                ReloadAndUpdate()
                CUI:RefreshPage(true)
                PromptReloadIfUnspawned({ unitName })
            end,
        }, ownFrames and CUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CUI.BlizzStyle.Get("unitframes") or unitSettings.showPortrait ~= false
            end,
            setValue = function(value)
                unitSettings.showPortrait = value
                ReloadAndUpdate()
                CUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if ownFrames and not CUI._prebuilding then
            AttachPortraitSideCog(portraitLine._rightRegion, unitSettings, true, unitName)
        end
        AttachFrameSourceCog(portraitLine._leftRegion, unitName, {
            tooltip = "Due to Blizzard API restrictions, Blizzard's native "
                .. childName
                .. " can't be hidden in combat and will show the whole time you are in combat. Recommended: match the "
                .. parentLabel
                .. " frame's source -- both Blizzard Default, or both CludesUI.",
            disabled = function() return mod.GetUnitFrameSource(parentKey) ~= "blizzard" end,
            disabledTooltip = '"Blizzard Default" is only available when the '
                .. parentLabel
                .. " frame's source is set to Blizzard Default -- the "
                .. childName
                .. " then comes from Blizzard's "
                .. parentKey
                .. " frame.",
        })
        return portraitLine, height
    end

    local headerFrame, sizeRow, textHeader, textRow
    posY, headerFrame, sizeRow, textHeader, textRow =
        BuildMiniTextAndSize(W, hostFrame, posY, unitSettings, unitName, enableRow)

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        healthBar = { section = headerFrame, target = sizeRow },
        portrait = { section = headerFrame, target = portraitLine, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
    }

    return abs(posY)
end

function mod.UFO_BuildPetOptions(W, hostFrame, posY)
    local environ = mod._UFO_OptEnv
    local AttachFrameSourceCog, BuildApplyAllRow, MINI_GROUP_ORDER, PromptReloadIfUnspawned =
        environ.AttachFrameSourceCog,
        environ.BuildApplyAllRow,
        environ.MINI_GROUP_ORDER,
        environ.PromptReloadIfUnspawned
    local ReloadAndUpdate, UpdatePreview, abs, saved =
        environ.ReloadAndUpdate, environ.UpdatePreview, environ.abs, environ.db
    local _, height

    _, height = BuildApplyAllRow(hostFrame, posY, MINI_GROUP_ORDER, "pet", true)
    posY = posY - height

    local portraitLine
    local function enableRow(Ww, profile, rowY)
        local ownFrames = mod.GetUnitFrameSource("pet") == "cui"
        portraitLine, height = Ww:DualRow(profile, rowY, {
            type = "toggle",
            text = "Enable Pet Frame",
            getValue = function() return saved.profile.enabledFrames.pet ~= false end,
            setValue = function(value)
                saved.profile.enabledFrames.pet = value
                ReloadAndUpdate()
                CUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "pet" })
            end,
        }, ownFrames and CUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CUI.BlizzStyle.Get("unitframes") or saved.profile.pet.showPortrait ~= false
            end,
            setValue = function(value)
                saved.profile.pet.showPortrait = value
                ReloadAndUpdate()
                CUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if ownFrames and not CUI._prebuilding then
            AttachPortraitSideCog(portraitLine._rightRegion, saved.profile.pet)
        end
        AttachFrameSourceCog(portraitLine._leftRegion, "pet", {
            extraRows = {
                {
                    type = "toggle",
                    label = "Always Show Pet Frame",
                    tooltip = "Show the pet frame whenever you have a pet, ignoring the Player frame's visibility settings.",
                    get = function() return saved.profile.pet.alwaysShow == true end,
                    set = function(value)
                        saved.profile.pet.alwaysShow = value and true or nil
                        if mod.UpdateFrameVisibility then mod.UpdateFrameVisibility() end
                    end,
                },
            },
        })
        return portraitLine, height
    end

    -- WoW Forever: the pet has power (its POWER BAR section exists in the
    -- CUI look only; the stock styles paint their own stock bar) and
    -- hunter pets track happiness (PET HAPPINESS, below the power bar).
    -- Retail builds neither.
    local petOpts, petPower, happyHeader, happyRow
    if CUI.IS_FOREVER == true then
        petPower = mod.UF_PetHasPower and not CUI.BlizzStyle.Get("unitframes")
        local P = saved.profile.pet
        local function happyOff() return P.happinessEnabled == false end
        -- The live icon repaints itself; the preview mirrors it.
        local function applyHappiness()
            mod.UF_ApplyPetHappiness()
            UpdatePreview()
        end
        petOpts = {
            hasPowerBar = petPower,
            afterPowerRow = function(Ww, profile, rowY)
                local hh
                happyHeader, hh = Ww:SectionHeader(profile, "PET HAPPINESS", rowY)
                rowY = rowY - hh

                -- Row 1: Show Happiness | Size
                happyRow, hh = Ww:DualRow(profile, rowY, {
                    type = "toggle",
                    text = "Show Happiness",
                    tooltip = "Shows your hunter pet's happiness beside the pet frame.",
                    getValue = function() return P.happinessEnabled ~= false end,
                    setValue = function(value)
                        P.happinessEnabled = value
                        applyHappiness()
                        CUI:RefreshPage()
                    end,
                }, {
                    type = "slider",
                    text = "Size",
                    min = 10,
                    max = 64,
                    step = 1,
                    disabled = happyOff,
                    disabledTooltip = "Show Happiness",
                    getValue = function() return P.happinessSize or 20 end,
                    setValue = function(value)
                        P.happinessSize = value
                        applyHappiness()
                    end,
                })
                rowY = rowY - hh

                -- Row 2: Position (+ offsets cog) | blank (odd last slot)
                local posRow
                posRow, hh = Ww:DualRow(profile, rowY, {
                    type = "segmented",
                    text = "Position",
                    values = { left = "Left", right = "Right", top = "Top" },
                    order = { "left", "right", "top" },
                    disabled = happyOff,
                    disabledTooltip = "Show Happiness",
                    getValue = function() return P.happinessAlign or "right" end,
                    setValue = function(value)
                        P.happinessAlign = value
                        applyHappiness()
                    end,
                }, CUI.BlankRowCfg())
                rowY = rowY - hh
                if not CUI._prebuilding then
                    CUI.BuildInlineCog(posRow._leftRegion, {
                        disabled = happyOff,
                        disabledTooltip = "Show Happiness",
                        title = "Happiness Position",
                        rows = {
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function() return P.happinessX or 0 end,
                                set = function(value)
                                    P.happinessX = value
                                    applyHappiness()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function() return P.happinessY or 0 end,
                                set = function(value)
                                    P.happinessY = value
                                    applyHappiness()
                                end,
                            },
                        },
                    })
                end
                return rowY
            end,
        }
    end

    local headerFrame, sizeRow, textHeader, textRow
    posY, headerFrame, sizeRow, textHeader, textRow =
        BuildMiniTextAndSize(W, hostFrame, posY, saved.profile.pet, "pet", enableRow, nil, petOpts)

    -- BUFFS AND DEBUFFS, on the CludesUI pet frame only (an inactive frame
    -- shows the notice above instead). Location, size (Cropped Icons
    -- included), position and layout are the pet's own; the aura look (border,
    -- duration and stack text, zoom, dispel borders) comes from Copy Auras
    -- From, a view over that frame's keys (CUI_UnitFrames_AuraContainers.lua).
    -- Every getter reads db.profile.pet live (Spec Override slot marks trace
    -- those reads) and writes nothing.
    local auraHeader, buffRow, debuffRow
    if mod.GetUnitFrameSource("pet") == "cui" then
        local SwapAuraSlot = environ.SwapAuraSlot
        local function PGet(settingKey, default)
            local value = saved.profile.pet[settingKey]
            if value == nil then return default end
            return value
        end
        local function PSet(settingKey, value)
            saved.profile.pet[settingKey] = value
            ReloadAndUpdate()
        end
        local function buffsOff() return saved.profile.pet.showBuffs == false end
        local function debuffsOff() return (saved.profile.pet.debuffAnchor or "none") == "none" end
        local function anyOn() return not (buffsOff() and debuffsOff()) end
        -- The two stacks never share a spot (SwapAuraSlot); the reload pass
        -- builds the containers once one of them is on. Copy Auras From is
        -- built only while one is on, so turning the first on or the last off
        -- rebuilds the page.
        local function PlaceAuras(settingKey)
            return CUI.DependentSetValue(anyOn, function(value)
                SwapAuraSlot(saved.profile.pet, settingKey, value)
                ReloadAndUpdate()
                CUI:RefreshPage()
            end)
        end
        auraHeader, height = W:SectionHeader(hostFrame, "BUFFS AND DEBUFFS", posY)
        posY = posY - height

        -- Buffs Location | Buff Size, then Debuffs Location | Debuff Size: the
        -- settings cog on each Location, the position cog on each Size.
        buffRow, height = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Buffs Location",
            values = environ.buffAnchorValues,
            order = environ.buffAnchorOrder,
            getValue = function()
                local pet = saved.profile.pet
                if pet.showBuffs == false then return "none" end
                return pet.buffAnchor or "topleft"
            end,
            setValue = PlaceAuras("buffAnchor"),
        }, {
            type = "slider",
            text = "Buff Size",
            min = 10,
            max = 70,
            step = 1,
            disabled = buffsOff,
            disabledTooltip = "Buffs Location",
            getValue = function() return PGet("buffSize", 22) end,
            setValue = function(value) PSet("buffSize", value) end,
        })
        posY = posY - height
        debuffRow, height = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Debuffs Location",
            values = environ.buffAnchorValues,
            order = environ.buffAnchorOrder,
            getValue = function() return PGet("debuffAnchor", "none") end,
            setValue = PlaceAuras("debuffAnchor"),
        }, {
            type = "slider",
            text = "Debuff Size",
            min = 10,
            max = 70,
            step = 1,
            disabled = debuffsOff,
            disabledTooltip = "Debuffs Location",
            getValue = function() return PGet("debuffSize", 22) end,
            setValue = function(value) PSet("debuffSize", value) end,
        })
        posY = posY - height

        -- Copy Auras From | (blank: odd last slot), built while buffs or
        -- debuffs show. Shows the frame in use: the pick while that frame can
        -- lend its look, else the pet's Copy Look From frame, which a pet with
        -- no pick follows. Every pick is stored, so it sticks when Copy Look
        -- From changes later.
        if anyOn() then
            _, height = W:DualRow(hostFrame, posY, {
                type = "segmented",
                text = "Copy Auras From",
                tooltip = "The frame whose aura look the pet copies.",
                values = { target = "Target", focus = "Focus", player = "Player" },
                order = { "target", "focus", "player" },
                getValue = function() return mod.UF_MiniAuraSourceKey("pet") end,
                setValue = function(value)
                    if value == saved.profile.pet.auraSource then return end
                    saved.profile.pet.auraSource = value
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                end,
                -- Slot marks follow the stored pick alone: the frame shown
                -- also reads the other frames' enable and Visibility keys.
                accessors = {
                    {
                        getValue = function() return saved.profile.pet.auraSource end,
                    },
                },
            }, CUI.BlankRowCfg())
            posY = posY - height
        end

        if not CUI._prebuilding then
            CUI.BuildInlineCog(buffRow._leftRegion, {
                disabled = buffsOff,
                disabledTooltip = "Buffs Location",
                title = "Buff Settings",
                rows = mod.UFO_AuraSettingsRows("buff", PGet, PSet, 40, 4),
            })
            CUI.BuildInlineCog(buffRow._rightRegion, {
                disabled = buffsOff,
                disabledTooltip = "Buffs Location",
                title = "Buff Position",
                rows = mod.UFO_AuraPositionRows("buff", PGet, PSet),
            })
            CUI.BuildInlineCog(debuffRow._leftRegion, {
                disabled = debuffsOff,
                disabledTooltip = "Debuffs Location",
                title = "Debuff Settings",
                rows = mod.UFO_AuraSettingsRows("debuff", PGet, PSet, 20, 10),
            })
            CUI.BuildInlineCog(debuffRow._rightRegion, {
                disabled = debuffsOff,
                disabledTooltip = "Debuffs Location",
                title = "Debuff Position",
                rows = mod.UFO_AuraPositionRows("debuff", PGet, PSet),
            })
        end
    end

    -- CAST BAR, on the CludesUI pet frame only. Off by default; the bar is
    -- built at login, so turning it on asks for a reload. Move it in Unlock Mode.
    if mod.GetUnitFrameSource("pet") == "cui" then
        local P = saved.profile.pet
        local function castOff() return P.showCastbar ~= true end
        _, height = W:SectionHeader(hostFrame, "CAST BAR", posY)
        posY = posY - height
        _, height = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Cast Bar",
            tooltip = "Shows a cast bar for your pet's spells (e.g. Seduction). Turning it on needs a reload. Position it in Layout Mode.",
            getValue = function() return P.showCastbar == true end,
            setValue = function(value)
                P.showCastbar = value
                ReloadAndUpdate()
                local popFrame = mod.frames and mod.frames.pet
                if value and popFrame and not popFrame.Castbar then
                    CUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "The pet cast bar is built at login. Reload to show it.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Cast Bar Width",
            min = 30,
            max = 400,
            step = 1,
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function() return P.castbarWidth or 120 end,
            setValue = function(value)
                P.castbarWidth = value
                ReloadAndUpdate()
            end,
        })
        posY = posY - height
        _, height = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Cast Bar Height",
            min = 1,
            max = 40,
            step = 1,
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function() return P.castbarHeight or 12 end,
            setValue = function(value)
                P.castbarHeight = value
                ReloadAndUpdate()
            end,
        }, {
            type = "toggle",
            text = "Hide When Idle",
            tooltip = "Only show the cast bar while a cast is in progress.",
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function() return P.castbarHideWhenInactive ~= false end,
            setValue = function(value)
                P.castbarHideWhenInactive = value
                ReloadAndUpdate()
            end,
        })
        posY = posY - height
    end

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        healthBar = { section = headerFrame, target = sizeRow },
        portrait = { section = headerFrame, target = portraitLine, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        buffIcon = auraHeader and { section = auraHeader, target = buffRow, slotSide = "left" } or nil,
        debuffIcon = auraHeader and { section = auraHeader, target = debuffRow, slotSide = "left" } or nil,
    }
    -- WoW Forever: the preview's power bar, power text and happiness icon
    -- (only once the sections exist: an inactive frame builds none).
    if happyRow then
        local tg = hostFrame._ufClickTargets
        if petPower then
            tg.powerBar = {
                section = hostFrame._powerHeaderFrame,
                target = hostFrame._powerHeightRow,
                slotSide = "left",
            }
            tg.powerBarText =
                { section = hostFrame._powerHeaderFrame, target = hostFrame._powerTextRow, slotSide = "left" }
        end
        tg.petHappiness = { section = happyHeader, target = happyRow, slotSide = "left" }
    end

    return abs(posY)
end

function mod.UFO_BuildBossOptions(W, hostFrame, posY)
    local environ = mod._UFO_OptEnv
    local AttachDebuffModeWarn, AttachFrameSourceCog, DebuffModeDropdownCfg, Pix =
        environ.AttachDebuffModeWarn, environ.AttachFrameSourceCog, environ.DebuffModeDropdownCfg, environ.PP
    local HideExhaustionRow = environ.HideExhaustionRow
    local PromptReloadIfUnspawned, ReloadAndUpdate, SwapAuraSlot, abs =
        environ.PromptReloadIfUnspawned, environ.ReloadAndUpdate, environ.SwapAuraSlot, environ.abs
    local buffAnchorOrder, buffAnchorValues, buffGrowthOrder, buffGrowthValues =
        environ.buffAnchorOrder, environ.buffAnchorValues, environ.buffGrowthOrder, environ.buffGrowthValues
    local saved = environ.db

    -- A cog row on one boss setting: get reads it (default when unset or
    -- false), set writes it and redraws the frames, and the preview's auras
    -- too when refreshAuras is set.
    local function BossGet(settingKey, default)
        return function()
            local value = saved.profile.boss[settingKey]
            if default == nil then return value end
            return value or default
        end
    end
    -- A text colour swatch left of a cog (Duration / Stack Text Color): one
    -- boss colour key, white when unset; dimmed and dead while off() holds.
    local function BossTextSwatch(region, settingKey, tip, off)
        local swatch, upd = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
            local color = saved.profile.boss[settingKey]
            if color then return color.r, color.g, color.b end
            return 1, 1, 1
        end, function(red, green, blue)
            saved.profile.boss[settingKey] = { r = red, g = green, b = blue }
            ReloadAndUpdate()
        end, false, 20)
        swatch:HookScript("OnEnter", function() CUI.ShowWidgetTooltip(swatch, tip) end)
        swatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        Pix.Point(swatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = swatch
        local function Paint()
            upd()
            local o = off()
            swatch:SetAlpha(o and 0.3 or 1)
            swatch:EnableMouse(not o)
        end
        Paint()
        CUI.RegisterWidgetRefresh(Paint)
    end
    local function BossSet(settingKey, refreshAuras)
        return function(value)
            saved.profile.boss[settingKey] = value
            ReloadAndUpdate()
            if refreshAuras and mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
        end
    end
    local _, height

    -- Activate/Deactivate Boss Preview button (matches Party Mode's activate
    -- button, centered above the first section). Disabled while Boss Frames are
    -- off: the in-game preview rides on the real (now-disabled) boss frames and renders broken.
    local activateBtnFrame, activateBtnLbl, activateButton
    local function PreviewLabel()
        return mod._bossPreviewActive and CUI.L("Deactivate Boss Preview")
            or CUI.L("Activate Boss Preview")
    end
    local function BossFramesDisabled() return mod.GetUnitFrameSource("boss") ~= "cui" end
    activateBtnFrame, height = W:WideButton(hostFrame, PreviewLabel(), posY, function()
        if BossFramesDisabled() then return end
        if not mod.SetBossPreview then return end
        mod.SetBossPreview(not mod._bossPreviewActive)
        if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
    end)
    posY = posY - height
    do
        -- The row's button and its label, picked by kind and use rather than by
        -- position: on a kept page the row frame may still hold idle children
        -- and regions of an earlier dress (page reuse).
        local kids = { activateBtnFrame:GetChildren() }
        for idx = 1, #kids do
            local c = kids[idx]
            if c:GetObjectType() == "Button" and not PoolIsIdle(c) then
                activateButton = c
                break
            end
        end
        if activateButton then
            local regions = { activateButton:GetRegions() }
            for idx = 1, #regions do
                local region = regions[idx]
                if region and region.GetText and not PoolIsIdle(region) then
                    local t = region:GetText()
                    if t and t ~= "" then
                        activateBtnLbl = region
                        break
                    end
                end
            end
        end
    end
    local function UpdateActivateBtn()
        local off = BossFramesDisabled()
        if activateBtnLbl then activateBtnLbl:SetText(PreviewLabel()) end
        if activateButton then
            activateButton:SetAlpha(off and 0.4 or 1)
            activateButton:EnableMouse(not off)
        end
    end
    UpdateActivateBtn()
    CUI.RegisterWidgetRefresh(UpdateActivateBtn)

    -- Rows exposed as upvalues so the click-to-scroll targets (below) can point at
    -- them. growthRow holds Show Cast Icon + Cast Bar Height after the swap;
    -- simpleRow/simpleBuffRow/bossAuraRow + bossAuraHeader are the Buffs and Debuffs section rows.
    local portraitLine, growthRow, simpleRow, simpleBuffRow, bossAuraRow, bossAuraHeader, bossCastHeader, castMainRow
    local function enableRow(Ww, profile, rowY)
        local ownFrames = mod.GetUnitFrameSource("boss") == "cui"
        local eh
        portraitLine, eh = Ww:DualRow(profile, rowY, {
            type = "toggle",
            text = "Enable Boss Frames",
            getValue = function() return saved.profile.enabledFrames.boss ~= false end,
            setValue = function(value)
                saved.profile.enabledFrames.boss = value
                -- Force-stop the in-game preview when disabling boss frames;
                -- it rides on the now-disabled frames and renders broken.
                if not value and mod._bossPreviewActive and mod.SetBossPreview then
                    mod.SetBossPreview(false)
                end
                -- Live apply on the spawned CUI frames (unit-watch register/
                -- unregister). Frames never spawned this session no-op here
                -- and hit the reload prompt below instead.
                if mod.UF_SetBossFramesActive then mod.UF_SetBossFramesActive(value) end
                ReloadAndUpdate()
                CUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "boss" })
            end,
        }, ownFrames and CUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CUI.BlizzStyle.Get("unitframes") or saved.profile.boss.showPortrait ~= false
            end,
            setValue = function(value)
                saved.profile.boss.showPortrait = value
                ReloadAndUpdate()
                CUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if ownFrames and not CUI._prebuilding then
            AttachPortraitSideCog(portraitLine._rightRegion, saved.profile.boss, false, "boss")
        end
        AttachFrameSourceCog(portraitLine._leftRegion, "boss", {
            onBeforeSet = function(value)
                -- Force-stop the in-game preview when boss frames are no longer
                -- CUI-owned; it rides on the real boss frames and renders broken.
                if value ~= "cui" and mod._bossPreviewActive and mod.SetBossPreview then
                    mod.SetBossPreview(false)
                end
            end,
        })
        local sum = eh
        if ownFrames then
            local castRow, ch = Ww:DualRow(
                profile,
                rowY - eh,
                {
                    type = "segmented",
                    text = "Stack Direction",
                    values = { up = "Up", down = "Down" },
                    order = { "up", "down" },
                    getValue = function() return saved.profile.boss.bossStackDirection or "down" end,
                    setValue = function(value)
                        saved.profile.boss.bossStackDirection = value
                        ReloadAndUpdate()
                    end,
                },
                -- Top-to-top step; Stack Direction sets the side, so no negatives.
                {
                    type = "slider",
                    pixel = true,
                    text = "Vertical Spacing",
                    min = 0,
                    max = 200,
                    step = 1,
                    getValue = function() return math.abs(saved.profile.bossSpacing or 80) end,
                    setValue = function(value)
                        saved.profile.bossSpacing = value
                        ReloadAndUpdate()
                    end,
                }
            )
            sum = sum + ch
        end
        return portraitLine, sum
    end

    local function bossAfterSize(Ww, profile, rowY)
        local _, hh
        -- BUFFS AND DEBUFFS section (below DISPLAY)
        bossAuraHeader, hh = Ww:SectionHeader(profile, "BUFFS AND DEBUFFS", rowY)
        rowY = rowY - hh

        -- Effective boss aura locations: Simple display overrides the stored
        -- location at runtime (dropdowns show None while active), so every
        -- disabled check must treat location as None whenever simple mode is on.
        -- Raw key checks deadlock: defaults hold simpleDebuffs="left" alongside
        -- debuffAnchor="bottomleft", locking BOTH the Simple dropdown (raw anchor not none) and the Location dropdown (simple active) at once.
        local function BossDebuffLocationActive()
            local cfg = saved.profile.boss
            if mod.GetBossSimpleDebuffMode(cfg) ~= "none" then return false end
            return (cfg.debuffAnchor or "bottomleft") ~= "none"
        end
        local function BossBuffLocationActive()
            local cfg = saved.profile.boss
            if mod.GetBossSimpleBuffMode(cfg) ~= "none" then return false end
            if cfg.showBuffs == false then return false end
            return (cfg.buffAnchor or "topleft") ~= "none"
        end
        -- Composite show-state of the two aura sizing rows (Buff/Debuff Size +
        -- Text Size). A row hides while its column's effective Location is None
        -- (Simple mode also reads as None; it has its own text/size controls). All
        -- four Location/Simple setters capture this BEFORE writing and force a full
        -- rebuild on change: any of them can flip EITHER row (collision pushes, SwapAuraSlot displacing the other anchor, simple forcing showBuffs/debuffAnchor).
        local function BossBuffRowShown()
            local bossCfg = saved.profile.boss
            return mod.GetBossSimpleBuffMode(bossCfg) == "none" and bossCfg.showBuffs ~= false
        end
        local function BossDebuffRowShown()
            local bossCfg = saved.profile.boss
            return mod.GetBossSimpleDebuffMode(bossCfg) == "none"
                and (bossCfg.debuffAnchor or "bottomleft") ~= "none"
        end
        local function BossAuraRowsState()
            return tostring(BossBuffRowShown()) .. "/" .. tostring(BossDebuffRowShown())
        end

        -- Simple Buff Display: identical to Simple Debuff Display above but for
        -- buffs. Defaults to None. Forces a single Left/Right column matched to
        -- the frame height, overriding Buffs Location + Buff Size while active.
        local simpleBuffTextOff = function()
            return BossBuffLocationActive()
                or mod.GetBossSimpleBuffMode(saved.profile.boss) == "none"
                or not saved.profile.boss.simpleBuffShowCooldownText
        end
        simpleBuffRow, hh = Ww:DualRow(profile, rowY, {
            type = "segmented",
            text = "Simple Buff Display",
            disabled = function() return BossBuffLocationActive() end,
            disabledTooltip = "Buffs Location",
            requireState = "disabled",
            tooltip = "Force boss buffs into a single large column matched to the frame height.",
            values = { none = "None", left = "Left", right = "Right" },
            order = { "none", "left", "right" },
            getValue = function() return mod.GetBossSimpleBuffMode(saved.profile.boss) end,
            setValue = function(value)
                local lastState = BossAuraRowsState()
                saved.profile.boss.simpleBuffs = value
                if value ~= "none" then
                    -- Same-side collision: if Simple Debuff Display occupies this
                    -- side, push it off (set to None) so they never overlap.
                    if mod.GetBossSimpleDebuffMode(saved.profile.boss) == value then
                        saved.profile.boss.simpleDebuffs = "none"
                    end
                    -- Selecting a side takes over from the normal Buffs
                    -- Location, so force that setting to None.
                    saved.profile.boss.showBuffs = false
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                if BossAuraRowsState() ~= lastState then
                    CUI:RefreshPage(true)
                else
                    CUI:RefreshPage()
                end
            end,
        }, {
            type = "slider",
            text = "Buff Text Size",
            min = 6,
            max = 100,
            step = 1,
            trackWidth = 120,
            disabled = simpleBuffTextOff,
            disabledTooltip = "Show Duration (Inside Cog)",
            getValue = function() return saved.profile.boss.simpleBuffCooldownTextSize or 14 end,
            setValue = function(value)
                saved.profile.boss.simpleBuffCooldownTextSize = value
                ReloadAndUpdate()
            end,
        })
        rowY = rowY - hh

        -- Directions cog on Simple Buff Display: the simple column's own X/Y
        -- offset (defaults to the regular buff offsets via ns.GetBossSimpleBuffOffset);
        -- writing here makes the simple offset independent. Disabled while None.
        if not CUI._prebuilding then
            local leftRegion = simpleBuffRow._leftRegion
            CUI.BuildInlineCog(leftRegion, {
                disabled = function() return mod.GetBossSimpleBuffMode(saved.profile.boss) == "none" end,
                disabledTooltip = "Simple Buff Display",
                title = "Simple Buff Position",
                rows = {
                    -- Max buffs shown in simple mode. Shares the boss maxBuffs key
                    -- with Buffs Location (the two modes are mutually exclusive);
                    -- the runtime caps frame.Buffs.num to it.
                    {
                        type = "slider",
                        label = "Max Count",
                        min = 1,
                        max = 20,
                        step = 1,
                        tooltip = mod.UFO_MAX_COUNT_TOOLTIP,
                        get = BossGet("maxBuffs", 4),
                        set = BossSet("maxBuffs", true),
                    },
                    -- Shares the boss buffMaxPerRow key with Buffs Location
                    -- (mutually exclusive modes), like Max Count above.
                    {
                        type = "slider",
                        label = "Max Per Row",
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function()
                            return saved.profile.boss.buffMaxPerRow or saved.profile.boss.maxBuffs or 4
                        end,
                        set = function(value)
                            saved.profile.boss.buffMaxPerRow = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            local posX = mod.GetBossSimpleBuffOffset(saved.profile.boss)
                            return posX
                        end,
                        set = function(value)
                            saved.profile.boss.simpleBuffOffsetX = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            local _, posY = mod.GetBossSimpleBuffOffset(saved.profile.boss)
                            return posY
                        end,
                        set = function(value)
                            saved.profile.boss.simpleBuffOffsetY = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    -- Physical-pixel-perfect gap between the simple buff icons.
                    {
                        type = "slider",
                        pixel = true,
                        label = "Spacing",
                        min = -1,
                        max = 10,
                        step = 1,
                        get = BossGet("simpleBuffSpacing", 1),
                        set = BossSet("simpleBuffSpacing", true),
                    },
                },
            })
        end

        -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
        do
            local rightRegion = simpleBuffRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Buff Text Size
            -- swatches (same keys); greyed + disabled on this row cog's condition.
            local buffOff = function()
                return BossBuffLocationActive() or mod.GetBossSimpleBuffMode(saved.profile.boss) == "none"
            end
            CUI.BuildInlineCog(rightRegion, {
                disabled = buffOff,
                disabledTooltip = "Simple Buff Display",
                title = "Duration & Stack",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Duration",
                        get = function() return saved.profile.boss.simpleBuffShowCooldownText end,
                        set = function(value)
                            saved.profile.boss.simpleBuffShowCooldownText = value
                            ReloadAndUpdate()
                            CUI:RefreshPage()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Duration X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("simpleBuffCooldownTextOffsetX", 0),
                        set = BossSet("simpleBuffCooldownTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Duration Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("simpleBuffCooldownTextOffsetY", 0),
                        set = BossSet("simpleBuffCooldownTextOffsetY"),
                    },
                    {
                        type = "slider",
                        label = "Stack Size",
                        min = 6,
                        max = 100,
                        step = 1,
                        get = BossGet("buffStackTextSize", 14),
                        set = BossSet("buffStackTextSize"),
                    },
                    {
                        type = "dropdown",
                        label = "Stack Position",
                        values = {
                            bottomright = "Bottom Right",
                            bottomleft = "Bottom Left",
                            topright = "Top Right",
                            topleft = "Top Left",
                            center = "Center",
                        },
                        order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                        get = BossGet("buffStackTextPosition", "bottomright"),
                        set = BossSet("buffStackTextPosition"),
                    },
                    {
                        type = "slider",
                        label = "Stack X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("buffStackTextOffsetX", 0),
                        set = BossSet("buffStackTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Stack Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("buffStackTextOffsetY", 0),
                        set = BossSet("buffStackTextOffsetY"),
                    },
                },
            })
            BossTextSwatch(rightRegion, "buffCooldownTextColor", "Duration Text Color", buffOff)
            BossTextSwatch(rightRegion, "buffStackTextColor", "Stack Text Color", buffOff)
        end
        -- (Show Duration toggle lives inside the Duration & Stack cog above.)

        -- Simple Debuff Display: forces Left anchor + debuff height =
        -- frame bar height so boss debuffs render as one large column.
        -- Row 1 slot 2 is "Simple Text Size": the cooldown-text size slider,
        -- gated by an inline Show-Cooldown-Text toggle, with an inline cog
        -- holding the stack size and stack X/Y position controls.

        local simpleTextOff = function()
            return BossDebuffLocationActive()
                or mod.GetBossSimpleDebuffMode(saved.profile.boss) == "none"
                or not saved.profile.boss.simpleDebuffShowCooldownText
        end
        simpleRow, hh = Ww:DualRow(profile, rowY, {
            type = "segmented",
            text = "Simple Debuff Display",
            disabled = function() return BossDebuffLocationActive() end,
            disabledTooltip = "Debuffs Location",
            requireState = "disabled",
            tooltip = "Force boss debuffs into a single large column matched to the frame height.",
            values = { none = "None", left = "Left", right = "Right" },
            order = { "none", "left", "right" },
            getValue = function() return mod.GetBossSimpleDebuffMode(saved.profile.boss) end,
            setValue = function(value)
                local lastState = BossAuraRowsState()
                saved.profile.boss.simpleDebuffs = value
                if value ~= "none" then
                    -- Same-side collision: if Simple Buff Display occupies this
                    -- side, push it off (set to None) so they never overlap.
                    if mod.GetBossSimpleBuffMode(saved.profile.boss) == value then
                        saved.profile.boss.simpleBuffs = "none"
                    end
                    -- Selecting a side takes over from the normal Debuffs
                    -- Location, so force that setting to None.
                    saved.profile.boss.debuffAnchor = "none"
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                if BossAuraRowsState() ~= lastState then
                    CUI:RefreshPage(true)
                else
                    CUI:RefreshPage()
                end
            end,
        }, {
            type = "slider",
            text = "Debuff Text Size",
            min = 6,
            max = 100,
            step = 1,
            trackWidth = 120,
            disabled = simpleTextOff,
            disabledTooltip = "Show Duration (Inside Cog)",
            getValue = function() return saved.profile.boss.simpleDebuffCooldownTextSize or 14 end,
            setValue = function(value)
                saved.profile.boss.simpleDebuffCooldownTextSize = value
                ReloadAndUpdate()
            end,
        })
        rowY = rowY - hh

        -- Directions cog on Simple Debuff Display: the simple column's own X/Y
        -- offset. Defaults to the regular debuff offsets for existing users
        -- (ns.GetBossSimpleDebuffOffset); writing here makes the simple offset
        -- independent. Disabled while Simple Debuff Display is None.
        if not CUI._prebuilding then
            local leftRegion = simpleRow._leftRegion
            CUI.BuildInlineCog(leftRegion, {
                disabled = function() return mod.GetBossSimpleDebuffMode(saved.profile.boss) == "none" end,
                disabledTooltip = "Simple Debuff Display",
                title = "Simple Debuff Position",
                rows = {
                    -- Max debuffs shown in simple mode. Shares the boss maxDebuffs
                    -- key with Debuffs Location (the two modes are mutually
                    -- exclusive); the runtime caps frame.Debuffs.num to it.
                    {
                        type = "slider",
                        label = "Max Count",
                        min = 1,
                        max = 20,
                        step = 1,
                        tooltip = mod.UFO_MAX_COUNT_TOOLTIP,
                        get = BossGet("maxDebuffs", 10),
                        set = BossSet("maxDebuffs", true),
                    },
                    mod.UFO_MaxImportantRow(
                        function() return saved.profile.boss end,
                        ReloadAndUpdate,
                        20,
                        10
                    ),
                    -- Shares the boss debuffMaxPerRow key with Debuffs Location
                    -- (mutually exclusive modes), like Max Count above.
                    {
                        type = "slider",
                        label = "Max Per Row",
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function()
                            return saved.profile.boss.debuffMaxPerRow or saved.profile.boss.maxDebuffs or 10
                        end,
                        set = function(value)
                            saved.profile.boss.debuffMaxPerRow = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            local posX = mod.GetBossSimpleDebuffOffset(saved.profile.boss)
                            return posX
                        end,
                        set = function(value)
                            saved.profile.boss.simpleDebuffOffsetX = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            local _, posY = mod.GetBossSimpleDebuffOffset(saved.profile.boss)
                            return posY
                        end,
                        set = function(value)
                            saved.profile.boss.simpleDebuffOffsetY = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    -- Physical-pixel-perfect gap between the simple debuff icons.
                    {
                        type = "slider",
                        pixel = true,
                        label = "Spacing",
                        min = -1,
                        max = 10,
                        step = 1,
                        get = BossGet("simpleDebuffSpacing", 1),
                        set = BossSet("simpleDebuffSpacing", true),
                    },
                },
            })
        end

        -- Inline cog on Simple Text Size: duration X/Y + stack size / X/Y.
        if not CUI._prebuilding then
            local rightRegion = simpleRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Debuff Text
            -- Size swatches (same keys); greyed + disabled on this row cog's
            -- condition.
            local debuffOff = function()
                return BossDebuffLocationActive() or mod.GetBossSimpleDebuffMode(saved.profile.boss) == "none"
            end
            CUI.BuildInlineCog(rightRegion, {
                disabled = debuffOff,
                disabledTooltip = "Simple Debuff Display",
                title = "Duration & Stack",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Duration",
                        get = function() return saved.profile.boss.simpleDebuffShowCooldownText end,
                        set = function(value)
                            saved.profile.boss.simpleDebuffShowCooldownText = value
                            ReloadAndUpdate()
                            CUI:RefreshPage()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Duration X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("simpleDebuffCooldownTextOffsetX", 0),
                        set = BossSet("simpleDebuffCooldownTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Duration Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("simpleDebuffCooldownTextOffsetY", 0),
                        set = BossSet("simpleDebuffCooldownTextOffsetY"),
                    },
                    {
                        type = "slider",
                        label = "Stack Size",
                        min = 6,
                        max = 100,
                        step = 1,
                        get = BossGet("debuffStackTextSize", 14),
                        set = BossSet("debuffStackTextSize"),
                    },
                    {
                        type = "dropdown",
                        label = "Stack Position",
                        values = {
                            bottomright = "Bottom Right",
                            bottomleft = "Bottom Left",
                            topright = "Top Right",
                            topleft = "Top Left",
                            center = "Center",
                        },
                        order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                        get = BossGet("debuffStackTextPosition", "bottomright"),
                        set = BossSet("debuffStackTextPosition"),
                    },
                    {
                        type = "slider",
                        label = "Stack X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("debuffStackTextOffsetX", 0),
                        set = BossSet("debuffStackTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Stack Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = BossGet("debuffStackTextOffsetY", 0),
                        set = BossSet("debuffStackTextOffsetY"),
                    },
                },
            })
            BossTextSwatch(rightRegion, "debuffCooldownTextColor", "Duration Text Color", debuffOff)
            BossTextSwatch(rightRegion, "debuffStackTextColor", "Stack Text Color", debuffOff)
        end
        -- (Show Duration toggle lives inside the Duration & Stack cog above.)

        bossAuraRow, hh = Ww:DualRow(profile, rowY, {
            type = "dropdown",
            text = "Buffs Location",
            values = buffAnchorValues,
            order = buffAnchorOrder,
            disabled = function() return mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none" end,
            disabledTooltip = "Simple Buff Display",
            requireState = "disabled",
            getValue = function()
                local cfg = saved.profile.boss
                -- Forced to None while Simple Buff Display is active (it takes
                -- over placement); the setter also stores None (showBuffs=false).
                if mod.GetBossSimpleBuffMode(cfg) ~= "none" then return "none" end
                if cfg.showBuffs == false then return "none" end
                return cfg.buffAnchor or "topleft"
            end,
            setValue = function(value)
                local lastState = BossAuraRowsState()
                local cfg = saved.profile.boss
                if value == "none" then
                    cfg.showBuffs = false
                else
                    cfg.showBuffs = true
                    SwapAuraSlot(cfg, "buffAnchor", value)
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                if BossAuraRowsState() ~= lastState then
                    CUI:RefreshPage(true)
                else
                    CUI:RefreshPage()
                end
            end,
        }, {
            type = "dropdown",
            text = "Debuffs Location",
            values = buffAnchorValues,
            order = buffAnchorOrder,
            disabled = function() return mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" end,
            disabledTooltip = "Simple Debuff Display",
            requireState = "disabled",
            getValue = function()
                -- Forced to None while Simple Debuff Display is active (it
                -- takes over placement); the setter also stores None.
                if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then return "none" end
                return saved.profile.boss.debuffAnchor or "bottomleft"
            end,
            setValue = function(value)
                local lastState = BossAuraRowsState()
                SwapAuraSlot(saved.profile.boss, "debuffAnchor", value)
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                -- Full rebuild when either aura row's visibility flipped;
                -- otherwise the fast refresh keeps dependent disabled
                -- states (Boss Debuff Filter) current.
                if BossAuraRowsState() ~= lastState then
                    CUI:RefreshPage(true)
                else
                    CUI:RefreshPage()
                end
            end,
        })
        rowY = rowY - hh

        -- Boss Buff Size | Debuff Size: icon size sliders, each with an inline
        -- DIRECTIONS cog holding the cluster X/Y offset; setters refresh live
        -- frames + both previews. Debuff Size (and its cog) disable while Simple
        -- Debuff Display frame-matches the size, or when no debuffs show at all (Simple None + Location None).
        local bossDebuffSizeOff = function()
            local bossCfg = saved.profile.boss
            return mod.GetBossSimpleDebuffMode(bossCfg) ~= "none"
                or (bossCfg.debuffAnchor or "bottomleft") == "none"
        end
        -- Buff Size (and its directions cog) are disabled while Simple Buff
        -- Display frame-matches the size, or when buffs are hidden (Buffs
        -- Location None). Shared so the cog matches.
        local bossBuffSizeOff = function()
            local bossCfg = saved.profile.boss
            return mod.GetBossSimpleBuffMode(bossCfg) ~= "none" or bossCfg.showBuffs == false
        end
        -- Buff Text Size gates on the "Show Duration" toggle inside its
        -- Duration & Stack cog (mirrors Debuff Text Size on the row below).
        local buffTextOff = function()
            return not BossBuffLocationActive() or not saved.profile.boss.buffShowCooldownText
        end
        -- Buff Size | Buff Text Size row: HIDDEN entirely while the buff
        -- column's effective Location is None (see BossBuffRowShown; the
        -- dropdown setters above force the rebuild on flips).
        if BossBuffRowShown() then
            local bossAuraSizeRow
            bossAuraSizeRow, hh = Ww:DualRow(profile, rowY, {
                type = "slider",
                text = "Buff Size",
                min = 10,
                max = 70,
                step = 1,
                disabled = bossBuffSizeOff,
                disabledTooltip = function()
                    if mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none" then
                        return CUI.DisabledTooltip("Simple Buff Display", "disabled")
                    end
                    return CUI.DisabledTooltip("Buffs Location")
                end,
                rawTooltip = true,
                getValue = function() return saved.profile.boss.buffSize or 22 end,
                setValue = function(value)
                    saved.profile.boss.buffSize = value
                    ReloadAndUpdate()
                    if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                end,
            }, {
                type = "slider",
                text = "Buff Text Size",
                min = 6,
                max = 100,
                step = 1,
                trackWidth = 120,
                disabled = buffTextOff,
                disabledTooltip = "Show Duration (Inside Cog)",
                getValue = function() return saved.profile.boss.buffCooldownTextSize or 10 end,
                setValue = function(value)
                    saved.profile.boss.buffCooldownTextSize = value
                    ReloadAndUpdate()
                end,
            })
            rowY = rowY - hh
            if not CUI._prebuilding then -- Directions cog on Buff Size (X/Y cluster offset)
                CUI.BuildInlineCog(bossAuraSizeRow._leftRegion, {
                    disabled = bossBuffSizeOff,
                    title = "Buff Position",
                    rows = {
                        {
                            type = "slider",
                            label = "Offset X",
                            min = -200,
                            max = 200,
                            step = 1,
                            get = BossGet("buffOffsetX", 0),
                            set = BossSet("buffOffsetX", true),
                        },
                        {
                            type = "slider",
                            label = "Offset Y",
                            min = -200,
                            max = 200,
                            step = 1,
                            get = BossGet("buffOffsetY", 0),
                            set = BossSet("buffOffsetY", true),
                        },
                        -- Physical-pixel-perfect gap between the boss buff icons.
                        {
                            type = "slider",
                            pixel = true,
                            label = "Spacing",
                            min = -1,
                            max = 10,
                            step = 1,
                            get = BossGet("buffSpacing", 1),
                            set = BossSet("buffSpacing", true),
                        },
                    },
                })
            end
            if not CUI._prebuilding then -- Icon Zoom cog on Buff Size (gated only on buffs hidden, so it
                -- stays adjustable in Simple Buff Display, where zoom still applies)
                local bossBuffZoomOff = function() return saved.profile.boss.showBuffs == false end
                CUI.BuildInlineCog(bossAuraSizeRow._leftRegion, {
                    disabled = bossBuffZoomOff,
                    disabledTooltip = "Buffs Location",
                    title = "Icon Zoom",
                    rows = {
                        {
                            type = "slider",
                            label = "Zoom",
                            min = 0,
                            max = 0.20,
                            step = 0.01,
                            get = BossGet("buffIconZoom", 0.07),
                            set = BossSet("buffIconZoom", true),
                        },
                    },
                })
            end
            -- Buff Text Size cog + swatches (right slot): Show Duration +
            -- Duration X/Y + Stack, with inline Duration/Stack text-color
            -- swatches; greyed on the same condition as the cog.
            if not CUI._prebuilding then
                local Pix = CUI.PanelPP
                local rightRegion = bossAuraSizeRow._rightRegion
                local buffOff = function() return not BossBuffLocationActive() end
                CUI.BuildInlineCog(rightRegion, {
                    disabled = buffOff,
                    disabledTooltip = "Buffs Location",
                    title = "Duration & Stack",
                    rows = {
                        {
                            type = "toggle",
                            label = "Show Duration",
                            get = function() return saved.profile.boss.buffShowCooldownText end,
                            set = function(value)
                                saved.profile.boss.buffShowCooldownText = value
                                ReloadAndUpdate()
                                CUI:RefreshPage()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Duration X",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = BossGet("buffCooldownTextOffsetX", 0),
                            set = BossSet("buffCooldownTextOffsetX"),
                        },
                        {
                            type = "slider",
                            label = "Duration Y",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = BossGet("buffCooldownTextOffsetY", 0),
                            set = BossSet("buffCooldownTextOffsetY"),
                        },
                        {
                            type = "slider",
                            label = "Stack Size",
                            min = 6,
                            max = 100,
                            step = 1,
                            get = BossGet("buffStackTextSize", 14),
                            set = BossSet("buffStackTextSize"),
                        },
                        {
                            type = "dropdown",
                            label = "Stack Position",
                            values = {
                                bottomright = "Bottom Right",
                                bottomleft = "Bottom Left",
                                topright = "Top Right",
                                topleft = "Top Left",
                                center = "Center",
                            },
                            order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                            get = BossGet("buffStackTextPosition", "bottomright"),
                            set = BossSet("buffStackTextPosition"),
                        },
                        {
                            type = "slider",
                            label = "Stack X",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = BossGet("buffStackTextOffsetX", 0),
                            set = BossSet("buffStackTextOffsetX"),
                        },
                        {
                            type = "slider",
                            label = "Stack Y",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = BossGet("buffStackTextOffsetY", 0),
                            set = BossSet("buffStackTextOffsetY"),
                        },
                    },
                })
                BossTextSwatch(rightRegion, "buffCooldownTextColor", "Duration Text Color", buffOff)
                BossTextSwatch(rightRegion, "buffStackTextColor", "Stack Text Color", buffOff)
            end
        end -- close buff sizing row hidden-while-None gate

        -- Per-unit aura filters for boss frames (NOT synced; boss1-5 share the
        -- one "boss" settings table). Debuff Filter = the single-select mode
        -- dropdown (DebuffModeDropdownCfg; per-spell control through Tracked
        -- Auras), Buff Filter = the two-lane checkbox dropdown.
        do
            local Pix = CUI.PanelPP
            local buffFilterItems, BUFF_FILTER_KEYS, BOSS_BUFF_NEG_SKEYS
            -- Non-player buff vocabulary is just these three (see
            -- the Main Frames list).
            buffFilterItems = {
                { isHeader = true, label = "Show", rightLabel = "Hide" },
                {
                    key = "stealable",
                    label = "Stealable",
                    dual = true,
                    tooltip = "Buffs you can spellsteal or purge",
                },
                {
                    key = "bigDefensive",
                    label = "Big Defensive",
                    dual = true,
                    tooltip = "Major defensive cooldowns",
                },
                {
                    key = "dispellable",
                    label = "Dispellable",
                    dual = true,
                    tooltip = "Auras with a dispel type you can dispel",
                },
            }
            BUFF_FILTER_KEYS = {
                ownOnly = "onlyPlayerBuffs",
                raidFrames = "buffRaid",
                raidInCombat = "buffRaidInCombat",
                dispellable = "buffDispellable",
                crowdControl = "buffCrowdControl",
                bigDefensive = "buffBigDefensive",
                externalDefensive = "buffExternalDefensive",
                cancelable = "buffCancelable",
                stealable = "buffStealable",
            }
            BOSS_BUFF_NEG_SKEYS =
                { stealable = "Stealable", bigDefensive = "BigDefensive", dispellable = "Dispellable" }
            -- Debuff Size | Debuff Text Size: mirrors the buff pair above. Debuff
            -- Text Size gates on "Show Duration" inside its Duration & Stack cog
            -- (also holds Duration X/Y + Stack size/position/X/Y). HIDDEN while the
            -- debuff column's effective Location is None (BossDebuffRowShown; setters above force rebuild on flips).
            if BossDebuffRowShown() then
                local debuffTextOff = function()
                    return not BossDebuffLocationActive() or not saved.profile.boss.debuffShowCooldownText
                end
                local textSizeRow
                textSizeRow, hh = Ww:DualRow(profile, rowY, {
                    type = "slider",
                    text = "Debuff Size",
                    min = 10,
                    max = 70,
                    step = 1,
                    disabled = bossDebuffSizeOff,
                    disabledTooltip = function()
                        if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then
                            return CUI.DisabledTooltip("Simple Debuff Display", "disabled")
                        end
                        return CUI.DisabledTooltip("Debuffs Location")
                    end,
                    rawTooltip = true,
                    getValue = function() return saved.profile.boss.debuffSize or 22 end,
                    setValue = function(value)
                        saved.profile.boss.debuffSize = value
                        ReloadAndUpdate()
                        if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                    end,
                }, {
                    type = "slider",
                    text = "Debuff Text Size",
                    min = 6,
                    max = 100,
                    step = 1,
                    trackWidth = 120,
                    disabled = debuffTextOff,
                    disabledTooltip = "Show Duration (Inside Cog)",
                    getValue = function() return saved.profile.boss.debuffCooldownTextSize or 10 end,
                    setValue = function(value)
                        saved.profile.boss.debuffCooldownTextSize = value
                        ReloadAndUpdate()
                    end,
                })
                rowY = rowY - hh
                if not CUI._prebuilding then -- Directions cog on Debuff Size (X/Y cluster offset)
                    CUI.BuildInlineCog(textSizeRow._leftRegion, {
                        disabled = bossDebuffSizeOff,
                        title = "Debuff Position",
                        rows = {
                            {
                                type = "slider",
                                label = "Offset X",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = BossGet("debuffOffsetX", 0),
                                set = BossSet("debuffOffsetX", true),
                            },
                            {
                                type = "slider",
                                label = "Offset Y",
                                min = -200,
                                max = 200,
                                step = 1,
                                get = BossGet("debuffOffsetY", 0),
                                set = BossSet("debuffOffsetY", true),
                            },
                            -- Physical-pixel-perfect gap between the boss debuff icons.
                            {
                                type = "slider",
                                pixel = true,
                                label = "Spacing",
                                min = -1,
                                max = 10,
                                step = 1,
                                get = BossGet("debuffSpacing", 1),
                                set = BossSet("debuffSpacing", true),
                            },
                        },
                    })
                end
                if not CUI._prebuilding then -- Icon Zoom cog on Debuff Size
                    local bossDebuffZoomOff = function()
                        return (saved.profile.boss.debuffAnchor or "bottomleft") == "none"
                    end
                    CUI.BuildInlineCog(textSizeRow._leftRegion, {
                        disabled = bossDebuffZoomOff,
                        disabledTooltip = "Debuffs Location",
                        title = "Icon Zoom",
                        rows = {
                            {
                                type = "slider",
                                label = "Zoom",
                                min = 0,
                                max = 0.20,
                                step = 0.01,
                                get = BossGet("debuffIconZoom", 0.07),
                                set = BossSet("debuffIconZoom", true),
                            },
                        },
                    })
                end
                -- Debuff Text Size cog (right): Show Duration + Duration X/Y + Stack.
                -- Disabled while Simple Debuff Display is active.
                if not CUI._prebuilding then
                    local rightRegion = textSizeRow._rightRegion
                    -- Inline Duration + Stack text-color swatches on the Debuff Text
                    -- Size slider; greyed + mouse-disabled on the same condition as
                    -- the row's cog.
                    local debuffOff = function() return not BossDebuffLocationActive() end
                    CUI.BuildInlineCog(rightRegion, {
                        disabled = debuffOff,
                        disabledTooltip = "Debuffs Location",
                        title = "Duration & Stack",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show Duration",
                                get = function() return saved.profile.boss.debuffShowCooldownText end,
                                set = function(value)
                                    saved.profile.boss.debuffShowCooldownText = value
                                    ReloadAndUpdate()
                                    CUI:RefreshPage()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Duration X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = BossGet("debuffCooldownTextOffsetX", 0),
                                set = BossSet("debuffCooldownTextOffsetX"),
                            },
                            {
                                type = "slider",
                                label = "Duration Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = BossGet("debuffCooldownTextOffsetY", 0),
                                set = BossSet("debuffCooldownTextOffsetY"),
                            },
                            {
                                type = "slider",
                                label = "Stack Size",
                                min = 6,
                                max = 100,
                                step = 1,
                                get = BossGet("debuffStackTextSize", 14),
                                set = BossSet("debuffStackTextSize"),
                            },
                            {
                                type = "dropdown",
                                label = "Stack Position",
                                values = {
                                    bottomright = "Bottom Right",
                                    bottomleft = "Bottom Left",
                                    topright = "Top Right",
                                    topleft = "Top Left",
                                    center = "Center",
                                },
                                order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                                get = BossGet("debuffStackTextPosition", "bottomright"),
                                set = BossSet("debuffStackTextPosition"),
                            },
                            {
                                type = "slider",
                                label = "Stack X",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = BossGet("debuffStackTextOffsetX", 0),
                                set = BossSet("debuffStackTextOffsetX"),
                            },
                            {
                                type = "slider",
                                label = "Stack Y",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = BossGet("debuffStackTextOffsetY", 0),
                                set = BossSet("debuffStackTextOffsetY"),
                            },
                        },
                    })
                    -- Disabled while Simple Debuff Display is active: simple mode
                    -- uses its own (simpleDebuff*) cooldown text, so the regular
                    -- debuff Duration & Stack controls do not apply.
                    BossTextSwatch(rightRegion, "debuffCooldownTextColor", "Duration Text Color", debuffOff)
                    BossTextSwatch(rightRegion, "debuffStackTextColor", "Stack Text Color", debuffOff)
                end
            end -- close debuff sizing row hidden-while-None gate

            -- Built alongside the aura controls, then appended at the end
            -- of this section to keep border settings consistently last.
            local function AddBossAuraBorderSettings()
                local B = saved.profile.boss
                -- Row accessors over B: a key read (or its default) and written.
                local function BFieldThen(settingKey)
                    return function(value)
                        B[settingKey] = value
                        ReloadAndUpdate()
                    end
                end
                local function BFieldOr(settingKey, default)
                    return function() return B[settingKey] or default end
                end
                local texValues, texOrder = CUI.GetBorderTextureDropdown()
                local borderRow
                borderRow, hh = Ww:DualRow(
                    profile,
                    rowY,
                    CUI.BlizzStyle.Gate("unitframes", {
                        type = "dropdown",
                        text = "Border Style",
                        values = texValues,
                        order = texOrder,
                        getValue = BFieldOr("auraBorderTexture", "solid"),
                        setValue = function(value)
                            local color, behind, behindUnitFrame =
                                CUI.GetBorderStyleSelectDefaults(value)
                            B.auraBorderTexture = value
                            B.auraBorderTextureOffset = nil
                            B.auraBorderTextureOffsetY = nil
                            B.auraBorderTextureShiftX = nil
                            B.auraBorderTextureShiftY = nil
                            B.auraBorderBehind = behind
                            B.auraBorderBehindUnitFrame = behindUnitFrame
                            B.auraBorderR = color.r
                            B.auraBorderG = color.g
                            B.auraBorderB = color.b
                            B.auraBorderA = 1
                            local ds = CUI.GetBorderDefaultSize("unitframes", value)
                            if ds then B.auraBorderSize = ds end
                            -- A style pick returns the icons to their legacy step; clear a
                            -- set exact size (false travels through mirror sync, nil would not).
                            if B.auraBorderSizePx then B.auraBorderSizePx = false end
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                            -- The Width / Height Offset row exists only under a textured style.
                            CUI:RefreshPage(true)
                        end,
                    }),
                    CUI.BlizzStyle.Gate(
                        "unitframes",
                        CUI.BorderPxSliderCfg({
                            text = "Border Size",
                            trackWidth = 120,
                            getStep = function() return B.auraBorderSize or 1 end,
                            setStep = function(step) B.auraBorderSize = step end,
                            getTex = function() return B.auraBorderTexture or "solid" end,
                            getPx = function() return B.auraBorderSizePx end,
                            setPx = function(value) B.auraBorderSizePx = value end,
                            apply = function()
                                ReloadAndUpdate()
                                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                            end,
                        })
                    )
                )
                rowY = rowY - hh
                -- Width Offset | Height Offset: a textured aura border's outward
                -- offsets (a Solid border has none).
                do
                    local abTex = B.auraBorderTexture or "solid"
                    if abTex ~= "solid" and abTex ~= "" then
                        local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                            addonKey = "unitframes",
                            getTex = function() return B.auraBorderTexture or "solid" end,
                            getStep = function() return B.auraBorderSize or 1 end,
                            getSizeKey = function() return B.auraBorderSize or 1 end,
                            getPx = function() return B.auraBorderSizePx end,
                            getX = function() return B.auraBorderTextureOffset end,
                            setX = function(value) B.auraBorderTextureOffset = value end,
                            getY = function() return B.auraBorderTextureOffsetY end,
                            setY = function(value) B.auraBorderTextureOffsetY = value end,
                            apply = function()
                                ReloadAndUpdate()
                                if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                            end,
                        })
                        local offRow
                        offRow, hh = Ww:DualRow(
                            profile,
                            rowY,
                            CUI.BlizzStyle.Gate("unitframes", ocfgL),
                            CUI.BlizzStyle.Gate("unitframes", ocfgR)
                        )
                        rowY = rowY - hh
                    end
                end
                if not CUI._prebuilding then
                    local region = borderRow._leftRegion
                    local button = CUI.BuildInlineCog(region, {
                        title = "Border Options",
                        rows = {
                            {
                                type = "slider",
                                label = "Shift X",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local value = B.auraBorderTextureShiftX
                                    if value ~= nil then return value end
                                    local _, _, posX = CUI.GetBorderDefaults(
                                        "unitframes",
                                        B.auraBorderTexture or "solid",
                                        B.auraBorderSize or 1
                                    )
                                    return posX
                                end,
                                set = function(value)
                                    B.auraBorderTextureShiftX = value == 0 and nil or value
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Shift Y",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local value = B.auraBorderTextureShiftY
                                    if value ~= nil then return value end
                                    local _, _, _, posY = CUI.GetBorderDefaults(
                                        "unitframes",
                                        B.auraBorderTexture or "solid",
                                        B.auraBorderSize or 1
                                    )
                                    return posY
                                end,
                                set = function(value)
                                    B.auraBorderTextureShiftY = value == 0 and nil or value
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show Behind",
                                get = BFieldOr("auraBorderBehind", false),
                                set = BFieldThen("auraBorderBehind"),
                            },
                            {
                                type = "toggle",
                                label = "Behind Unit Frame",
                                get = BFieldOr("auraBorderBehindUnitFrame", false),
                                set = BFieldThen("auraBorderBehindUnitFrame"),
                            },
                            {
                                type = "toggle",
                                label = "Border Above Effects",
                                tooltip = "Draws boss aura icon borders over their cooldown swipes and glows. Duration and stack text stay above the borders.",
                                disabled = function()
                                    local texture = B.auraBorderTexture or "solid"
                                    return B.auraBorderBehind
                                        or B.auraBorderBehindUnitFrame
                                        or texture == "solid"
                                        or texture == ""
                                        or (B.auraBorderSize or 1) <= 0
                                end,
                                disabledTooltip = "This option requires a textured Aura Border with a size above 0, and its Show Behind and Behind Unit Frame options disabled.",
                                rawTooltip = true,
                                get = function() return B.auraBorderAboveEffects == true end,
                                set = BFieldThen("auraBorderAboveEffects"),
                            },
                        },
                    })
                    local function vis()
                        if (B.auraBorderTexture or "solid") == "solid" then
                            button:Hide()
                        else
                            button:Show()
                        end
                    end
                    CUI.RegisterWidgetRefresh(vis)
                    vis()
                end
                if not CUI._prebuilding then
                    local region = borderRow._rightRegion
                    local swatch, upd = CUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            return B.auraBorderR or 0,
                                B.auraBorderG or 0,
                                B.auraBorderB or 0,
                                B.auraBorderA or 1
                        end,
                        function(red, green, blue, a)
                            B.auraBorderR = red
                            B.auraBorderG = green
                            B.auraBorderB = blue
                            B.auraBorderA = a
                            ReloadAndUpdate()
                        end,
                        true,
                        20
                    )
                    Pix.Point(swatch, "RIGHT", region._control, "LEFT", -8, 0)
                    CUI.RegisterWidgetRefresh(upd)
                end
            end
            AddBossAuraBorderSettings()
            -- Boss Debuff Filter in slot 1: the native mode dropdown, disabled
            -- with the requirement tooltip while no debuffs show at all (Simple
            -- Debuff Display None + Debuffs Location None). The right slot is the
            -- Boss Buff Filter.
            local filterRow
            local filterOff = function()
                local bossCfg = saved.profile.boss
                return mod.GetBossSimpleDebuffMode(bossCfg) == "none"
                    and (bossCfg.debuffAnchor or "bottomleft") == "none"
            end
            local function BossS() return saved.profile.boss end
            local buffFilterOff
            local bossFilterRightSlot = { type = "label", text = "" }
            buffFilterOff = function()
                local bossCfg = saved.profile.boss
                return mod.GetBossSimpleBuffMode(bossCfg) == "none" and not bossCfg.showBuffs
            end
            bossFilterRightSlot = {
                type = "dropdown",
                text = "Boss Buff Filter",
                disabled = buffFilterOff,
                disabledTooltip = "Buffs",
                requireState = "displayed",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            }
            filterRow, hh = Ww:DualRow(
                profile,
                rowY,
                DebuffModeDropdownCfg(
                    "Boss Debuff Filter",
                    "boss",
                    BossS,
                    ReloadAndUpdate,
                    { disabled = filterOff, disabledTooltip = "Debuffs", requireState = "displayed" }
                ),
                bossFilterRightSlot
            )
            rowY = rowY - hh
            if not CUI._prebuilding then
                AttachDebuffModeWarn(filterRow._leftRegion, BossS, filterOff)
                -- Hide Exhaustion, the Debuff Filter cog row every unit shares.
                CUI.BuildInlineCog(filterRow._leftRegion, {
                    title = "Debuff Filter",
                    tip = "Debuff Filter Options",
                    disabled = filterOff,
                    disabledTooltip = "Debuffs",
                    requireState = "displayed",
                    rows = { HideExhaustionRow(BossS, ReloadAndUpdate) },
                })
            end
            -- Right slot: Boss Buff Filter (two-lane checkbox dropdown).
            if not CUI._prebuilding then
                local region = filterRow._rightRegion
                if region._control then region._control:Hide() end
                local checkDrop, cbRefresh = CUI.BuildVisOptsCBDropdown(
                    region,
                    210,
                    region:GetFrameLevel() + 2,
                    buffFilterItems,
                    function(keyName, neg)
                        if neg then
                            local m = saved.profile.boss.buffNegClasses
                            local sk = BOSS_BUFF_NEG_SKEYS[keyName]
                            return m ~= nil and sk ~= nil and m[sk] == true
                        end
                        return saved.profile.boss[BUFF_FILTER_KEYS[keyName]] or false
                    end,
                    function(keyName, value, neg)
                        local bt = saved.profile.boss
                        local sk = BOSS_BUFF_NEG_SKEYS[keyName]
                        if neg then
                            if not sk then return end
                            bt.buffNegClasses = bt.buffNegClasses or {}
                            bt.buffNegClasses[sk] = value and true or nil
                            if not next(bt.buffNegClasses) then bt.buffNegClasses = nil end
                            if value then bt[BUFF_FILTER_KEYS[keyName]] = nil end
                            ReloadAndUpdate()
                            return
                        end
                        if value and sk and bt.buffNegClasses then
                            bt.buffNegClasses[sk] = nil
                            if not next(bt.buffNegClasses) then bt.buffNegClasses = nil end
                        end
                        bt[BUFF_FILTER_KEYS[keyName]] = value
                        ReloadAndUpdate()
                    end
                )
                Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
                region._control = checkDrop
                region._lastInline = nil
                CUI.RegisterWidgetRefresh(cbRefresh)
                local buffFilterBlock = CUI.NewSwatchBlocker(checkDrop)
                buffFilterBlock:SetScript(
                    "OnEnter",
                    function()
                        CUI.ShowWidgetTooltip(checkDrop, CUI.DisabledTooltip("Buffs", "displayed"))
                    end
                )
                buffFilterBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                local function UpdateBuffFilterDisabled()
                    if buffFilterOff() then
                        checkDrop:SetAlpha(0.3)
                        buffFilterBlock:Show()
                    else
                        checkDrop:SetAlpha(1)
                        buffFilterBlock:Hide()
                    end
                end
                UpdateBuffFilterDisabled()
                CUI.RegisterWidgetRefresh(UpdateBuffFilterDisabled)
            end
        end

        -- Cogwheel on Buffs Location (disabled while Simple Buff Display
        -- overrides placement, or when Buffs Location is None)
        if not CUI._prebuilding then
            local leftRegion = bossAuraRow._leftRegion
            CUI.BuildInlineCog(leftRegion, {
                disabled = bossBuffSizeOff,
                -- Both branches are whole sentences (raw), so translated clients wrap once.
                disabledTooltip = function()
                    return mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none"
                            and CUI.DisabledTooltip("Simple Buff Display", "disabled")
                        or CUI.DisabledTooltip("Buffs Location")
                end,
                rawTooltip = true,
                title = "Buff Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Growth Direction",
                        values = buffGrowthValues,
                        order = buffGrowthOrder,
                        get = BossGet("buffGrowth", "auto"),
                        set = BossSet("buffGrowth"),
                    },
                    {
                        type = "slider",
                        label = "Max Count",
                        min = 1,
                        max = 20,
                        step = 1,
                        tooltip = mod.UFO_MAX_COUNT_TOOLTIP,
                        get = BossGet("maxBuffs", 4),
                        set = BossSet("maxBuffs"),
                    },
                    {
                        type = "slider",
                        label = "Max Per Row",
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function()
                            return saved.profile.boss.buffMaxPerRow or saved.profile.boss.maxBuffs or 4
                        end,
                        set = function(value)
                            saved.profile.boss.buffMaxPerRow = value
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Dispel Type Borders",
                        disabled = function() return CUI.BlizzStyle.Get("unitframes") end,
                        disabledTooltip = "This option requires Blizzard Style to be disabled",
                        get = function() return saved.profile.boss.buffDispelBorder == true end,
                        set = function(value)
                            saved.profile.boss.buffDispelBorder = value
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
        end

        -- Cogwheel on Debuffs Location (hidden when Simple Debuff Display overrides placement)
        if not CUI._prebuilding then
            local rightRegion = bossAuraRow._rightRegion
            CUI.BuildInlineCog(rightRegion, {
                disabled = bossDebuffSizeOff,
                disabledTooltip = function()
                    return mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none"
                            and CUI.DisabledTooltip("Simple Debuff Display", "disabled")
                        or CUI.DisabledTooltip("Debuffs Location")
                end,
                rawTooltip = true,
                title = "Debuff Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Growth Direction",
                        values = buffGrowthValues,
                        order = buffGrowthOrder,
                        get = BossGet("debuffGrowth", "auto"),
                        set = BossSet("debuffGrowth"),
                    },
                    {
                        type = "slider",
                        label = "Max Count",
                        min = 1,
                        max = 20,
                        step = 1,
                        tooltip = mod.UFO_MAX_COUNT_TOOLTIP,
                        get = BossGet("maxDebuffs", 10),
                        set = BossSet("maxDebuffs"),
                    },
                    mod.UFO_MaxImportantRow(
                        function() return saved.profile.boss end,
                        ReloadAndUpdate,
                        20,
                        10
                    ),
                    {
                        type = "slider",
                        label = "Max Per Row",
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function()
                            return saved.profile.boss.debuffMaxPerRow or saved.profile.boss.maxDebuffs or 10
                        end,
                        set = function(value)
                            saved.profile.boss.debuffMaxPerRow = value
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
        end

        -- Buff/Debuff text colors now live as inline swatches on the Buff Text
        -- Size / Debuff Text Size sliders above (Duration + Stack per side).

        return rowY
    end

    -- New "Indicators" section, rendered at the BOTTOM (below the Power Bar)
    -- via opts.afterPowerRow. Holds the non-aura indicators moved out of the
    -- Buffs and Debuffs section above.
    local function bossIndicators(Ww, profile, rowY)
        local hh

        _, hh = Ww:SectionHeader(profile, "INDICATORS", rowY)
        rowY = rowY - hh

        -- Row 1: Out of Range Alpha | Spell Target
        -- (Out of Range read live by the range ticker, so no reload needed.)
        local bossTgtRow
        bossTgtRow, hh = Ww:DualRow(profile, rowY, {
            type = "slider",
            text = "Out of Range Alpha",
            min = 10,
            max = 100,
            step = 1,
            tooltip = "Fades boss frames when the boss is out of range of your spells. Set to 100% to disable the fade.",
            getValue = function() return math.floor(((saved.profile.boss.oorAlpha or 0.4) * 100) + 0.5) end,
            setValue = function(value) saved.profile.boss.oorAlpha = value / 100 end,
        }, {
            type = "toggle",
            text = "Spell Target",
            tooltip = "Show the name of who the boss is casting on.",
            getValue = function() return saved.profile.boss.showCastTarget == true end,
            setValue = function(value)
                saved.profile.boss.showCastTarget = value
                ReloadAndUpdate()
            end,
        })
        rowY = rowY - hh
        -- Inline cog on Spell Target: X/Y offsets for the cast target
        -- text. Boss-scoped copies of the shared castbar keys, which the
        -- runtime and preview already consume (castSpellTargetX/Y ->
        -- _tgtOX/_tgtOY in the cast text zone layout).
        if not CUI._prebuilding then
            CUI.BuildInlineCog(bossTgtRow._rightRegion, {
                title = "Spell Target",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -300,
                        max = 300,
                        step = 1,
                        get = BossGet("castSpellTargetX", 0),
                        set = BossSet("castSpellTargetX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -300,
                        max = 300,
                        step = 1,
                        get = BossGet("castSpellTargetY", 0),
                        set = BossSet("castSpellTargetY"),
                    },
                },
            })
        end

        -- Row 2: Show Raid Marker | Raid Marker Size (+ position cog)
        local function bossRmOff() return saved.profile.boss.raidMarkerEnabled == false end
        local bossRmRow
        bossRmRow, hh = Ww:DualRow(profile, rowY, {
            type = "toggle",
            text = "Show Raid Marker",
            tooltip = "Shows the raid target marker icon on boss frames.",
            getValue = function() return saved.profile.boss.raidMarkerEnabled ~= false end,
            setValue = function(value)
                saved.profile.boss.raidMarkerEnabled = value
                ReloadAndUpdate()
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Raid Marker Size",
            min = 12,
            max = 48,
            step = 1,
            disabled = bossRmOff,
            disabledTooltip = "Raid Marker",
            getValue = function() return saved.profile.boss.raidMarkerSize or 28 end,
            setValue = function(value)
                saved.profile.boss.raidMarkerSize = value
                ReloadAndUpdate()
            end,
        })
        rowY = rowY - hh
        if not CUI._prebuilding then
            CUI.BuildInlineCog(bossRmRow._leftRegion, {
                title = "Raid Marker Position",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = BossGet("raidMarkerX", 0),
                        set = BossSet("raidMarkerX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = BossGet("raidMarkerY", 0),
                        set = BossSet("raidMarkerY"),
                    },
                    {
                        type = "dropdown",
                        label = "Alignment",
                        values = { left = "Left", center = "Center", right = "Right" },
                        order = { "left", "center", "right" },
                        get = BossGet("raidMarkerAlign", "left"),
                        set = BossSet("raidMarkerAlign"),
                    },
                },
            })
        end

        return rowY
    end

    -- CAST BAR section, rendered below the Power Bar. Mirrors the player cast
    -- bar's Show Cast Bar/Height/Bar Background/Spell Name/Duration/Reverse Fill.
    -- All keys are boss-scoped (db.profile.boss.*), read by the shared castbar
    -- runtime + preview so both live-update. "Show Cast Bar" off (showCastbar=false) hides it entirely (runtime disables Castbar; preview zero-heights it).
    local function bossCastBar(Ww, profile, rowY)
        local B = saved.profile.boss
        -- Row accessors over B: a key read (or its default) and written.
        local function BFieldThen(settingKey)
            return function(value)
                B[settingKey] = value
                ReloadAndUpdate()
            end
        end
        local function BFieldOr(settingKey, default)
            return function() return B[settingKey] or default end
        end
        local hh

        -- The Show Cast Bar toggle gates the rest of the section. AddCastBlock
        -- greys a region (slider/dropdown/toggle + any inline swatch) to 0.3 and
        -- blocks its mouse while the cast bar is off, tracked live via the
        -- widget-refresh fast path (mirrors AddDarkModeBlock). The toggle's own color swatches gate separately so the toggle stays interactive.
        local castColorSwatches = {}
        local function AddCastBlock(region, enabledAlpha)
            if not region then return end
            local block = CreateFrame("Frame", nil, region)
            block:SetAllPoints()
            block:SetFrameLevel(region:GetFrameLevel() + 50)
            block:EnableMouse(true)
            block:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(block, CUI.DisabledTooltip("Show Cast Bar")) end
            )
            block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function SyncCastAlpha()
                if B.showCastbar == false then
                    region:SetAlpha(0.3)
                    block:Show()
                else
                    region:SetAlpha(enabledAlpha and enabledAlpha() or 1)
                    block:Hide()
                end
            end
            SyncCastAlpha()
            CUI.RegisterWidgetRefresh(SyncCastAlpha)
        end

        bossCastHeader, hh = Ww:SectionHeader(profile, "CAST BAR", rowY)
        rowY = rowY - hh

        -- Row 1: Show Cast Bar (+ inline fill-color swatch) | Cast Bar Height
        castMainRow, hh = Ww:DualRow(profile, rowY, {
            type = "toggle",
            text = "Show Cast Bar",
            getValue = function() return B.showCastbar ~= false end,
            -- DependentSetValue: rows 2-4 below are hidden while the
            -- cast bar is off; the flip forces the full rebuild.
            setValue = CUI.DependentSetValue(
                function() return B.showCastbar ~= false end,
                function(value)
                    B.showCastbar = value
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                end
            ),
        }, {
            type = "slider",
            text = "Cast Bar Height",
            min = 1,
            max = 40,
            step = 1,
            disabled = function() return B.showCastbar == false end,
            disabledTooltip = "Show Cast Bar",
            getValue = BFieldOr("castbarHeight", 14),
            setValue = BFieldThen("castbarHeight"),
        })
        rowY = rowY - hh
        -- Inline settings cog matching target/focus, plus boss positioning.
        if not CUI._prebuilding then
            CUI.BuildInlineCog(castMainRow._leftRegion, {
                disabled = function() return B.showCastbar == false end,
                disabledTooltip = "Show Cast Bar",
                title = "Cast Bar",
                rows = {
                    {
                        type = "toggle",
                        label = "Hide When Idle",
                        tooltip = "Only show the cast bar while a cast is in progress; hide it the rest of the time.",
                        get = function() return B.castbarHideWhenInactive ~= false end,
                        set = BFieldThen("castbarHideWhenInactive"),
                    },
                    {
                        type = "slider",
                        label = "Fill Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        tooltip = "Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
                        get = BFieldOr("castFillOpacity", 100),
                        set = BFieldThen("castFillOpacity"),
                    },
                    {
                        type = "toggle",
                        label = "Raise Cast Bar Strata (All)",
                        tooltip = "Lifts player, target, focus, and boss cast bars above other frames so they are never hidden behind them.",
                        get = function() return saved.profile.raiseCastbarStrata ~= false end,
                        set = function(value)
                            saved.profile.raiseCastbarStrata = value
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Kick Ready Mid-Cast Tick",
                        tooltip = "Shows a small white tick mark where the cast will be when your interrupt comes off cooldown.",
                        get = function() return B.castbarKickTickEnabled ~= false end,
                        set = BFieldThen("castbarKickTickEnabled"),
                    },
                    {
                        type = "toggle",
                        label = "Show Kick Ready Mid-Cast Bar",
                        tooltip = "Colors the cast segment during which your interrupt will be available.",
                        get = function() return B.castbarInterruptMidCastEnabled == true end,
                        set = function(value)
                            B.castbarInterruptMidCastEnabled = value
                            ReloadAndUpdate()
                            CUI:RefreshPage()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -500,
                        max = 500,
                        step = 1,
                        get = BFieldOr("castbarOffsetX", 0),
                        set = function(value)
                            B.castbarOffsetX = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = BFieldOr("castbarOffsetY", 0),
                        set = function(value)
                            B.castbarOffsetY = value
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                        end,
                    },
                    -- Opt-in for the Border Style | Border Size rows (built
                    -- below only while on; the rebuild shows or drops them).
                    {
                        type = "toggle",
                        label = "Custom Border Style",
                        tooltip = "Show the border style and size controls for the cast bar.",
                        disabled = function() return CUI.BlizzStyle.Get("unitframes") end,
                        disabledTooltip = function() return CUI.BlizzStyle.Label("unitframes") end,
                        requireState = "disabled",
                        get = function() return B.castBorderCustom == true end,
                        set = function(value)
                            B.castBorderCustom = value
                            ReloadAndUpdate()
                            CUI:RefreshPage(true)
                        end,
                    },
                },
            })
        end
        -- Enemy cast colors on Show Cast Bar (left region), matching target/focus.
        if not CUI._prebuilding then
            local region = castMainRow._leftRegion
            local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
                local swatch, updateSw = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local color = B[colorKey] or fallback
                        return color.r, color.g, color.b, 1
                    end,
                    function(red, green, blue)
                        B[colorKey] = { r = red, g = green, b = blue }
                        ReloadAndUpdate()
                    end,
                    false,
                    20
                )
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                swatch:SetScript("OnEnter", function(self) CUI.ShowWidgetTooltip(self, tooltip) end)
                swatch:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                region._lastInline = swatch
                castColorSwatches[#castColorSwatches + 1] = {
                    sw = swatch,
                    enabledAlpha = disabledFn and function() return disabledFn() and 0.3 or 1 end,
                }
                if disabledFn then
                    local function SyncCastAlpha()
                        local off = disabledFn()
                        swatch:SetAlpha(off and 0.3 or 1)
                        swatch:EnableMouse(not off)
                        if updateSw then updateSw() end
                    end
                    SyncCastAlpha()
                    CUI.RegisterWidgetRefresh(SyncCastAlpha)
                end
            end
            AddCastColorSwatch(
                "Interrupt Ready Mid-Cast",
                "castbarInterruptMidCastColor",
                { r = 0.318, g = 0.820, b = 0.357 },
                function() return B.castbarInterruptMidCastEnabled ~= true end
            )
            AddCastColorSwatch(
                "Interrupt on CD",
                "castbarInterruptReadyColor",
                { r = 0.92, g = 0.35, b = 0.20 }
            )
            AddCastColorSwatch(
                "Uninterruptible Cast",
                "castbarUninterruptibleColor",
                { r = 0.5, g = 0.5, b = 0.5 }
            )
            AddCastColorSwatch("Interruptible Cast", "castbarFillColor", { r = 0.863, g = 0.820, b = 0.639 })
        end

        -- Rows 2-4 are HIDDEN entirely while Show Cast Bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips). The
        -- master row's own inlines (color swatches) keep the
        -- AddCastBlock grey+block treatment; its cog disables itself.
        if B.showCastbar ~= false then
            -- Row 2: Show Cast Icon (+ icon cog) | Cast Bar Width (right under Cast
            -- Bar Height so the two dimensions sit stacked in the same column)
            growthRow, hh = Ww:DualRow(profile, rowY, {
                type = "toggle",
                text = "Show Cast Icon",
                getValue = function() return B.showCastIcon ~= false end,
                setValue = BFieldThen("showCastIcon"),
            }, {
                type = "slider",
                text = "Cast Bar Width",
                min = 0,
                max = 500,
                step = 1,
                tooltip = "Sets a custom width for the cast bar. Set to 0 to match the boss frame width.",
                getValue = BFieldOr("castbarWidth", 0),
                -- Custom widths floor at 30 (matches the unlock-mode resize
                -- minimum): below the cast icon size the bar layout inverts.
                setValue = function(value)
                    if value > 0 and value < 30 then value = 30 end
                    B.castbarWidth = value
                    ReloadAndUpdate()
                    if mod.RefreshBossPreviewDebuffs then mod.RefreshBossPreviewDebuffs() end
                end,
            })
            rowY = rowY - hh
            -- Icon cog (left): "Icon Border" / "Make Icon Part of the Bar" /
            -- "Border Wraps Icon" / "Vertical Separator" / "Show Icon on Right".
            if not CUI._prebuilding then
                CUI.BuildInlineCog(growthRow._leftRegion, {
                    title = "Cast Icon",
                    rows = {
                        {
                            type = "toggle",
                            label = "Icon Border",
                            tooltip = "Use the cast bar's border style, size and color around the icon.",
                            disabled = function()
                                return CUI.BlizzStyle.Get("unitframes") or B.showCastIcon == false
                            end,
                            disabledTooltip = "This option requires Show Icon and the CludesUI style.",
                            get = function() return B.castIconBorder == true end,
                            set = BFieldThen("castIconBorder"),
                        },
                        {
                            type = "toggle",
                            label = "Make Icon Part of the Bar",
                            tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                            -- The stock styles count a shown icon as part of the bar
                            -- (their frame art wraps both), so the toggle reads on and locks.
                            disabled = function() return CUI.BlizzStyle.Get("unitframes") end,
                            disabledTooltip = function() return CUI.BlizzStyle.Label("unitframes") end,
                            requireState = "disabled",
                            get = function()
                                if CUI.BlizzStyle.Get("unitframes") then return true end
                                return B.castbarIconInWidth ~= false
                            end,
                            set = BFieldThen("castbarIconInWidth"),
                        },
                        {
                            type = "toggle",
                            label = "Border Wraps Icon",
                            tooltip = "Draw the custom cast bar border around the icon and the bar together. An icon with an offset keeps its own border.",
                            disabled = function()
                                return CUI.BlizzStyle.Get("unitframes")
                                    or B.castBorderCustom ~= true
                                    or not mod.UF_CastIconInWidth("boss", B)
                            end,
                            disabledTooltip = "This option requires Custom Border Style, Show Icon and Make Icon Part of the Bar, with the CludesUI style.",
                            get = function() return B.castBorderWrapIcon == true end,
                            set = BFieldThen("castBorderWrapIcon"),
                        },
                        {
                            type = "toggle",
                            label = "Vertical Separator",
                            tooltip = "Draw a divider between the integrated icon and the bar, using the cast bar's border appearance.",
                            disabled = function()
                                return CUI.BlizzStyle.Get("unitframes")
                                    or not mod.UF_CastIconInWidth("boss", B)
                                    or not mod.UF_CastIconSeamOK(B)
                            end,
                            disabledTooltip = function()
                                if
                                    CUI.BlizzStyle.Get("unitframes")
                                    or not mod.UF_CastIconInWidth("boss", B)
                                then
                                    return "This option requires Show Icon and Make Icon Part of the Bar, with the CludesUI style."
                                end
                                return "This option requires Solid or a border style with divider art, and a Border Size above 0."
                            end,
                            get = function() return B.castIconSeparator == true end,
                            set = BFieldThen("castIconSeparator"),
                        },
                        {
                            type = "toggle",
                            label = "Show Icon on Right",
                            tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                            get = function() return B.castbarIconRight == true end,
                            set = BFieldThen("castbarIconRight"),
                        },
                    },
                })
            end
            -- Row 3: Reverse Fill | Bar Background (opacity slider + color swatch).
            -- Bar Background sits right below the size sliders (mirrors the main
            -- frames' cast bar section, where it follows the Height row).
            local reverseRow
            reverseRow, hh = Ww:DualRow(profile, rowY, {
                type = "toggle",
                text = "Reverse Fill",
                getValue = function() return B.castReverseFill == true end,
                setValue = BFieldThen("castReverseFill"),
            }, {
                type = "slider",
                text = "Bar Background",
                min = 0,
                max = 100,
                step = 1,
                getValue = function() return math.floor((B.castBgAlpha or 0.5) * 100 + 0.5) end,
                setValue = function(value)
                    B.castBgAlpha = value / 100
                    ReloadAndUpdate()
                end,
            })
            rowY = rowY - hh
            -- Inline color swatch on Bar Background (right region).
            if not CUI._prebuilding then
                local region = reverseRow._rightRegion
                local swatch = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local color = B.castBgColor
                    if color then return color.r, color.g, color.b end
                    return 0, 0, 0
                end, function(red, green, blue)
                    B.castBgColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                end, false, 20)
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                swatch:SetScript(
                    "OnEnter",
                    function(self) CUI.ShowWidgetTooltip(self, "Cast Background") end
                )
                swatch:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                region._lastInline = swatch
            end

            -- Row 4: Spell Name (dropdown + Size/X/Y cog + swatch) | Duration (same)
            local castTextRow
            castTextRow, hh = Ww:DualRow(profile, rowY, {
                type = "dropdown",
                text = "Spell Name",
                values = { none = "None", left = "Left", right = "Right", center = "Center" },
                order = { "none", "left", "right", "center" },
                getValue = BFieldOr("castSpellNameSide", "left"),
                setValue = function(value)
                    B.castSpellNameSide = value
                    -- Conflict rule (mirrors player): name and the spell target may
                    -- not share a side -- setting the name onto the target's side
                    -- turns the target (Indicators) off.
                    if
                        value ~= "none"
                        and (B.showCastTarget ~= false)
                        and (B.castSpellTargetSide or "right") == value
                    then
                        B.showCastTarget = false
                    end
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                end,
            }, {
                type = "segmented",
                text = "Duration",
                values = { none = "None", right = "Right", left = "Left" },
                order = { "none", "right", "left" },
                getValue = function()
                    if B.showCastDuration == false then return "none" end
                    return B.castDurationSide or "right"
                end,
                setValue = function(value)
                    if value == "none" then
                        B.showCastDuration = false
                    else
                        B.showCastDuration = true
                        B.castDurationSide = value
                    end
                    ReloadAndUpdate()
                    CUI:RefreshPage()
                end,
            })
            rowY = rowY - hh
            -- Spell Name (left): Size/X/Y cog + color swatch
            if not CUI._prebuilding then
                local region = castTextRow._leftRegion
                CUI.BuildInlineCog(region, {
                    title = "Spell Name",
                    rows = {
                        {
                            type = "slider",
                            label = "Size",
                            min = 6,
                            max = 20,
                            step = 1,
                            get = BFieldOr("castSpellNameSize", 11),
                            set = BFieldThen("castSpellNameSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = BFieldOr("castSpellNameX", 0),
                            set = BFieldThen("castSpellNameX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = BFieldOr("castSpellNameY", 0),
                            set = BFieldThen("castSpellNameY"),
                        },
                    },
                })
                local swatch = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local color = B.castSpellNameColor or { r = 1, g = 1, b = 1 }
                    return color.r, color.g, color.b
                end, function(red, green, blue)
                    B.castSpellNameColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                end, false, 20)
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = swatch
            end
            -- Duration (right): Size/X/Y cog + color swatch
            if not CUI._prebuilding then
                local region = castTextRow._rightRegion
                CUI.BuildInlineCog(region, {
                    title = "Duration",
                    rows = {
                        {
                            type = "slider",
                            label = "Size",
                            min = 6,
                            max = 20,
                            step = 1,
                            get = BFieldOr("castDurationSize", 10),
                            set = BFieldThen("castDurationSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = BFieldOr("castDurationX", 0),
                            set = BFieldThen("castDurationX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = BFieldOr("castDurationY", 0),
                            set = BFieldThen("castDurationY"),
                        },
                    },
                })
                local swatch = CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local color = B.castDurationColor or { r = 1, g = 1, b = 1 }
                    return color.r, color.g, color.b
                end, function(red, green, blue)
                    B.castDurationColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                end, false, 20)
                swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = swatch
            end
            -- Custom Border Style rows (the Cast Bar cog's opt-in): one table
            -- styles all five boss cast bars; no unlock element, no sync links.
            if B.castBorderCustom == true then
                rowY = rowY
                    - mod.UF_CastBorderRows(Ww, profile, rowY, function() return B end, ReloadAndUpdate)
            end
            -- Classic WoW UI: Border Size closes the section (odd last slot).
            rowY = rowY
                - mod.UF_ClassicCastBorderRow(
                    Ww,
                    profile,
                    rowY,
                    function() return B end,
                    mod.UF_CastClassicKey("boss"),
                    function() ReloadAndUpdate() end
                )
        end -- close boss Cast Bar hidden-while-disabled gate

        -- The Show Cast Bar toggle's own color swatches stay gated grey +
        -- blocked while the cast bar is off (the Height slider uses a
        -- native disabled state; the hidden rows need nothing).
        for _, entry in ipairs(castColorSwatches) do
            AddCastBlock(entry.sw, entry.enabledAlpha)
        end
        return rowY
    end

    local headerFrame, sizeRow, textHeader, textRow
    posY, headerFrame, sizeRow, textHeader, textRow =
        BuildMiniTextAndSize(W, hostFrame, posY, saved.profile.boss, "boss", enableRow, bossAfterSize, {
            hasPowerBar = true,
            afterPowerRow = function(Ww, profile, rowY)
                rowY = bossCastBar(Ww, profile, rowY)
                return bossIndicators(Ww, profile, rowY)
            end,
        })

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        -- Health bar -> Health Bar Height (sizeRow left, HEALTH BAR section);
        -- Power bar -> Power Bar Height (pwrRow1 left, POWER BAR section).
        healthBar = { section = textHeader or headerFrame, target = sizeRow, slotSide = "left" },
        powerBar = {
            section = hostFrame._powerHeaderFrame or headerFrame,
            target = hostFrame._powerHeightRow,
            slotSide = "left",
        },
        powerBarText = {
            section = hostFrame._powerHeaderFrame or headerFrame,
            target = hostFrame._powerTextRow,
            slotSide = "left",
        },
        portrait = { section = headerFrame, target = portraitLine, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or headerFrame,
            textRow or sizeRow
        ),
        -- Blizzard Style level number -> Show Level (+ its cog).
        levelText = {
            section = textHeader or headerFrame,
            target = hostFrame._ufLevelRow,
            slotSide = "left",
        },
        -- Cast bar -> Cast Bar Height; spell icon -> Show Cast Icon. Both live
        -- in growthRow after the swap (Show Cast Icon left, Cast Bar Height right).
        castBar = {
            section = bossCastHeader or headerFrame,
            target = castMainRow or growthRow,
            slotSide = "left",
        },
        castIcon = { section = bossCastHeader or headerFrame, target = growthRow, slotSide = "left" },
        -- Buffs/Debuffs scroll to the active control: Simple Display when it's
        -- on (the column is forced), otherwise the normal Location dropdown.
        buffIcon = function()
            if mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none" then
                return { section = bossAuraHeader or headerFrame, target = simpleBuffRow }
            end
            return { section = bossAuraHeader or headerFrame, target = bossAuraRow, slotSide = "left" }
        end,
        debuffIcon = function()
            if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then
                return { section = bossAuraHeader or headerFrame, target = simpleRow }
            end
            return { section = bossAuraHeader or headerFrame, target = bossAuraRow, slotSide = "right" }
        end,
    }

    return abs(posY)
end
