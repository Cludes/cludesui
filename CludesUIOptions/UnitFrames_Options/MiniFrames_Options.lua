if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\MiniFrames_Options.lua
--  Unit Frames options: Mini Frames and Boss Frames builders. Definitions
--  only; the shared helpers come from ns._UFO_OptEnv (filled by
--  CUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIUnitFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept page go through the
-- options frame pool (CludesUI_FramePool.lua), which hands the next build
-- the previous build's frames reset to new; on any other parent it is the
-- plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
-- The pool's other calls this file makes, read once here as CreateFrame is:
-- the page path never calls the pool through its public slot, which
-- another addon could replace.
local PoolIsIdle = CludesUI._Pool.IsIdle

---------------------------------------------------------------------------
--  Mini frame donor settings helper
--  Returns the settings table unitKey copies its look from (its Copy Look
--  From pick, else focus, target, player). Routed through the runtime
--  resolver so the options preview and the live frames can never disagree
--  about which frame is on screen to inherit from.
---------------------------------------------------------------------------
local function GetMiniDonorSettings(unitKey)
    local environ = mod._UFO_OptEnv
    local saved = environ.db
    return mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitKey) or saved.profile.player
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
    settingsTable,
    unitKey,
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
    local _, hgt
    options = options or {}

    -- Shorthand accessors for this mini frame's settings
    local function MGet(key)
        return settingsTable[key]
    end
    local function MSet(key, val)
        settingsTable[key] = val
        ReloadAndUpdate()
    end
    local function MVal(key, default)
        local v = settingsTable[key]
        if v ~= nil then
            return v
        end
        return default
    end

    -- DISPLAY
    local displayHeader
    displayHeader, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - hgt
    -- The Move in Unlock Mode button on the frame's first section: its mover
    -- exists only for the CludesUI frame source, so the button explains
    -- itself while the frame is hidden (its enable toggle) or on Blizzard's frame.
    CludesUI.BuildSectionUnlockJump(displayHeader, {
        key = unitKey,
        disabled = function()
            return mod.GetUnitFrameSource(unitKey) ~= "cui"
        end,
        disabledTooltip = function()
            if mod.VisUnitDisabled(saved.profile, unitKey) then
                return MINI_ENABLE_LABELS[unitKey]
            end
            return "This option requires the CludesUI Frame Source."
        end,
    })
    posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "unitframes")

    -- Enable row (passed in from each builder)
    local enableRowFrame
    if enableRow then
        enableRowFrame, hgt = enableRow(W, hostFrame, posY)
        posY = posY - hgt
    end

    -- If this unit isn't on the CludesUI frame, skip the (inapplicable)
    -- settings below and show a short notice instead.
    if enableRow and mod.GetUnitFrameSource(unitKey) ~= "cui" then
        posY = BuildInactiveNotice(hostFrame, posY, mod.GetUnitFrameSource(unitKey))
        return posY, displayHeader, nil, nil, nil, enableRowFrame
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
            mo.background = function(key)
                if key == "inherit" then
                    local donor = GetMiniDonorSettings(unitKey)
                    local dk = donor and donor.healthBarTexture
                    if dk == "inherit" then
                        dk = nil
                    end
                    dk = dk or saved.profile.healthBarTexture
                    return dk and (mod.healthBarTextures or {})[dk] or nil
                end
                return baseBg and baseBg(key) or nil
            end
        end
        -- Boss frames get a "Hover Borders" control in the right slot (mirrors
        -- Raid Frames); the other mini frames leave that slot empty.
        local isBoss = (unitKey == "boss")
        local rightSlot
        if isBoss then
            rightSlot = {
                type = "dropdown",
                text = "Hover Borders",
                values = { __placeholder = "All" },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }
        else
            -- ToT / Focus Target / Pet: per-frame Strata override (same options as
            -- main frames' Frame Strata); inherits the global value until set
            -- (getter falls back to db.profile.frameStrata).
            local miniStrataValues = CludesUI.FRAME_STRATA_LABELS
            local miniStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
            rightSlot = {
                type = "dropdown",
                text = "Strata",
                tooltip = "Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
                values = miniStrataValues,
                order = miniStrataOrder,
                getValue = function()
                    return settingsTable.frameStrata or saved.profile.frameStrata or "MEDIUM"
                end,
                setValue = function(v)
                    settingsTable.frameStrata = v
                    ReloadAndUpdate()
                end,
            }
        end
        local barTexRow
        barTexRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Bar Texture",
            values = mtVals,
            order = mtOrder,
            getValue = function()
                local v = settingsTable.healthBarTexture
                if v == nil then
                    return "inherit"
                end
                return v
            end,
            setValue = function(v)
                if v == "inherit" then
                    settingsTable.healthBarTexture = nil
                else
                    settingsTable.healthBarTexture = v
                end
                ReloadAndUpdate()
            end,
        }, rightSlot)
        posY = posY - hgt
        -- Textured Background cog: while Bar Texture is Inherit the toggle
        -- follows the main frame and shows its value, greyed.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(barTexRow._leftRegion, {
                title = "Texture Settings",
                rows = {
                    TexBgRowCfg(function()
                        return settingsTable
                    end, ReloadAndUpdate, unitKey),
                },
            })
        end

        -- Boss Hover Borders: checkbox dropdown (Hover Border / Target Border,
        -- both default off) with inline color swatches. Enabling one recolors
        -- the boss frame's existing border to that color (hover > target).
        if isBoss and not CludesUI._prebuilding then
            local Pix = CludesUI.PP
            local rightRgn = barTexRow._rightRegion
            if rightRgn._control then
                rightRgn._control:Hide()
            end
            local hbKeyMap = { hover = "bossHoverBorderEnabled", target = "bossTargetBorderEnabled" }
            local hbItems = {
                { key = "hover", label = "Hover Border" },
                { key = "target", label = "Target Border" },
            }
            local UpdateHBSwatchVis -- forward declare; assigned after swatches
            local cbDD = CludesUI.BuildVisOptsCBDropdown(
                rightRgn,
                170,
                rightRgn:GetFrameLevel() + 2,
                hbItems,
                function(k)
                    return settingsTable[hbKeyMap[k]] and true or false
                end,
                function(k, v)
                    settingsTable[hbKeyMap[k]] = v
                    ReloadAndUpdate()
                    if UpdateHBSwatchVis then
                        UpdateHBSwatchVis()
                    end
                end
            )
            CludesUI.PanelPP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil

            -- Inline swatches: Hover (nearest the dropdown), then Target to its left.
            local lvl = barTexRow:GetFrameLevel() + 3
            local hoverSwatch, updHover = CludesUI.BuildColorSwatch(rightRgn, lvl, function()
                local c = settingsTable.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b, settingsTable.bossHoverBorderAlpha or 1
            end, function(r, g, b, a)
                settingsTable.bossHoverBorderColor = { r = r, g = g, b = b }
                settingsTable.bossHoverBorderAlpha = a
                ReloadAndUpdate()
            end, true, 20)
            hoverSwatch:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -8, 0)
            rightRgn._lastInline = hoverSwatch
            CludesUI.HoverTip(hoverSwatch, "Hover")

            local targetSwatch, updTarget = CludesUI.BuildColorSwatch(rightRgn, lvl, function()
                local c = settingsTable.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b, settingsTable.bossTargetBorderAlpha or 1
            end, function(r, g, b, a)
                settingsTable.bossTargetBorderColor = { r = r, g = g, b = b }
                settingsTable.bossTargetBorderAlpha = a
                ReloadAndUpdate()
            end, true, 20)
            targetSwatch:SetPoint("RIGHT", rightRgn._lastInline, "LEFT", -8, 0)
            rightRgn._lastInline = targetSwatch
            CludesUI.HoverTip(targetSwatch, "Target")

            -- Gray a swatch when its border state is off (still clickable so the
            -- color can be pre-set), matching the Raid Frames Hover Borders row.
            UpdateHBSwatchVis = function()
                hoverSwatch:SetAlpha(settingsTable.bossHoverBorderEnabled and 1 or 0.3)
                targetSwatch:SetAlpha(settingsTable.bossTargetBorderEnabled and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(function()
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
    if unitKey == "boss" then
        posY = posY - mod.UF_BossFrameBorderRows(W, hostFrame, posY, settingsTable, ReloadAndUpdate)
    end

    -- Dark Mode for this frame alone, as on the Main Frames page (unset follows the
    -- profile's). It feeds the Dark Mode override condition, so it rechecks it and is
    -- locked while such an override is edited.
    local darkCfg = {
        type = "toggle",
        text = "Dark Mode",
        tooltip = "Dark Mode for this frame. Global Settings > Colors switches every frame.",
        getValue = function()
            return mod.UF_DarkThemeOn(settingsTable)
        end,
        setValue = function(v)
            MSet("darkTheme", v)
            CludesUI.Conditions_Recheck()
            CludesUI:RefreshPage()
        end,
    }
    local function LockDark(region)
        if CludesUI._prebuilding then
            return
        end
        CludesUI.SpecOverrides_AttachEditLock(
            region,
            "Dark Mode drives a Dark Mode override condition and can't be changed while editing an override",
            CludesUI.SpecOverrides_DarkCondEditActive
        )
    end

    -- DISPLAY bottom row for boss: the mini frames carry their Strata
    -- override in the Bar Texture row's right slot, which boss spends on
    -- Hover Borders, so boss gets its own row here. Without it nothing in
    -- the UI writes a boss strata at all -- the main frames' dropdown is
    -- per-frame and the profile-wide value is only the fallback.
    if unitKey == "boss" then
        local bossStrataValues = CludesUI.FRAME_STRATA_LABELS
        local bossStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
        local strataRow
        strataRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Strata",
            tooltip = "Overrides the Frame Strata set in the main frames for this frame only. Controls the order that overlapping frames display in; set higher to show above other frames.",
            values = bossStrataValues,
            order = bossStrataOrder,
            getValue = function()
                return settingsTable.frameStrata or saved.profile.frameStrata or "MEDIUM"
            end,
            setValue = function(v)
                settingsTable.frameStrata = v
                ReloadAndUpdate()
            end,
        }, darkCfg)
        posY = posY - hgt
        LockDark(strataRow._rightRegion)
    end

    -- DISPLAY: per-frame Border Size override for ToT/Focus Target/Pet.
    -- Size only, no color/texture (those still inherit from main frames);
    -- borderSizeOverride nil = inherit donor size until set. Boss frames use
    -- their own Border Style | Border Size row above instead.
    if unitKey ~= "boss" then
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "slider",
                text = "Border Size",
                min = 0,
                max = 4,
                step = 1,
                tooltip = "Overrides the border size from the main frames for this frame only. Border color and texture still follow the main frames.",
                getValue = function()
                    local donor = GetMiniDonorSettings(unitKey)
                    return settingsTable.borderSizeOverride or (donor and donor.borderSize) or 1
                end,
                setValue = function(v)
                    settingsTable.borderSizeOverride = v
                    ReloadAndUpdate()
                end,
            }),
            {
                type = "toggle",
                text = "Show Highlight Border",
                tooltip = "Show the main frames' hover highlight border on this frame. Turn off so this frame never recolors on mouseover. No effect when Highlight is off in the main frames' Hover Borders.",
                getValue = function()
                    return settingsTable.showHighlightBorder ~= false
                end,
                setValue = function(v)
                    settingsTable.showHighlightBorder = v
                end,
            }
        )
        posY = posY - hgt
        local darkRow
        darkRow, hgt = W:DualRow(hostFrame, posY, darkCfg, CludesUI.BlankRowCfg())
        posY = posY - hgt
        LockDark(darkRow._leftRegion)
    end

    -- Optional extra rows after enable (e.g. portrait, cast icon, indicators)
    if afterSizeRow then
        posY = afterSizeRow(W, hostFrame, posY)
    end

    -- HEALTH BAR section
    local textHeader
    textHeader, hgt = W:SectionHeader(hostFrame, "HEALTH BAR", posY)
    posY = posY - hgt

    -- Row 1: Bar Height + Bar Width
    local sizeRow
    local mhDis, mhTip, mhRaw = CludesUI.MatchGuard(unitKey, "Height")
    local mwDis, mwTip, mwRaw = CludesUI.MatchGuard(unitKey, "Width")
    local rightSlot
    -- Vertical Fill wants tall, narrow bars: the Vertical Fill toggle rebuilds the page.
    local vertFill = settingsTable.healthVerticalFill == true
    if CludesUI.BlizzStyle.Get("unitframes") then
        -- Blizzard Style: the stock size is fixed, so the whole frame scales
        -- instead; the slider takes the gated width's slot (no blank slot).
        rightSlot = {
            type = "slider",
            text = "Frame Scale",
            min = 50,
            max = 200,
            step = 5,
            tooltip = "Scales the whole frame. Blizzard Style frames are the stock size, so this stands in for Bar Width and Health Bar Height.",
            getValue = function()
                return math.floor((settingsTable.blizzScale or 1) * 100 + 0.5)
            end,
            setValue = function(v)
                settingsTable.blizzScale = v / 100
                ReloadAndUpdate()
            end,
        }
    elseif options.hideBarWidth then
        rightSlot = { type = "label", text = "" }
    else
        rightSlot = CludesUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Bar Width",
            min = vertFill and 20 or 60,
            max = 300,
            step = 1,
            disabled = mwDis,
            disabledTooltip = mwTip,
            rawTooltip = mwRaw,
            getValue = function()
                return settingsTable.frameWidth
            end,
            setValue = function(v)
                settingsTable.frameWidth = v
                ReloadAndUpdate()
            end,
        })
    end
    sizeRow, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Health Bar Height",
            min = 10,
            max = vertFill and 400 or 100,
            step = 1,
            disabled = mhDis,
            disabledTooltip = mhTip,
            rawTooltip = mhRaw,
            getValue = function()
                return settingsTable.healthHeight
            end,
            setValue = function(v)
                settingsTable.healthHeight = v
                ReloadAndUpdate()
            end,
        }),
        rightSlot
    )
    posY = posY - hgt

    -- Row 2: Fill Color + Bar Background/Opacity. Boss frames present each as an
    -- opacity slider with inline class/custom swatches (mirroring Main Frames' Bar
    -- Background); other mini units keep the combined "Bar Color" multiSwatch + "Bar Opacity" slider.
    do
        local isBoss = (unitKey == "boss")

        local leftSlot2, rightSlot2
        if isBoss then
            -- Fill Color = the health fill opacity (formerly "Fill Opacity")
            -- with the fill color swatches moved inline below.
            leftSlot2 = {
                type = "slider",
                text = "Fill Color",
                min = 0,
                max = 100,
                step = 1,
                disabled = function()
                    return mod.UF_DarkThemeOn(settingsTable)
                end,
                disabledTooltip = "Dark Mode",
                requireState = "disabled",
                getValue = function()
                    return MVal("healthBarOpacity", 90)
                end,
                setValue = function(v)
                    MSet("healthBarOpacity", v)
                end,
            }
            rightSlot2 = {
                type = "slider",
                text = "Bar Background",
                min = 0,
                max = 100,
                step = 1,
                getValue = function()
                    return MVal("customBgAlpha", 100)
                end,
                setValue = function(v)
                    MSet("customBgAlpha", v)
                end,
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
                        local c = MGet("customFillColor")
                        if c then
                            return c.r, c.g, c.b
                        end
                        return 37 / 255, 193 / 255, 29 / 255
                    end,
                    setValue = function(r, g, b)
                        settingsTable.customFillColor = { r = r, g = g, b = b }
                        ReloadAndUpdate()
                    end,
                    onClick = function(self)
                        if MVal("healthClassColored", false) then
                            if MGet("customFillColor") == nil then
                                settingsTable.customFillColor = { r = 37 / 255, g = 193 / 255, b = 29 / 255 }
                            end
                            settingsTable.healthClassColored = false
                            ReloadAndUpdate()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return MVal("healthClassColored", false) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored Fill",
                    hasAlpha = false,
                    getValue = function()
                        local _, ct = UnitClass("player")
                        if ct and RAID_CLASS_COLORS[ct] then
                            local cc = RAID_CLASS_COLORS[ct]
                            return cc.r, cc.g, cc.b
                        end
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        settingsTable.healthClassColored = true
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return MVal("healthClassColored", false) and 1 or 0.3
                    end,
                },
            }
            leftSlot2 = { type = "multiSwatch", text = "Fill Color", swatches = fillSwatches }
            rightSlot2 = {
                type = "slider",
                text = "Fill Opacity",
                min = 0,
                max = 100,
                step = 1,
                disabled = function()
                    return mod.UF_DarkThemeOn(settingsTable)
                end,
                disabledTooltip = "Dark Mode",
                requireState = "disabled",
                getValue = function()
                    return MVal("healthBarOpacity", 90)
                end,
                setValue = function(v)
                    MSet("healthBarOpacity", v)
                end,
            }
        end

        local colorRow
        colorRow, hgt = W:DualRow(hostFrame, posY, leftSlot2, rightSlot2)
        posY = posY - hgt

        if isBoss then
            -- Inline Custom + Class fill swatches on the Fill Color slider (left
            -- region); both toggle healthClassColored, the inactive one dims to 0.3.
            if not CludesUI._prebuilding then
                local region = colorRow._leftRegion
                mod.UFO_SwatchPair(region, {
                    store = function()
                        return settingsTable
                    end,
                    flag = "healthClassColored",
                    flagDefault = false,
                    autoGet = function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then
                            return cc.r, cc.g, cc.b
                        end
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
            if not CludesUI._prebuilding then
                local region = colorRow._rightRegion
                mod.UFO_SwatchPair(region, {
                    store = function()
                        return settingsTable
                    end,
                    flag = "bgClassColored",
                    flagDefault = false,
                    autoGet = function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then
                            return cc.r, cc.g, cc.b
                        end
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
        if not CludesUI._prebuilding then
            AddDarkModeBlock(colorRow._leftRegion, function()
                return settingsTable
            end)
            if isBoss then
                AddDarkModeBlock(colorRow._rightRegion, function()
                    return settingsTable
                end)
            end
        end
    end

    -- Mini frames pair Smooth Health Bars with Vertical Fill below;
    -- boss frames keep it beside Reverse Fill.
    local smoothBarsWidget = {
        type = "toggle",
        text = "Smooth Health Bars",
        getValue = function()
            return MVal("smoothBars", false)
        end,
        setValue = function(v)
            MSet("smoothBars", v)
        end,
    }
    local reverseFillWidget = {
        type = "toggle",
        text = "Reverse Fill",
        getValue = function()
            return settingsTable.healthReverseFill
        end,
        setValue = function(v)
            settingsTable.healthReverseFill = v
            ReloadAndUpdate()
        end,
    }
    if unitKey == "boss" then
        _, hgt = W:DualRow(hostFrame, posY, smoothBarsWidget, reverseFillWidget)
        posY = posY - hgt
    else
        -- Bar Background (opacity slider + inline color swatch) | Reverse Fill.
        -- Reuses the existing customBgAlpha (opacity) + customBgColor (color)
        -- variables -- same as the Boss frames and the runtime health bg, so
        -- no saved option changes.
        local bgRow
        bgRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                return MVal("customBgAlpha", 100)
            end,
            setValue = function(v)
                MSet("customBgAlpha", v)
            end,
        }, reverseFillWidget)
        posY = posY - hgt
        -- inline bg colors - custom swatch + class swatch
        -- tot/focus use class for player, reaction for npc
        -- pet resolves to player's class color
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineSwatches(bgRow._leftRegion, {
                {
                    tooltip = "Custom Background Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = MGet("customBgColor")
                        if c then
                            return c.r, c.g, c.b
                        end
                        return 17 / 255, 17 / 255, 17 / 255
                    end,
                    setValue = function(r, g, b)
                        settingsTable.customBgColor = { r = r, g = g, b = b }
                        ReloadAndUpdate()
                    end,
                    onClick = function(self)
                        if MVal("bgClassColored", false) then
                            settingsTable.bgClassColored = false
                            ReloadAndUpdate()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return MVal("bgClassColored", false) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored Background",
                    hasAlpha = false,
                    getValue = function()
                        local _, ct = UnitClass("player")
                        local cc = ct and RAID_CLASS_COLORS[ct]
                        if cc then
                            return cc.r, cc.g, cc.b
                        end
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        settingsTable.bgClassColored = true
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return MVal("bgClassColored", false) and 1 or 0.3
                    end,
                },
            })
        end
    end

    -- Vertical Fill swaps the fill AXIS (Reverse Fill above flips direction within
    -- it, so vertical+reverse fills top-to-bottom); own row since Reverse Fill's row is already full on both layouts.
    _, hgt = W:DualRow(
        hostFrame,
        posY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Vertical Fill",
            tooltip = "Fill the health bar bottom-to-top instead of left-to-right. Reverse Fill flips it to top-to-bottom.",
            getValue = function()
                return settingsTable.healthVerticalFill
            end,
            setValue = function(v)
                settingsTable.healthVerticalFill = v
                ReloadAndUpdate()
                CludesUI:RefreshPage(true)
            end,
        }),
        unitKey ~= "boss" and smoothBarsWidget or CludesUI.BlankRowCfg()
    )
    posY = posY - hgt

    -- Blizzard Style: the stock level number in the boss art's level circle
    -- (the small frames' stock art carries none), with its size and
    -- offsets on a cog. The row is the preview level text's click target
    -- (stashed on the page: the boss targets table reads it).
    if unitKey == "boss" and CludesUI.BlizzStyle.Get("unitframes") then
        hostFrame._ufLevelRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Level",
            tooltip = "Shows the unit's level in the frame's level circle, as the default UI does.",
            getValue = function()
                return settingsTable.blizzShowLevel ~= false
            end,
            setValue = function(v)
                settingsTable.blizzShowLevel = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(hostFrame._ufLevelRow._leftRegion, {
                disabled = function()
                    return settingsTable.blizzShowLevel == false
                end,
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
                            return MVal("blizzLevelSize", MVal("leftTextSize", settingsTable.textSize or 12))
                        end,
                        set = function(v)
                            MSet("blizzLevelSize", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = function()
                            return MVal("blizzLevelX", 0)
                        end,
                        set = function(v)
                            MSet("blizzLevelX", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = function()
                            return MVal("blizzLevelY", 0)
                        end,
                        set = function(v)
                            MSet("blizzLevelY", v)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Difficulty Color",
                        tooltip = "Colors an attackable unit's level by difficulty, as the default UI does.",
                        get = function()
                            return MVal("blizzLevelDifficultyColor", true)
                        end,
                        set = function(v)
                            MSet("blizzLevelDifficultyColor", v)
                        end,
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
        local key, default = o.key, o.default
        local contentKey = key .. "Content"
        local classKey = key .. "ClassColor"
        local function Content()
            return MVal(contentKey, default)
        end
        local function Off()
            return Content() == "none"
        end
        local function Slider(label, suffix, lo, hi, step, def)
            return {
                type = "slider",
                label = label,
                min = lo,
                max = hi,
                step = step,
                get = function()
                    return MVal(key .. suffix, type(def) == "function" and def() or def)
                end,
                set = function(v)
                    MSet(key .. suffix, v)
                end,
            }
        end
        -- Separator and Prefix: pipes and outer spaces stripped.
        local function Clean(v)
            return (tostring(v or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", ""))
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
                get = function()
                    return MVal(key .. "Align", "left")
                end,
                set = function(v)
                    MSet(key .. "Align", v)
                end,
            }
        end
        rows[#rows + 1] = Slider("Size", "Size", 8, 100, 1, function()
            return settingsTable.textSize or 12
        end)
        rows[#rows + 1] = Slider("X Offset", "X", -xReach, xReach, 1, 0)
        rows[#rows + 1] = Slider("Y Offset", "Y", -yReach, yReach, 1, 0)
        rows[#rows + 1] = Slider("Width %", "WidthPct", 20, 200, 5, 100)
        -- The colour of the Name > Target / Target indicator: custom or class.
        local sepKey, sepClassKey = key .. "TargetSepColor", key .. "TargetSepClassColor"
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
                        local c = MVal(sepKey, nil)
                        if type(c) == "table" then
                            return c.r or 1, c.g or 1, c.b or 1
                        end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        MSet(sepKey, { r = r, g = g, b = b })
                    end,
                    onClick = function(self)
                        if MVal(sepClassKey, false) then
                            MSet(sepClassKey, false)
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return MVal(sepClassKey, false) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = CludesUI.PlayerClassRGB,
                    setValue = function() end,
                    onClick = function()
                        MSet(sepClassKey, true)
                    end,
                    refreshAlpha = function()
                        return MVal(sepClassKey, false) and 1 or 0.3
                    end,
                },
            },
        }
        rows[#rows + 1] = {
            type = "input",
            label = "Separator",
            inputWidth = 60,
            get = function()
                return MVal(key .. "TargetSep", ">")
            end,
            set = function(v)
                v = Clean(v)
                MSet(key .. "TargetSep", v ~= "" and v or ">")
            end,
            disabled = function()
                return Content() ~= "nametotarget"
            end,
            disabledTooltip = "This option only applies when Name > Target is selected.",
        }
        rows[#rows + 1] = {
            type = "input",
            label = "Prefix",
            inputWidth = 60,
            tooltip = "Text shown before the target's name.",
            get = function()
                return MVal(key .. "TargetPrefix", "T:")
            end,
            -- Unlike Separator, empty is kept: no prefix.
            set = function(v)
                MSet(key .. "TargetPrefix", Clean(v))
            end,
            disabled = function()
                return Content() ~= "targetname"
            end,
            disabledTooltip = "This option only applies when Target is selected.",
        }
        local shown = o.shown or o.name
        return {
            key = key,
            position = shown,
            default = default,
            cfg = {
                type = "dropdown",
                text = shown,
                values = healthTextValues,
                order = o.order,
                getValue = Content,
                -- A content only one slot may show leaves the slots that held it.
                setValue = function(v)
                    settingsTable[contentKey] = v
                    if o.clears and mod.UF_IsUniqueContent(v) then
                        for _, other in ipairs(o.clears) do
                            if settingsTable[other .. "Content"] == v then
                                settingsTable[other .. "Content"] = "none"
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end,
            },
            decorate = function(region)
                if CludesUI._prebuilding then
                    return
                end
                CludesUI.BuildInlineCog(region, {
                    disabled = Off,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = o.name .. " Settings",
                    rows = mod.UF_CoreTextRows(key, default, MVal, MSet, rows),
                })
                -- Class, then Custom, left of the cog. Both are dead while the slot
                -- shows nothing; the one not in use dims.
                local classSw, classSwUp = CludesUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local cc = class and CludesUI.GetClassColor(class)
                        if cc then
                            return cc.r, cc.g, cc.b
                        end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(classSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                classSw:SetScript("OnClick", function()
                    if Off() then
                        return
                    end
                    MSet(classKey, true)
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(classSw, "Class Colored")
                local sw, swUp = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    return MVal(key .. "ColorR", 1), MVal(key .. "ColorG", 1), MVal(key .. "ColorB", 1)
                end, function(r, g, b)
                    settingsTable[key .. "ColorR"] = r
                    settingsTable[key .. "ColorG"] = g
                    settingsTable[key .. "ColorB"] = b
                    ReloadAndUpdate()
                end, nil, 20)
                Pix.Point(sw, "RIGHT", classSw, "LEFT", -8, 0)
                region._lastInline = sw
                local stockClick = sw:GetScript("OnClick")
                sw:SetScript("OnClick", function(self, ...)
                    if Off() then
                        return
                    end
                    if MVal(classKey, false) then
                        MSet(classKey, false)
                        CludesUI:RefreshPage()
                        return
                    end
                    if stockClick then
                        stockClick(self, ...)
                    end
                end)
                CludesUI.HoverTip(sw, "Custom Colored")
                local function Dim()
                    local isNone, isClass = Off(), MVal(classKey, false)
                    sw:SetAlpha((isClass or isNone) and 0.3 or 1)
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
    local slotOrder = (unitKey == "boss") and healthTextOrderBoss or healthTextOrder
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
    if unitKey == "boss" then
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
        unit = unitKey,
        page = unitKey == "boss" and "Boss Frames" or "Mini Frames",
        db = function()
            return settingsTable
        end,
        liveDB = function()
            return saved.profile[unitKey]
        end,
        apply = ReloadAndUpdate,
    })

    -- POWER BAR section (mini units with a power bar: boss, and the pet on WoW Forever).
    -- Fill always uses the unit's power color (powerPercentPowerColor default on);
    -- a height of 0 effectively hides the bar.
    if options.hasPowerBar then
        local powerHeader
        powerHeader, hgt = W:SectionHeader(hostFrame, "POWER BAR", posY)
        posY = posY - hgt

        -- Row 1: Power Bar Height (+ Reverse Fill cog) | Above Health Bar toggle
        local pwrRow1
        pwrRow1, hgt = W:DualRow(
            hostFrame,
            posY,
            -- Blizzard Style: the stock track fixes height and spot; the
            -- Reverse Fill cog on this slot keeps working (keepRow).
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "slider",
                text = "Power Bar Height",
                min = 0,
                max = 100,
                step = 1,
                getValue = function()
                    return MVal("powerHeight", 6)
                end,
                setValue = function(v)
                    MSet("powerHeight", v)
                end,
            }, true),
            CludesUI.BlizzStyle.Gate("unitframes", {
                type = "toggle",
                text = "Above Health Bar",
                getValue = function()
                    return MVal("powerPosition", "below") == "above"
                end,
                setValue = function(v)
                    MSet("powerPosition", v and "above" or "below")
                end,
            })
        )
        posY = posY - hgt
        -- Expose the Power Bar Height row + POWER BAR header so the boss
        -- preview's power-bar click overlay can scroll here.
        hostFrame._powerHeaderFrame = powerHeader
        hostFrame._powerHeightRow = pwrRow1
        -- Reverse Fill cog on Power Bar Height (left) -- mirrors Main Frames.
        if not CludesUI._prebuilding then
            local region = pwrRow1._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Power Bar Fill",
                rows = {
                    {
                        type = "toggle",
                        label = "Reverse Fill",
                        get = function()
                            return MVal("powerReverseFill", false)
                        end,
                        set = function(v)
                            MSet("powerReverseFill", v)
                        end,
                    },
                },
            })
        end

        -- Row 2: Bar Background (opacity slider + power/custom bg swatches) |
        -- Fill Color (opacity slider + power/custom fill swatches). Mirrors the
        -- Main Frames power bar; the opacity sliders replace the old plain ones.
        local pwrRow2
        pwrRow2, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                return MVal("customPowerBgAlpha", 100)
            end,
            setValue = function(v)
                MSet("customPowerBgAlpha", v)
            end,
        }, {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                return MVal("powerBarOpacity", 100)
            end,
            setValue = function(v)
                MSet("powerBarOpacity", v)
            end,
        })
        posY = posY - hgt
        -- Inline Power Colored + Custom background swatches on Bar Background
        -- (left region); both toggle powerBgPowerColored, the inactive one
        -- dims to 0.3 (mirrors the Main Frames power Bar Background).
        if not CludesUI._prebuilding then
            local region = pwrRow2._leftRegion
            mod.UFO_SwatchPair(region, {
                store = function()
                    return settingsTable
                end,
                flag = "powerBgPowerColored",
                flagDefault = false,
                autoGet = function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    local f = CludesUI.GetPowerBgDarkenFactor()
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
        if not CludesUI._prebuilding then
            local region = pwrRow2._rightRegion
            local fPwrGet = function()
                local _, pToken = UnitPowerType("player")
                local details = CludesUI.GetPowerColor(pToken or "MANA")
                return details.r, details.g, details.b
            end
            local fPwrSw, fPwrUpdate = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                fPwrGet,
                function() end,
                false,
                20
            )
            fPwrSw._eabOrigClick = fPwrSw:GetScript("OnClick")
            fPwrSw:SetScript("OnClick", function()
                settingsTable.powerPercentPowerColor = true
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end)
            fPwrSw:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    fPwrSw,
                    "Power Colored Fill. Power colors can be adjusted in Global Settings -> Colors."
                )
            end)
            fPwrSw:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            Pix.Point(fPwrSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = fPwrSw
            RegisterWidgetRefresh(function()
                fPwrUpdate()
                fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)
            end)
            fPwrSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 1 or 0.3)

            local fGet = function()
                local c = MGet("customPowerFillColor")
                if c then
                    return c.r, c.g, c.b
                end
                return 0, 0, 1
            end
            local fSet = function(r, g, b)
                settingsTable.customPowerFillColor = { r = r, g = g, b = b }
                ReloadAndUpdate()
            end
            local fSw, fSwUp =
                CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, fGet, fSet, false, 20)
            fSw._eabOrigClick = fSw:GetScript("OnClick")
            fSw:SetScript("OnClick", function(self)
                if MVal("powerPercentPowerColor", true) ~= false then
                    settingsTable.powerPercentPowerColor = false
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then
                    self._eabOrigClick(self)
                end
            end)
            fSw:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(fSw, "Custom Colored Fill")
            end)
            fSw:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            Pix.Point(fSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = fSw
            RegisterWidgetRefresh(function()
                fSwUp()
                fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
            end)
            fSw:SetAlpha((MVal("powerPercentPowerColor", true) ~= false) and 0.3 or 1)
        end

        -- Row 3: Power Text (format) + Text Position -- ported from Main Frames.
        -- Reads/writes the same per-unit keys; MSet -> ReloadAndUpdate live-updates
        -- the real boss frames AND the preview (runtime already supports boss).
        local pwrTextRow
        local function SetPowerTextFormat(v)
            settingsTable.powerTextFormat = v
            if v ~= "none" and MVal("powerPercentText", "none") == "none" then
                settingsTable.powerPercentText = "center"
            end
            if v == "none" then
                settingsTable.powerPercentText = "none"
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
            -- The page stays, so the menu is rebuilt for Custom's pencil.
            mod.UFO_RefreshMenus(pwrTextRow and pwrTextRow._leftRegion)
        end
        pwrTextRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Power Text",
            values = mod.UFO_CustomTextValues({
                ["none"] = "None",
                ["smart"] = "Smart Text",
                ["curpp"] = "Power Value",
                ["perpp"] = "Power %",
                ["both"] = "Value | %",
            }, function()
                return MVal("powerTextFormat", "perpp")
            end, function()
                mod.UFO_EditCustomText("powerText", settingsTable, unitKey, function()
                    SetPowerTextFormat("custom")
                end)
            end),
            -- WoW Forever lists no Smart Text (CludesUI.PowerTextFormat).
            order = CludesUI.PowerTextFormatOrder({
                "none",
                "---",
                "custom",
                "---",
                "smart",
                "curpp",
                "perpp",
                "both",
            }),
            getValue = function()
                return CludesUI.PowerTextFormat(MVal("powerTextFormat", "perpp"))
            end,
            setValue = SetPowerTextFormat,
        }, {
            type = "dropdown",
            text = "Text Position",
            values = { ["none"] = "None", ["left"] = "Left", ["right"] = "Right", ["center"] = "Center" },
            order = { "none", "---", "left", "right", "center" },
            getValue = function()
                return MVal("powerPercentText", "none")
            end,
            setValue = function(v)
                MSet("powerPercentText", v)
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt
        -- Expose the power-text row so the preview's power-text click overlay
        -- can scroll here (mirrors parent._powerHeightRow / _powerHeaderFrame).
        hostFrame._powerTextRow = pwrTextRow
        if not CludesUI._prebuilding then
            mod.UFO_AddCustomFormatAccessor(
                pwrTextRow._leftRegion,
                "Power Text",
                "powerText",
                MVal("powerTextFormat", "perpp"),
                function()
                    return settingsTable
                end,
                ReloadAndUpdate
            )
        end
        -- Show % cog on Power Text (left)
        if not CludesUI._prebuilding then
            local region = pwrTextRow._leftRegion
            CludesUI.BuildInlineCog(
                region,
                mod.UFO_PowerTextCog(MVal, MSet, { none = true, curpp = true }, function(v)
                    MSet("powerShowPercent", v)
                end)
            )
        end
        -- Inline Text Color swatches on Power Text (left): Custom + Power Colored,
        -- mutually exclusive (mirrors Main Frames' Text Color multiSwatch). Custom
        -- click: first clears power-colored (selecting custom), second opens the
        -- picker. Power-colored click: selects power-colored + clears custom.
        if not CludesUI._prebuilding then
            local region = pwrTextRow._leftRegion
            local customSw, customSwUp = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local c = MGet("powerTextColor")
                    if c then
                        return c.r, c.g, c.b
                    end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    settingsTable.powerTextColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end,
                false,
                20
            )
            Pix.Point(customSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = customSw
            local customOrigClick = customSw:GetScript("OnClick")
            customSw:SetScript("OnClick", function(self, ...)
                if MVal("powerPercentTextPowerColor", false) then
                    settingsTable.powerPercentTextPowerColor = false
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                    return
                end
                if customOrigClick then
                    customOrigClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customSw, "Custom Text Color")
            local powerSw, powerSwUp = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        return details.r, details.g, details.b
                    end
                    return 1, 1, 1
                end,
                function() end,
                false,
                20
            )
            Pix.Point(powerSw, "RIGHT", customSw, "LEFT", -8, 0)
            region._lastInline = powerSw
            powerSw:SetScript("OnClick", function()
                settingsTable.powerPercentTextPowerColor = true
                settingsTable.powerTextColor = nil
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(powerSw, "Power Colored Text")
            local function UpdSwatches()
                local isPower = MVal("powerPercentTextPowerColor", false)
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
        if not CludesUI._prebuilding then
            local region = pwrTextRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    return MVal("powerPercentText", "none") == "none"
                end,
                disabledTooltip = "This option requires a text position other than none.",
                title = "Text Position",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 100,
                        step = 1,
                        get = function()
                            return MVal("powerPercentSize", 9)
                        end,
                        set = function(v)
                            MSet("powerPercentSize", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return MVal("powerPercentX", 0)
                        end,
                        set = function(v)
                            MSet("powerPercentX", v)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return MVal("powerPercentY", 0)
                        end,
                        set = function(v)
                            MSet("powerPercentY", v)
                        end,
                    },
                },
            })
        end

        -- Power bar border size and color, matching Player/Target/Focus.
        local pwrBorderRow
        pwrBorderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 4,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return MVal("powerBorderSize", 0)
            end,
            setValue = function(v)
                MSet("powerBorderSize", v)
            end,
        }, { type = "label", text = "" })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            local region = pwrBorderRow._leftRegion
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                pwrBorderRow:GetFrameLevel() + 3,
                function()
                    local c = MGet("powerBorderColor") or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b, MVal("powerBorderAlpha", 1)
                end,
                function(r, g, b, a)
                    settingsTable.powerBorderColor = { r = r, g = g, b = b }
                    settingsTable.powerBorderAlpha = a
                    ReloadAndUpdate()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
            CludesUI.HoverTip(colorSwatch, "Border Color")
            region._lastInline = colorSwatch
            RegisterWidgetRefresh(updateSwatch)
        end
    end

    -- Extra section rendered at the very bottom, below the Power Bar (boss "Indicators").
    if options.afterPowerRow then
        posY = options.afterPowerRow(W, hostFrame, posY)
    end

    return posY, displayHeader, sizeRow, textHeader, textRow, enableRowFrame
end

-- Inline "Portrait on Right" cog attached to a Show Portrait toggle
-- region. Clicking the cog opens a popup with a toggle that swaps
-- settings.portraitSide between "left" and "right" live; withArtStyle
-- (Target of Target / Focus Target) adds the 2D / Class art choice.
local function AttachPortraitSideCog(region, settingsTable, withArtStyle, unitKey)
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
            get = function()
                return (settingsTable.portraitSide or "left") == "right"
            end,
            set = function(v)
                settingsTable.portraitSide = v and "right" or "left"
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
            get = function()
                return settingsTable.portraitMode == "class" and "class" or "2d"
            end,
            set = function(v)
                local function ApplyArt()
                    settingsTable.portraitMode = v
                    ReloadAndUpdate()
                    UpdatePreview()
                end
                if
                    v == "2d"
                    and settingsTable.portraitMode == "class"
                    and settingsTable.portraitMirror
                    and not CludesUI.BlizzStyle.Get("unitframes")
                    and mod.UF_Ask2DMirroredPortraits(function()
                        ApplyArt()
                        CludesUI:RefreshPage()
                    end)
                then
                    if portraitShow and portraitShow._popupFrame then
                        portraitShow._popupFrame:Hide()
                    end
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
            get = function()
                return settingsTable.classThemeStyle or "modern"
            end,
            set = function(v)
                settingsTable.classThemeStyle = v
                ReloadAndUpdate()
                UpdatePreview()
            end,
            disabled = function()
                return settingsTable.portraitMode ~= "class"
            end,
            disabledTooltip = "This option requires Art Style to be set to Class",
            rawTooltip = true,
        }
        -- The Non-Player Portrait opt-in and its choice, as on the main frames.
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Custom Non-Player Portrait",
            tooltip = "Pick what NPCs show in Class art instead of their 2D portrait.",
            get = function()
                return settingsTable.portraitNonPlayerOn == true
            end,
            set = function(v)
                settingsTable.portraitNonPlayerOn = v or nil
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
            get = function()
                return settingsTable.portraitNonPlayer == "none" and "none" or "2d"
            end,
            set = function(v)
                settingsTable.portraitNonPlayer = v
                ReloadAndUpdate()
            end,
            disabled = function()
                return settingsTable.portraitMode ~= "class" or not settingsTable.portraitNonPlayerOn
            end,
            disabledTooltip = function()
                if settingsTable.portraitMode ~= "class" then
                    return "This option requires Art Style to be set to Class"
                end
                return "Custom Non-Player Portrait"
            end,
        }
    end
    if unitKey == "targettarget" or unitKey == "boss" then
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Mirror Portrait",
            tooltip = "Mirrors playable-race portraits in 2D. Always flips class art horizontally.",
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                return CludesUI.BlizzStyle.Label("unitframes")
            end,
            requireState = "disabled",
            get = function()
                return settingsTable.portraitMirror == true
            end,
            set = function(v)
                local function ApplyMirror()
                    settingsTable.portraitMirror = v or nil
                    mod.UF_RefreshPortraitMirror(unitKey)
                    UpdatePreview()
                end
                if
                    v
                    and not settingsTable.portraitMirror
                    and settingsTable.portraitMode ~= "3d"
                    and settingsTable.portraitMode ~= "class"
                    and mod.UF_Ask2DMirroredPortraits(function()
                        ApplyMirror()
                        CludesUI:RefreshPage()
                    end)
                then
                    if portraitShow and portraitShow._popupFrame then
                        portraitShow._popupFrame:Hide()
                    end
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
                local donor = unitKey == "boss" and mod.UF_BossBorderSettings()
                    or GetMiniDonorSettings(unitKey)
                return CludesUI.BlizzStyle.Get("unitframes")
                    or (settingsTable.borderSizeOverride or donor.borderSize or 1) <= 0
                    or not CludesUI.GetBorderCompanion(donor.borderTexture or "solid", "sepV")
            end,
            disabledTooltip = function()
                if CludesUI.BlizzStyle.Get("unitframes") then
                    return CludesUI.BlizzStyle.Label("unitframes")
                end
                return "This option requires a border style with divider art and a Border Size above 0."
            end,
            rawTooltip = true,
            get = function()
                return settingsTable.portraitSeparator == true
            end,
            set = function(v)
                settingsTable.portraitSeparator = v or nil
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }
    end
    _, portraitShow = CludesUI.BuildInlineCog(region, {
        gap = 9,
        title = "Portrait Settings",
        -- Side and art only show on a shown portrait (the stock styles
        -- always show one); the Show Portrait setters refresh this state.
        disabled = function()
            return settingsTable.showPortrait == false and not CludesUI.BlizzStyle.Get("unitframes")
        end,
        disabledTooltip = "Show Portrait",
        rows = rowList,
    })
end

-- Shared builder for the two independent mini frames (Target of Target,
-- Focus Target). settingsTable/unitKey select which one; each renders its
-- own single enable toggle + Show Portrait (right slot), Pet-style.
function mod.UFO_BuildFoTToTOptions(W, hostFrame, posY, settingsTable, unitKey)
    local environ = mod._UFO_OptEnv
    local AttachFrameSourceCog, BuildApplyAllRow, MINI_GROUP_ORDER, PromptReloadIfUnspawned =
        environ.AttachFrameSourceCog,
        environ.BuildApplyAllRow,
        environ.MINI_GROUP_ORDER,
        environ.PromptReloadIfUnspawned
    local ReloadAndUpdate, abs, saved = environ.ReloadAndUpdate, environ.abs, environ.db
    settingsTable = settingsTable or saved.profile.targettarget
    unitKey = unitKey or "targettarget"
    local enableText = (unitKey == "focustarget") and "Enable Focus Target" or "Enable Target of Target"
    local _, hgt

    _, hgt = BuildApplyAllRow(hostFrame, posY, MINI_GROUP_ORDER, unitKey, true)
    posY = posY - hgt

    local portraitRow
    local function enableRow(Ww, pp, yy)
        local isCUI = mod.GetUnitFrameSource(unitKey) == "cui"
        -- The Frame Source cog's "Blizzard Default" only makes sense when the
        -- parent target/focus frame is itself on Blizzard's frame (its native
        -- child target-of-target is then alive; see ns.GetUnitFrameSource);
        -- the cog's dropdown is blocked otherwise with an explanation.
        local parentLabel = (unitKey == "focustarget") and "Focus" or "Target"
        local parentKey = (unitKey == "focustarget") and "focus" or "target"
        local childName = (unitKey == "focustarget") and "focus-target" or "target-of-target"
        portraitRow, hgt = Ww:DualRow(pp, yy, {
            type = "toggle",
            text = enableText,
            getValue = function()
                return saved.profile.enabledFrames[unitKey] ~= false
            end,
            setValue = function(v)
                saved.profile.enabledFrames[unitKey] = v
                ReloadAndUpdate()
                CludesUI:RefreshPage(true)
                PromptReloadIfUnspawned({ unitKey })
            end,
        }, isCUI and CludesUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CludesUI.BlizzStyle.Get("unitframes") or settingsTable.showPortrait ~= false
            end,
            setValue = function(v)
                settingsTable.showPortrait = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if isCUI and not CludesUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, settingsTable, true, unitKey)
        end
        AttachFrameSourceCog(portraitRow._leftRegion, unitKey, {
            tooltip = "Due to Blizzard API restrictions, Blizzard's native "
                .. childName
                .. " can't be hidden in combat and will show the whole time you are in combat. Recommended: match the "
                .. parentLabel
                .. " frame's source -- both Blizzard Default, or both CludesUI.",
            disabled = function()
                return mod.GetUnitFrameSource(parentKey) ~= "blizzard"
            end,
            disabledTooltip = '"Blizzard Default" is only available when the '
                .. parentLabel
                .. " frame's source is set to Blizzard Default -- the "
                .. childName
                .. " then comes from Blizzard's "
                .. parentKey
                .. " frame.",
        })
        return portraitRow, hgt
    end

    local displayHeader, sizeRow, textHeader, textRow
    posY, displayHeader, sizeRow, textHeader, textRow =
        BuildMiniTextAndSize(W, hostFrame, posY, settingsTable, unitKey, enableRow)

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        healthBar = { section = displayHeader, target = sizeRow },
        portrait = { section = displayHeader, target = portraitRow, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or displayHeader,
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
    local _, hgt

    _, hgt = BuildApplyAllRow(hostFrame, posY, MINI_GROUP_ORDER, "pet", true)
    posY = posY - hgt

    local portraitRow
    local function enableRow(Ww, pp, yy)
        local isCUI = mod.GetUnitFrameSource("pet") == "cui"
        portraitRow, hgt = Ww:DualRow(pp, yy, {
            type = "toggle",
            text = "Enable Pet Frame",
            getValue = function()
                return saved.profile.enabledFrames.pet ~= false
            end,
            setValue = function(v)
                saved.profile.enabledFrames.pet = v
                ReloadAndUpdate()
                CludesUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "pet" })
            end,
        }, isCUI and CludesUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CludesUI.BlizzStyle.Get("unitframes") or saved.profile.pet.showPortrait ~= false
            end,
            setValue = function(v)
                saved.profile.pet.showPortrait = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if isCUI and not CludesUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, saved.profile.pet)
        end
        AttachFrameSourceCog(portraitRow._leftRegion, "pet", {
            extraRows = {
                {
                    type = "toggle",
                    label = "Always Show Pet Frame",
                    tooltip = "Show the pet frame whenever you have a pet, ignoring the Player frame's visibility settings.",
                    get = function()
                        return saved.profile.pet.alwaysShow == true
                    end,
                    set = function(v)
                        saved.profile.pet.alwaysShow = v and true or nil
                        if mod.UpdateFrameVisibility then
                            mod.UpdateFrameVisibility()
                        end
                    end,
                },
            },
        })
        return portraitRow, hgt
    end

    -- WoW Forever: the pet has power (its POWER BAR section exists in the
    -- CUI look only; the stock styles paint their own stock bar) and
    -- hunter pets track happiness (PET HAPPINESS, below the power bar).
    -- Retail builds neither.
    local petOpts, petPower, happyHeader, happyRow
    if CludesUI.IS_FOREVER == true then
        petPower = mod.UF_PetHasPower and not CludesUI.BlizzStyle.Get("unitframes")
        local P = saved.profile.pet
        local function happyOff()
            return P.happinessEnabled == false
        end
        -- The live icon repaints itself; the preview mirrors it.
        local function happyApply()
            mod.UF_ApplyPetHappiness()
            UpdatePreview()
        end
        petOpts = {
            hasPowerBar = petPower,
            afterPowerRow = function(Ww, pp, yy)
                local hh
                happyHeader, hh = Ww:SectionHeader(pp, "PET HAPPINESS", yy)
                yy = yy - hh

                -- Row 1: Show Happiness | Size
                happyRow, hh = Ww:DualRow(pp, yy, {
                    type = "toggle",
                    text = "Show Happiness",
                    tooltip = "Shows your hunter pet's happiness beside the pet frame.",
                    getValue = function()
                        return P.happinessEnabled ~= false
                    end,
                    setValue = function(v)
                        P.happinessEnabled = v
                        happyApply()
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "slider",
                    text = "Size",
                    min = 10,
                    max = 64,
                    step = 1,
                    disabled = happyOff,
                    disabledTooltip = "Show Happiness",
                    getValue = function()
                        return P.happinessSize or 20
                    end,
                    setValue = function(v)
                        P.happinessSize = v
                        happyApply()
                    end,
                })
                yy = yy - hh

                -- Row 2: Position (+ offsets cog) | blank (odd last slot)
                local posRow
                posRow, hh = Ww:DualRow(pp, yy, {
                    type = "segmented",
                    text = "Position",
                    values = { left = "Left", right = "Right", top = "Top" },
                    order = { "left", "right", "top" },
                    disabled = happyOff,
                    disabledTooltip = "Show Happiness",
                    getValue = function()
                        return P.happinessAlign or "right"
                    end,
                    setValue = function(v)
                        P.happinessAlign = v
                        happyApply()
                    end,
                }, CludesUI.BlankRowCfg())
                yy = yy - hh
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(posRow._leftRegion, {
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
                                get = function()
                                    return P.happinessX or 0
                                end,
                                set = function(v)
                                    P.happinessX = v
                                    happyApply()
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -100,
                                max = 100,
                                step = 1,
                                get = function()
                                    return P.happinessY or 0
                                end,
                                set = function(v)
                                    P.happinessY = v
                                    happyApply()
                                end,
                            },
                        },
                    })
                end
                return yy
            end,
        }
    end

    local displayHeader, sizeRow, textHeader, textRow
    posY, displayHeader, sizeRow, textHeader, textRow =
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
        local function PGet(key, default)
            local v = saved.profile.pet[key]
            if v == nil then
                return default
            end
            return v
        end
        local function PSet(key, v)
            saved.profile.pet[key] = v
            ReloadAndUpdate()
        end
        local function buffsOff()
            return saved.profile.pet.showBuffs == false
        end
        local function debuffsOff()
            return (saved.profile.pet.debuffAnchor or "none") == "none"
        end
        local function anyOn()
            return not (buffsOff() and debuffsOff())
        end
        -- The two stacks never share a spot (SwapAuraSlot); the reload pass
        -- builds the containers once one of them is on. Copy Auras From is
        -- built only while one is on, so turning the first on or the last off
        -- rebuilds the page.
        local function PlaceAuras(key)
            return CludesUI.DependentSetValue(anyOn, function(v)
                SwapAuraSlot(saved.profile.pet, key, v)
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end)
        end
        auraHeader, hgt = W:SectionHeader(hostFrame, "BUFFS AND DEBUFFS", posY)
        posY = posY - hgt

        -- Buffs Location | Buff Size, then Debuffs Location | Debuff Size: the
        -- settings cog on each Location, the position cog on each Size.
        buffRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Buffs Location",
            values = environ.buffAnchorValues,
            order = environ.buffAnchorOrder,
            getValue = function()
                local pet = saved.profile.pet
                if pet.showBuffs == false then
                    return "none"
                end
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
            getValue = function()
                return PGet("buffSize", 22)
            end,
            setValue = function(v)
                PSet("buffSize", v)
            end,
        })
        posY = posY - hgt
        debuffRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Debuffs Location",
            values = environ.buffAnchorValues,
            order = environ.buffAnchorOrder,
            getValue = function()
                return PGet("debuffAnchor", "none")
            end,
            setValue = PlaceAuras("debuffAnchor"),
        }, {
            type = "slider",
            text = "Debuff Size",
            min = 10,
            max = 70,
            step = 1,
            disabled = debuffsOff,
            disabledTooltip = "Debuffs Location",
            getValue = function()
                return PGet("debuffSize", 22)
            end,
            setValue = function(v)
                PSet("debuffSize", v)
            end,
        })
        posY = posY - hgt

        -- Copy Auras From | (blank: odd last slot), built while buffs or
        -- debuffs show. Shows the frame in use: the pick while that frame can
        -- lend its look, else the pet's Copy Look From frame, which a pet with
        -- no pick follows. Every pick is stored, so it sticks when Copy Look
        -- From changes later.
        if anyOn() then
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "segmented",
                text = "Copy Auras From",
                tooltip = "The frame whose aura look the pet copies.",
                values = { target = "Target", focus = "Focus", player = "Player" },
                order = { "target", "focus", "player" },
                getValue = function()
                    return mod.UF_MiniAuraSourceKey("pet")
                end,
                setValue = function(v)
                    if v == saved.profile.pet.auraSource then
                        return
                    end
                    saved.profile.pet.auraSource = v
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
                -- Slot marks follow the stored pick alone: the frame shown
                -- also reads the other frames' enable and Visibility keys.
                accessors = {
                    {
                        getValue = function()
                            return saved.profile.pet.auraSource
                        end,
                    },
                },
            }, CludesUI.BlankRowCfg())
            posY = posY - hgt
        end

        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(buffRow._leftRegion, {
                disabled = buffsOff,
                disabledTooltip = "Buffs Location",
                title = "Buff Settings",
                rows = mod.UFO_AuraSettingsRows("buff", PGet, PSet, 40, 4),
            })
            CludesUI.BuildInlineCog(buffRow._rightRegion, {
                disabled = buffsOff,
                disabledTooltip = "Buffs Location",
                title = "Buff Position",
                rows = mod.UFO_AuraPositionRows("buff", PGet, PSet),
            })
            CludesUI.BuildInlineCog(debuffRow._leftRegion, {
                disabled = debuffsOff,
                disabledTooltip = "Debuffs Location",
                title = "Debuff Settings",
                rows = mod.UFO_AuraSettingsRows("debuff", PGet, PSet, 20, 10),
            })
            CludesUI.BuildInlineCog(debuffRow._rightRegion, {
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
        local function castOff()
            return P.showCastbar ~= true
        end
        _, hgt = W:SectionHeader(hostFrame, "CAST BAR", posY)
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Cast Bar",
            tooltip = "Shows a cast bar for your pet's spells (e.g. Seduction). Turning it on needs a reload. Position it in Layout Mode.",
            getValue = function()
                return P.showCastbar == true
            end,
            setValue = function(v)
                P.showCastbar = v
                ReloadAndUpdate()
                local popFrame = mod.frames and mod.frames.pet
                if v and popFrame and not popFrame.Castbar then
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "The pet cast bar is built at login. Reload to show it.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Cast Bar Width",
            min = 30,
            max = 400,
            step = 1,
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function()
                return P.castbarWidth or 120
            end,
            setValue = function(v)
                P.castbarWidth = v
                ReloadAndUpdate()
            end,
        })
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Cast Bar Height",
            min = 1,
            max = 40,
            step = 1,
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function()
                return P.castbarHeight or 12
            end,
            setValue = function(v)
                P.castbarHeight = v
                ReloadAndUpdate()
            end,
        }, {
            type = "toggle",
            text = "Hide When Idle",
            tooltip = "Only show the cast bar while a cast is in progress.",
            disabled = castOff,
            disabledTooltip = "Show Cast Bar",
            getValue = function()
                return P.castbarHideWhenInactive ~= false
            end,
            setValue = function(v)
                P.castbarHideWhenInactive = v
                ReloadAndUpdate()
            end,
        })
        posY = posY - hgt
    end

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        healthBar = { section = displayHeader, target = sizeRow },
        portrait = { section = displayHeader, target = portraitRow, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or displayHeader,
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
    local function BossGet(key, default)
        return function()
            local v = saved.profile.boss[key]
            if default == nil then
                return v
            end
            return v or default
        end
    end
    -- A text colour swatch left of a cog (Duration / Stack Text Color): one
    -- boss colour key, white when unset; dimmed and dead while off() holds.
    local function BossTextSwatch(rgn, key, tip, off)
        local sw, upd = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, function()
            local c = saved.profile.boss[key]
            if c then
                return c.r, c.g, c.b
            end
            return 1, 1, 1
        end, function(r, g, b)
            saved.profile.boss[key] = { r = r, g = g, b = b }
            ReloadAndUpdate()
        end, false, 20)
        sw:HookScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(sw, tip)
        end)
        sw:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        Pix.Point(sw, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = sw
        local function Paint()
            upd()
            local o = off()
            sw:SetAlpha(o and 0.3 or 1)
            sw:EnableMouse(not o)
        end
        Paint()
        CludesUI.RegisterWidgetRefresh(Paint)
    end
    local function BossSet(key, refreshAuras)
        return function(v)
            saved.profile.boss[key] = v
            ReloadAndUpdate()
            if refreshAuras and mod.RefreshBossPreviewDebuffs then
                mod.RefreshBossPreviewDebuffs()
            end
        end
    end
    local _, hgt

    -- Activate/Deactivate Boss Preview button (matches Party Mode's activate
    -- button, centered above the first section). Disabled while Boss Frames are
    -- off: the in-game preview rides on the real (now-disabled) boss frames and renders broken.
    local activateBtnFrame, activateBtnLbl, activateBtn
    local function PreviewLabel()
        return mod._bossPreviewActive and CludesUI.L("Deactivate Boss Preview")
            or CludesUI.L("Activate Boss Preview")
    end
    local function BossFramesDisabled()
        return mod.GetUnitFrameSource("boss") ~= "cui"
    end
    activateBtnFrame, hgt = W:WideButton(hostFrame, PreviewLabel(), posY, function()
        if BossFramesDisabled() then
            return
        end
        if not mod.SetBossPreview then
            return
        end
        mod.SetBossPreview(not mod._bossPreviewActive)
        if activateBtnLbl then
            activateBtnLbl:SetText(PreviewLabel())
        end
    end)
    posY = posY - hgt
    do
        -- The row's button and its label, picked by kind and use rather than by
        -- position: on a kept page the row frame may still hold idle children
        -- and regions of an earlier dress (page reuse).
        local kids = { activateBtnFrame:GetChildren() }
        for idx = 1, #kids do
            local c = kids[idx]
            if c:GetObjectType() == "Button" and not PoolIsIdle(c) then
                activateBtn = c
                break
            end
        end
        if activateBtn then
            local regions = { activateBtn:GetRegions() }
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
        if activateBtnLbl then
            activateBtnLbl:SetText(PreviewLabel())
        end
        if activateBtn then
            activateBtn:SetAlpha(off and 0.4 or 1)
            activateBtn:EnableMouse(not off)
        end
    end
    UpdateActivateBtn()
    CludesUI.RegisterWidgetRefresh(UpdateActivateBtn)

    -- Rows exposed as upvalues so the click-to-scroll targets (below) can point at
    -- them. growthRow holds Show Cast Icon + Cast Bar Height after the swap;
    -- simpleRow/simpleBuffRow/bossAuraRow + bossAuraHeader are the Buffs and Debuffs section rows.
    local portraitRow, growthRow, simpleRow, simpleBuffRow, bossAuraRow, bossAuraHeader, bossCastHeader, castMainRow
    local function enableRow(Ww, pp, yy)
        local isCUI = mod.GetUnitFrameSource("boss") == "cui"
        local eh
        portraitRow, eh = Ww:DualRow(pp, yy, {
            type = "toggle",
            text = "Enable Boss Frames",
            getValue = function()
                return saved.profile.enabledFrames.boss ~= false
            end,
            setValue = function(v)
                saved.profile.enabledFrames.boss = v
                -- Force-stop the in-game preview when disabling boss frames;
                -- it rides on the now-disabled frames and renders broken.
                if not v and mod._bossPreviewActive and mod.SetBossPreview then
                    mod.SetBossPreview(false)
                end
                -- Live apply on the spawned CUI frames (unit-watch register/
                -- unregister). Frames never spawned this session no-op here
                -- and hit the reload prompt below instead.
                if mod.UF_SetBossFramesActive then
                    mod.UF_SetBossFramesActive(v)
                end
                ReloadAndUpdate()
                CludesUI:RefreshPage(true)
                PromptReloadIfUnspawned({ "boss" })
            end,
        }, isCUI and CludesUI.BlizzStyle.Gate("unitframes", {
            type = "toggle",
            text = "Show Portrait",
            getValue = function()
                return CludesUI.BlizzStyle.Get("unitframes") or saved.profile.boss.showPortrait ~= false
            end,
            setValue = function(v)
                saved.profile.boss.showPortrait = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
        }) or { type = "label", text = "" })
        if isCUI and not CludesUI._prebuilding then
            AttachPortraitSideCog(portraitRow._rightRegion, saved.profile.boss, false, "boss")
        end
        AttachFrameSourceCog(portraitRow._leftRegion, "boss", {
            onBeforeSet = function(v)
                -- Force-stop the in-game preview when boss frames are no longer
                -- CUI-owned; it rides on the real boss frames and renders broken.
                if v ~= "cui" and mod._bossPreviewActive and mod.SetBossPreview then
                    mod.SetBossPreview(false)
                end
            end,
        })
        local sum = eh
        if isCUI then
            local castRow, ch = Ww:DualRow(
                pp,
                yy - eh,
                {
                    type = "segmented",
                    text = "Stack Direction",
                    values = { up = "Up", down = "Down" },
                    order = { "up", "down" },
                    getValue = function()
                        return saved.profile.boss.bossStackDirection or "down"
                    end,
                    setValue = function(v)
                        saved.profile.boss.bossStackDirection = v
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
                    getValue = function()
                        return math.abs(saved.profile.bossSpacing or 80)
                    end,
                    setValue = function(v)
                        saved.profile.bossSpacing = v
                        ReloadAndUpdate()
                    end,
                }
            )
            sum = sum + ch
        end
        return portraitRow, sum
    end

    local function bossAfterSize(Ww, pp, yy)
        local _, hh
        -- BUFFS AND DEBUFFS section (below DISPLAY)
        bossAuraHeader, hh = Ww:SectionHeader(pp, "BUFFS AND DEBUFFS", yy)
        yy = yy - hh

        -- Effective boss aura locations: Simple display overrides the stored
        -- location at runtime (dropdowns show None while active), so every
        -- disabled check must treat location as None whenever simple mode is on.
        -- Raw key checks deadlock: defaults hold simpleDebuffs="left" alongside
        -- debuffAnchor="bottomleft", locking BOTH the Simple dropdown (raw anchor not none) and the Location dropdown (simple active) at once.
        local function BossDebuffLocationActive()
            local s = saved.profile.boss
            if mod.GetBossSimpleDebuffMode(s) ~= "none" then
                return false
            end
            return (s.debuffAnchor or "bottomleft") ~= "none"
        end
        local function BossBuffLocationActive()
            local s = saved.profile.boss
            if mod.GetBossSimpleBuffMode(s) ~= "none" then
                return false
            end
            if s.showBuffs == false then
                return false
            end
            return (s.buffAnchor or "topleft") ~= "none"
        end
        -- Composite show-state of the two aura sizing rows (Buff/Debuff Size +
        -- Text Size). A row hides while its column's effective Location is None
        -- (Simple mode also reads as None; it has its own text/size controls). All
        -- four Location/Simple setters capture this BEFORE writing and force a full
        -- rebuild on change: any of them can flip EITHER row (collision pushes, SwapAuraSlot displacing the other anchor, simple forcing showBuffs/debuffAnchor).
        local function BossBuffRowShown()
            local p = saved.profile.boss
            return mod.GetBossSimpleBuffMode(p) == "none" and p.showBuffs ~= false
        end
        local function BossDebuffRowShown()
            local p = saved.profile.boss
            return mod.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") ~= "none"
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
        simpleBuffRow, hh = Ww:DualRow(pp, yy, {
            type = "segmented",
            text = "Simple Buff Display",
            disabled = function()
                return BossBuffLocationActive()
            end,
            disabledTooltip = "Buffs Location",
            requireState = "disabled",
            tooltip = "Force boss buffs into a single large column matched to the frame height.",
            values = { none = "None", left = "Left", right = "Right" },
            order = { "none", "left", "right" },
            getValue = function()
                return mod.GetBossSimpleBuffMode(saved.profile.boss)
            end,
            setValue = function(v)
                local prevState = BossAuraRowsState()
                saved.profile.boss.simpleBuffs = v
                if v ~= "none" then
                    -- Same-side collision: if Simple Debuff Display occupies this
                    -- side, push it off (set to None) so they never overlap.
                    if mod.GetBossSimpleDebuffMode(saved.profile.boss) == v then
                        saved.profile.boss.simpleDebuffs = "none"
                    end
                    -- Selecting a side takes over from the normal Buffs
                    -- Location, so force that setting to None.
                    saved.profile.boss.showBuffs = false
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then
                    mod.RefreshBossPreviewDebuffs()
                end
                if BossAuraRowsState() ~= prevState then
                    CludesUI:RefreshPage(true)
                else
                    CludesUI:RefreshPage()
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
            getValue = function()
                return saved.profile.boss.simpleBuffCooldownTextSize or 14
            end,
            setValue = function(v)
                saved.profile.boss.simpleBuffCooldownTextSize = v
                ReloadAndUpdate()
            end,
        })
        yy = yy - hh

        -- Directions cog on Simple Buff Display: the simple column's own X/Y
        -- offset (defaults to the regular buff offsets via ns.GetBossSimpleBuffOffset);
        -- writing here makes the simple offset independent. Disabled while None.
        if not CludesUI._prebuilding then
            local leftRgn = simpleBuffRow._leftRegion
            CludesUI.BuildInlineCog(leftRgn, {
                disabled = function()
                    return mod.GetBossSimpleBuffMode(saved.profile.boss) == "none"
                end,
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
                        set = function(v)
                            saved.profile.boss.buffMaxPerRow = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
                        set = function(v)
                            saved.profile.boss.simpleBuffOffsetX = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
                        set = function(v)
                            saved.profile.boss.simpleBuffOffsetY = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
            local rightRgn = simpleBuffRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Buff Text Size
            -- swatches (same keys); greyed + disabled on this row cog's condition.
            local buffOff = function()
                return BossBuffLocationActive() or mod.GetBossSimpleBuffMode(saved.profile.boss) == "none"
            end
            CludesUI.BuildInlineCog(rightRgn, {
                disabled = buffOff,
                disabledTooltip = "Simple Buff Display",
                title = "Duration & Stack",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Duration",
                        get = function()
                            return saved.profile.boss.simpleBuffShowCooldownText
                        end,
                        set = function(v)
                            saved.profile.boss.simpleBuffShowCooldownText = v
                            ReloadAndUpdate()
                            CludesUI:RefreshPage()
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
            BossTextSwatch(rightRgn, "buffCooldownTextColor", "Duration Text Color", buffOff)
            BossTextSwatch(rightRgn, "buffStackTextColor", "Stack Text Color", buffOff)
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
        simpleRow, hh = Ww:DualRow(pp, yy, {
            type = "segmented",
            text = "Simple Debuff Display",
            disabled = function()
                return BossDebuffLocationActive()
            end,
            disabledTooltip = "Debuffs Location",
            requireState = "disabled",
            tooltip = "Force boss debuffs into a single large column matched to the frame height.",
            values = { none = "None", left = "Left", right = "Right" },
            order = { "none", "left", "right" },
            getValue = function()
                return mod.GetBossSimpleDebuffMode(saved.profile.boss)
            end,
            setValue = function(v)
                local prevState = BossAuraRowsState()
                saved.profile.boss.simpleDebuffs = v
                if v ~= "none" then
                    -- Same-side collision: if Simple Buff Display occupies this
                    -- side, push it off (set to None) so they never overlap.
                    if mod.GetBossSimpleBuffMode(saved.profile.boss) == v then
                        saved.profile.boss.simpleBuffs = "none"
                    end
                    -- Selecting a side takes over from the normal Debuffs
                    -- Location, so force that setting to None.
                    saved.profile.boss.debuffAnchor = "none"
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then
                    mod.RefreshBossPreviewDebuffs()
                end
                if BossAuraRowsState() ~= prevState then
                    CludesUI:RefreshPage(true)
                else
                    CludesUI:RefreshPage()
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
            getValue = function()
                return saved.profile.boss.simpleDebuffCooldownTextSize or 14
            end,
            setValue = function(v)
                saved.profile.boss.simpleDebuffCooldownTextSize = v
                ReloadAndUpdate()
            end,
        })
        yy = yy - hh

        -- Directions cog on Simple Debuff Display: the simple column's own X/Y
        -- offset. Defaults to the regular debuff offsets for existing users
        -- (ns.GetBossSimpleDebuffOffset); writing here makes the simple offset
        -- independent. Disabled while Simple Debuff Display is None.
        if not CludesUI._prebuilding then
            local leftRgn = simpleRow._leftRegion
            CludesUI.BuildInlineCog(leftRgn, {
                disabled = function()
                    return mod.GetBossSimpleDebuffMode(saved.profile.boss) == "none"
                end,
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
                    mod.UFO_MaxImportantRow(function()
                        return saved.profile.boss
                    end, ReloadAndUpdate, 20, 10),
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
                        set = function(v)
                            saved.profile.boss.debuffMaxPerRow = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
                        set = function(v)
                            saved.profile.boss.simpleDebuffOffsetX = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
                        set = function(v)
                            saved.profile.boss.simpleDebuffOffsetY = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
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
        if not CludesUI._prebuilding then
            local rightRgn = simpleRow._rightRegion
            -- Inline Duration + Stack swatches mirroring the regular Debuff Text
            -- Size swatches (same keys); greyed + disabled on this row cog's
            -- condition.
            local debuffOff = function()
                return BossDebuffLocationActive() or mod.GetBossSimpleDebuffMode(saved.profile.boss) == "none"
            end
            CludesUI.BuildInlineCog(rightRgn, {
                disabled = debuffOff,
                disabledTooltip = "Simple Debuff Display",
                title = "Duration & Stack",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Duration",
                        get = function()
                            return saved.profile.boss.simpleDebuffShowCooldownText
                        end,
                        set = function(v)
                            saved.profile.boss.simpleDebuffShowCooldownText = v
                            ReloadAndUpdate()
                            CludesUI:RefreshPage()
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
            BossTextSwatch(rightRgn, "debuffCooldownTextColor", "Duration Text Color", debuffOff)
            BossTextSwatch(rightRgn, "debuffStackTextColor", "Stack Text Color", debuffOff)
        end
        -- (Show Duration toggle lives inside the Duration & Stack cog above.)

        bossAuraRow, hh = Ww:DualRow(pp, yy, {
            type = "dropdown",
            text = "Buffs Location",
            values = buffAnchorValues,
            order = buffAnchorOrder,
            disabled = function()
                return mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none"
            end,
            disabledTooltip = "Simple Buff Display",
            requireState = "disabled",
            getValue = function()
                local s = saved.profile.boss
                -- Forced to None while Simple Buff Display is active (it takes
                -- over placement); the setter also stores None (showBuffs=false).
                if mod.GetBossSimpleBuffMode(s) ~= "none" then
                    return "none"
                end
                if s.showBuffs == false then
                    return "none"
                end
                return s.buffAnchor or "topleft"
            end,
            setValue = function(v)
                local prevState = BossAuraRowsState()
                local s = saved.profile.boss
                if v == "none" then
                    s.showBuffs = false
                else
                    s.showBuffs = true
                    SwapAuraSlot(s, "buffAnchor", v)
                end
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then
                    mod.RefreshBossPreviewDebuffs()
                end
                if BossAuraRowsState() ~= prevState then
                    CludesUI:RefreshPage(true)
                else
                    CludesUI:RefreshPage()
                end
            end,
        }, {
            type = "dropdown",
            text = "Debuffs Location",
            values = buffAnchorValues,
            order = buffAnchorOrder,
            disabled = function()
                return mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none"
            end,
            disabledTooltip = "Simple Debuff Display",
            requireState = "disabled",
            getValue = function()
                -- Forced to None while Simple Debuff Display is active (it
                -- takes over placement); the setter also stores None.
                if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then
                    return "none"
                end
                return saved.profile.boss.debuffAnchor or "bottomleft"
            end,
            setValue = function(v)
                local prevState = BossAuraRowsState()
                SwapAuraSlot(saved.profile.boss, "debuffAnchor", v)
                ReloadAndUpdate()
                if mod.RefreshBossPreviewDebuffs then
                    mod.RefreshBossPreviewDebuffs()
                end
                -- Full rebuild when either aura row's visibility flipped;
                -- otherwise the fast refresh keeps dependent disabled
                -- states (Boss Debuff Filter) current.
                if BossAuraRowsState() ~= prevState then
                    CludesUI:RefreshPage(true)
                else
                    CludesUI:RefreshPage()
                end
            end,
        })
        yy = yy - hh

        -- Boss Buff Size | Debuff Size: icon size sliders, each with an inline
        -- DIRECTIONS cog holding the cluster X/Y offset; setters refresh live
        -- frames + both previews. Debuff Size (and its cog) disable while Simple
        -- Debuff Display frame-matches the size, or when no debuffs show at all (Simple None + Location None).
        local bossDebuffSizeOff = function()
            local p = saved.profile.boss
            return mod.GetBossSimpleDebuffMode(p) ~= "none" or (p.debuffAnchor or "bottomleft") == "none"
        end
        -- Buff Size (and its directions cog) are disabled while Simple Buff
        -- Display frame-matches the size, or when buffs are hidden (Buffs
        -- Location None). Shared so the cog matches.
        local bossBuffSizeOff = function()
            local p = saved.profile.boss
            return mod.GetBossSimpleBuffMode(p) ~= "none" or p.showBuffs == false
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
            bossAuraSizeRow, hh = Ww:DualRow(pp, yy, {
                type = "slider",
                text = "Buff Size",
                min = 10,
                max = 70,
                step = 1,
                disabled = bossBuffSizeOff,
                disabledTooltip = function()
                    if mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none" then
                        return CludesUI.DisabledTooltip("Simple Buff Display", "disabled")
                    end
                    return CludesUI.DisabledTooltip("Buffs Location")
                end,
                rawTooltip = true,
                getValue = function()
                    return saved.profile.boss.buffSize or 22
                end,
                setValue = function(v)
                    saved.profile.boss.buffSize = v
                    ReloadAndUpdate()
                    if mod.RefreshBossPreviewDebuffs then
                        mod.RefreshBossPreviewDebuffs()
                    end
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
                getValue = function()
                    return saved.profile.boss.buffCooldownTextSize or 10
                end,
                setValue = function(v)
                    saved.profile.boss.buffCooldownTextSize = v
                    ReloadAndUpdate()
                end,
            })
            yy = yy - hh
            if not CludesUI._prebuilding then -- Directions cog on Buff Size (X/Y cluster offset)
                CludesUI.BuildInlineCog(bossAuraSizeRow._leftRegion, {
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
            if not CludesUI._prebuilding then -- Icon Zoom cog on Buff Size (gated only on buffs hidden, so it
                -- stays adjustable in Simple Buff Display, where zoom still applies)
                local bossBuffZoomOff = function()
                    return saved.profile.boss.showBuffs == false
                end
                CludesUI.BuildInlineCog(bossAuraSizeRow._leftRegion, {
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
            if not CludesUI._prebuilding then
                local Pix = CludesUI.PanelPP
                local rightRgn = bossAuraSizeRow._rightRegion
                local buffOff = function()
                    return not BossBuffLocationActive()
                end
                CludesUI.BuildInlineCog(rightRgn, {
                    disabled = buffOff,
                    disabledTooltip = "Buffs Location",
                    title = "Duration & Stack",
                    rows = {
                        {
                            type = "toggle",
                            label = "Show Duration",
                            get = function()
                                return saved.profile.boss.buffShowCooldownText
                            end,
                            set = function(v)
                                saved.profile.boss.buffShowCooldownText = v
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
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
                BossTextSwatch(rightRgn, "buffCooldownTextColor", "Duration Text Color", buffOff)
                BossTextSwatch(rightRgn, "buffStackTextColor", "Stack Text Color", buffOff)
            end
        end -- close buff sizing row hidden-while-None gate

        -- Per-unit aura filters for boss frames (NOT synced; boss1-5 share the
        -- one "boss" settings table). Debuff Filter = the single-select mode
        -- dropdown (DebuffModeDropdownCfg; per-spell control through Tracked
        -- Auras), Buff Filter = the two-lane checkbox dropdown.
        do
            local Pix = CludesUI.PanelPP
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
                textSizeRow, hh = Ww:DualRow(pp, yy, {
                    type = "slider",
                    text = "Debuff Size",
                    min = 10,
                    max = 70,
                    step = 1,
                    disabled = bossDebuffSizeOff,
                    disabledTooltip = function()
                        if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then
                            return CludesUI.DisabledTooltip("Simple Debuff Display", "disabled")
                        end
                        return CludesUI.DisabledTooltip("Debuffs Location")
                    end,
                    rawTooltip = true,
                    getValue = function()
                        return saved.profile.boss.debuffSize or 22
                    end,
                    setValue = function(v)
                        saved.profile.boss.debuffSize = v
                        ReloadAndUpdate()
                        if mod.RefreshBossPreviewDebuffs then
                            mod.RefreshBossPreviewDebuffs()
                        end
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
                    getValue = function()
                        return saved.profile.boss.debuffCooldownTextSize or 10
                    end,
                    setValue = function(v)
                        saved.profile.boss.debuffCooldownTextSize = v
                        ReloadAndUpdate()
                    end,
                })
                yy = yy - hh
                if not CludesUI._prebuilding then -- Directions cog on Debuff Size (X/Y cluster offset)
                    CludesUI.BuildInlineCog(textSizeRow._leftRegion, {
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
                if not CludesUI._prebuilding then -- Icon Zoom cog on Debuff Size
                    local bossDebuffZoomOff = function()
                        return (saved.profile.boss.debuffAnchor or "bottomleft") == "none"
                    end
                    CludesUI.BuildInlineCog(textSizeRow._leftRegion, {
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
                if not CludesUI._prebuilding then
                    local rightRgn = textSizeRow._rightRegion
                    -- Inline Duration + Stack text-color swatches on the Debuff Text
                    -- Size slider; greyed + mouse-disabled on the same condition as
                    -- the row's cog.
                    local debuffOff = function()
                        return not BossDebuffLocationActive()
                    end
                    CludesUI.BuildInlineCog(rightRgn, {
                        disabled = debuffOff,
                        disabledTooltip = "Debuffs Location",
                        title = "Duration & Stack",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show Duration",
                                get = function()
                                    return saved.profile.boss.debuffShowCooldownText
                                end,
                                set = function(v)
                                    saved.profile.boss.debuffShowCooldownText = v
                                    ReloadAndUpdate()
                                    CludesUI:RefreshPage()
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
                    BossTextSwatch(rightRgn, "debuffCooldownTextColor", "Duration Text Color", debuffOff)
                    BossTextSwatch(rightRgn, "debuffStackTextColor", "Stack Text Color", debuffOff)
                end
            end -- close debuff sizing row hidden-while-None gate

            -- Built alongside the aura controls, then appended at the end
            -- of this section to keep border settings consistently last.
            local function AddBossAuraBorderSettings()
                local B = saved.profile.boss
                local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
                local borderRow
                borderRow, hh = Ww:DualRow(
                    pp,
                    yy,
                    CludesUI.BlizzStyle.Gate("unitframes", {
                        type = "dropdown",
                        text = "Border Style",
                        values = texValues,
                        order = texOrder,
                        getValue = function()
                            return B.auraBorderTexture or "solid"
                        end,
                        setValue = function(v)
                            local color, behind, behindUnitFrame = CludesUI.GetBorderStyleSelectDefaults(v)
                            B.auraBorderTexture = v
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
                            local ds = CludesUI.GetBorderDefaultSize("unitframes", v)
                            if ds then
                                B.auraBorderSize = ds
                            end
                            -- A style pick returns the icons to their legacy step; clear a
                            -- set exact size (false travels through mirror sync, nil would not).
                            if B.auraBorderSizePx then
                                B.auraBorderSizePx = false
                            end
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
                            -- The Width / Height Offset row exists only under a textured style.
                            CludesUI:RefreshPage(true)
                        end,
                    }),
                    CludesUI.BlizzStyle.Gate(
                        "unitframes",
                        CludesUI.BorderPxSliderCfg({
                            text = "Border Size",
                            trackWidth = 120,
                            getStep = function()
                                return B.auraBorderSize or 1
                            end,
                            setStep = function(step)
                                B.auraBorderSize = step
                            end,
                            getTex = function()
                                return B.auraBorderTexture or "solid"
                            end,
                            getPx = function()
                                return B.auraBorderSizePx
                            end,
                            setPx = function(v)
                                B.auraBorderSizePx = v
                            end,
                            apply = function()
                                ReloadAndUpdate()
                                if mod.RefreshBossPreviewDebuffs then
                                    mod.RefreshBossPreviewDebuffs()
                                end
                            end,
                        })
                    )
                )
                yy = yy - hh
                -- Width Offset | Height Offset: a textured aura border's outward
                -- offsets (a Solid border has none).
                do
                    local abTex = B.auraBorderTexture or "solid"
                    if abTex ~= "solid" and abTex ~= "" then
                        local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                            addonKey = "unitframes",
                            getTex = function()
                                return B.auraBorderTexture or "solid"
                            end,
                            getStep = function()
                                return B.auraBorderSize or 1
                            end,
                            getSizeKey = function()
                                return B.auraBorderSize or 1
                            end,
                            getPx = function()
                                return B.auraBorderSizePx
                            end,
                            getX = function()
                                return B.auraBorderTextureOffset
                            end,
                            setX = function(v)
                                B.auraBorderTextureOffset = v
                            end,
                            getY = function()
                                return B.auraBorderTextureOffsetY
                            end,
                            setY = function(v)
                                B.auraBorderTextureOffsetY = v
                            end,
                            apply = function()
                                ReloadAndUpdate()
                                if mod.RefreshBossPreviewDebuffs then
                                    mod.RefreshBossPreviewDebuffs()
                                end
                            end,
                        })
                        local offRow
                        offRow, hh = Ww:DualRow(
                            pp,
                            yy,
                            CludesUI.BlizzStyle.Gate("unitframes", ocfgL),
                            CludesUI.BlizzStyle.Gate("unitframes", ocfgR)
                        )
                        yy = yy - hh
                    end
                end
                if not CludesUI._prebuilding then
                    local region = borderRow._leftRegion
                    local button = CludesUI.BuildInlineCog(region, {
                        title = "Border Options",
                        rows = {
                            {
                                type = "slider",
                                label = "Shift X",
                                min = -10,
                                max = 10,
                                step = 1,
                                get = function()
                                    local v = B.auraBorderTextureShiftX
                                    if v ~= nil then
                                        return v
                                    end
                                    local _, _, posX = CludesUI.GetBorderDefaults(
                                        "unitframes",
                                        B.auraBorderTexture or "solid",
                                        B.auraBorderSize or 1
                                    )
                                    return posX
                                end,
                                set = function(v)
                                    B.auraBorderTextureShiftX = v == 0 and nil or v
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
                                    local v = B.auraBorderTextureShiftY
                                    if v ~= nil then
                                        return v
                                    end
                                    local _, _, _, posY = CludesUI.GetBorderDefaults(
                                        "unitframes",
                                        B.auraBorderTexture or "solid",
                                        B.auraBorderSize or 1
                                    )
                                    return posY
                                end,
                                set = function(v)
                                    B.auraBorderTextureShiftY = v == 0 and nil or v
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show Behind",
                                get = function()
                                    return B.auraBorderBehind or false
                                end,
                                set = function(v)
                                    B.auraBorderBehind = v
                                    ReloadAndUpdate()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Behind Unit Frame",
                                get = function()
                                    return B.auraBorderBehindUnitFrame or false
                                end,
                                set = function(v)
                                    B.auraBorderBehindUnitFrame = v
                                    ReloadAndUpdate()
                                end,
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
                                get = function()
                                    return B.auraBorderAboveEffects == true
                                end,
                                set = function(v)
                                    B.auraBorderAboveEffects = v
                                    ReloadAndUpdate()
                                end,
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
                    CludesUI.RegisterWidgetRefresh(vis)
                    vis()
                end
                if not CludesUI._prebuilding then
                    local region = borderRow._rightRegion
                    local sw, upd = CludesUI.BuildColorSwatch(
                        region,
                        borderRow:GetFrameLevel() + 3,
                        function()
                            return B.auraBorderR or 0,
                                B.auraBorderG or 0,
                                B.auraBorderB or 0,
                                B.auraBorderA or 1
                        end,
                        function(r, g, b, a)
                            B.auraBorderR = r
                            B.auraBorderG = g
                            B.auraBorderB = b
                            B.auraBorderA = a
                            ReloadAndUpdate()
                        end,
                        true,
                        20
                    )
                    Pix.Point(sw, "RIGHT", region._control, "LEFT", -8, 0)
                    CludesUI.RegisterWidgetRefresh(upd)
                end
            end
            AddBossAuraBorderSettings()
            -- Boss Debuff Filter in slot 1: the native mode dropdown, disabled
            -- with the requirement tooltip while no debuffs show at all (Simple
            -- Debuff Display None + Debuffs Location None). The right slot is the
            -- Boss Buff Filter.
            local filterRow
            local filterOff = function()
                local p = saved.profile.boss
                return mod.GetBossSimpleDebuffMode(p) == "none" and (p.debuffAnchor or "bottomleft") == "none"
            end
            local function BossS()
                return saved.profile.boss
            end
            local buffFilterOff
            local bossFilterRightSlot = { type = "label", text = "" }
            buffFilterOff = function()
                local p = saved.profile.boss
                return mod.GetBossSimpleBuffMode(p) == "none" and not p.showBuffs
            end
            bossFilterRightSlot = {
                type = "dropdown",
                text = "Boss Buff Filter",
                disabled = buffFilterOff,
                disabledTooltip = "Buffs",
                requireState = "displayed",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }
            filterRow, hh = Ww:DualRow(
                pp,
                yy,
                DebuffModeDropdownCfg(
                    "Boss Debuff Filter",
                    "boss",
                    BossS,
                    ReloadAndUpdate,
                    { disabled = filterOff, disabledTooltip = "Debuffs", requireState = "displayed" }
                ),
                bossFilterRightSlot
            )
            yy = yy - hh
            if not CludesUI._prebuilding then
                AttachDebuffModeWarn(filterRow._leftRegion, BossS, filterOff)
                -- Hide Exhaustion, the Debuff Filter cog row every unit shares.
                CludesUI.BuildInlineCog(filterRow._leftRegion, {
                    title = "Debuff Filter",
                    tip = "Debuff Filter Options",
                    disabled = filterOff,
                    disabledTooltip = "Debuffs",
                    requireState = "displayed",
                    rows = { HideExhaustionRow(BossS, ReloadAndUpdate) },
                })
            end
            -- Right slot: Boss Buff Filter (two-lane checkbox dropdown).
            if not CludesUI._prebuilding then
                local region = filterRow._rightRegion
                if region._control then
                    region._control:Hide()
                end
                local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                    region,
                    210,
                    region:GetFrameLevel() + 2,
                    buffFilterItems,
                    function(k, neg)
                        if neg then
                            local m = saved.profile.boss.buffNegClasses
                            local sk = BOSS_BUFF_NEG_SKEYS[k]
                            return m ~= nil and sk ~= nil and m[sk] == true
                        end
                        return saved.profile.boss[BUFF_FILTER_KEYS[k]] or false
                    end,
                    function(k, v, neg)
                        local bt = saved.profile.boss
                        local sk = BOSS_BUFF_NEG_SKEYS[k]
                        if neg then
                            if not sk then
                                return
                            end
                            bt.buffNegClasses = bt.buffNegClasses or {}
                            bt.buffNegClasses[sk] = v and true or nil
                            if not next(bt.buffNegClasses) then
                                bt.buffNegClasses = nil
                            end
                            if v then
                                bt[BUFF_FILTER_KEYS[k]] = nil
                            end
                            ReloadAndUpdate()
                            return
                        end
                        if v and sk and bt.buffNegClasses then
                            bt.buffNegClasses[sk] = nil
                            if not next(bt.buffNegClasses) then
                                bt.buffNegClasses = nil
                            end
                        end
                        bt[BUFF_FILTER_KEYS[k]] = v
                        ReloadAndUpdate()
                    end
                )
                Pix.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
                region._control = cbDD
                region._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbRefresh)
                local buffFilterBlock = CludesUI.NewSwatchBlocker(cbDD)
                buffFilterBlock:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(cbDD, CludesUI.DisabledTooltip("Buffs", "displayed"))
                end)
                buffFilterBlock:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateBuffFilterDisabled()
                    if buffFilterOff() then
                        cbDD:SetAlpha(0.3)
                        buffFilterBlock:Show()
                    else
                        cbDD:SetAlpha(1)
                        buffFilterBlock:Hide()
                    end
                end
                UpdateBuffFilterDisabled()
                CludesUI.RegisterWidgetRefresh(UpdateBuffFilterDisabled)
            end
        end

        -- Cogwheel on Buffs Location (disabled while Simple Buff Display
        -- overrides placement, or when Buffs Location is None)
        if not CludesUI._prebuilding then
            local leftRgn = bossAuraRow._leftRegion
            CludesUI.BuildInlineCog(leftRgn, {
                disabled = bossBuffSizeOff,
                -- Both branches are whole sentences (raw), so translated clients wrap once.
                disabledTooltip = function()
                    return mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none"
                            and CludesUI.DisabledTooltip("Simple Buff Display", "disabled")
                        or CludesUI.DisabledTooltip("Buffs Location")
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
                        set = function(v)
                            saved.profile.boss.buffMaxPerRow = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Dispel Type Borders",
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes")
                        end,
                        disabledTooltip = "This option requires Blizzard Style to be disabled",
                        get = function()
                            return saved.profile.boss.buffDispelBorder == true
                        end,
                        set = function(v)
                            saved.profile.boss.buffDispelBorder = v
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
        end

        -- Cogwheel on Debuffs Location (hidden when Simple Debuff Display overrides placement)
        if not CludesUI._prebuilding then
            local rightRgn = bossAuraRow._rightRegion
            CludesUI.BuildInlineCog(rightRgn, {
                disabled = bossDebuffSizeOff,
                disabledTooltip = function()
                    return mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none"
                            and CludesUI.DisabledTooltip("Simple Debuff Display", "disabled")
                        or CludesUI.DisabledTooltip("Debuffs Location")
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
                    mod.UFO_MaxImportantRow(function()
                        return saved.profile.boss
                    end, ReloadAndUpdate, 20, 10),
                    {
                        type = "slider",
                        label = "Max Per Row",
                        min = 1,
                        max = 20,
                        step = 1,
                        get = function()
                            return saved.profile.boss.debuffMaxPerRow or saved.profile.boss.maxDebuffs or 10
                        end,
                        set = function(v)
                            saved.profile.boss.debuffMaxPerRow = v
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
        end

        -- Buff/Debuff text colors now live as inline swatches on the Buff Text
        -- Size / Debuff Text Size sliders above (Duration + Stack per side).

        return yy
    end

    -- New "Indicators" section, rendered at the BOTTOM (below the Power Bar)
    -- via opts.afterPowerRow. Holds the non-aura indicators moved out of the
    -- Buffs and Debuffs section above.
    local function bossIndicators(Ww, pp, yy)
        local hh

        _, hh = Ww:SectionHeader(pp, "INDICATORS", yy)
        yy = yy - hh

        -- Row 1: Out of Range Alpha | Spell Target
        -- (Out of Range read live by the range ticker, so no reload needed.)
        local bossTgtRow
        bossTgtRow, hh = Ww:DualRow(pp, yy, {
            type = "slider",
            text = "Out of Range Alpha",
            min = 10,
            max = 100,
            step = 1,
            tooltip = "Fades boss frames when the boss is out of range of your spells. Set to 100% to disable the fade.",
            getValue = function()
                return math.floor(((saved.profile.boss.oorAlpha or 0.4) * 100) + 0.5)
            end,
            setValue = function(v)
                saved.profile.boss.oorAlpha = v / 100
            end,
        }, {
            type = "toggle",
            text = "Spell Target",
            tooltip = "Show the name of who the boss is casting on.",
            getValue = function()
                return saved.profile.boss.showCastTarget == true
            end,
            setValue = function(v)
                saved.profile.boss.showCastTarget = v
                ReloadAndUpdate()
            end,
        })
        yy = yy - hh
        -- Inline cog on Spell Target: X/Y offsets for the cast target
        -- text. Boss-scoped copies of the shared castbar keys, which the
        -- runtime and preview already consume (castSpellTargetX/Y ->
        -- _tgtOX/_tgtOY in the cast text zone layout).
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(bossTgtRow._rightRegion, {
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
        local function bossRmOff()
            return saved.profile.boss.raidMarkerEnabled == false
        end
        local bossRmRow
        bossRmRow, hh = Ww:DualRow(pp, yy, {
            type = "toggle",
            text = "Show Raid Marker",
            tooltip = "Shows the raid target marker icon on boss frames.",
            getValue = function()
                return saved.profile.boss.raidMarkerEnabled ~= false
            end,
            setValue = function(v)
                saved.profile.boss.raidMarkerEnabled = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Raid Marker Size",
            min = 12,
            max = 48,
            step = 1,
            disabled = bossRmOff,
            disabledTooltip = "Raid Marker",
            getValue = function()
                return saved.profile.boss.raidMarkerSize or 28
            end,
            setValue = function(v)
                saved.profile.boss.raidMarkerSize = v
                ReloadAndUpdate()
            end,
        })
        yy = yy - hh
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(bossRmRow._leftRegion, {
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

        return yy
    end

    -- CAST BAR section, rendered below the Power Bar. Mirrors the player cast
    -- bar's Show Cast Bar/Height/Bar Background/Spell Name/Duration/Reverse Fill.
    -- All keys are boss-scoped (db.profile.boss.*), read by the shared castbar
    -- runtime + preview so both live-update. "Show Cast Bar" off (showCastbar=false) hides it entirely (runtime disables Castbar; preview zero-heights it).
    local function bossCastBar(Ww, pp, yy)
        local B = saved.profile.boss
        local hh

        -- The Show Cast Bar toggle gates the rest of the section. AddCastBlock
        -- greys a region (slider/dropdown/toggle + any inline swatch) to 0.3 and
        -- blocks its mouse while the cast bar is off, tracked live via the
        -- widget-refresh fast path (mirrors AddDarkModeBlock). The toggle's own color swatches gate separately so the toggle stays interactive.
        local castColorSwatches = {}
        local function AddCastBlock(region, enabledAlpha)
            if not region then
                return
            end
            local block = CreateFrame("Frame", nil, region)
            block:SetAllPoints()
            block:SetFrameLevel(region:GetFrameLevel() + 50)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(block, CludesUI.DisabledTooltip("Show Cast Bar"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function Update()
                if B.showCastbar == false then
                    region:SetAlpha(0.3)
                    block:Show()
                else
                    region:SetAlpha(enabledAlpha and enabledAlpha() or 1)
                    block:Hide()
                end
            end
            Update()
            CludesUI.RegisterWidgetRefresh(Update)
        end

        bossCastHeader, hh = Ww:SectionHeader(pp, "CAST BAR", yy)
        yy = yy - hh

        -- Row 1: Show Cast Bar (+ inline fill-color swatch) | Cast Bar Height
        castMainRow, hh = Ww:DualRow(pp, yy, {
            type = "toggle",
            text = "Show Cast Bar",
            getValue = function()
                return B.showCastbar ~= false
            end,
            -- DependentSetValue: rows 2-4 below are hidden while the
            -- cast bar is off; the flip forces the full rebuild.
            setValue = CludesUI.DependentSetValue(function()
                return B.showCastbar ~= false
            end, function(v)
                B.showCastbar = v
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end),
        }, {
            type = "slider",
            text = "Cast Bar Height",
            min = 1,
            max = 40,
            step = 1,
            disabled = function()
                return B.showCastbar == false
            end,
            disabledTooltip = "Show Cast Bar",
            getValue = function()
                return B.castbarHeight or 14
            end,
            setValue = function(v)
                B.castbarHeight = v
                ReloadAndUpdate()
            end,
        })
        yy = yy - hh
        -- Inline settings cog matching target/focus, plus boss positioning.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(castMainRow._leftRegion, {
                disabled = function()
                    return B.showCastbar == false
                end,
                disabledTooltip = "Show Cast Bar",
                title = "Cast Bar",
                rows = {
                    {
                        type = "toggle",
                        label = "Hide When Idle",
                        tooltip = "Only show the cast bar while a cast is in progress; hide it the rest of the time.",
                        get = function()
                            return B.castbarHideWhenInactive ~= false
                        end,
                        set = function(v)
                            B.castbarHideWhenInactive = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Fill Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        tooltip = "Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
                        get = function()
                            return B.castFillOpacity or 100
                        end,
                        set = function(v)
                            B.castFillOpacity = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Raise Cast Bar Strata (All)",
                        tooltip = "Lifts player, target, focus, and boss cast bars above other frames so they are never hidden behind them.",
                        get = function()
                            return saved.profile.raiseCastbarStrata ~= false
                        end,
                        set = function(v)
                            saved.profile.raiseCastbarStrata = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Kick Ready Mid-Cast Tick",
                        tooltip = "Shows a small white tick mark where the cast will be when your interrupt comes off cooldown.",
                        get = function()
                            return B.castbarKickTickEnabled ~= false
                        end,
                        set = function(v)
                            B.castbarKickTickEnabled = v
                            ReloadAndUpdate()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Kick Ready Mid-Cast Bar",
                        tooltip = "Colors the cast segment during which your interrupt will be available.",
                        get = function()
                            return B.castbarInterruptMidCastEnabled == true
                        end,
                        set = function(v)
                            B.castbarInterruptMidCastEnabled = v
                            ReloadAndUpdate()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -500,
                        max = 500,
                        step = 1,
                        get = function()
                            return B.castbarOffsetX or 0
                        end,
                        set = function(v)
                            B.castbarOffsetX = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -200,
                        max = 200,
                        step = 1,
                        get = function()
                            return B.castbarOffsetY or 0
                        end,
                        set = function(v)
                            B.castbarOffsetY = v
                            ReloadAndUpdate()
                            if mod.RefreshBossPreviewDebuffs then
                                mod.RefreshBossPreviewDebuffs()
                            end
                        end,
                    },
                    -- Opt-in for the Border Style | Border Size rows (built
                    -- below only while on; the rebuild shows or drops them).
                    {
                        type = "toggle",
                        label = "Custom Border Style",
                        tooltip = "Show the border style and size controls for the cast bar.",
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes")
                        end,
                        disabledTooltip = function()
                            return CludesUI.BlizzStyle.Label("unitframes")
                        end,
                        requireState = "disabled",
                        get = function()
                            return B.castBorderCustom == true
                        end,
                        set = function(v)
                            B.castBorderCustom = v
                            ReloadAndUpdate()
                            CludesUI:RefreshPage(true)
                        end,
                    },
                },
            })
        end
        -- Enemy cast colors on Show Cast Bar (left region), matching target/focus.
        if not CludesUI._prebuilding then
            local region = castMainRow._leftRegion
            local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
                local sw, updateSw = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local c = B[colorKey] or fallback
                    return c.r, c.g, c.b, 1
                end, function(r, g, b)
                    B[colorKey] = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                sw:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, tooltip)
                end)
                sw:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                region._lastInline = sw
                castColorSwatches[#castColorSwatches + 1] = {
                    sw = sw,
                    enabledAlpha = disabledFn and function()
                        return disabledFn() and 0.3 or 1
                    end,
                }
                if disabledFn then
                    local function Update()
                        local off = disabledFn()
                        sw:SetAlpha(off and 0.3 or 1)
                        sw:EnableMouse(not off)
                        if updateSw then
                            updateSw()
                        end
                    end
                    Update()
                    CludesUI.RegisterWidgetRefresh(Update)
                end
            end
            AddCastColorSwatch(
                "Interrupt Ready Mid-Cast",
                "castbarInterruptMidCastColor",
                { r = 0.318, g = 0.820, b = 0.357 },
                function()
                    return B.castbarInterruptMidCastEnabled ~= true
                end
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
            growthRow, hh = Ww:DualRow(pp, yy, {
                type = "toggle",
                text = "Show Cast Icon",
                getValue = function()
                    return B.showCastIcon ~= false
                end,
                setValue = function(v)
                    B.showCastIcon = v
                    ReloadAndUpdate()
                end,
            }, {
                type = "slider",
                text = "Cast Bar Width",
                min = 0,
                max = 500,
                step = 1,
                tooltip = "Sets a custom width for the cast bar. Set to 0 to match the boss frame width.",
                getValue = function()
                    return B.castbarWidth or 0
                end,
                -- Custom widths floor at 30 (matches the unlock-mode resize
                -- minimum): below the cast icon size the bar layout inverts.
                setValue = function(v)
                    if v > 0 and v < 30 then
                        v = 30
                    end
                    B.castbarWidth = v
                    ReloadAndUpdate()
                    if mod.RefreshBossPreviewDebuffs then
                        mod.RefreshBossPreviewDebuffs()
                    end
                end,
            })
            yy = yy - hh
            -- Icon cog (left): "Icon Border" / "Make Icon Part of the Bar" /
            -- "Border Wraps Icon" / "Vertical Separator" / "Show Icon on Right".
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(growthRow._leftRegion, {
                    title = "Cast Icon",
                    rows = {
                        {
                            type = "toggle",
                            label = "Icon Border",
                            tooltip = "Use the cast bar's border style, size and color around the icon.",
                            disabled = function()
                                return CludesUI.BlizzStyle.Get("unitframes") or B.showCastIcon == false
                            end,
                            disabledTooltip = "This option requires Show Icon and the CludesUI style.",
                            get = function()
                                return B.castIconBorder == true
                            end,
                            set = function(v)
                                B.castIconBorder = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Make Icon Part of the Bar",
                            tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                            -- The stock styles count a shown icon as part of the bar
                            -- (their frame art wraps both), so the toggle reads on and locks.
                            disabled = function()
                                return CludesUI.BlizzStyle.Get("unitframes")
                            end,
                            disabledTooltip = function()
                                return CludesUI.BlizzStyle.Label("unitframes")
                            end,
                            requireState = "disabled",
                            get = function()
                                if CludesUI.BlizzStyle.Get("unitframes") then
                                    return true
                                end
                                return B.castbarIconInWidth ~= false
                            end,
                            set = function(v)
                                B.castbarIconInWidth = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Border Wraps Icon",
                            tooltip = "Draw the custom cast bar border around the icon and the bar together. An icon with an offset keeps its own border.",
                            disabled = function()
                                return CludesUI.BlizzStyle.Get("unitframes")
                                    or B.castBorderCustom ~= true
                                    or not mod.UF_CastIconInWidth("boss", B)
                            end,
                            disabledTooltip = "This option requires Custom Border Style, Show Icon and Make Icon Part of the Bar, with the CludesUI style.",
                            get = function()
                                return B.castBorderWrapIcon == true
                            end,
                            set = function(v)
                                B.castBorderWrapIcon = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Vertical Separator",
                            tooltip = "Draw a divider between the integrated icon and the bar, using the cast bar's border appearance.",
                            disabled = function()
                                return CludesUI.BlizzStyle.Get("unitframes")
                                    or not mod.UF_CastIconInWidth("boss", B)
                                    or not mod.UF_CastIconSeamOK(B)
                            end,
                            disabledTooltip = function()
                                if
                                    CludesUI.BlizzStyle.Get("unitframes")
                                    or not mod.UF_CastIconInWidth("boss", B)
                                then
                                    return "This option requires Show Icon and Make Icon Part of the Bar, with the CludesUI style."
                                end
                                return "This option requires Solid or a border style with divider art, and a Border Size above 0."
                            end,
                            get = function()
                                return B.castIconSeparator == true
                            end,
                            set = function(v)
                                B.castIconSeparator = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Icon on Right",
                            tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                            get = function()
                                return B.castbarIconRight == true
                            end,
                            set = function(v)
                                B.castbarIconRight = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
            end
            -- Row 3: Reverse Fill | Bar Background (opacity slider + color swatch).
            -- Bar Background sits right below the size sliders (mirrors the main
            -- frames' cast bar section, where it follows the Height row).
            local reverseRow
            reverseRow, hh = Ww:DualRow(pp, yy, {
                type = "toggle",
                text = "Reverse Fill",
                getValue = function()
                    return B.castReverseFill == true
                end,
                setValue = function(v)
                    B.castReverseFill = v
                    ReloadAndUpdate()
                end,
            }, {
                type = "slider",
                text = "Bar Background",
                min = 0,
                max = 100,
                step = 1,
                getValue = function()
                    return math.floor((B.castBgAlpha or 0.5) * 100 + 0.5)
                end,
                setValue = function(v)
                    B.castBgAlpha = v / 100
                    ReloadAndUpdate()
                end,
            })
            yy = yy - hh
            -- Inline color swatch on Bar Background (right region).
            if not CludesUI._prebuilding then
                local region = reverseRow._rightRegion
                local sw = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local c = B.castBgColor
                    if c then
                        return c.r, c.g, c.b
                    end
                    return 0, 0, 0
                end, function(r, g, b)
                    B.castBgColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                sw:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                sw:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, "Cast Background")
                end)
                sw:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                region._lastInline = sw
            end

            -- Row 4: Spell Name (dropdown + Size/X/Y cog + swatch) | Duration (same)
            local castTextRow
            castTextRow, hh = Ww:DualRow(pp, yy, {
                type = "dropdown",
                text = "Spell Name",
                values = { none = "None", left = "Left", right = "Right", center = "Center" },
                order = { "none", "left", "right", "center" },
                getValue = function()
                    return B.castSpellNameSide or "left"
                end,
                setValue = function(v)
                    B.castSpellNameSide = v
                    -- Conflict rule (mirrors player): name and the spell target may
                    -- not share a side -- setting the name onto the target's side
                    -- turns the target (Indicators) off.
                    if
                        v ~= "none"
                        and (B.showCastTarget ~= false)
                        and (B.castSpellTargetSide or "right") == v
                    then
                        B.showCastTarget = false
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "segmented",
                text = "Duration",
                values = { none = "None", right = "Right", left = "Left" },
                order = { "none", "right", "left" },
                getValue = function()
                    if B.showCastDuration == false then
                        return "none"
                    end
                    return B.castDurationSide or "right"
                end,
                setValue = function(v)
                    if v == "none" then
                        B.showCastDuration = false
                    else
                        B.showCastDuration = true
                        B.castDurationSide = v
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
            })
            yy = yy - hh
            -- Spell Name (left): Size/X/Y cog + color swatch
            if not CludesUI._prebuilding then
                local region = castTextRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Spell Name",
                    rows = {
                        {
                            type = "slider",
                            label = "Size",
                            min = 6,
                            max = 20,
                            step = 1,
                            get = function()
                                return B.castSpellNameSize or 11
                            end,
                            set = function(v)
                                B.castSpellNameSize = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return B.castSpellNameX or 0
                            end,
                            set = function(v)
                                B.castSpellNameX = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return B.castSpellNameY or 0
                            end,
                            set = function(v)
                                B.castSpellNameY = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
                local sw = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local c = B.castSpellNameColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b
                end, function(r, g, b)
                    B.castSpellNameColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                sw:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = sw
            end
            -- Duration (right): Size/X/Y cog + color swatch
            if not CludesUI._prebuilding then
                local region = castTextRow._rightRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Duration",
                    rows = {
                        {
                            type = "slider",
                            label = "Size",
                            min = 6,
                            max = 20,
                            step = 1,
                            get = function()
                                return B.castDurationSize or 10
                            end,
                            set = function(v)
                                B.castDurationSize = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return B.castDurationX or 0
                            end,
                            set = function(v)
                                B.castDurationX = v
                                ReloadAndUpdate()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return B.castDurationY or 0
                            end,
                            set = function(v)
                                B.castDurationY = v
                                ReloadAndUpdate()
                            end,
                        },
                    },
                })
                local sw = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, function()
                    local c = B.castDurationColor or { r = 1, g = 1, b = 1 }
                    return c.r, c.g, c.b
                end, function(r, g, b)
                    B.castDurationColor = { r = r, g = g, b = b }
                    ReloadAndUpdate()
                end, false, 20)
                sw:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = sw
            end
            -- Custom Border Style rows (the Cast Bar cog's opt-in): one table
            -- styles all five boss cast bars; no unlock element, no sync links.
            if B.castBorderCustom == true then
                yy = yy
                    - mod.UF_CastBorderRows(Ww, pp, yy, function()
                        return B
                    end, ReloadAndUpdate)
            end
            -- Classic WoW UI: Border Size closes the section (odd last slot).
            yy = yy
                - mod.UF_ClassicCastBorderRow(
                    Ww,
                    pp,
                    yy,
                    function()
                        return B
                    end,
                    mod.UF_CastClassicKey("boss"),
                    function()
                        ReloadAndUpdate()
                    end
                )
        end -- close boss Cast Bar hidden-while-disabled gate

        -- The Show Cast Bar toggle's own color swatches stay gated grey +
        -- blocked while the cast bar is off (the Height slider uses a
        -- native disabled state; the hidden rows need nothing).
        for _, item in ipairs(castColorSwatches) do
            AddCastBlock(item.sw, item.enabledAlpha)
        end
        return yy
    end

    local displayHeader, sizeRow, textHeader, textRow
    posY, displayHeader, sizeRow, textHeader, textRow =
        BuildMiniTextAndSize(W, hostFrame, posY, saved.profile.boss, "boss", enableRow, bossAfterSize, {
            hasPowerBar = true,
            afterPowerRow = function(Ww, pp, yy)
                yy = bossCastBar(Ww, pp, yy)
                return bossIndicators(Ww, pp, yy)
            end,
        })

    -- Store click targets for hover highlight system
    hostFrame._ufClickTargets = {
        -- Health bar -> Health Bar Height (sizeRow left, HEALTH BAR section);
        -- Power bar -> Power Bar Height (pwrRow1 left, POWER BAR section).
        healthBar = { section = textHeader or displayHeader, target = sizeRow, slotSide = "left" },
        powerBar = {
            section = hostFrame._powerHeaderFrame or displayHeader,
            target = hostFrame._powerHeightRow,
            slotSide = "left",
        },
        powerBarText = {
            section = hostFrame._powerHeaderFrame or displayHeader,
            target = hostFrame._powerTextRow,
            slotSide = "left",
        },
        portrait = { section = displayHeader, target = portraitRow, slotSide = "right" },
        nameText = mod.UFO_TextClickTarget(
            hostFrame,
            "leftText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        healthText = mod.UFO_TextClickTarget(
            hostFrame,
            "rightText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        centerText = mod.UFO_TextClickTarget(
            hostFrame,
            "centerText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        extraText = mod.UFO_TextClickTarget(
            hostFrame,
            "extraText",
            textHeader or displayHeader,
            textRow or sizeRow
        ),
        -- Blizzard Style level number -> Show Level (+ its cog).
        levelText = {
            section = textHeader or displayHeader,
            target = hostFrame._ufLevelRow,
            slotSide = "left",
        },
        -- Cast bar -> Cast Bar Height; spell icon -> Show Cast Icon. Both live
        -- in growthRow after the swap (Show Cast Icon left, Cast Bar Height right).
        castBar = {
            section = bossCastHeader or displayHeader,
            target = castMainRow or growthRow,
            slotSide = "left",
        },
        castIcon = { section = bossCastHeader or displayHeader, target = growthRow, slotSide = "left" },
        -- Buffs/Debuffs scroll to the active control: Simple Display when it's
        -- on (the column is forced), otherwise the normal Location dropdown.
        buffIcon = function()
            if mod.GetBossSimpleBuffMode(saved.profile.boss) ~= "none" then
                return { section = bossAuraHeader or displayHeader, target = simpleBuffRow }
            end
            return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "left" }
        end,
        debuffIcon = function()
            if mod.GetBossSimpleDebuffMode(saved.profile.boss) ~= "none" then
                return { section = bossAuraHeader or displayHeader, target = simpleRow }
            end
            return { section = bossAuraHeader or displayHeader, target = bossAuraRow, slotSide = "right" }
        end,
    }

    return abs(posY)
end
