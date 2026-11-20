if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedBars_Options.lua
--  Unit Frames options: Health Bar, Power Bar, Class Resource and Absorbs sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
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

function mod.UFO_BuildHealthBarSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local AddDarkModeBlock, GROUP_UNIT_ORDER, Pix, RegisterWidgetRefresh =
        environ.AddDarkModeBlock, environ.GROUP_UNIT_ORDER, environ.PP, environ.RegisterWidgetRefresh
    local ReloadAndUpdate, UNIT_DB_MAP, UpdatePreview =
        environ.ReloadAndUpdate, environ.UNIT_DB_MAP, environ.UpdatePreview
    local saved, healthTextOrder, healthTextOrderPlayer, healthTextOrderTargetFocus =
        environ.db, environ.healthTextOrder, environ.healthTextOrderPlayer, environ.healthTextOrderTargetFocus
    local healthTextValues, optionState = environ.healthTextValues, environ.optState
    local W, SDB, SGet, SSet = context.W, context.SDB, context.SGet, context.SSet
    -- Row setters over SSet: the key written with the row's value, then UpdatePreview() for the Then form.
    local function SSetRow(settingKey)
        return function(value)
            SSet(settingKey, value)
        end
    end
    local function SSetRowThen(settingKey)
        return function(value)
            SSet(settingKey, value)
            UpdatePreview()
        end
    end
    local SVal = context.SVal
    -- A row getter over SVal: the key's value, or the default given.
    local function SValRow(settingKey, default)
        return function()
            return SVal(settingKey, default)
        end
    end
    local _, height

    -------------------------------------------------------------------
    --  HEALTH BAR
    -------------------------------------------------------------------
    local sharedBarsHeader
    sharedBarsHeader, height = W:SectionHeader(hostFrame, "HEALTH BAR", cursorY)
    cursorY = cursorY - height

    -- Row 1: Bar Height + Bar Width
    local sharedSizeRow
    local ufhDis, ufhTip, ufhRaw = CludesUI.MatchGuard(optionState.selectedUnit, "Height")
    local ufwDis, ufwTip, ufwRaw = CludesUI.MatchGuard(optionState.selectedUnit, "Width")
    -- Vertical Fill wants tall, narrow bars: the Vertical Fill toggle rebuilds the page.
    local vertFill = SVal("healthVerticalFill", false) == true
    sharedSizeRow, height = W:DualRow(
        hostFrame,
        cursorY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Health Bar Height",
            min = 15,
            max = vertFill and 400 or 100,
            step = 1,
            disabled = ufhDis,
            disabledTooltip = ufhTip,
            rawTooltip = ufhRaw,
            getValue = SValRow("healthHeight", 46),
            setValue = SSetRow("healthHeight"),
        }),
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "slider",
            text = "Bar Width",
            min = vertFill and 20 or 80,
            max = 400,
            step = 1,
            disabled = ufwDis,
            disabledTooltip = ufwTip,
            rawTooltip = ufwRaw,
            getValue = SValRow("frameWidth", 181),
            setValue = SSetRow("frameWidth"),
        })
    )
    cursorY = cursorY - height
    -- Blizzard Style: the stock size is fixed, so the whole frame scales instead
    -- (this row is the preview's health-bar click target while the size row hides).
    local sharedScaleRow
    if CludesUI.BlizzStyle.Get("unitframes") then
        sharedScaleRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "slider",
                text = "Frame Scale",
                min = 50,
                max = 200,
                step = 5,
                tooltip = "Scales the whole frame. Blizzard Style frames are the stock size, so this stands in for Bar Width and Health Bar Height.",
                getValue = function()
                    return math.floor(SVal("blizzScale", 1) * 100 + 0.5)
                end,
                setValue = function(val)
                    SSet("blizzScale", val / 100)
                end,
            },
            -- Reverse Fill otherwise lives in the cog on the hidden size row.
            {
                type = "toggle",
                text = "Reverse Fill",
                getValue = SValRow("healthReverseFill", false),
                setValue = function(val)
                    SSet("healthReverseFill", val)
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
            }
        )
        cursorY = cursorY - height
    end
    -- Sync icons: Bar Height (left) and Bar Width (right)
    if not CludesUI._prebuilding then
        local region = sharedSizeRow._leftRegion
        mod.UFO_UnitSync(region, "Health Bar Height", {
            key = "healthHeight",
            default = 46,
        })
    end
    -- Reverse Fill cog on Bar Height (left region)
    if not CludesUI._prebuilding then
        local region = sharedSizeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Health Bar Fill",
            rows = {
                {
                    type = "toggle",
                    label = "Reverse Fill",
                    get = SValRow("healthReverseFill", false),
                    set = function(val)
                        SSet("healthReverseFill", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                },
                -- Vertical Fill swaps the bar's fill AXIS; Reverse Fill flips the
                -- direction within it (bottom-to-top default, top-to-bottom reversed).
                {
                    type = "toggle",
                    label = "Vertical Fill",
                    tooltip = "Fill the health bar bottom-to-top instead of left-to-right. Reverse Fill flips it to top-to-bottom.",
                    get = SValRow("healthVerticalFill", false),
                    -- A full rebuild: the size sliders' ranges follow Vertical Fill
                    -- (baked in at build), and the Absorbs Placement dropdowns
                    -- re-label for the new axis (cog popups bake labels in too).
                    set = function(val)
                        SSet("healthVerticalFill", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage(true)
                    end,
                },
            },
        })
    end
    if not CludesUI._prebuilding then
        local region = sharedSizeRow._rightRegion
        mod.UFO_UnitSync(region, "Bar Width", {
            key = "frameWidth",
            default = 181,
        })
    end

    -- Row 2: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
    local sharedHealthColorRow
    sharedHealthColorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Fill Color",
        swatches = {
            {
                tooltip = "Gradient End Color",
                hasAlpha = false,
                disabled = function()
                    return not SVal("gradientEnabled", false)
                end,
                disabledTooltip = function()
                    return "Gradient"
                end,
                getValue = function()
                    local color = SGet("gradientColor")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 0.20, 0.20, 0.80
                end,
                setValue = function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]().gradientColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
            },
            {
                tooltip = "Custom Colored Fill",
                hasAlpha = false,
                -- Dynamic Color resolves the fill from health percent, so the flat
                -- custom/class choice below has no effect while it is on. Greyed and
                -- click-blocked rather than reset: the stored customFillColor and
                -- healthClassColored are left exactly as the user had them and come
                -- back untouched the moment Dynamic Color goes to Off.
                disabled = function()
                    return SVal("healthColorMode", "none") ~= "none"
                end,
                disabledTooltip = "Dynamic Color is on -- the fill color comes from the unit's health",
                rawTooltip = true,
                getValue = function()
                    local color = SGet("customFillColor")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 37 / 255, 193 / 255, 29 / 255
                end,
                setValue = function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]().customFillColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
                onClick = function(self)
                    if SVal("healthClassColored", true) then
                        -- Seed the custom fill on first use: without a stored
                        -- customFillColor the runtime falls back to oUF's class/reaction
                        -- color (bar looks unchanged until dragged); never overwrites an existing custom color.
                        if SGet("customFillColor") == nil then
                            UNIT_DB_MAP[optionState.selectedUnit]().customFillColor =
                                { r = 37 / 255, g = 193 / 255, b = 29 / 255 }
                        end
                        SSet("healthClassColored", false)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return SVal("healthClassColored", true) and 0.3 or 1
                end,
            },
            {
                tooltip = "Class Colored Fill",
                hasAlpha = false,
                -- Same as the custom swatch: inert while Dynamic Color is on, so it
                -- greys out instead of silently doing nothing. Class Reactive still
                -- uses the class color, but as the 100% stop of the curve, not as
                -- this flat choice.
                disabled = function()
                    return SVal("healthColorMode", "none") ~= "none"
                end,
                disabledTooltip = "Dynamic Color is on -- the fill color comes from the unit's health",
                rawTooltip = true,
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
                    SSet("healthClassColored", true)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return SVal("healthClassColored", true) and 1 or 0.3
                end,
            },
        },
    }, {
        type = "slider",
        text = "Bar Background",
        min = 0,
        max = 100,
        step = 1,
        getValue = SValRow("customBgAlpha", 100),
        setValue = function(val)
            SSet("customBgAlpha", val)
            ReloadAndUpdate()
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height
    -- Inline swatches on Bar Background (right): Custom + Class pair mirroring the
    -- Bar Color picker; either toggles bgClassColored, the inactive one dims to 0.3.
    if not CludesUI._prebuilding then
        local region = sharedHealthColorRow._rightRegion
        mod.UFO_SwatchPair(region, {
            store = function()
                return UNIT_DB_MAP[optionState.selectedUnit]()
            end,
            flag = "bgClassColored",
            flagDefault = false,
            autoGet = function()
                local _, ct = UnitClass("player")
                local classColor = ct and RAID_CLASS_COLORS[ct]
                if classColor then
                    return classColor.r, classColor.g, classColor.b
                end
                return 1, 1, 1
            end,
            autoTip = "Class Colored Background",
            colorKey = "customBgColor",
            colorDefault = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
            customTip = "Custom Background Color",
            apply = function()
                ReloadAndUpdate()
                UpdatePreview()
            end,
        })
    end
    -- Sync icon: Bar Background (right) -- background color + opacity
    if not CludesUI._prebuilding then
        local region = sharedHealthColorRow._rightRegion
        local function ApplyBgTo(keyList)
            local source = UNIT_DB_MAP[optionState.selectedUnit]()
            local bc = source.customBgColor or { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
            local bgA = source.customBgAlpha or 100
            local bgClass = source.bgClassColored or false
            for _, settingKey in ipairs(keyList) do
                if settingKey ~= optionState.selectedUnit then
                    local d = UNIT_DB_MAP[settingKey]()
                    d.customBgColor = { r = bc.r, g = bc.g, b = bc.b }
                    d.customBgAlpha = bgA
                    d.bgClassColored = bgClass
                end
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
        end
        mod.UFO_UnitSync(region, "Bar Background", {
            applyTo = ApplyBgTo,
            isSynced = function()
                local source = UNIT_DB_MAP[optionState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then
                        return true
                    end
                    if a == nil or b == nil then
                        return false
                    end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[settingKey]()
                    if not colEq(d.customBgColor, source.customBgColor) then
                        return false
                    end
                    if (d.customBgAlpha or 100) ~= (source.customBgAlpha or 100) then
                        return false
                    end
                    if (d.bgClassColored or false) ~= (source.bgClassColored or false) then
                        return false
                    end
                end
                return true
            end,
        })
    end
    -- Sync icon: Bar Color (left) -- fill/class color and gradient
    if not CludesUI._prebuilding then
        local region = sharedHealthColorRow._leftRegion
        -- Dynamic Color lives in this slot's cog, and its three stops are inline
        -- swatches on this row, so they travel with the rest of Bar Color.
        local DYN_STOP_KEYS = { "dynamicColor100", "dynamicColor50", "dynamicColor0" }
        local function ApplyColorTo(keyList)
            local source = UNIT_DB_MAP[optionState.selectedUnit]()
            local classColor = source.healthClassColored or false
            local fc = source.customFillColor
            local gEn = source.gradientEnabled or false
            local gDir = source.gradientDir or "HORIZONTAL"
            local gc = source.gradientColor
            local dynMode = source.healthColorMode or "none"
            for _, settingKey in ipairs(keyList) do
                if settingKey ~= optionState.selectedUnit then
                    local d = UNIT_DB_MAP[settingKey]()
                    d.healthClassColored = classColor
                    if fc then
                        d.customFillColor = { r = fc.r, g = fc.g, b = fc.b }
                    else
                        d.customFillColor = nil
                    end
                    d.gradientEnabled = gEn
                    d.gradientDir = gDir
                    if gc then
                        d.gradientColor = { r = gc.r, g = gc.g, b = gc.b }
                    else
                        d.gradientColor = nil
                    end
                    d.healthColorMode = dynMode
                    for _, ck in ipairs(DYN_STOP_KEYS) do
                        local sc = source[ck]
                        if sc then
                            d[ck] = { r = sc.r, g = sc.g, b = sc.b }
                        else
                            d[ck] = nil
                        end
                    end
                end
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
        end
        mod.UFO_UnitSync(region, "Bar Color", {
            applyTo = ApplyColorTo,
            isSynced = function()
                local source = UNIT_DB_MAP[optionState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then
                        return true
                    end
                    if a == nil or b == nil then
                        return false
                    end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[settingKey]()
                    if (d.healthClassColored or false) ~= (source.healthClassColored or false) then
                        return false
                    end
                    if not colEq(d.customFillColor, source.customFillColor) then
                        return false
                    end
                    if (d.gradientEnabled or false) ~= (source.gradientEnabled or false) then
                        return false
                    end
                    if not colEq(d.gradientColor, source.gradientColor) then
                        return false
                    end
                    if (d.gradientDir or "HORIZONTAL") ~= (source.gradientDir or "HORIZONTAL") then
                        return false
                    end
                    if (d.healthColorMode or "none") ~= (source.healthColorMode or "none") then
                        return false
                    end
                    for _, ck in ipairs(DYN_STOP_KEYS) do
                        if not colEq(d[ck], source[ck]) then
                            return false
                        end
                    end
                end
                return true
            end,
        })
    end
    -- Fill Color cog on Bar Color (left region): the two settings that decide
    -- what color the fill actually ends up, beyond the flat swatches.
    -- Dynamic Color and Gradient COMPOSE -- Dynamic picks the color from the
    -- unit's health percent, Gradient then runs from that color to the
    -- gradient end color -- so they share one popup rather than fighting.
    if not CludesUI._prebuilding then
        local region = sharedHealthColorRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Fill Color Settings",
            rows = {
                -- Ported from the Raid Frames "Fill Color" dropdown: same modes,
                -- same curve shape, same stop defaults, so a unit frame and a
                -- party frame on the same mode paint the same color at the same
                -- health. The 100%/50%/0% stops are swatches on the row itself
                -- (cog popups have no color row type).
                {
                    type = "dropdown",
                    label = "Dynamic Color",
                    tooltip = "Color the health bar by how much health is left, instead of a flat color. Classic runs green at full health through yellow to red at empty. Custom Colors blends between the three stop swatches on this row -- full (100%), half (50%) and empty (0%). Class Reactive shows the class color at full health, bleeding into the 50% and 0% colors as the unit takes damage. Off leaves the flat Fill Color swatches in charge; either way the Gradient below still applies, running from whichever color this picks.",
                    values = {
                        none = "Off",
                        classic = "Classic",
                        customDynamic = "Custom Colors",
                        classReactive = "Class Reactive",
                    },
                    order = { "none", "classic", "customDynamic", "classReactive" },
                    get = SValRow("healthColorMode", "none"),
                    -- RefreshPage re-runs the stop swatches' show/hide pass.
                    set = function(val)
                        SSet("healthColorMode", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "toggle",
                    label = "Enable Gradient",
                    get = SValRow("gradientEnabled", false),
                    set = function(val)
                        SSet("gradientEnabled", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = SValRow("gradientDir", "HORIZONTAL"),
                    set = function(val)
                        SSet("gradientDir", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                },
            },
        })
    end
    -- Dynamic Color stop swatches (100% | 50% | 0%), chained LEFT of the cog so
    -- they sit at the far end of the row's inline run: hiding them for the modes
    -- that don't read them then leaves no hole in the middle of the controls,
    -- and Off restores exactly the original [cog][gradient][custom][class] look.
    if not CludesUI._prebuilding then
        local region = sharedHealthColorRow._leftRegion
        local dynDefs = {
            {
                key = "dynamicColor100",
                def = { r = 0, g = 1, b = 0 },
                tip = "Health bar color at full (100%) health",
            },
            {
                key = "dynamicColor50",
                def = { r = 0xEC / 255, g = 0xEC / 255, b = 0x32 / 255 },
                tip = "Health bar color at half (50%) health",
            },
            {
                key = "dynamicColor0",
                def = { r = 0xE3 / 255, g = 0x30 / 255, b = 0x30 / 255 },
                tip = "Health bar color at empty (0%) health",
            },
        }
        local dynSwatches, dynUpdaters = {}, {}
        local prevAnchor = region._lastInline or region._control
        for idx = #dynDefs, 1, -1 do
            local dropdown = dynDefs[idx]
            local sw, swUpdate = CludesUI.BuildColorSwatch(
                region,
                sharedHealthColorRow:GetFrameLevel() + 3,
                function()
                    local c = SGet(dropdown.key) or dropdown.def
                    return c.r, c.g, c.b, 1
                end,
                function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]()[dropdown.key] = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
                false,
                18
            )
            sw:SetPoint("RIGHT", prevAnchor, "LEFT", -8, 0)
            sw:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(sw, dropdown.tip)
            end)
            sw:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            dynSwatches[idx] = sw
            dynUpdaters[idx] = swUpdate
            prevAnchor = sw
        end
        region._lastInline = prevAnchor
        -- dynSwatches[1] is the 100% stop. Class Reactive drives that stop from
        -- the unit's own class color, so only 50%/0% are editable there.
        -- The swatch UPDATERS must run on every refresh too: the stops are
        -- per-unit, and switching the selected unit refreshes widgets rather
        -- than rebuilding the page, so without this the swatches keep showing
        -- the previous unit's colors.
        local function UpdateDynSwatchVis()
            local mode = SVal("healthColorMode", "none")
            local isDynamic = mode == "customDynamic"
            local isReactive = mode == "classReactive"
            for idx, sw in ipairs(dynSwatches) do
                if dynUpdaters[idx] then
                    dynUpdaters[idx]()
                end
                if isDynamic or (isReactive and idx > 1) then
                    sw:Show()
                else
                    sw:Hide()
                end
            end
        end
        RegisterWidgetRefresh(UpdateDynSwatchVis)
        UpdateDynSwatchVis()
    end

    -- Dark Mode: disable all Bar Color + Bar Background controls (the flat dark
    -- health bar ignores fill/background colors).
    if not CludesUI._prebuilding then
        AddDarkModeBlock(sharedHealthColorRow._leftRegion, SDB)
        AddDarkModeBlock(sharedHealthColorRow._rightRegion, SDB)
    end

    -- Row 3: Smooth Health Bars + Bar Opacity
    local sharedOpacityRow
    sharedOpacityRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Smooth Health Bars",
        getValue = SValRow("smoothBars", false),
        setValue = SSetRow("smoothBars"),
    }, {
        type = "slider",
        text = "Fill Opacity",
        min = 0,
        max = 100,
        step = 1,
        disabled = function()
            return mod.UF_DarkThemeOn(SDB())
        end,
        disabledTooltip = "Dark Mode",
        requireState = "disabled",
        getValue = SValRow("healthBarOpacity", 90),
        setValue = SSetRowThen("healthBarOpacity"),
    })
    cursorY = cursorY - height
    -- Sync icon: Bar Opacity (right)
    if not CludesUI._prebuilding then
        local region = sharedOpacityRow._rightRegion
        mod.UFO_UnitSync(region, "Bar Opacity", {
            key = "healthBarOpacity",
            default = 90,
        })
    end

    -- Blizzard Style: the stock level number in the frame's level circle,
    -- with its size, offsets and difficulty colouring on a cog. The row is
    -- the preview level text's click target (stashed on the page: the
    -- targets table at the end reads it).
    if CludesUI.BlizzStyle.Get("unitframes") then
        hostFrame._ufLevelRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Level",
            tooltip = "Shows the unit's level in the frame's level circle, as the default UI does.",
            getValue = SValRow("blizzShowLevel", true),
            setValue = function(val)
                SSet("blizzShowLevel", val)
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(hostFrame._ufLevelRow._leftRegion, {
                disabled = function()
                    return not SVal("blizzShowLevel", true)
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
                            return SVal("blizzLevelSize", SVal("leftTextSize", SDB().textSize or 12))
                        end,
                        set = SSetRowThen("blizzLevelSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = SValRow("blizzLevelX", 0),
                        set = SSetRowThen("blizzLevelX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -150,
                        max = 150,
                        step = 1,
                        get = SValRow("blizzLevelY", 0),
                        set = SSetRowThen("blizzLevelY"),
                    },
                    -- The player's own level never takes a difficulty colour.
                    {
                        type = "toggle",
                        label = "Difficulty Color",
                        tooltip = "Colors an attackable unit's level by difficulty, as the default UI does.",
                        disabled = function()
                            return optionState.selectedUnit == "player"
                        end,
                        disabledTooltip = "This option does not apply to the player frame.",
                        get = SValRow("blizzLevelDifficultyColor", true),
                        set = SSetRowThen("blizzLevelDifficultyColor"),
                    },
                },
            })
        end
    end

    -- Active text slots, retaining the existing inline controls.
    local textSlots = {}
    textSlots[1] = {
        key = "leftText",
        position = "Left Text",
        default = "name",
        cfg = {
            type = "dropdown",
            text = "Left Text",
            values = healthTextValues,
            order = (optionState.selectedUnit == "player" and healthTextOrderPlayer)
                or ((optionState.selectedUnit == "target" or optionState.selectedUnit == "focus") and healthTextOrderTargetFocus)
                or healthTextOrder,
            getValue = SValRow("leftTextContent", "name"),
            setValue = function(val)
                SSet("leftTextContent", val)
                if mod.UF_IsUniqueContent(val) then
                    if SGet("rightTextContent") == val then
                        SSet("rightTextContent", "none")
                    end
                    if SGet("centerTextContent") == val then
                        SSet("centerTextContent", "none")
                    end
                end
                UpdatePreview()
                CludesUI:RefreshPage(true)
            end,
        },
        decorate = function(region)
            -- Sync icon: Left Text (left)
            if not CludesUI._prebuilding then
                local function ApplyLeftTextTo(keyList)
                    local source = UNIT_DB_MAP[optionState.selectedUnit]()
                    local val = source.leftTextContent or "name"
                    for _, settingKey in ipairs(keyList) do
                        if settingKey ~= optionState.selectedUnit then
                            local d = UNIT_DB_MAP[settingKey]()
                            d.leftTextContent = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            d.leftTextClassColor = source.leftTextClassColor
                            d.leftTextColorR, d.leftTextColorG, d.leftTextColorB =
                                source.leftTextColorR, source.leftTextColorG, source.leftTextColorB
                            d.leftTextSize = source.leftTextSize
                            d.leftTextX, d.leftTextY = source.leftTextX, source.leftTextY
                            d.leftTextWidthPct = source.leftTextWidthPct
                            if val == "custom" then
                                d.leftTextCustomFormat = source.leftTextCustomFormat
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end
                mod.UFO_UnitSync(region, "Left Text", {
                    applyTo = ApplyLeftTextTo,
                    isSynced = function()
                        local source = UNIT_DB_MAP[optionState.selectedUnit]()
                        local val = source.leftTextContent or "name"
                        for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                            local d = UNIT_DB_MAP[settingKey]()
                            local expected = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            if (d.leftTextContent or "name") ~= expected then
                                return false
                            end
                            if (d.leftTextClassColor or false) ~= (source.leftTextClassColor or false) then
                                return false
                            end
                            if (d.leftTextColorR or 1) ~= (source.leftTextColorR or 1) then
                                return false
                            end
                            if (d.leftTextColorG or 1) ~= (source.leftTextColorG or 1) then
                                return false
                            end
                            if (d.leftTextColorB or 1) ~= (source.leftTextColorB or 1) then
                                return false
                            end
                            if (d.leftTextSize or 0) ~= (source.leftTextSize or 0) then
                                return false
                            end
                            if (d.leftTextX or 0) ~= (source.leftTextX or 0) then
                                return false
                            end
                            if (d.leftTextY or 0) ~= (source.leftTextY or 0) then
                                return false
                            end
                            if (d.leftTextWidthPct or 100) ~= (source.leftTextWidthPct or 100) then
                                return false
                            end
                            if
                                val == "custom"
                                and (d.leftTextCustomFormat or "") ~= (source.leftTextCustomFormat or "")
                            then
                                return false
                            end
                        end
                        return true
                    end,
                })
            end
            -- Cogwheel on Left Text (left region)
            if not CludesUI._prebuilding then
                local leftRegion = region
                CludesUI.BuildInlineCog(leftRegion, {
                    disabled = function()
                        return SVal("leftTextContent", "name") == "none"
                    end,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = "Left Text Settings",
                    rows = mod.UF_CoreTextRows("leftText", "name", SVal, SSet, {
                        {
                            type = "slider",
                            label = "Size",
                            min = 8,
                            max = 100,
                            step = 1,
                            get = function()
                                return SVal("leftTextSize", SDB().textSize or 12)
                            end,
                            set = SSetRowThen("leftTextSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("leftTextX", 0),
                            set = SSetRowThen("leftTextX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("leftTextY", 0),
                            set = SSetRowThen("leftTextY"),
                        },
                        {
                            type = "slider",
                            label = "Width %",
                            min = 20,
                            max = 200,
                            step = 5,
                            get = SValRow("leftTextWidthPct", 100),
                            set = SSetRowThen("leftTextWidthPct"),
                        },
                        {
                            type = "multiswatch",
                            label = "Indicator Color",
                            disabled = function()
                                local c = SVal("leftTextContent", "name")
                                return c ~= "nametotarget" and c ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Name > Target or Target is selected.",
                            swatches = {
                                {
                                    tooltip = "Custom Colored",
                                    hasAlpha = false,
                                    getValue = function()
                                        local color = SVal("leftTextTargetSepColor", nil)
                                        if type(color) == "table" then
                                            return color.r or 1, color.g or 1, color.b or 1
                                        end
                                        return 1, 1, 1
                                    end,
                                    setValue = function(red, green, blue)
                                        SSet("leftTextTargetSepColor", { r = red, g = green, b = blue })
                                        UpdatePreview()
                                    end,
                                    onClick = function(self)
                                        if SVal("leftTextTargetSepClassColor", false) then
                                            SSet("leftTextTargetSepClassColor", false)
                                            UpdatePreview()
                                            return
                                        end
                                        if self._eabOrigClick then
                                            self._eabOrigClick(self)
                                        end
                                    end,
                                    refreshAlpha = function()
                                        return SVal("leftTextTargetSepClassColor", false) and 0.3 or 1
                                    end,
                                },
                                {
                                    tooltip = "Class Colored",
                                    hasAlpha = false,
                                    getValue = CludesUI.PlayerClassRGB,
                                    setValue = function() end,
                                    onClick = function()
                                        SSet("leftTextTargetSepClassColor", true)
                                        UpdatePreview()
                                    end,
                                    refreshAlpha = function()
                                        return SVal("leftTextTargetSepClassColor", false) and 1 or 0.3
                                    end,
                                },
                            },
                        },
                        {
                            type = "input",
                            label = "Separator",
                            inputWidth = 60,
                            get = SValRow("leftTextTargetSep", ">"),
                            set = function(val)
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if val == "" then
                                    val = ">"
                                end
                                SSet("leftTextTargetSep", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("leftTextContent", "name") ~= "nametotarget"
                            end,
                            disabledTooltip = "This option only applies when Name > Target is selected.",
                        },
                        {
                            type = "input",
                            label = "Prefix",
                            inputWidth = 60,
                            tooltip = "Text shown before the target's name.",
                            get = SValRow("leftTextTargetPrefix", "T:"),
                            set = function(val)
                                -- Unlike Separator, empty is kept: no prefix.
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                SSet("leftTextTargetPrefix", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("leftTextContent", "name") ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Target is selected.",
                        },
                    }),
                })
            end
            -- Inline swatches on Left Text (CDM Border Size double-swatch pattern): class
            -- sets leftTextClassColor, custom opens the picker and switches back from class.
            if not CludesUI._prebuilding then
                local leftRegion = region
                local ltAnchor = leftRegion._lastInline or leftRegion._control
                -- Class Colored swatch (nearest the cog): shows the player's class color.
                local leftClassSwatch, ltUpdateClassSwatch = CludesUI.BuildColorSwatch(
                    leftRegion,
                    leftRegion:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and CludesUI.GetClassColor(class)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(leftClassSwatch, "RIGHT", ltAnchor, "LEFT", -8, 0)
                leftClassSwatch:SetScript("OnClick", function()
                    if SVal("leftTextContent", "name") == "none" then
                        return
                    end
                    -- Attribution read before the write: a setter that rebuilds the page
                    -- may dress this swatch again for another slot.
                    local snapshot = CludesUI._SOAttribution(leftClassSwatch)
                    SSet("leftTextClassColor", true)
                    -- Bespoke write: notify for exact Spec Overrides attribution (the
                    -- forced RefreshPage below would otherwise resync-absorb it).
                    CludesUI._NotifySettingWrite(leftClassSwatch, snapshot)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(leftClassSwatch, "Class Colored")
                -- Custom Colored swatch (left of the class swatch): opens the color picker.
                local ltSwGet = function()
                    return SVal("leftTextColorR", 1), SVal("leftTextColorG", 1), SVal("leftTextColorB", 1)
                end
                local ltSwSet = function(red, green, blue)
                    SSet("leftTextColorR", red)
                    SSet("leftTextColorG", green)
                    SSet("leftTextColorB", blue)
                    UpdatePreview()
                end
                local ltSwatch, ltUpdateSwatch =
                    CludesUI.BuildColorSwatch(leftRegion, leftRegion:GetFrameLevel() + 5, ltSwGet, ltSwSet, nil, 20)
                Pix.Point(ltSwatch, "RIGHT", leftClassSwatch, "LEFT", -8, 0)
                leftRegion._lastInline = ltSwatch
                local ltOrigClick = ltSwatch:GetScript("OnClick")
                ltSwatch:SetScript("OnClick", function(self, ...)
                    if SVal("leftTextContent", "name") == "none" then
                        return
                    end
                    if SVal("leftTextClassColor", false) then
                        local snapshot = CludesUI._SOAttribution(self)
                        SSet("leftTextClassColor", false)
                        CludesUI._NotifySettingWrite(self, snapshot)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if ltOrigClick then
                        ltOrigClick(self, ...)
                    end
                end)
                CludesUI.HoverTip(ltSwatch, "Custom Colored")
                local function UpdateLtSwatches()
                    local noneMode = SVal("leftTextContent", "name") == "none"
                    local classMode = SVal("leftTextClassColor", false)
                    ltSwatch:SetAlpha((classMode or noneMode) and 0.3 or 1)
                    leftClassSwatch:SetAlpha((classMode and not noneMode) and 1 or 0.3)
                end
                RegisterWidgetRefresh(function()
                    ltUpdateSwatch()
                    ltUpdateClassSwatch()
                    UpdateLtSwatches()
                end)
                UpdateLtSwatches()
                -- The class-color mode flag is written only by bespoke swatch OnClicks (no
                -- widget getter reads it), so Spec Overrides' read-trace can't link an
                -- override to this row without a capture accessor declared explicitly.
                if CludesUI.AddCaptureAccessor then
                    CludesUI.AddCaptureAccessor(leftRegion, {
                        type = "toggle",
                        text = "Left Text Class Color",
                        getValue = SValRow("leftTextClassColor", false),
                        setValue = SSetRow("leftTextClassColor"),
                    })
                end
            end
        end,
    }
    textSlots[2] = {
        key = "rightText",
        position = "Right Text",
        default = "both",
        cfg = {
            type = "dropdown",
            text = "Right Text",
            values = healthTextValues,
            order = (optionState.selectedUnit == "player" and healthTextOrderPlayer)
                or ((optionState.selectedUnit == "target" or optionState.selectedUnit == "focus") and healthTextOrderTargetFocus)
                or healthTextOrder,
            getValue = SValRow("rightTextContent", "both"),
            setValue = function(val)
                SSet("rightTextContent", val)
                if mod.UF_IsUniqueContent(val) then
                    if SGet("leftTextContent") == val then
                        SSet("leftTextContent", "none")
                    end
                    if SGet("centerTextContent") == val then
                        SSet("centerTextContent", "none")
                    end
                end
                UpdatePreview()
                CludesUI:RefreshPage(true)
            end,
        },
        decorate = function(region)
            -- Sync icon: Right Text (right)
            if not CludesUI._prebuilding then
                local function ApplyRightTextTo(keyList)
                    local source = UNIT_DB_MAP[optionState.selectedUnit]()
                    local val = source.rightTextContent or "both"
                    for _, settingKey in ipairs(keyList) do
                        if settingKey ~= optionState.selectedUnit then
                            local d = UNIT_DB_MAP[settingKey]()
                            d.rightTextContent = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            d.rightTextClassColor = source.rightTextClassColor
                            d.rightTextColorR, d.rightTextColorG, d.rightTextColorB =
                                source.rightTextColorR, source.rightTextColorG, source.rightTextColorB
                            d.rightTextSize = source.rightTextSize
                            d.rightTextX, d.rightTextY = source.rightTextX, source.rightTextY
                            d.rightTextWidthPct = source.rightTextWidthPct
                            if val == "custom" then
                                d.rightTextCustomFormat = source.rightTextCustomFormat
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end
                mod.UFO_UnitSync(region, "Right Text", {
                    applyTo = ApplyRightTextTo,
                    isSynced = function()
                        local source = UNIT_DB_MAP[optionState.selectedUnit]()
                        local val = source.rightTextContent or "both"
                        for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                            local d = UNIT_DB_MAP[settingKey]()
                            local expected = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            if (d.rightTextContent or "both") ~= expected then
                                return false
                            end
                            if (d.rightTextClassColor or false) ~= (source.rightTextClassColor or false) then
                                return false
                            end
                            if (d.rightTextColorR or 1) ~= (source.rightTextColorR or 1) then
                                return false
                            end
                            if (d.rightTextColorG or 1) ~= (source.rightTextColorG or 1) then
                                return false
                            end
                            if (d.rightTextColorB or 1) ~= (source.rightTextColorB or 1) then
                                return false
                            end
                            if (d.rightTextSize or 0) ~= (source.rightTextSize or 0) then
                                return false
                            end
                            if (d.rightTextX or 0) ~= (source.rightTextX or 0) then
                                return false
                            end
                            if (d.rightTextY or 0) ~= (source.rightTextY or 0) then
                                return false
                            end
                            if (d.rightTextWidthPct or 100) ~= (source.rightTextWidthPct or 100) then
                                return false
                            end
                            if
                                val == "custom"
                                and (d.rightTextCustomFormat or "")
                                    ~= (source.rightTextCustomFormat or "")
                            then
                                return false
                            end
                        end
                        return true
                    end,
                })
            end
            -- Cogwheel on Right Text (right region)
            if not CludesUI._prebuilding then
                local rightRegion = region
                CludesUI.BuildInlineCog(rightRegion, {
                    disabled = function()
                        return SVal("rightTextContent", "both") == "none"
                    end,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = "Right Text Settings",
                    rows = mod.UF_CoreTextRows("rightText", "both", SVal, SSet, {
                        {
                            type = "slider",
                            label = "Size",
                            min = 8,
                            max = 100,
                            step = 1,
                            get = function()
                                return SVal("rightTextSize", SDB().textSize or 12)
                            end,
                            set = SSetRowThen("rightTextSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("rightTextX", 0),
                            set = SSetRowThen("rightTextX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("rightTextY", 0),
                            set = SSetRowThen("rightTextY"),
                        },
                        {
                            type = "slider",
                            label = "Width %",
                            min = 20,
                            max = 200,
                            step = 5,
                            get = SValRow("rightTextWidthPct", 100),
                            set = SSetRowThen("rightTextWidthPct"),
                        },
                        {
                            type = "multiswatch",
                            label = "Indicator Color",
                            disabled = function()
                                local c = SVal("rightTextContent", "both")
                                return c ~= "nametotarget" and c ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Name > Target or Target is selected.",
                            swatches = {
                                {
                                    tooltip = "Custom Colored",
                                    hasAlpha = false,
                                    getValue = function()
                                        local color = SVal("rightTextTargetSepColor", nil)
                                        if type(color) == "table" then
                                            return color.r or 1, color.g or 1, color.b or 1
                                        end
                                        return 1, 1, 1
                                    end,
                                    setValue = function(red, green, blue)
                                        SSet("rightTextTargetSepColor", { r = red, g = green, b = blue })
                                        UpdatePreview()
                                    end,
                                    onClick = function(self)
                                        if SVal("rightTextTargetSepClassColor", false) then
                                            SSet("rightTextTargetSepClassColor", false)
                                            UpdatePreview()
                                            return
                                        end
                                        if self._eabOrigClick then
                                            self._eabOrigClick(self)
                                        end
                                    end,
                                    refreshAlpha = function()
                                        return SVal("rightTextTargetSepClassColor", false) and 0.3 or 1
                                    end,
                                },
                                {
                                    tooltip = "Class Colored",
                                    hasAlpha = false,
                                    getValue = CludesUI.PlayerClassRGB,
                                    setValue = function() end,
                                    onClick = function()
                                        SSet("rightTextTargetSepClassColor", true)
                                        UpdatePreview()
                                    end,
                                    refreshAlpha = function()
                                        return SVal("rightTextTargetSepClassColor", false) and 1 or 0.3
                                    end,
                                },
                            },
                        },
                        {
                            type = "input",
                            label = "Separator",
                            inputWidth = 60,
                            get = SValRow("rightTextTargetSep", ">"),
                            set = function(val)
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if val == "" then
                                    val = ">"
                                end
                                SSet("rightTextTargetSep", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("rightTextContent", "both") ~= "nametotarget"
                            end,
                            disabledTooltip = "This option only applies when Name > Target is selected.",
                        },
                        {
                            type = "input",
                            label = "Prefix",
                            inputWidth = 60,
                            tooltip = "Text shown before the target's name.",
                            get = SValRow("rightTextTargetPrefix", "T:"),
                            set = function(val)
                                -- Unlike Separator, empty is kept: no prefix.
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                SSet("rightTextTargetPrefix", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("rightTextContent", "both") ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Target is selected.",
                        },
                    }),
                })
            end
            -- Inline swatches on Right Text (CDM Border Size double-swatch pattern): class
            -- sets rightTextClassColor, custom opens the picker and switches back from class.
            if not CludesUI._prebuilding then
                local rightRegion = region
                local rtAnchor = rightRegion._lastInline or rightRegion._control
                local rightClassSwatch, rtUpdateClassSwatch = CludesUI.BuildColorSwatch(
                    rightRegion,
                    rightRegion:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and CludesUI.GetClassColor(class)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(rightClassSwatch, "RIGHT", rtAnchor, "LEFT", -8, 0)
                rightClassSwatch:SetScript("OnClick", function()
                    if SVal("rightTextContent", "both") == "none" then
                        return
                    end
                    -- Attribution read before the write (see the Left Text swatch).
                    local snapshot = CludesUI._SOAttribution(rightClassSwatch)
                    SSet("rightTextClassColor", true)
                    -- Bespoke write: notify for exact Spec Overrides attribution (the
                    -- forced RefreshPage below would otherwise resync-absorb it).
                    CludesUI._NotifySettingWrite(rightClassSwatch, snapshot)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(rightClassSwatch, "Class Colored")
                local rtSwGet = function()
                    return SVal("rightTextColorR", 1), SVal("rightTextColorG", 1), SVal("rightTextColorB", 1)
                end
                local rtSwSet = function(red, green, blue)
                    SSet("rightTextColorR", red)
                    SSet("rightTextColorG", green)
                    SSet("rightTextColorB", blue)
                    UpdatePreview()
                end
                local rtSwatch, rtUpdateSwatch = CludesUI.BuildColorSwatch(
                    rightRegion,
                    rightRegion:GetFrameLevel() + 5,
                    rtSwGet,
                    rtSwSet,
                    nil,
                    20
                )
                Pix.Point(rtSwatch, "RIGHT", rightClassSwatch, "LEFT", -8, 0)
                rightRegion._lastInline = rtSwatch
                local rtOrigClick = rtSwatch:GetScript("OnClick")
                rtSwatch:SetScript("OnClick", function(self, ...)
                    if SVal("rightTextContent", "both") == "none" then
                        return
                    end
                    if SVal("rightTextClassColor", false) then
                        local snapshot = CludesUI._SOAttribution(self)
                        SSet("rightTextClassColor", false)
                        CludesUI._NotifySettingWrite(self, snapshot)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if rtOrigClick then
                        rtOrigClick(self, ...)
                    end
                end)
                CludesUI.HoverTip(rtSwatch, "Custom Colored")
                local function UpdateRtSwatches()
                    local noneMode = SVal("rightTextContent", "both") == "none"
                    local classMode = SVal("rightTextClassColor", false)
                    rtSwatch:SetAlpha((classMode or noneMode) and 0.3 or 1)
                    rightClassSwatch:SetAlpha((classMode and not noneMode) and 1 or 0.3)
                end
                RegisterWidgetRefresh(function()
                    rtUpdateSwatch()
                    rtUpdateClassSwatch()
                    UpdateRtSwatches()
                end)
                UpdateRtSwatches()
                -- Mirror of the Left Text class-flag accessor: see that comment.
                if CludesUI.AddCaptureAccessor then
                    CludesUI.AddCaptureAccessor(rightRegion, {
                        type = "toggle",
                        text = "Right Text Class Color",
                        getValue = SValRow("rightTextClassColor", false),
                        setValue = SSetRow("rightTextClassColor"),
                    })
                end
            end
        end,
    }
    textSlots[3] = {
        key = "centerText",
        position = "Center Text",
        default = "none",
        cfg = {
            type = "dropdown",
            text = "Center Text",
            values = healthTextValues,
            order = (optionState.selectedUnit == "player" and healthTextOrderPlayer)
                or ((optionState.selectedUnit == "target" or optionState.selectedUnit == "focus") and healthTextOrderTargetFocus)
                or healthTextOrder,
            getValue = SValRow("centerTextContent", "none"),
            setValue = function(val)
                SSet("centerTextContent", val)
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage(true)
            end,
        },
        decorate = function(region)
            -- Sync icon: Center Text (left)
            if not CludesUI._prebuilding then
                local function ApplyCenterTextTo(keyList)
                    local source = UNIT_DB_MAP[optionState.selectedUnit]()
                    local val = source.centerTextContent or "none"
                    for _, settingKey in ipairs(keyList) do
                        if settingKey ~= optionState.selectedUnit then
                            local d = UNIT_DB_MAP[settingKey]()
                            d.centerTextContent = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            d.centerTextClassColor = source.centerTextClassColor
                            d.centerTextColorR, d.centerTextColorG, d.centerTextColorB =
                                source.centerTextColorR, source.centerTextColorG, source.centerTextColorB
                            d.centerTextSize = source.centerTextSize
                            d.centerTextX, d.centerTextY = source.centerTextX, source.centerTextY
                            d.centerTextWidthPct = source.centerTextWidthPct
                            if val == "custom" then
                                d.centerTextCustomFormat = source.centerTextCustomFormat
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end
                mod.UFO_UnitSync(region, "Center Text", {
                    applyTo = ApplyCenterTextTo,
                    isSynced = function()
                        local source = UNIT_DB_MAP[optionState.selectedUnit]()
                        local val = source.centerTextContent or "none"
                        for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                            local d = UNIT_DB_MAP[settingKey]()
                            local expected = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            if (d.centerTextContent or "none") ~= expected then
                                return false
                            end
                            if
                                (d.centerTextClassColor or false) ~= (source.centerTextClassColor or false)
                            then
                                return false
                            end
                            if (d.centerTextColorR or 1) ~= (source.centerTextColorR or 1) then
                                return false
                            end
                            if (d.centerTextColorG or 1) ~= (source.centerTextColorG or 1) then
                                return false
                            end
                            if (d.centerTextColorB or 1) ~= (source.centerTextColorB or 1) then
                                return false
                            end
                            if (d.centerTextSize or 0) ~= (source.centerTextSize or 0) then
                                return false
                            end
                            if (d.centerTextX or 0) ~= (source.centerTextX or 0) then
                                return false
                            end
                            if (d.centerTextY or 0) ~= (source.centerTextY or 0) then
                                return false
                            end
                            if (d.centerTextWidthPct or 100) ~= (source.centerTextWidthPct or 100) then
                                return false
                            end
                            if
                                val == "custom"
                                and (d.centerTextCustomFormat or "")
                                    ~= (source.centerTextCustomFormat or "")
                            then
                                return false
                            end
                        end
                        return true
                    end,
                })
            end
            -- Cogwheel on Center Text (left region)
            if not CludesUI._prebuilding then
                local ctrRgn = region
                CludesUI.BuildInlineCog(ctrRgn, {
                    disabled = function()
                        return SVal("centerTextContent", "none") == "none"
                    end,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = "Center Text Settings",
                    rows = mod.UF_CoreTextRows("centerText", "none", SVal, SSet, {
                        {
                            type = "slider",
                            label = "Size",
                            min = 8,
                            max = 100,
                            step = 1,
                            get = function()
                                return SVal("centerTextSize", SDB().textSize or 12)
                            end,
                            set = SSetRowThen("centerTextSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("centerTextX", 0),
                            set = SSetRowThen("centerTextX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("centerTextY", 0),
                            set = SSetRowThen("centerTextY"),
                        },
                        {
                            type = "slider",
                            label = "Width %",
                            min = 20,
                            max = 200,
                            step = 5,
                            get = SValRow("centerTextWidthPct", 100),
                            set = SSetRowThen("centerTextWidthPct"),
                        },
                        {
                            type = "multiswatch",
                            label = "Indicator Color",
                            disabled = function()
                                local c = SVal("centerTextContent", "none")
                                return c ~= "nametotarget" and c ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Name > Target or Target is selected.",
                            swatches = {
                                {
                                    tooltip = "Custom Colored",
                                    hasAlpha = false,
                                    getValue = function()
                                        local color = SVal("centerTextTargetSepColor", nil)
                                        if type(color) == "table" then
                                            return color.r or 1, color.g or 1, color.b or 1
                                        end
                                        return 1, 1, 1
                                    end,
                                    setValue = function(red, green, blue)
                                        SSet("centerTextTargetSepColor", { r = red, g = green, b = blue })
                                        UpdatePreview()
                                    end,
                                    onClick = function(self)
                                        if SVal("centerTextTargetSepClassColor", false) then
                                            SSet("centerTextTargetSepClassColor", false)
                                            UpdatePreview()
                                            return
                                        end
                                        if self._eabOrigClick then
                                            self._eabOrigClick(self)
                                        end
                                    end,
                                    refreshAlpha = function()
                                        return SVal("centerTextTargetSepClassColor", false) and 0.3 or 1
                                    end,
                                },
                                {
                                    tooltip = "Class Colored",
                                    hasAlpha = false,
                                    getValue = CludesUI.PlayerClassRGB,
                                    setValue = function() end,
                                    onClick = function()
                                        SSet("centerTextTargetSepClassColor", true)
                                        UpdatePreview()
                                    end,
                                    refreshAlpha = function()
                                        return SVal("centerTextTargetSepClassColor", false) and 1 or 0.3
                                    end,
                                },
                            },
                        },
                        {
                            type = "input",
                            label = "Separator",
                            inputWidth = 60,
                            get = SValRow("centerTextTargetSep", ">"),
                            set = function(val)
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if val == "" then
                                    val = ">"
                                end
                                SSet("centerTextTargetSep", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("centerTextContent", "none") ~= "nametotarget"
                            end,
                            disabledTooltip = "This option only applies when Name > Target is selected.",
                        },
                        {
                            type = "input",
                            label = "Prefix",
                            inputWidth = 60,
                            tooltip = "Text shown before the target's name.",
                            get = SValRow("centerTextTargetPrefix", "T:"),
                            set = function(val)
                                -- Unlike Separator, empty is kept: no prefix.
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                SSet("centerTextTargetPrefix", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("centerTextContent", "none") ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Target is selected.",
                        },
                    }),
                })
            end
            -- Inline swatches on Center Text (CDM Border Size double-swatch pattern): class
            -- sets centerTextClassColor, custom opens the picker and switches back from class.
            if not CludesUI._prebuilding then
                local ctrRgn = region
                local ctAnchor = ctrRgn._lastInline or ctrRgn._control
                local ctClassSwatch, ctUpdateClassSwatch = CludesUI.BuildColorSwatch(
                    ctrRgn,
                    ctrRgn:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and CludesUI.GetClassColor(class)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(ctClassSwatch, "RIGHT", ctAnchor, "LEFT", -8, 0)
                ctClassSwatch:SetScript("OnClick", function()
                    if SVal("centerTextContent", "none") == "none" then
                        return
                    end
                    SSet("centerTextClassColor", true)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(ctClassSwatch, "Class Colored")
                local ctSwGet = function()
                    return SVal("centerTextColorR", 1),
                        SVal("centerTextColorG", 1),
                        SVal("centerTextColorB", 1)
                end
                local ctSwSet = function(red, green, blue)
                    SSet("centerTextColorR", red)
                    SSet("centerTextColorG", green)
                    SSet("centerTextColorB", blue)
                    UpdatePreview()
                end
                local ctSwatch, ctUpdateSwatch =
                    CludesUI.BuildColorSwatch(ctrRgn, ctrRgn:GetFrameLevel() + 5, ctSwGet, ctSwSet, nil, 20)
                Pix.Point(ctSwatch, "RIGHT", ctClassSwatch, "LEFT", -8, 0)
                ctrRgn._lastInline = ctSwatch
                local ctOrigClick = ctSwatch:GetScript("OnClick")
                ctSwatch:SetScript("OnClick", function(self, ...)
                    if SVal("centerTextContent", "none") == "none" then
                        return
                    end
                    if SVal("centerTextClassColor", false) then
                        SSet("centerTextClassColor", false)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if ctOrigClick then
                        ctOrigClick(self, ...)
                    end
                end)
                CludesUI.HoverTip(ctSwatch, "Custom Colored")
                local function UpdateCtSwatches()
                    local noneMode = SVal("centerTextContent", "none") == "none"
                    local classMode = SVal("centerTextClassColor", false)
                    ctSwatch:SetAlpha((classMode or noneMode) and 0.3 or 1)
                    ctClassSwatch:SetAlpha((classMode and not noneMode) and 1 or 0.3)
                end
                RegisterWidgetRefresh(function()
                    ctUpdateSwatch()
                    ctUpdateClassSwatch()
                    UpdateCtSwatches()
                end)
                UpdateCtSwatches()
            end
        end,
    }
    textSlots[4] = {
        key = "extraText",
        position = "Extra Text (full length)",
        default = "none",
        cfg = {
            type = "dropdown",
            text = "Extra Text (full length)",
            values = healthTextValues,
            order = (optionState.selectedUnit == "player" and healthTextOrderPlayer)
                or ((optionState.selectedUnit == "target" or optionState.selectedUnit == "focus") and healthTextOrderTargetFocus)
                or healthTextOrder,
            getValue = SValRow("extraTextContent", "none"),
            setValue = function(val)
                SSet("extraTextContent", val)
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage(true)
            end,
        },
        decorate = function(region)
            -- Sync icon: Extra Text.
            if not CludesUI._prebuilding then
                local function ApplyExtraTextTo(keyList)
                    local source = UNIT_DB_MAP[optionState.selectedUnit]()
                    local val = source.extraTextContent or "none"
                    for _, settingKey in ipairs(keyList) do
                        if settingKey ~= optionState.selectedUnit then
                            local d = UNIT_DB_MAP[settingKey]()
                            d.extraTextContent = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            d.extraTextClassColor = source.extraTextClassColor
                            d.extraTextColorR, d.extraTextColorG, d.extraTextColorB =
                                source.extraTextColorR, source.extraTextColorG, source.extraTextColorB
                            d.extraTextSize = source.extraTextSize
                            d.extraTextX, d.extraTextY = source.extraTextX, source.extraTextY
                            d.extraTextAlign = source.extraTextAlign
                            d.extraTextWidthPct = source.extraTextWidthPct
                            if val == "custom" then
                                d.extraTextCustomFormat = source.extraTextCustomFormat
                            end
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage(true)
                end
                mod.UFO_UnitSync(region, "Extra Text", {
                    applyTo = ApplyExtraTextTo,
                    isSynced = function()
                        local source = UNIT_DB_MAP[optionState.selectedUnit]()
                        local val = source.extraTextContent or "none"
                        for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                            local d = UNIT_DB_MAP[settingKey]()
                            local expected = (
                                (
                                    val == "absorb"
                                    or val == "absorbshort"
                                    or val == "healabsorb"
                                    or val == "healabsorbshort"
                                    or val == "group"
                                ) and settingKey ~= "player"
                            )
                                    and "none"
                                or val
                            if (d.extraTextContent or "none") ~= expected then
                                return false
                            end
                            if (d.extraTextClassColor or false) ~= (source.extraTextClassColor or false) then
                                return false
                            end
                            if (d.extraTextColorR or 1) ~= (source.extraTextColorR or 1) then
                                return false
                            end
                            if (d.extraTextColorG or 1) ~= (source.extraTextColorG or 1) then
                                return false
                            end
                            if (d.extraTextColorB or 1) ~= (source.extraTextColorB or 1) then
                                return false
                            end
                            if (d.extraTextSize or 0) ~= (source.extraTextSize or 0) then
                                return false
                            end
                            if (d.extraTextX or 0) ~= (source.extraTextX or 0) then
                                return false
                            end
                            if (d.extraTextY or 0) ~= (source.extraTextY or 0) then
                                return false
                            end
                            if (d.extraTextAlign or "left") ~= (source.extraTextAlign or "left") then
                                return false
                            end
                            if (d.extraTextWidthPct or 100) ~= (source.extraTextWidthPct or 100) then
                                return false
                            end
                            if
                                val == "custom"
                                and (d.extraTextCustomFormat or "")
                                    ~= (source.extraTextCustomFormat or "")
                            then
                                return false
                            end
                        end
                        return true
                    end,
                })
            end
            -- Cogwheel on Extra Text (Center row right region): Alignment + Size/X/Y
            if not CludesUI._prebuilding then
                local etrRgn = region
                CludesUI.BuildInlineCog(etrRgn, {
                    disabled = function()
                        return SVal("extraTextContent", "none") == "none"
                    end,
                    disabledTooltip = "This option requires a text selection other than none.",
                    title = "Extra Text Settings",
                    rows = mod.UF_CoreTextRows("extraText", "none", SVal, SSet, {
                        {
                            type = "dropdown",
                            label = "Alignment",
                            values = { ["left"] = "Left", ["right"] = "Right", ["center"] = "Center" },
                            order = { "left", "right", "center" },
                            get = SValRow("extraTextAlign", "left"),
                            set = function(val)
                                SSet("extraTextAlign", val)
                                ReloadAndUpdate()
                                UpdatePreview()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Size",
                            min = 8,
                            max = 100,
                            step = 1,
                            get = function()
                                return SVal("extraTextSize", SDB().textSize or 12)
                            end,
                            set = SSetRowThen("extraTextSize"),
                        },
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("extraTextX", 0),
                            set = SSetRowThen("extraTextX"),
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -300,
                            max = 300,
                            step = 1,
                            get = SValRow("extraTextY", 0),
                            set = SSetRowThen("extraTextY"),
                        },
                        {
                            type = "slider",
                            label = "Width %",
                            min = 20,
                            max = 200,
                            step = 5,
                            get = SValRow("extraTextWidthPct", 100),
                            set = SSetRowThen("extraTextWidthPct"),
                        },
                        {
                            type = "multiswatch",
                            label = "Indicator Color",
                            disabled = function()
                                local c = SVal("extraTextContent", "none")
                                return c ~= "nametotarget" and c ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Name > Target or Target is selected.",
                            swatches = {
                                {
                                    tooltip = "Custom Colored",
                                    hasAlpha = false,
                                    getValue = function()
                                        local color = SVal("extraTextTargetSepColor", nil)
                                        if type(color) == "table" then
                                            return color.r or 1, color.g or 1, color.b or 1
                                        end
                                        return 1, 1, 1
                                    end,
                                    setValue = function(red, green, blue)
                                        SSet("extraTextTargetSepColor", { r = red, g = green, b = blue })
                                        UpdatePreview()
                                    end,
                                    onClick = function(self)
                                        if SVal("extraTextTargetSepClassColor", false) then
                                            SSet("extraTextTargetSepClassColor", false)
                                            UpdatePreview()
                                            return
                                        end
                                        if self._eabOrigClick then
                                            self._eabOrigClick(self)
                                        end
                                    end,
                                    refreshAlpha = function()
                                        return SVal("extraTextTargetSepClassColor", false) and 0.3 or 1
                                    end,
                                },
                                {
                                    tooltip = "Class Colored",
                                    hasAlpha = false,
                                    getValue = CludesUI.PlayerClassRGB,
                                    setValue = function() end,
                                    onClick = function()
                                        SSet("extraTextTargetSepClassColor", true)
                                        UpdatePreview()
                                    end,
                                    refreshAlpha = function()
                                        return SVal("extraTextTargetSepClassColor", false) and 1 or 0.3
                                    end,
                                },
                            },
                        },
                        {
                            type = "input",
                            label = "Separator",
                            inputWidth = 60,
                            get = SValRow("extraTextTargetSep", ">"),
                            set = function(val)
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                if val == "" then
                                    val = ">"
                                end
                                SSet("extraTextTargetSep", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("extraTextContent", "none") ~= "nametotarget"
                            end,
                            disabledTooltip = "This option only applies when Name > Target is selected.",
                        },
                        {
                            type = "input",
                            label = "Prefix",
                            inputWidth = 60,
                            tooltip = "Text shown before the target's name.",
                            get = SValRow("extraTextTargetPrefix", "T:"),
                            set = function(val)
                                -- Unlike Separator, empty is kept: no prefix.
                                val = tostring(val or ""):gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "")
                                SSet("extraTextTargetPrefix", val)
                                UpdatePreview()
                            end,
                            disabled = function()
                                return SVal("extraTextContent", "none") ~= "targetname"
                            end,
                            disabledTooltip = "This option only applies when Target is selected.",
                        },
                    }),
                })
            end
            -- Inline swatches on Extra Text: class sets
            -- extraTextClassColor, custom opens the picker.
            if not CludesUI._prebuilding then
                local etrRgn = region
                local etAnchor = etrRgn._lastInline or etrRgn._control
                local etClassSwatch, etUpdateClassSwatch = CludesUI.BuildColorSwatch(
                    etrRgn,
                    etrRgn:GetFrameLevel() + 5,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and CludesUI.GetClassColor(class)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 1, 1, 1
                    end,
                    function() end,
                    nil,
                    20
                )
                Pix.Point(etClassSwatch, "RIGHT", etAnchor, "LEFT", -8, 0)
                etClassSwatch:SetScript("OnClick", function()
                    if SVal("extraTextContent", "none") == "none" then
                        return
                    end
                    SSet("extraTextClassColor", true)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(etClassSwatch, "Class Colored")
                local etSwGet = function()
                    return SVal("extraTextColorR", 1), SVal("extraTextColorG", 1), SVal("extraTextColorB", 1)
                end
                local etSwSet = function(red, green, blue)
                    SSet("extraTextColorR", red)
                    SSet("extraTextColorG", green)
                    SSet("extraTextColorB", blue)
                    UpdatePreview()
                end
                local etSwatch, etUpdateSwatch =
                    CludesUI.BuildColorSwatch(etrRgn, etrRgn:GetFrameLevel() + 5, etSwGet, etSwSet, nil, 20)
                Pix.Point(etSwatch, "RIGHT", etClassSwatch, "LEFT", -8, 0)
                etrRgn._lastInline = etSwatch
                local etOrigClick = etSwatch:GetScript("OnClick")
                etSwatch:SetScript("OnClick", function(self, ...)
                    if SVal("extraTextContent", "none") == "none" then
                        return
                    end
                    if SVal("extraTextClassColor", false) then
                        SSet("extraTextClassColor", false)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if etOrigClick then
                        etOrigClick(self, ...)
                    end
                end)
                CludesUI.HoverTip(etSwatch, "Custom Colored")
                local function UpdateEtSwatches()
                    local noneMode = SVal("extraTextContent", "none") == "none"
                    local classMode = SVal("extraTextClassColor", false)
                    etSwatch:SetAlpha((classMode or noneMode) and 0.3 or 1)
                    etClassSwatch:SetAlpha((classMode and not noneMode) and 1 or 0.3)
                end
                RegisterWidgetRefresh(function()
                    etUpdateSwatch()
                    etUpdateClassSwatch()
                    UpdateEtSwatches()
                end)
                UpdateEtSwatches()
            end
        end,
    }
    local sharedTextRow, sharedCenterTextRow
    cursorY, sharedTextRow = mod.UFO_BuildTextSlots(W, hostFrame, cursorY, {
        slots = textSlots,
        values = healthTextValues,
        contentOrder = textSlots[1].cfg.order,
        unit = optionState.selectedUnit,
        page = "Main Frames",
        db = SDB,
        liveDB = SDB,
        apply = function()
            ReloadAndUpdate()
            UpdatePreview()
        end,
    })
    sharedCenterTextRow = sharedTextRow

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY, sharedBarsHeader, sharedScaleRow, sharedSizeRow, sharedTextRow, sharedCenterTextRow
end

function mod.UFO_BuildPowerBarSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local GROUP_UNIT_ORDER, Pix, RegisterWidgetRefresh, ReloadAndUpdate =
        environ.GROUP_UNIT_ORDER, environ.PP, environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local UNIT_DB_MAP, UpdatePreview, optionState =
        environ.UNIT_DB_MAP, environ.UpdatePreview, environ.optState
    local W, SDB, SGet, SSet = context.W, context.SDB, context.SGet, context.SSet
    -- Row setters over SSet: the key written with the row's value, then UpdatePreview() for the Then form.
    local function SSetRowThen(settingKey)
        return function(value)
            SSet(settingKey, value)
            UpdatePreview()
        end
    end
    local SSetSupported, SVal, SValSupported = context.SSetSupported, context.SVal, context.SValSupported
    -- A row getter over SValSupported: the key's value, or the default given.
    local function SValSupportedRow(settingKey, default)
        return function()
            return SValSupported(settingKey, default)
        end
    end
    -- A row getter over SVal: the key's value, or the default given.
    local function SValRow(settingKey, default)
        return function()
            return SVal(settingKey, default)
        end
    end
    local _, height

    -------------------------------------------------------------------
    --  POWER BAR
    -------------------------------------------------------------------
    local sharedPowerHeader
    sharedPowerHeader, height = W:SectionHeader(hostFrame, "POWER BAR", cursorY)
    cursorY = cursorY - height

    local ppPosValues = {
        ["below"] = "Below Health Bar",
        ["above"] = "Above Health Bar",
        ["detached_bottom"] = "Detached Bottom",
        ["detached_top"] = "Detached Top",
        ["none"] = "None",
    }
    local ppPosOrder = { "below", "above", "---", "detached_bottom", "detached_top", "---", "none" }
    local ppTextValues = { ["none"] = "None", ["left"] = "Left", ["right"] = "Right", ["center"] = "Center" }
    local ppTextOrder = { "none", "---", "left", "right", "center" }
    local ppFmtValues = {
        ["none"] = "None",
        ["smart"] = "Smart Text",
        ["curpp"] = "Power Value",
        ["curmaxpp"] = "Power Value / Max",
        ["perpp"] = "Power %",
        ["both"] = "Value | %",
    }
    -- WoW Forever lists no Smart Text, and a saved "smart" there reads as the
    -- value (CludesUI.PowerTextFormat).
    local ppFmtOrder =
        CludesUI.PowerTextFormatOrder({ "none", "smart", "curpp", "curmaxpp", "perpp", "both" })
    -- Power Text alone offers Custom; Form Power Text keeps the lists above.
    local ppTextFmtOrder = CludesUI.PowerTextFormatOrder({
        "none",
        "---",
        "custom",
        "---",
        "smart",
        "curpp",
        "curmaxpp",
        "perpp",
        "both",
    })

    -- Row 1: Bar Height + Bar Position. Under a stock style the track fixes
    -- the bar's height and place: the height slot is Hide Power Bar instead
    -- (the health bar then takes the track too) and Bar Position shows the
    -- stock Below Health Bar, locked (ns.UF_PowerPos).
    local blizzPower = CludesUI.BlizzStyle.Get("unitframes")
    local powerLeftCfg
    if blizzPower then
        powerLeftCfg = {
            type = "toggle",
            text = "Hide Power Bar",
            tooltip = "Hides the power bar and stretches the health bar over its space.",
            getValue = function()
                return mod.UF_StockHidesPower(SDB())
            end,
            setValue = function(val)
                SSet("blizzHidePower", val and true or false)
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }
    else
        powerLeftCfg = {
            type = "slider",
            text = "Power Bar Height",
            min = 0,
            max = 100,
            step = 1,
            getValue = SValSupportedRow("powerHeight", 6),
            setValue = function(val)
                SSetSupported("powerHeight", val)
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }
    end
    local sharedPowerRow1
    sharedPowerRow1, height = W:DualRow(
        hostFrame,
        cursorY,
        powerLeftCfg,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "dropdown",
            text = "Bar Position",
            values = ppPosValues,
            order = ppPosOrder,
            getValue = function()
                return blizzPower and "below" or SVal("powerPosition", "below")
            end,
            setValue = function(val)
                SSet("powerPosition", val)
                ReloadAndUpdate()
                UpdatePreview()
                -- Attached bars paint a Solid border: the power border's Width /
                -- Height Offset row comes and goes with the detached state.
                CludesUI:RefreshPage(true)
            end,
        })
    )
    cursorY = cursorY - height
    -- Cog on Position for X/Y offsets + Width (disabled unless detached, and
    -- under a stock style, which places the bar itself)
    if not CludesUI._prebuilding then
        local posRgn = sharedPowerRow1._rightRegion
        CludesUI.BuildInlineCog(posRgn, {
            disabled = function()
                if blizzPower then
                    return true
                end
                local place = SVal("powerPosition", "below")
                return place ~= "detached_top" and place ~= "detached_bottom"
            end,
            disabledTooltip = blizzPower and CludesUI.BlizzStyle.Label("unitframes")
                or "This option requires a detached position to be active.",
            requireState = blizzPower and "disabled" or nil,
            title = "Position Settings",
            rows = {
                {
                    type = "slider",
                    label = "Width",
                    min = 0,
                    max = 400,
                    step = 1,
                    get = SValRow("powerWidth", 0),
                    set = SSetRowThen("powerWidth"),
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = SValRow("powerX", 0),
                    set = SSetRowThen("powerX"),
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -200,
                    max = 200,
                    step = 1,
                    get = SValRow("powerY", 0),
                    set = SSetRowThen("powerY"),
                },
            },
        })
    end
    -- Sync icons: Power Height, or Hide Power Bar under a stock style (left),
    -- and Power Position (right; a stock style places the bar itself)
    if not CludesUI._prebuilding and blizzPower then
        local region = sharedPowerRow1._leftRegion
        local function HiddenOf(settingKey)
            return mod.UF_StockHidesPower(UNIT_DB_MAP[settingKey]())
        end
        local function ApplyHideTo(keyList)
            local val = HiddenOf(optionState.selectedUnit)
            for _, settingKey in ipairs(keyList) do
                UNIT_DB_MAP[settingKey]().blizzHidePower = val
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
        end
        mod.UFO_UnitSync(region, "Hide Power Bar", {
            applyTo = ApplyHideTo,
            isSynced = function()
                local val = HiddenOf(optionState.selectedUnit)
                for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                    if HiddenOf(settingKey) ~= val then
                        return false
                    end
                end
                return true
            end,
        })
    elseif not CludesUI._prebuilding then
        local region = sharedPowerRow1._leftRegion
        mod.UFO_UnitSync(region, "Power Bar Height", {
            key = "powerHeight",
            default = 6,
            self = true,
        })
    end
    -- Reverse Fill cog on Bar Height or Hide Power Bar (left region)
    if not CludesUI._prebuilding then
        local region = sharedPowerRow1._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Power Bar Fill",
            disabled = blizzPower and function()
                return mod.UF_StockHidesPower(SDB())
            end or nil,
            disabledTooltip = blizzPower and "Hide Power Bar" or nil,
            requireState = blizzPower and "disabled" or nil,
            rows = {
                {
                    type = "toggle",
                    label = "Reverse Fill",
                    get = SValRow("powerReverseFill", false),
                    set = function(val)
                        SSet("powerReverseFill", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                },
            },
        })
    end
    if not CludesUI._prebuilding and not blizzPower then
        local region = sharedPowerRow1._rightRegion
        mod.UFO_UnitSync(region, "Bar Position", {
            key = "powerPosition",
            default = "below",
            self = true,
        })
    end

    -- Row 2: Power Text (format) + Fill Opacity
    local sharedPowerRow2
    local function SetPowerTextFormat(val)
        SSet("powerTextFormat", val)
        -- Auto-set position to center if user picks a format while position is "none"
        if val ~= "none" and SVal("powerPercentText", "none") == "none" then
            SSet("powerPercentText", "center")
        end
        -- If format is "none", clear position too
        if val == "none" then
            SSet("powerPercentText", "none")
        end
        ReloadAndUpdate()
        UpdatePreview()
        CludesUI:RefreshPage()
        -- The page stays, so the menu is rebuilt for Custom's pencil.
        mod.UFO_RefreshMenus(sharedPowerRow2 and sharedPowerRow2._leftRegion)
    end
    local ppTextFmtValues = mod.UFO_CustomTextValues(ppFmtValues, function()
        return SVal("powerTextFormat", "perpp")
    end, function()
        mod.UFO_EditCustomText("powerText", SDB(), optionState.selectedUnit, function()
            SetPowerTextFormat("custom")
        end)
    end)
    sharedPowerRow2, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Power Text",
        values = ppTextFmtValues,
        order = ppTextFmtOrder,
        getValue = function()
            return CludesUI.PowerTextFormat(SVal("powerTextFormat", "perpp"))
        end,
        setValue = SetPowerTextFormat,
    }, {
        type = "slider",
        text = "Fill Opacity",
        min = 0,
        max = 100,
        step = 1,
        getValue = SValRow("powerBarOpacity", 100),
        setValue = SSetRowThen("powerBarOpacity"),
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        mod.UFO_AddCustomFormatAccessor(
            sharedPowerRow2._leftRegion,
            "Power Text",
            "powerText",
            SVal("powerTextFormat", "perpp"),
            SDB,
            function()
                ReloadAndUpdate()
                UpdatePreview()
            end
        )
    end
    -- Cogwheel on Power Text for Show % toggle
    if not CludesUI._prebuilding then
        local fmtRgn = sharedPowerRow2._leftRegion
        CludesUI.BuildInlineCog(
            fmtRgn,
            mod.UFO_PowerTextCog(SVal, SSet, { none = true, curpp = true, curmaxpp = true }, function(val)
                SSet("powerShowPercent", val)
                UpdatePreview()
            end)
        )
    end
    -- Sync icon: Power Text Format (left of row 2)
    if not CludesUI._prebuilding then
        mod.UFO_FormatSync(
            sharedPowerRow2._leftRegion,
            "Power Text Format",
            "powerTextFormat",
            "powerTextCustomFormat",
            "perpp"
        )
    end
    -- Fill Opacity sync (right of row 2)
    if not CludesUI._prebuilding then
        local region = sharedPowerRow2._rightRegion
        mod.UFO_UnitSync(region, "Bar Opacity", {
            key = "powerBarOpacity",
            default = 100,
        })
    end

    -- Row 3: Bar Color (multiSwatch) + Bar Background (slider + inline swatch)
    local sharedPowerRow3
    sharedPowerRow3, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Fill Color",
        swatches = {
            {
                tooltip = "Gradient End Color",
                hasAlpha = false,
                disabled = function()
                    return not SVal("powerGradientEnabled", false)
                end,
                disabledTooltip = function()
                    return "Gradient"
                end,
                getValue = function()
                    local color = SGet("powerGradientColor")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 0.20, 0.20, 0.80
                end,
                setValue = function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]().powerGradientColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
            },
            {
                tooltip = "Custom Colored Fill",
                hasAlpha = false,
                getValue = function()
                    local color = SGet("customPowerFillColor")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 0, 0, 1
                end,
                setValue = function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]().customPowerFillColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
                onClick = function(self)
                    local val = SVal("powerPercentPowerColor", true)
                    if val then
                        SSet("powerPercentPowerColor", false)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return SVal("powerPercentPowerColor", true) and 0.3 or 1
                end,
            },
            {
                tooltip = "Power Colored Fill. Power colors can be adjusted in Global Settings -> Colors.",
                hasAlpha = false,
                getValue = function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    return details.r, details.g, details.b
                end,
                setValue = function() end,
                onClick = function()
                    UNIT_DB_MAP[optionState.selectedUnit]().powerClassColored = false
                    SSet("powerPercentPowerColor", true)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return (SVal("powerPercentPowerColor", true) and not SVal("powerClassColored", false))
                            and 1
                        or 0.3
                end,
            },
            {
                tooltip = "Class Colored Fill. Units without a class keep their power color.",
                hasAlpha = false,
                getValue = function()
                    local _, ct = UnitClass("player")
                    local classColor = CludesUI.GetClassColor(ct)
                    return classColor.r, classColor.g, classColor.b
                end,
                setValue = function() end,
                onClick = function()
                    UNIT_DB_MAP[optionState.selectedUnit]().powerPercentPowerColor = true
                    SSet("powerClassColored", true)
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return (SVal("powerPercentPowerColor", true) and SVal("powerClassColored", false)) and 1
                        or 0.3
                end,
            },
        },
    }, {
        type = "slider",
        text = "Bar Background",
        min = 0,
        max = 100,
        step = 1,
        getValue = SValRow("customPowerBgAlpha", 100),
        setValue = function(val)
            SSet("customPowerBgAlpha", val)
            ReloadAndUpdate()
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height
    -- Inline swatches on Bar Background (right): Custom + Power Colored pair
    -- mirroring Bar Color; either toggles powerBgPowerColored, inactive dims to 0.3.
    if not CludesUI._prebuilding then
        local region = sharedPowerRow3._rightRegion
        mod.UFO_SwatchPair(region, {
            store = function()
                return UNIT_DB_MAP[optionState.selectedUnit]()
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
            apply = function()
                ReloadAndUpdate()
                UpdatePreview()
            end,
        })
    end
    -- Sync icon: Bar Background (right) -- background color + opacity
    if not CludesUI._prebuilding then
        local region = sharedPowerRow3._rightRegion
        local function ApplyBgTo(keyList)
            local source = UNIT_DB_MAP[optionState.selectedUnit]()
            local bc = source.customPowerBgColor or { r = 17 / 255, g = 17 / 255, b = 17 / 255 }
            local bgA = source.customPowerBgAlpha or 100
            local bgPwr = source.powerBgPowerColored or false
            for _, settingKey in ipairs(keyList) do
                if settingKey ~= optionState.selectedUnit then
                    local d = UNIT_DB_MAP[settingKey]()
                    d.customPowerBgColor = { r = bc.r, g = bc.g, b = bc.b }
                    d.customPowerBgAlpha = bgA
                    d.powerBgPowerColored = bgPwr
                end
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
        end
        mod.UFO_UnitSync(region, "Bar Background", {
            applyTo = ApplyBgTo,
            isSynced = function()
                local source = UNIT_DB_MAP[optionState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then
                        return true
                    end
                    if a == nil or b == nil then
                        return false
                    end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[settingKey]()
                    if not colEq(d.customPowerBgColor, source.customPowerBgColor) then
                        return false
                    end
                    if (d.customPowerBgAlpha or 100) ~= (source.customPowerBgAlpha or 100) then
                        return false
                    end
                    if (d.powerBgPowerColored or false) ~= (source.powerBgPowerColored or false) then
                        return false
                    end
                end
                return true
            end,
        })
    end
    -- Sync icon: Bar Color (left) -- fill/power color and gradient
    if not CludesUI._prebuilding then
        local region = sharedPowerRow3._leftRegion
        local function ApplyColorTo(keyList)
            local source = UNIT_DB_MAP[optionState.selectedUnit]()
            local pc = source.powerPercentPowerColor
            if pc == nil then
                pc = true
            end
            local pcc = source.powerClassColored or false
            local fc = source.customPowerFillColor
            local gEn = source.powerGradientEnabled or false
            local gDir = source.powerGradientDir or "HORIZONTAL"
            local gc = source.powerGradientColor
            for _, settingKey in ipairs(keyList) do
                if settingKey ~= optionState.selectedUnit then
                    local d = UNIT_DB_MAP[settingKey]()
                    d.powerPercentPowerColor = pc
                    d.powerClassColored = pcc
                    if fc then
                        d.customPowerFillColor = { r = fc.r, g = fc.g, b = fc.b }
                    else
                        d.customPowerFillColor = nil
                    end
                    d.powerGradientEnabled = gEn
                    d.powerGradientDir = gDir
                    if gc then
                        d.powerGradientColor = { r = gc.r, g = gc.g, b = gc.b }
                    else
                        d.powerGradientColor = nil
                    end
                end
            end
            ReloadAndUpdate()
            CludesUI:RefreshPage()
        end
        mod.UFO_UnitSync(region, "Bar Color", {
            applyTo = ApplyColorTo,
            isSynced = function()
                local source = UNIT_DB_MAP[optionState.selectedUnit]()
                local function colEq(a, b)
                    if a == nil and b == nil then
                        return true
                    end
                    if a == nil or b == nil then
                        return false
                    end
                    return a.r == b.r and a.g == b.g and a.b == b.b
                end
                local val = source.powerPercentPowerColor
                if val == nil then
                    val = true
                end
                for _, settingKey in ipairs(GROUP_UNIT_ORDER) do
                    local d = UNIT_DB_MAP[settingKey]()
                    local shade = d.powerPercentPowerColor
                    if shade == nil then
                        shade = true
                    end
                    if shade ~= val then
                        return false
                    end
                    if (d.powerClassColored or false) ~= (source.powerClassColored or false) then
                        return false
                    end
                    if not colEq(d.customPowerFillColor, source.customPowerFillColor) then
                        return false
                    end
                    if (d.powerGradientEnabled or false) ~= (source.powerGradientEnabled or false) then
                        return false
                    end
                    if not colEq(d.powerGradientColor, source.powerGradientColor) then
                        return false
                    end
                    if (d.powerGradientDir or "HORIZONTAL") ~= (source.powerGradientDir or "HORIZONTAL") then
                        return false
                    end
                end
                return true
            end,
        })
    end
    -- Gradient cog on Bar Color (left region)
    if not CludesUI._prebuilding then
        local region = sharedPowerRow3._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Gradient Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Enable Gradient",
                    get = SValRow("powerGradientEnabled", false),
                    set = function(val)
                        SSet("powerGradientEnabled", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = SValRow("powerGradientDir", "HORIZONTAL"),
                    set = function(val)
                        SSet("powerGradientDir", val)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                },
            },
        })
    end

    -- Row 4: Text Position + Text Color
    local sharedPowerRow4
    sharedPowerRow4, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Text Position",
        values = ppTextValues,
        order = ppTextOrder,
        getValue = SValRow("powerPercentText", "none"),
        setValue = function(val)
            SSet("powerPercentText", val)
            ReloadAndUpdate()
            UpdatePreview()
        end,
    }, {
        type = "multiSwatch",
        text = "Text Color",
        swatches = {
            {
                tooltip = "Custom Text Color",
                hasAlpha = false,
                getValue = function()
                    local color = SGet("powerTextColor")
                    if color then
                        return color.r, color.g, color.b
                    end
                    return 1, 1, 1
                end,
                setValue = function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]().powerTextColor = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
                onClick = function(self)
                    local val = SVal("powerPercentTextPowerColor", false)
                    if val then
                        SSet("powerPercentTextPowerColor", false)
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return SVal("powerPercentTextPowerColor", false) and 0.3 or 1
                end,
            },
            {
                tooltip = "Power Colored Text",
                hasAlpha = false,
                getValue = function()
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    return details.r, details.g, details.b
                end,
                setValue = function() end,
                onClick = function()
                    SSet("powerPercentTextPowerColor", true)
                    UNIT_DB_MAP[optionState.selectedUnit]().powerTextColor = nil
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return SVal("powerPercentTextPowerColor", false) and 1 or 0.3
                end,
            },
        },
    })
    cursorY = cursorY - height
    -- Cogwheel on Text Position for size + x/y offsets (left of row 4)
    if not CludesUI._prebuilding then
        local ppRgn = sharedPowerRow4._leftRegion
        local ppRows = {
            {
                type = "slider",
                label = "Size",
                min = 6,
                max = 100,
                step = 1,
                get = SValRow("powerPercentSize", 9),
                set = SSetRowThen("powerPercentSize"),
            },
            {
                type = "slider",
                label = "X Offset",
                min = -50,
                max = 50,
                step = 1,
                get = SValRow("powerPercentX", 0),
                set = SSetRowThen("powerPercentX"),
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -50,
                max = 50,
                step = 1,
                get = SValRow("powerPercentY", 0),
                set = SSetRowThen("powerPercentY"),
            },
        }
        CludesUI.BuildInlineCog(ppRgn, {
            disabled = function()
                return SVal("powerPercentText", "none") == "none"
            end,
            disabledTooltip = "This option requires a text position other than none.",
            title = "Text Position",
            rows = ppRows,
        })
    end
    -- Text Position sync (left of row 4)
    if not CludesUI._prebuilding then
        local region = sharedPowerRow4._leftRegion
        mod.UFO_UnitSync(region, "Power Text Position", {
            key = "powerPercentText",
            default = "none",
            self = true,
        })
    end
    -- Sync icon: Text Color (right of row 4)
    if not CludesUI._prebuilding then
        -- Power colour on/off travels with the custom colour (or its absence);
        -- only the on/off decides whether the frames agree.
        mod.UFO_UnitSync(sharedPowerRow4._rightRegion, "Text Color", {
            self = true,
            copy = function(t, from)
                local color = from.powerTextColor
                t.powerPercentTextPowerColor = from.powerPercentTextPowerColor or false
                t.powerTextColor = color and { r = color.r, g = color.g, b = color.b } or nil
            end,
            same = function(t, from)
                return (t.powerPercentTextPowerColor or false) == (from.powerPercentTextPowerColor or false)
            end,
        })
    end

    -- Row 5: Power Border Style (+ cog) | Power Border Size (+ inline swatches)
    local pbTexValues, pbTexOrder = CludesUI.GetBorderTextureDropdown()
    local sharedPowerBorderRow
    sharedPowerBorderRow, height = W:DualRow(
        hostFrame,
        cursorY,
        CludesUI.BlizzStyle.Gate("unitframes", {
            type = "dropdown",
            text = "Border Style",
            disabled = function()
                local place = SVal("powerPosition", "below")
                return place ~= "detached_top" and place ~= "detached_bottom"
            end,
            disabledTooltip = function()
                return CludesUI.L(
                    "Border Style is only configurable when the Power Bar is detached. Attached Power Bars always use Solid."
                )
            end,
            rawTooltip = true,
            values = pbTexValues,
            order = pbTexOrder,
            getValue = function()
                return SGet("powerBorderStyle") or "solid"
            end,
            setValue = function(val)
                SSet("powerBorderStyle", val)
                SSet("powerBorderOffsetX", nil)
                SSet("powerBorderOffsetY", nil)
                SSet("powerBorderShiftX", nil)
                SSet("powerBorderShiftY", nil)
                if val ~= "solid" then
                    -- The style's select colour (Pixels grey), else white.
                    SSet("powerBorderColor", CludesUI.GetBorderSelectColor(val) or { r = 1, g = 1, b = 1 })
                    SSet("powerBorderAlpha", 1)
                else
                    SSet("powerBorderColor", { r = 0, g = 0, b = 0 })
                    SSet("powerBorderAlpha", 1)
                end
                local defSz = CludesUI.GetBorderDefaultSize("unitframes", val)
                if defSz then
                    SSet("powerBorderSize", defSz)
                end
                -- A style pick returns the bar to its legacy step; clear a set
                -- exact size (false travels through mirror sync, nil would not).
                if SGet("powerBorderSizePx") then
                    SDB().powerBorderSizePx = false
                end
                ReloadAndUpdate()
                -- The Width / Height Offset row exists only under a textured style.
                CludesUI:RefreshPage(true)
            end,
        }),
        CludesUI.BlizzStyle.Gate(
            "unitframes",
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = function()
                    local place = SVal("powerPosition", "below")
                    return place == "none"
                end,
                disabledTooltip = function()
                    return CludesUI.L("Border is only available when the Power Bar is shown.")
                end,
                rawTooltip = true,
                trackWidth = 120,
                getStep = function()
                    return SVal("powerBorderSize", 0)
                end,
                setStep = function(step)
                    SDB().powerBorderSize = step
                end,
                getTex = function()
                    -- The style the bar is painted with (ns.UpdatePowerBorder): an
                    -- attached bar is forced Solid whatever the dropdown holds.
                    local place = SVal("powerPosition", "below")
                    if place == "above" or place == "below" then
                        return "solid"
                    end
                    return SGet("powerBorderStyle") or "solid"
                end,
                getPx = function()
                    return SGet("powerBorderSizePx")
                end,
                setPx = function(val)
                    SDB().powerBorderSizePx = val
                end,
                apply = ReloadAndUpdate,
            })
        )
    )
    cursorY = cursorY - height
    -- Width Offset | Height Offset: a textured power border's outward offsets.
    -- Only a detached bar can be textured (an attached bar is painted Solid),
    -- so the row exists only while the painted style is textured.
    do
        local pbPos = SVal("powerPosition", "below")
        local pbTex = SGet("powerBorderStyle") or "solid"
        if (pbPos == "detached_top" or pbPos == "detached_bottom") and pbTex ~= "solid" and pbTex ~= "" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                getTex = function()
                    local place = SVal("powerPosition", "below")
                    if place == "above" or place == "below" then
                        return "solid"
                    end
                    return SGet("powerBorderStyle") or "solid"
                end,
                getStep = function()
                    return SVal("powerBorderSize", 0)
                end,
                getSizeKey = function()
                    return SVal("powerBorderSize", 0)
                end,
                getPx = function()
                    return SGet("powerBorderSizePx")
                end,
                getX = function()
                    return SGet("powerBorderOffsetX")
                end,
                setX = function(val)
                    SDB().powerBorderOffsetX = val
                end,
                getY = function()
                    return SGet("powerBorderOffsetY")
                end,
                setY = function(val)
                    SDB().powerBorderOffsetY = val
                end,
                apply = ReloadAndUpdate,
            })
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("unitframes", ocfgL),
                CludesUI.BlizzStyle.Gate("unitframes", ocfgR)
            )
            cursorY = cursorY - height
        end
    end
    -- Cog for power border shift / layering (left region)
    if not CludesUI._prebuilding then
        local region = sharedPowerBorderRow._leftRegion
        local cogBtn = CludesUI.BuildInlineCog(region, {
            title = "Power Border Options",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        local val = SGet("powerBorderShiftX")
                        if val then
                            return val
                        end
                        local texture = SGet("powerBorderStyle") or "solid"
                        local sz = SVal("powerBorderSize", 0)
                        local _, _, dsx = CludesUI.GetBorderDefaults("unitframes", texture, sz)
                        return dsx
                    end,
                    set = function(val)
                        SSet("powerBorderShiftX", val == 0 and nil or val)
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
                        local val = SGet("powerBorderShiftY")
                        if val then
                            return val
                        end
                        local texture = SGet("powerBorderStyle") or "solid"
                        local sz = SVal("powerBorderSize", 0)
                        local _, _, _, dsy = CludesUI.GetBorderDefaults("unitframes", texture, sz)
                        return dsy
                    end,
                    set = function(val)
                        SSet("powerBorderShiftY", val == 0 and nil or val)
                        ReloadAndUpdate()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = SValRow("powerBorderBehind", false),
                    set = function(val)
                        SSet("powerBorderBehind", val)
                        ReloadAndUpdate()
                    end,
                },
            },
        })
        local function UpdatePBCogVis()
            local place = SVal("powerPosition", "below")
            local isDet = (place == "detached_top" or place == "detached_bottom")
            local texture = SGet("powerBorderStyle") or "solid"
            if not isDet or texture == "solid" then
                cogBtn:Hide()
            else
                cogBtn:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdatePBCogVis)
        UpdatePBCogVis()
    end
    -- Inline swatches on Border Size (right region)
    if not CludesUI._prebuilding then
        local rightRegion = sharedPowerBorderRow._rightRegion
        local control = rightRegion._lastInline or rightRegion._control
        -- Border color swatch
        local pbSwatch, updatePBSwatch = CludesUI.BuildColorSwatch(
            rightRegion,
            sharedPowerBorderRow:GetFrameLevel() + 3,
            function()
                local color = SGet("powerBorderColor") or { r = 0, g = 0, b = 0 }
                return color.r, color.g, color.b, SVal("powerBorderAlpha", 1)
            end,
            function(red, green, blue, a)
                UNIT_DB_MAP[optionState.selectedUnit]().powerBorderColor = { r = red, g = green, b = blue }
                UNIT_DB_MAP[optionState.selectedUnit]().powerBorderAlpha = a
                ReloadAndUpdate()
            end,
            true,
            20
        )
        Pix.Point(pbSwatch, "RIGHT", control, "LEFT", -8, 0)
        CludesUI.HoverTip(pbSwatch, "Border Color")
        rightRegion._lastInline = pbSwatch
        CludesUI.RegisterWidgetRefresh(function()
            updatePBSwatch()
        end)
    end

    -- Spell Cost Prediction (player only, WoW Forever only; the page rebuilds
    -- on unit change): toggle with a preview eyeball | its color. Above Power
    -- Type, which keeps its height when hidden. Built with the engine
    -- (CludesUI_SpellCostPrediction.lua, nil off Forever) loaded: the
    -- color and the preview read its color rule.
    if optionState.selectedUnit == "player" and CludesUI.SpellCostPrediction then
        local costRow
        costRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Spell Cost Prediction",
            tooltip = "While you cast, shows on the bar the mana the spell will cost.",
            getValue = function()
                return SVal("powerCostPrediction", false) == true
            end,
            setValue = function(val)
                SSet("powerCostPrediction", val)
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "colorpicker",
            text = "Spell Cost Color",
            disabled = function()
                return SVal("powerCostPrediction", false) ~= true
            end,
            disabledTooltip = "Spell Cost Prediction",
            getValue = function()
                local red, green, b = mod.UF_PowerCostColor(SDB())
                return red, green, b
            end,
            setValue = function(red, green, blue)
                SSet("powerCostColor", { r = red, g = green, b = blue })
                UpdatePreview()
            end,
        })
        cursorY = cursorY - height
        -- Inline eyeball: preview the cost on the live preview. Session-only.
        if not CludesUI._prebuilding then
            local region = costRow._leftRegion
            CludesUI.AddPreviewEye(region, mod, "_ufShowPowerCostPreview", "spell cost", UpdatePreview)
        end
    end
    if optionState.selectedUnit == "player" and CludesUI.IS_FOREVER == true then
        -- Mana Regen Spark (CludesUI_ManaRegenSpark.lua), the section's
        -- last row; warriors and rogues get no spark engine, so no row. A
        -- druid's Power Type shares it: one choice for every form, stored
        -- under a string key so it can never meet a retail spec ID in the
        -- table.
        -- Off or one of two modes: a view over manaRegenSpark (on/off) and
        -- manaRegenSparkMode (nil = 5-Second Rule), so saved choices read as before.
        local sparkCfg = {
            type = "dropdown",
            text = "Mana Regen Spark",
            tooltip = "5-Second Rule sweeps a spark across the bar for 5 seconds after you spend mana, until mana regen resumes. Regen Ticks then keeps sweeping every 2 seconds while mana regenerates.",
            values = { off = "Off", fsr = "5-Second Rule", ticks = "Regen Ticks" },
            order = { "off", "fsr", "ticks" },
            getValue = function()
                if SVal("manaRegenSpark", false) ~= true then
                    return "off"
                end
                return SVal("manaRegenSparkMode", "fsr") == "ticks" and "ticks" or "fsr"
            end,
            setValue = function(val)
                if val ~= "off" then
                    SSet("manaRegenSparkMode", val == "ticks" and "ticks" or nil)
                end
                SSet("manaRegenSpark", val ~= "off")
            end,
        }
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            local powerTypeRow
            powerTypeRow, height = W:DualRow(
                hostFrame,
                cursorY,
                -- Mana + Form Power: Mana plus foreverFormBar (a second bar
                -- with the form's power, CUI_UnitFrames_ForeverFormBar.lua).
                {
                    type = "dropdown",
                    text = "Power Type",
                    tooltip = "Mana keeps the bar on Mana in Bear and Cat Form. Mana + Form Power also shows your Energy or Rage in a second bar.",
                    values = { ["default"] = "Match Form", ["alt"] = "Mana", ["both"] = "Mana + Form Power" },
                    order = { "default", "alt", "both" },
                    getValue = function()
                        local playerDB = UNIT_DB_MAP["player"]()
                        local shade = playerDB.powerTypeOverride
                        if not (shade and shade.foreverDruid) then
                            return "default"
                        end
                        return playerDB.foreverFormBar and "both" or "alt"
                    end,
                    -- The Form rows below exist only with Mana + Form Power: the page
                    -- rebuilds when that choice comes or goes.
                    setValue = CludesUI.DependentSetValue(function()
                        return SVal("foreverFormBar", false) == true
                    end, function(val)
                        local playerDB = UNIT_DB_MAP["player"]()
                        if val ~= "default" then
                            if not playerDB.powerTypeOverride then
                                playerDB.powerTypeOverride = {}
                            end
                            playerDB.powerTypeOverride.foreverDruid = true
                        elseif playerDB.powerTypeOverride then
                            playerDB.powerTypeOverride.foreverDruid = nil
                        end
                        playerDB.foreverFormBar = (val == "both") or nil
                        ReloadAndUpdate()
                        CludesUI:RefreshPage()
                    end),
                },
                sparkCfg
            )
            cursorY = cursorY - height
            -- The Form Power bar's own settings re-apply only that bar
            -- (CUI_UnitFrames_ForeverFormBar.lua), not the whole frame.
            local function NoFormBar()
                return not SVal("foreverFormBar", false)
            end
            local function SetForm(settingKey, val)
                SDB()[settingKey] = val
                mod.UF_ForeverFormBarRelayout()
            end
            -- A Form Power Text setting; unset follows the power bar's.
            local function FormVal(settingKey, base, def)
                local val = SVal(settingKey, nil)
                if val == nil then
                    val = SVal(base, def)
                end
                return val
            end
            local FORM_TIP = "Requires Power Type: Mana + Form Power."
            -- Cog: the Form Power bar's offsets.
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(powerTypeRow._leftRegion, {
                    disabled = NoFormBar,
                    disabledTooltip = FORM_TIP,
                    rawTooltip = true,
                    title = "Form Power Bar",
                    rows = {
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("foreverFormBarX", 0),
                            set = function(val)
                                SetForm("foreverFormBarX", val)
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = SValRow("foreverFormBarY", 0),
                            set = function(val)
                                SetForm("foreverFormBarY", val)
                            end,
                        },
                    },
                })
            end
            -- Form Power Text (its colour swatches inline) + Form Text Position:
            -- the form bar's text, apart from the power bar's (Mana) text. Built
            -- only with Mana + Form Power (Power Type rebuilds the page).
            if not NoFormBar() then
                local formTextRow
                formTextRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Form Power Text",
                    values = ppFmtValues,
                    order = ppFmtOrder,
                    getValue = function()
                        -- An inherited Custom draws Power % on the form bar.
                        local val = CludesUI.PowerTextFormat(
                            FormVal("foreverFormTextFormat", "powerTextFormat", "perpp")
                        )
                        return val == "custom" and "perpp" or val
                    end,
                    setValue = function(val)
                        local place = FormVal("foreverFormTextPos", "powerPercentText", "none")
                        if val ~= "none" and place == "none" then
                            SDB().foreverFormTextPos = "center"
                        end
                        if val == "none" then
                            SDB().foreverFormTextPos = "none"
                        end
                        SetForm("foreverFormTextFormat", val)
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "dropdown",
                    text = "Form Text Position",
                    values = ppTextValues,
                    order = ppTextOrder,
                    getValue = function()
                        return FormVal("foreverFormTextPos", "powerPercentText", "none")
                    end,
                    setValue = function(val)
                        SetForm("foreverFormTextPos", val)
                    end,
                })
                cursorY = cursorY - height
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(formTextRow._leftRegion, {
                        disabled = function()
                            local fmt = CludesUI.PowerTextFormat(
                                FormVal("foreverFormTextFormat", "powerTextFormat", "perpp")
                            )
                            return fmt == "none" or fmt == "curpp" or fmt == "curmaxpp"
                        end,
                        disabledTooltip = "This option is only available for formats that display a percentage.",
                        title = "Form Power Text",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show %",
                                get = function()
                                    return FormVal("foreverFormShowPercent", "powerShowPercent", true)
                                        ~= false
                                end,
                                set = function(val)
                                    SetForm("foreverFormShowPercent", val)
                                end,
                            },
                        },
                    })
                    -- Text colour: custom, or the form power's colour. Neither set
                    -- follows the power bar's Text Color.
                    local function FormPowerColored()
                        local pc = SVal("foreverFormTextPowerColor", nil)
                        if pc == nil and SVal("foreverFormTextColor", nil) == nil then
                            pc = SVal("powerPercentTextPowerColor", false)
                        end
                        return pc and true or false
                    end
                    CludesUI.BuildInlineSwatches(formTextRow._leftRegion, {
                        {
                            tooltip = "Custom Text Color",
                            hasAlpha = false,
                            getValue = function()
                                local color = SVal("foreverFormTextColor", nil)
                                if color == nil and SVal("foreverFormTextPowerColor", nil) == nil then
                                    color = SGet("powerTextColor")
                                end
                                if color then
                                    return color.r, color.g, color.b
                                end
                                return 1, 1, 1
                            end,
                            setValue = function(red, green, blue)
                                SDB().foreverFormTextPowerColor = false
                                SetForm("foreverFormTextColor", { r = red, g = green, b = blue })
                            end,
                            onClick = function(self)
                                if FormPowerColored() then
                                    SDB().foreverFormTextColor = nil
                                    SetForm("foreverFormTextPowerColor", false)
                                    CludesUI:RefreshPage()
                                    return
                                end
                                if self._eabOrigClick then
                                    self._eabOrigClick(self)
                                end
                            end,
                            refreshAlpha = function()
                                return FormPowerColored() and 0.3 or 1
                            end,
                        },
                        {
                            tooltip = "Power Colored Text",
                            hasAlpha = false,
                            getValue = function()
                                local details = CludesUI.GetPowerColor("ENERGY")
                                return details.r, details.g, details.b
                            end,
                            setValue = function() end,
                            onClick = function()
                                SDB().foreverFormTextColor = nil
                                SetForm("foreverFormTextPowerColor", true)
                                CludesUI:RefreshPage()
                            end,
                            refreshAlpha = function()
                                return FormPowerColored() and 1 or 0.3
                            end,
                        },
                    })
                    CludesUI.BuildInlineCog(formTextRow._rightRegion, {
                        disabled = function()
                            return FormVal("foreverFormTextPos", "powerPercentText", "none") == "none"
                        end,
                        disabledTooltip = "This option requires a text position other than none.",
                        title = "Form Text Position",
                        rows = {
                            {
                                type = "slider",
                                label = "Size",
                                min = 6,
                                max = 100,
                                step = 1,
                                get = function()
                                    return FormVal("foreverFormTextSize", "powerPercentSize", 9)
                                end,
                                set = function(val)
                                    SetForm("foreverFormTextSize", val)
                                end,
                            },
                            {
                                type = "slider",
                                label = "X Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return FormVal("foreverFormTextX", "powerPercentX", 0)
                                end,
                                set = function(val)
                                    SetForm("foreverFormTextX", val)
                                end,
                            },
                            {
                                type = "slider",
                                label = "Y Offset",
                                min = -50,
                                max = 50,
                                step = 1,
                                get = function()
                                    return FormVal("foreverFormTextY", "powerPercentY", 0)
                                end,
                                set = function(val)
                                    SetForm("foreverFormTextY", val)
                                end,
                            },
                        },
                    })
                end
            end
        elseif CludesUI.ManaRegenSpark then
            _, height = W:DualRow(hostFrame, cursorY, sparkCfg, CludesUI.BlankRowCfg())
            cursorY = cursorY - height
        end
    end

    -- Row 6: Power Type override (player-only, spec-dependent)
    do
        local _, playerClass = UnitClass("player")
        -- Specs that offer an alternative power type on the player power bar.
        -- { defaultLabel, altLabel, altPowerType (Enum.PowerType value to force) },
        -- plus astral = Balance's third choice (Astral Power outside Cat and Bear
        -- Form), listed between the two; tip = the row's tooltip for the class.
        -- For Shadow Priest the alt is "no override" (nil) so UnitPowerType returns Insanity.
        local SPEC_POWER_ALTS = {
            DRUID = {
                [1] = { "Match Form", "Mana", 0, astral = "Astral Power" }, -- Balance
                [2] = { "Match Form", "Mana", 0 }, -- Feral
                [3] = { "Match Form", "Mana", 0 }, -- Guardian
                [4] = { "Match Form", "Mana", 0 }, -- Restoration
                tip = "The first choice follows your form, with Energy in Cat Form and Rage in Bear Form. Mana stays on Mana in every form, and Astral Power shows Astral Power in every form except Cat and Bear Form.",
            },
            PRIEST = {
                [3] = { "Mana", "Insanity", nil }, -- Shadow (default is our Mana override)
            },
            SHAMAN = {
                [1] = { "Maelstrom", "Mana", 0 }, -- Elemental
            },
        }
        local classAlts = SPEC_POWER_ALTS[playerClass]
        -- Retail only: these alternatives are retail spec resources, and the
        -- WoW Forever classes have no specs to key them on.
        if classAlts and not CludesUI.IS_FOREVER then
            local GetSpec = C_SpecializationInfo.GetSpecialization
            -- Labels follow the CURRENT spec: the page is built once and
            -- cached, so they are refilled on every spec change (see
            -- UpdatePowerTypeRow), never only at build time.
            local ptValues = {}
            local ptOrder = { "default", "alt" }
            local function FillPowerTypeValues(s)
                local payload = s and classAlts[s]
                ptValues["default"] = payload and payload[1] or nil
                ptValues["alt"] = payload and payload[2] or nil
                ptValues["astral"] = payload and payload.astral or nil
                if ptValues["astral"] then
                    ptOrder[2], ptOrder[3] = "astral", "alt"
                else
                    ptOrder[2], ptOrder[3] = "alt", nil
                end
            end
            local labelSpec = GetSpec()
            FillPowerTypeValues(labelSpec)

            local sharedPowerRow5
            sharedPowerRow5, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Power Type",
                tooltip = classAlts.tip,
                values = ptValues,
                order = ptOrder,
                -- Stored by SPEC ID, not the GetSpecialization() index: one
                -- profile holds one set, so an index key collides across
                -- classes (slot 3 is Guardian, Shadow AND Augmentation).
                -- classAlts stays index-keyed, it is already per class.
                getValue = function()
                    local s = GetSpec()
                    if not s or not classAlts[s] then
                        return "default"
                    end
                    local spellRef = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(s)
                    if not spellRef then
                        return "default"
                    end
                    local shade = UNIT_DB_MAP["player"]().powerTypeOverride
                    if shade and shade[spellRef] == "astral" then
                        return "astral"
                    end
                    if shade and shade[spellRef] then
                        return "alt"
                    end
                    return "default"
                end,
                setValue = function(val)
                    local s = GetSpec()
                    if not s then
                        return
                    end
                    local spellRef = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(s)
                    if not spellRef then
                        return
                    end
                    local playerDB = UNIT_DB_MAP["player"]()
                    if val == "alt" then
                        if not playerDB.powerTypeOverride then
                            playerDB.powerTypeOverride = {}
                        end
                        playerDB.powerTypeOverride[spellRef] = true
                    elseif val == "astral" then
                        if not playerDB.powerTypeOverride then
                            playerDB.powerTypeOverride = {}
                        end
                        playerDB.powerTypeOverride[spellRef] = "astral"
                    else
                        if playerDB.powerTypeOverride then
                            playerDB.powerTypeOverride[spellRef] = nil
                        end
                    end
                    ReloadAndUpdate()
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height

            local function UpdatePowerTypeRow()
                local s = GetSpec()
                if s ~= labelSpec then
                    labelSpec = s
                    FillPowerTypeValues(s)
                    local dropdown = sharedPowerRow5._leftRegion and sharedPowerRow5._leftRegion._control
                    if dropdown and dropdown._invalidateMenu then
                        dropdown._invalidateMenu()
                    end
                end
                if optionState.selectedUnit == "player" and s and classAlts[s] then
                    sharedPowerRow5:Show()
                else
                    sharedPowerRow5:Hide()
                end
            end
            RegisterWidgetRefresh(UpdatePowerTypeRow)
            UpdatePowerTypeRow()
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY, sharedPowerHeader, sharedPowerRow1, sharedPowerRow2
end

function mod.UFO_BuildClassResourceSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local RegisterWidgetRefresh, ReloadAndUpdate = environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local UNIT_DB_MAP, UpdatePreview, classPowerPosOrder, classPowerPosValues =
        environ.UNIT_DB_MAP, environ.UpdatePreview, environ.classPowerPosOrder, environ.classPowerPosValues
    local classPowerStyleOrder, classPowerStyleValues, optionState =
        environ.classPowerStyleOrder, environ.classPowerStyleValues, environ.optState
    local W, SApplySupport, SGetSupported, SSetSupported =
        context.W, context.SApplySupport, context.SGetSupported, context.SSetSupported
    local SValSupported = context.SValSupported
    -- A row getter over SValSupported: the key's value, or the default given.
    local function SValSupportedRow(settingKey, default)
        return function()
            return SValSupported(settingKey, default)
        end
    end
    local _, height
    local row

    -- CLASS RESOURCE section: only shown in multi-edit or when player is selected
    local _showClassRes = optionState.selectedUnit == "player"
    -- Declared outside the gate: returned for the click mapping.
    local sharedClassResHeader, sharedClassResRow
    if _showClassRes then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -------------------------------------------------------------------
        --  CLASS RESOURCE
        -------------------------------------------------------------------
        sharedClassResHeader, height = W:SectionHeader(hostFrame, "CLASS RESOURCE", cursorY)
        cursorY = cursorY - height

        -- The class resource style that builds: WoW Forever outside its own
        -- style builds a saved "blizzard" as modern, and a rogue under the
        -- CludesUI look reads its own style (ns.UF_ForeverCPStyle, nil
        -- elsewhere). Display and gating only; writes and syncs keep the saved value.
        local function SCPStyle()
            local val = SValSupported("classPowerStyle", "none")
            if mod.UF_ForeverCPStyle then
                val = mod.UF_ForeverCPStyle(val)
            end
            return val
        end

        -- Row 1: Enable Class Resource + Class Colors (with inline swatch)
        sharedClassResRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Enable Class Resource",
            values = classPowerStyleValues,
            order = classPowerStyleOrder,
            -- Forever ships no class resource bar that can be re-parented: the
            -- per-class globals the Blizzard style adopts are all Mainline-only.
            -- Under the WoW Forever style the entry is the combo point arc
            -- instead (placed by Combo Points, below), and stays live.
            disabledValues = function(keyName)
                if
                    keyName == "blizzard"
                    and CludesUI.IS_FOREVER
                    and not CludesUI.BlizzStyle.Forever("unitframes")
                then
                    return "This option requires the WoW Forever style."
                end
                -- One owner for Blizzard's class resource frame: while Resource
                -- Bars' Blizzard Class Resource Art is on, Blizzard is greyed here.
                -- Only while not already chosen, so it can still be changed away.
                if keyName == "blizzard" and SValSupported("classPowerStyle", "none") ~= "blizzard" then
                    if _G._CURB_BlizzArtWanted and _G._CURB_BlizzArtWanted() then
                        return "This option can't be used while Blizzard Class Resource Art is enabled in Resource Bars."
                    end
                end
            end,
            getValue = function()
                return SCPStyle()
            end,
            -- DependentSetValue: Rows 2-3 below are hidden while the style
            -- is None; only the None <-> enabled flip forces the rebuild
            -- (style-to-style changes keep the cheap refresh path).
            setValue = CludesUI.DependentSetValue(function()
                return SCPStyle() ~= "none"
            end, function(val)
                -- WoW Forever rogues under the CludesUI look pick their
                -- own style (ns.UF_RogueCPKey); the shared one stays as is.
                local rogueKey = mod.UF_RogueCPKey and mod.UF_RogueCPKey()
                if rogueKey then
                    UNIT_DB_MAP[optionState.selectedUnit]()[rogueKey] = val
                    if mod.frames and mod.frames._toggleClassPower then
                        mod.frames._toggleClassPower()
                    end
                    ReloadAndUpdate()
                else
                    SSetSupported("classPowerStyle", val)
                    SSetSupported("showClassPowerBar", val ~= "none")
                    if mod.frames and mod.frames._toggleClassPower then
                        mod.frames._toggleClassPower(val)
                    end
                end
                UpdatePreview()
                C_Timer.After(0, function()
                    local rl = CludesUI._widgetRefreshList
                    if rl then
                        for idx = 1, #rl do
                            rl[idx]()
                        end
                    end
                end)
                -- WoW Forever: Blizzard's own combo points (beside Blizzard's
                -- own target frame) went to the hidden parent for another
                -- Combo Points spot: only a reload brings them back.
                if val == "none" and mod._ufComboFrameByLoc then
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Blizzard's combo points return to its target frame after a UI reload.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end
            end),
        }, {
            type = "multiSwatch",
            text = "Fill Color",
            disabled = function()
                return SCPStyle() ~= "modern"
            end,
            disabledTooltip = "Class Resource must be set to Modern",
            rawTooltip = true,
            swatches = {
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local color = SGetSupported("classPowerCustomColor")
                        color = color or { r = 1, g = 0.82, b = 0 }
                        return color.r, color.g, color.b, 1
                    end,
                    setValue = function(red, green, blue)
                        UNIT_DB_MAP[optionState.selectedUnit]().classPowerCustomColor =
                            { r = red, g = green, b = blue }
                        if mod.frames and mod.frames._toggleClassPower then
                            mod.frames._toggleClassPower()
                        end
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                    onClick = function(self)
                        if SGetSupported("classPowerClassColor") then
                            SSetSupported("classPowerClassColor", false)
                            ReloadAndUpdate()
                            UpdatePreview()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return SGetSupported("classPowerClassColor") and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Dynamic Colored",
                    getValue = function()
                        local _, ct = UnitClass("player")
                        if ct and RAID_CLASS_COLORS[ct] then
                            local classColor = RAID_CLASS_COLORS[ct]
                            return classColor.r, classColor.g, classColor.b, 1
                        end
                        return 1, 0.82, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        SSetSupported("classPowerClassColor", true)
                        ReloadAndUpdate()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return SGetSupported("classPowerClassColor") and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height
        SApplySupport(sharedClassResRow._leftRegion, "classPowerStyle")
        SApplySupport(sharedClassResRow._rightRegion, "classPowerClassColor")

        -- Inline "Empty Bar Color" swatch on Class Colors row (next to custom color swatch)
        if not CludesUI._prebuilding then
            local ccRgn = sharedClassResRow._rightRegion
            local emptySwatch = CludesUI.BuildColorSwatch(ccRgn, ccRgn:GetFrameLevel() + 5, function()
                local color = SGetSupported("classPowerEmptyColor")
                color = color or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }
                return color.r, color.g, color.b, color.a or 1
            end, function(red, green, blue, a)
                UNIT_DB_MAP[optionState.selectedUnit]().classPowerEmptyColor =
                    { r = red, g = green, b = blue, a = a or 1 }
                if mod.frames and mod.frames._toggleClassPower then
                    mod.frames._toggleClassPower()
                end
                ReloadAndUpdate()
                UpdatePreview()
            end, true, 20)
            emptySwatch:SetPoint("RIGHT", ccRgn._lastInline or ccRgn._control, "LEFT", -6, 0)
            ccRgn._lastInline = emptySwatch
            local function UpdateEmptySwatch()
                local crOff = SCPStyle() ~= "modern"
                if crOff then
                    emptySwatch:SetAlpha(0.15)
                    emptySwatch:Disable()
                else
                    emptySwatch:SetAlpha(1)
                    emptySwatch:Enable()
                end
            end
            UpdateEmptySwatch()
            RegisterWidgetRefresh(UpdateEmptySwatch)
            emptySwatch:HookScript("OnEnter", function(self)
                if SCPStyle() ~= "modern" then
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.DisabledTooltip("This option requires Class Resource to be set to Modern.")
                    )
                else
                    CludesUI.ShowWidgetTooltip(self, "Empty Bar Color")
                end
            end)
            emptySwatch:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        -- Sync icons: Enable Class Resource (left) and Class Colors (right)
        if not CludesUI._prebuilding then
            -- A style of None also hides the bar.
            mod.UFO_UnitSync(sharedClassResRow._leftRegion, "Class Resource Style", {
                self = true,
                copy = function(t, from)
                    local style = from.classPowerStyle or "none"
                    t.classPowerStyle = style
                    t.showClassPowerBar = style ~= "none"
                end,
                same = function(t, from)
                    return (t.classPowerStyle or "none") == (from.classPowerStyle or "none")
                end,
            })
            mod.UFO_UnitSync(sharedClassResRow._rightRegion, "Class Colors", {
                key = "classPowerClassColor",
                default = true,
                unsetOnly = true,
                self = true,
            })
        end

        -- Rows 2-3 are HIDDEN entirely while Enable Class Resource is None
        -- (the dropdown's DependentSetValue forces the rebuild on flips).
        if SCPStyle() ~= "none" then
            -- Row 2: Position (with cog for x/y) + Size
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Position",
                values = classPowerPosValues,
                order = classPowerPosOrder,
                disabled = function()
                    return SCPStyle() ~= "modern"
                end,
                disabledTooltip = "Class Resource must be set to Modern",
                rawTooltip = true,
                getValue = SValSupportedRow("classPowerPosition", "top"),
                setValue = function(val)
                    SSetSupported("classPowerPosition", val)
                    if mod.frames and mod.frames._toggleClassPower then
                        mod.frames._toggleClassPower()
                    end
                    UpdatePreview()
                    UpdatePreview()
                end,
            }, {
                type = "slider",
                text = "Size",
                min = 4,
                max = 100,
                step = 1,
                disabled = function()
                    return SCPStyle() ~= "modern"
                end,
                disabledTooltip = "Class Resource must be set to Modern",
                rawTooltip = true,
                getValue = SValSupportedRow("classPowerSize", 8),
                setValue = function(val)
                    SSetSupported("classPowerSize", val)
                    if mod.frames and mod.frames._toggleClassPower then
                        mod.frames._toggleClassPower()
                    end
                    UpdatePreview()
                    UpdatePreview()
                end,
            })
            cursorY = cursorY - height
            SApplySupport(row._leftRegion, "classPowerPosition")
            SApplySupport(row._rightRegion, "classPowerSize")
            -- Cog on Position for X/Y
            if not CludesUI._prebuilding then
                local posRgn = row._leftRegion
                CludesUI.BuildInlineCog(posRgn, {
                    disabled = function()
                        return SCPStyle() ~= "modern" or SValSupported("classPowerPosition", "top") == "above"
                    end,
                    disabledTooltip = function()
                        return SCPStyle() ~= "modern"
                                and "This option requires Class Resource to be set to Modern."
                            or "This option requires a dropdown selection other than Above Health Bar"
                    end,
                    title = "Class Resource Position",
                    rows = {
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = SValSupportedRow("classPowerBarX", 0),
                            set = function(val)
                                SSetSupported("classPowerBarX", val)
                                if mod.frames and mod.frames._toggleClassPower then
                                    mod.frames._toggleClassPower()
                                end
                                UpdatePreview()
                                UpdatePreview()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -100,
                            max = 100,
                            step = 1,
                            get = SValSupportedRow("classPowerBarY", 0),
                            set = function(val)
                                SSetSupported("classPowerBarY", val)
                                if mod.frames and mod.frames._toggleClassPower then
                                    mod.frames._toggleClassPower()
                                end
                                UpdatePreview()
                                UpdatePreview()
                            end,
                        },
                    },
                })
            end
            -- Sync icons: Class Resource Position (left) and Size (right)
            if not CludesUI._prebuilding then
                local region = row._leftRegion
                mod.UFO_UnitSync(region, "Class Resource Position", {
                    key = "classPowerPosition",
                    default = "top",
                    self = true,
                })
            end
            if not CludesUI._prebuilding then
                local region = row._rightRegion
                mod.UFO_UnitSync(region, "Class Resource Size", {
                    key = "classPowerSize",
                    default = 8,
                    self = true,
                })
            end

            -- Row 3: Bar Spacing + Background Color (with alpha)
            local sharedClassResRow3
            sharedClassResRow3, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                pixel = true,
                text = "Bar Spacing",
                min = 0,
                max = 10,
                step = 1,
                disabled = function()
                    return SCPStyle() ~= "modern"
                end,
                disabledTooltip = "Class Resource must be set to Modern",
                rawTooltip = true,
                getValue = SValSupportedRow("classPowerSpacing", 2),
                setValue = function(val)
                    SSetSupported("classPowerSpacing", val)
                    if mod.frames and mod.frames._toggleClassPower then
                        mod.frames._toggleClassPower()
                    end
                    UpdatePreview()
                    UpdatePreview()
                end,
            }, {
                type = "colorpicker",
                text = "Background Color",
                hasAlpha = true,
                disabled = function()
                    return SCPStyle() ~= "modern"
                end,
                disabledTooltip = "Class Resource must be set to Modern",
                rawTooltip = true,
                getValue = function()
                    local color = SGetSupported("classPowerBgColor")
                    color = color or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
                    return color.r, color.g, color.b, color.a
                end,
                setValue = function(red, green, blue, a)
                    SSetSupported("classPowerBgColor", { r = red, g = green, b = blue, a = a or 1 })
                    UpdatePreview()
                end,
            })
            cursorY = cursorY - height
            SApplySupport(sharedClassResRow3._leftRegion, "classPowerSpacing")
            SApplySupport(sharedClassResRow3._rightRegion, "classPowerBgColor")
            -- Sync icons: Bar Spacing (left) and Background Color (right)
            if not CludesUI._prebuilding then
                local region = sharedClassResRow3._leftRegion
                mod.UFO_UnitSync(region, "Class Resource Bar Spacing", {
                    key = "classPowerSpacing",
                    default = 2,
                    self = true,
                })
            end
            if not CludesUI._prebuilding then
                -- Unset draws black at half alpha, so it equals that colour set.
                local function Bg(c)
                    return c and c.r or 0, c and c.g or 0, c and c.b or 0, c and c.a or 0.5
                end
                mod.UFO_UnitSync(sharedClassResRow3._rightRegion, "Class Resource Background Color", {
                    self = true,
                    copy = function(t, from)
                        local color = from.classPowerBgColor
                        t.classPowerBgColor = color and { r = color.r, g = color.g, b = color.b, a = color.a } or nil
                    end,
                    same = function(t, from)
                        local r1, g1, b1, a1 = Bg(t.classPowerBgColor)
                        local r2, g2, b2, a2 = Bg(from.classPowerBgColor)
                        return r1 == r2 and g1 == g2 and b1 == b2 and a1 == a2
                    end,
                })
            end

            -- WoW Forever: where the "Blizzard" class resource (the combo point arc)
            -- shows -- the target frame (the stock spot), the player frame, or
            -- nowhere. The section's last row, built under the WoW Forever style for
            -- the classes with combo points there.
            if
                CludesUI.IS_FOREVER == true
                and CludesUI.BlizzStyle.Forever("unitframes")
                and mod.UF_ComboClass()
            then
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Combo Points",
                    tooltip = "Choose where your combo points show.",
                    values = { target = "Target Frame", player = "Player Frame", never = "Never" },
                    order = { "target", "player", "never" },
                    disabled = function()
                        return SCPStyle() ~= "blizzard"
                    end,
                    disabledTooltip = "Class Resource must be set to Blizzard",
                    rawTooltip = true,
                    getValue = function()
                        return mod.UF_ComboLocation()
                    end,
                    setValue = function(val)
                        UNIT_DB_MAP["player"]().foreverComboLocation = val
                        mod.UF_ApplyForeverComboArc()
                        -- Blizzard's own, beside Blizzard's own target frame, went
                        -- to the hidden parent for another spot: only a reload
                        -- brings it back.
                        if val == "target" and mod._ufComboFrameByLoc then
                            CludesUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = "Blizzard's combo points return to its target frame after a UI reload.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end
                    end,
                }, CludesUI.BlankRowCfg())
                cursorY = cursorY - height
            end
        end -- close Class Resource hidden-while-None gate
    end -- _showClassRes

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY, sharedClassResHeader, sharedClassResRow
end

function mod.UFO_BuildAbsorbsHealsSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local RegisterWidgetRefresh, ReloadAndUpdate = environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local UNIT_DB_MAP, UpdatePreview, saved, optionState =
        environ.UNIT_DB_MAP, environ.UpdatePreview, environ.db, environ.optState
    local W, SApplySupport, SGetSupported, SSetSupported =
        context.W, context.SApplySupport, context.SGetSupported, context.SSetSupported
    -- Row setters over SSetSupported: the key written with the row's value.
    local function SSetSupportedRow(settingKey)
        return function(value)
            SSetSupported(settingKey, value)
        end
    end
    local SValSupported = context.SValSupported
    -- A row getter over SValSupported: the key's value, or the default given.
    local function SValSupportedRow(settingKey, default)
        return function()
            return SValSupported(settingKey, default)
        end
    end
    local _, height

    -------------------------------------------------------------------
    --  ABSORBS (player/target/focus -- mirrors the Raid Frames section)
    -------------------------------------------------------------------
    -- Declared outside the gate: the click-mapping table at the bottom of
    -- this function references them (block-locals would be nil there).
    local sharedAbsorbsHeader, absorbRow, healAbsorbRow
    local _supportsAbsorbs = (
        optionState.selectedUnit == "player"
        or optionState.selectedUnit == "target"
        or optionState.selectedUnit == "focus"
    )
    if _supportsAbsorbs then
        sharedAbsorbsHeader, height = W:SectionHeader(hostFrame, "ABSORBS AND HEALS", cursorY)
        cursorY = cursorY - height

        -- Names and orders live on ns (CUI_UnitFrames_Absorb.lua, shared with the
        -- Textures page tile); fresh copies here because the SharedMedia tail
        -- below is appended into them. Shield (regular) absorb order; heal absorb
        -- uses its own (it adds the two "Outlined" variants on top).
        local absorbStyleValues = CopyTable(mod.ABSORB_STYLE_NAMES)
        local absorbStyleOrder = CopyTable(mod.ABSORB_STYLE_ORDER)
        local healAbsorbStyleOrder = CopyTable(mod.HEAL_ABSORB_STYLE_ORDER)
        -- Max Health Style: the Raid Frames list minus its raid-only art.
        absorbStyleValues.maxHealthStripes = "Max Health Stripes"
        local maxHealthStyleOrder = {
            "none",
            "maxHealthStripes",
            "striped",
            "stripedReversed",
            "stripedThick",
            "stripedThickR",
            "clean",
            "blizzard",
            "largeOutlinedStripes",
            "largeOutlinedStripesR",
            "largeStripes",
            "largeStripesR",
            "pixelsShield",
        }
        -- Append SharedMedia statusbar textures after a divider, mirroring the Bar
        -- Texture dropdown. SM keys ("sm:" prefixed) come from AppendSharedMediaTextures
        -- into the shared health-bar tables; render resolves via ns.ResolveAbsorbStyleTex
        -- -> the health-bar texture lookup. Shield and heal-absorb share absorbStyleValues, so both gain the SM entries and preview swatch.
        do
            CludesUI.AppendSharedMediaTextures(
                mod.healthBarTextureNames or {},
                mod.healthBarTextureOrder or {},
                nil,
                mod.healthBarTextures
            )
            local smNames = mod.healthBarTextureNames or {}
            local smKeys = {}
            for _, keyName in ipairs(mod.healthBarTextureOrder or {}) do
                if type(keyName) == "string" and keyName:find("^sm:") then
                    smKeys[#smKeys + 1] = keyName
                    absorbStyleValues[keyName] = smNames[keyName] or keyName
                end
            end
            if #smKeys > 0 then
                absorbStyleOrder[#absorbStyleOrder + 1] = "---"
                healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = "---"
                maxHealthStyleOrder[#maxHealthStyleOrder + 1] = "---"
                for _, keyName in ipairs(smKeys) do
                    absorbStyleOrder[#absorbStyleOrder + 1] = keyName
                    healAbsorbStyleOrder[#healAbsorbStyleOrder + 1] = keyName
                    maxHealthStyleOrder[#maxHealthStyleOrder + 1] = keyName
                end
            end
            -- Preview swatch behind each menu row, resolved exactly like render.
            absorbStyleValues._menuOpts = {
                itemHeight = 28,
                background = function(settingKey)
                    if not settingKey or settingKey == "---" or settingKey == "none" then
                        return nil
                    end
                    if settingKey == "maxHealthStripes" then
                        return CludesUI.MAX_HEALTH_STRIPES_TEX
                    end
                    return mod.ResolveAbsorbStyleTex and mod.ResolveAbsorbStyleTex(settingKey) or nil
                end,
            }
        end

        -- Effective absorb opacity: absorbOpacity once set, otherwise the
        -- pre-split behavior (clean -> absorbCleanAlpha, other styles 80).
        -- Must match GetAbsorbOpacity in CUI_UnitFrames_Absorb.lua.
        local function EffAbsorbOpacity()
            local val = SValSupported("absorbOpacity", nil)
            if val then
                return val
            end
            if SValSupported("showPlayerAbsorb", "none") == "clean" then
                return SValSupported("absorbCleanAlpha", 30)
            end
            return 80
        end

        -- Absorb Style / Heal Absorb Style sync icons carry style + swatch + every
        -- inline-cog setting together. Each entry is a DB key + default, so an unset
        -- value compares equal to an explicit one; color tables are deep-copied and compared by component.
        local ABSORB_SYNC_DEFS = {
            { k = "showPlayerAbsorb", d = "none" },
            { k = "absorbColor", d = { r = 1, g = 1, b = 1 } },
            { k = "absorbEdgeMode", d = "overlay" },
            { k = "showOvershield", d = true },
            { k = "overshieldMode" }, -- d nil on purpose: unset copies as unset (legacy-boolean fallback stays live)
            { k = "absorbGlowLine", d = false },
            { k = "absorbGlowLineTexture", d = "blizzard" },
        }
        local HEAL_ABSORB_SYNC_DEFS = {
            { k = "healAbsorbStyle", d = "clean" },
            { k = "healAbsorbColor", d = { r = 0.8, g = 0.15, b = 0.15 } },
            { k = "healAbsorbEdgeMode", d = "overlay" },
            { k = "healAbsorbBgOpacity", d = 15 },
        }
        local function _AbsSyncValEq(a, b)
            if type(a) == "table" or type(b) == "table" then
                a = a or {}
                b = b or {}
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end
            return a == b
        end
        -- The sync of an absorb setting group: each key of defs, unset reading
        -- as its default, colours copied as tables of their own.
        local function AbsorbSync(defs)
            local function Val(t, e)
                local value = t[e.k]
                if value == nil then
                    return e.d
                end
                return value
            end
            return {
                copy = function(t, from)
                    for _, entry in ipairs(defs) do
                        local value = Val(from, entry)
                        if type(value) == "table" then
                            value = { r = value.r, g = value.g, b = value.b, a = value.a }
                        end
                        t[entry.k] = value
                    end
                end,
                same = function(t, from)
                    for _, entry in ipairs(defs) do
                        if not _AbsSyncValEq(Val(from, entry), Val(t, entry)) then
                            return false
                        end
                    end
                    return true
                end,
            }
        end

        -- Row 1: Absorb Style (+ placement cog + color swatch) | Absorb Opacity
        absorbRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Absorb Style",
            values = absorbStyleValues,
            order = absorbStyleOrder,
            getValue = SValSupportedRow("showPlayerAbsorb", "none"),
            setValue = function(val)
                if val == "clean" then
                    UNIT_DB_MAP[optionState.selectedUnit]().absorbOpacity = 30
                else
                    UNIT_DB_MAP[optionState.selectedUnit]().absorbOpacity = 90
                end
                SSetSupported("showPlayerAbsorb", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Absorb Opacity",
            min = 5,
            max = 100,
            step = 1,
            disabled = function()
                return SValSupported("showPlayerAbsorb", "none") == "none"
            end,
            disabledTooltip = "Absorb Style",
            getValue = EffAbsorbOpacity,
            setValue = SSetSupportedRow("absorbOpacity"),
        })
        cursorY = cursorY - height
        SApplySupport(absorbRow._leftRegion, "showPlayerAbsorb")
        SApplySupport(absorbRow._rightRegion, "absorbOpacity")
        -- Inline cog: absorb placement (overlay / right edge / left edge)
        do
            local region = absorbRow._leftRegion
            -- Placement labels follow the FILL AXIS: saved values stay right/left (they
            -- mean the FAR/NEAR end of the fill), but wording flips to top/bottom on a
            -- vertical bar. MUTATED IN PLACE, never rebuilt: RefreshPage's fast path
            -- doesn't rebuild the page and the cog popup is built once then cached, so a
            -- fresh table would never reach it; _invalidateMenu forces the cached menu to reread this table on next click.
            local absorbEdgeLabels = {
                overlay = "Overlay",
                overlayReverse = "Overlay Reverse",
                overlayReverseFull = "Overlay Reverse (Full)",
            }
            local absorbEdgeLabelsVert -- last applied axis; nil until the first sync
            -- Returns true only if the axis flipped, so the caller can skip
            -- _invalidateMenu on unrelated refreshes (would break a wired-open click).
            local function SyncAbsorbEdgeLabels()
                local vert = (SValSupported("healthVerticalFill", false)) and true or false
                if absorbEdgeLabelsVert == vert then
                    return false
                end
                absorbEdgeLabelsVert = vert
                absorbEdgeLabels.right = vert and "From Top Edge" or "From Right Edge"
                absorbEdgeLabels.left = vert and "From Bottom Edge" or "From Left Edge"
                return true
            end
            SyncAbsorbEdgeLabels()
            local _, cogShow = CludesUI.BuildInlineCog(region, {
                title = "Absorb Rendering",
                rows = {
                    {
                        type = "dropdown",
                        label = "Placement",
                        values = absorbEdgeLabels,
                        -- Wide enough for "Overlay Reverse (Full)".
                        ddWidth = 190,
                        order = { "overlay", "overlayReverse", "overlayReverseFull", "right", "left" },
                        get = function()
                            SyncAbsorbEdgeLabels()
                            return SValSupported("absorbEdgeMode", "overlay")
                        end,
                        set = SSetSupportedRow("absorbEdgeMode"),
                    },
                    {
                        type = "dropdown",
                        label = "Show Overshield",
                        tooltip = "Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                        values = { never = "Never", always = "Always", fromleft = "From Left" },
                        order = { "never", "always", "fromleft" },
                        -- From Left only exists in the plain Overlay placement:
                        -- edge modes have no overshield, Overlay Reverse
                        -- already clamps the whole absorb inside the fill and
                        -- its Full variant draws the excess from the origin edge.
                        itemDisabled = function(val)
                            return val == "fromleft"
                                and SValSupported("absorbEdgeMode", "overlay") ~= "overlay"
                        end,
                        get = function()
                            -- Legacy boolean fallback: profiles saved before the
                            -- dropdown keep their toggle's meaning.
                            local m = SValSupported("overshieldMode", nil)
                            if m == nil then
                                m = (SValSupported("showOvershield", true) == false) and "never" or "always"
                            end
                            return m
                        end,
                        set = function(val)
                            -- Mirror the legacy boolean so pre-dropdown readers
                            -- (incl. the live-client profile) track Never/Always.
                            SSetSupported("showOvershield", val ~= "never")
                            SSetSupported("overshieldMode", val)
                        end,
                    },
                    -- Opt-in glow line on the shield's edge (runtime twin:
                    -- ns.UF_AbsorbGlowApply). Nothing is drawn with Absorb Style
                    -- None, on a vertical fill or with the placement on the edge
                    -- the health fills from.
                    {
                        type = "toggle",
                        label = "Blizzard Glow Line",
                        tooltip = "Adds the Blizzard shield glow line where the shield meets current health.",
                        disabled = function()
                            if SValSupported("showPlayerAbsorb", "none") == "none" then
                                return true
                            end
                            if SValSupported("healthVerticalFill", false) == true then
                                return true
                            end
                            local originEdge = (SValSupported("healthReverseFill", false) == true) and "right"
                                or "left"
                            return SValSupported("absorbEdgeMode", "overlay") == originEdge
                        end,
                        disabledTooltip = function()
                            if SValSupported("showPlayerAbsorb", "none") == "none" then
                                return "The glow line is not shown with Absorb Style None"
                            end
                            if
                                SValSupported("healthVerticalFill", false) ~= true
                                and SValSupported("healthReverseFill", false) == true
                            then
                                return "The glow line is not shown on a vertical fill or with the From Right Edge placement"
                            end
                            return "The glow line is not shown on a vertical fill or with the From Left Edge placement"
                        end,
                        rawTooltip = true,
                        get = function()
                            return SValSupported("absorbGlowLine", false) == true
                        end,
                        set = function(val)
                            SSetSupported("absorbGlowLine", val and true or false)
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Glow Line Texture",
                        tooltip = "Art used for the glow line and the overshield edge.",
                        values = {
                            blizzard = "Blizzard",
                            pixelsGlow = "Pixels Glow Line",
                            pixelsOvershield = "Pixels Overshield Line",
                        },
                        order = { "blizzard", "pixelsGlow", "pixelsOvershield" },
                        disabled = function()
                            return SValSupported("absorbGlowLine", false) ~= true
                        end,
                        disabledTooltip = "Blizzard Glow Line",
                        get = SValSupportedRow("absorbGlowLineTexture", "blizzard"),
                        set = SSetSupportedRow("absorbGlowLineTexture"),
                    },
                    -- Single global toggle (boss block key, nil = enabled):
                    -- boss frames render absorbs with the TARGET frame's
                    -- absorb styling -- no per-boss customization.
                    {
                        type = "toggle",
                        label = "Show on Boss Frames",
                        tooltip = "Render absorbs on Boss Frames using the Target frame's absorb styling.",
                        get = function()
                            return not (saved.profile.boss and saved.profile.boss.showAbsorbs == false)
                        end,
                        set = function(val)
                            local b = saved.profile.boss
                            if b then
                                if val then
                                    b.showAbsorbs = nil
                                else
                                    b.showAbsorbs = false
                                end
                            end
                            ReloadAndUpdate()
                        end,
                    },
                },
            })
            -- Re-label on every page refresh (the Vertical Fill toggle fires one) and
            -- drop any built menu so its entries rebuild with the new wording.
            RegisterWidgetRefresh(function()
                if not SyncAbsorbEdgeLabels() then
                    return
                end
                local popFrame = cogShow and cogShow._popupFrame
                if popFrame and popFrame.GetChildren then
                    for _, childFrame in ipairs({ popFrame:GetChildren() }) do
                        -- an idle child is a parked control of an earlier dress
                        -- (page reuse): its menu belongs to no row any more
                        if childFrame._invalidateMenu and not PoolIsIdle(childFrame) then
                            childFrame._invalidateMenu()
                        end
                    end
                end
            end)
        end
        -- Inline color swatch for absorb color
        if not CludesUI._prebuilding then
            local region = absorbRow._leftRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, absorbRow:GetFrameLevel() + 3, function()
                local color = SGetSupported("absorbColor")
                if color then
                    return color.r, color.g, color.b, 1
                end
                return 1, 1, 1, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().absorbColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local function UpdateAbsorbSwatchVis()
                colorSwatch:SetAlpha(SValSupported("showPlayerAbsorb", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
            UpdateAbsorbSwatchVis()
        end
        -- Sync icon: Absorb Style + color swatch + cog settings across all frames
        if not CludesUI._prebuilding then
            local region = absorbRow._leftRegion
            mod.UFO_UnitSync(region, "Absorb Style, color and rendering", AbsorbSync(ABSORB_SYNC_DEFS))
        end

        -- Row 2: Heal Absorb Style (+ placement cog + color swatch) | Heal Absorb Opacity
        healAbsorbRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Heal Absorb Style",
            values = absorbStyleValues,
            order = healAbsorbStyleOrder,
            getValue = SValSupportedRow("healAbsorbStyle", "clean"),
            setValue = function(val)
                if val == "clean" then
                    UNIT_DB_MAP[optionState.selectedUnit]().healAbsorbOpacity = 50
                else
                    UNIT_DB_MAP[optionState.selectedUnit]().healAbsorbOpacity = 75
                end
                SSetSupported("healAbsorbStyle", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Heal Absorb Opacity",
            min = 5,
            max = 100,
            step = 1,
            disabled = function()
                return SValSupported("healAbsorbStyle", "clean") == "none"
            end,
            disabledTooltip = "Heal Absorb Style",
            getValue = SValSupportedRow("healAbsorbOpacity", 65),
            setValue = SSetSupportedRow("healAbsorbOpacity"),
        })
        cursorY = cursorY - height
        SApplySupport(healAbsorbRow._leftRegion, "healAbsorbStyle")
        SApplySupport(healAbsorbRow._rightRegion, "healAbsorbOpacity")
        -- Inline eyeball: preview heal absorb on the live preview (hides the shield
        -- absorb there so heal absorb shows in isolation). Session-only runtime flag.
        if not CludesUI._prebuilding then
            local region = healAbsorbRow._leftRegion
            CludesUI.AddPreviewEye(region, optionState, "showHealAbsorbPreview", "heal absorb", UpdatePreview)
        end
        -- Inline cog: heal absorb placement (independent of shield absorb)
        do
            local region = healAbsorbRow._leftRegion
            -- Placement labels follow the FILL AXIS: saved values stay right/left (they
            -- mean the FAR/NEAR end of the fill), but wording flips to top/bottom on a
            -- vertical bar. MUTATED IN PLACE, never rebuilt: RefreshPage's fast path
            -- doesn't rebuild the page and the cog popup is built once then cached, so a
            -- fresh table would never reach it; _invalidateMenu forces the cached menu to reread this table on next click.
            local healAbsorbEdgeLabels = { overlay = "Overlay" }
            local healAbsorbEdgeLabelsVert -- last applied axis; nil until the first sync
            -- Returns true only if the axis flipped, so the caller can skip
            -- _invalidateMenu on unrelated refreshes (would break a wired-open click).
            local function SyncHealAbsorbEdgeLabels()
                local vert = (SValSupported("healthVerticalFill", false)) and true or false
                if healAbsorbEdgeLabelsVert == vert then
                    return false
                end
                healAbsorbEdgeLabelsVert = vert
                healAbsorbEdgeLabels.right = vert and "From Top Edge" or "From Right Edge"
                healAbsorbEdgeLabels.left = vert and "From Bottom Edge" or "From Left Edge"
                return true
            end
            SyncHealAbsorbEdgeLabels()
            local _, cogShow = CludesUI.BuildInlineCog(region, {
                title = "Heal Absorb Rendering",
                rows = {
                    {
                        type = "dropdown",
                        label = "Placement",
                        values = healAbsorbEdgeLabels,
                        order = { "overlay", "right", "left" },
                        get = function()
                            SyncHealAbsorbEdgeLabels()
                            return SValSupported("healAbsorbEdgeMode", "overlay")
                        end,
                        set = SSetSupportedRow("healAbsorbEdgeMode"),
                    },
                    {
                        type = "slider",
                        label = "Backing Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("healAbsorbBgOpacity", 15),
                        set = SSetSupportedRow("healAbsorbBgOpacity"),
                    },
                },
            })
            -- Re-label on every page refresh (the Vertical Fill toggle fires one) and
            -- drop any built menu so its entries rebuild with the new wording.
            RegisterWidgetRefresh(function()
                if not SyncHealAbsorbEdgeLabels() then
                    return
                end
                local popFrame = cogShow and cogShow._popupFrame
                if popFrame and popFrame.GetChildren then
                    for _, childFrame in ipairs({ popFrame:GetChildren() }) do
                        -- an idle child is a parked control of an earlier dress
                        -- (page reuse): its menu belongs to no row any more
                        if childFrame._invalidateMenu and not PoolIsIdle(childFrame) then
                            childFrame._invalidateMenu()
                        end
                    end
                end
            end)
        end
        -- Inline color swatch for heal absorb color
        if not CludesUI._prebuilding then
            local region = healAbsorbRow._leftRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, healAbsorbRow:GetFrameLevel() + 3, function()
                local color = SGetSupported("healAbsorbColor")
                if color then
                    return color.r or 0.8, color.g or 0.15, color.b or 0.15, 1
                end
                return 0.8, 0.15, 0.15, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().healAbsorbColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            -- Blocking overlay: disabled for "none" and the pre-colored
            -- "Large Outlined Stripes" heal styles (their texture is not tinted).
            local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
            swatchBlock:Hide()
            local function UpdateHealAbsorbSwatchVis()
                local state = SValSupported("healAbsorbStyle", "clean")
                local off = (state == "none" or state == "largeOutlinedStripes" or state == "largeOutlinedStripesR")
                colorSwatch:SetAlpha(off and 0.3 or 1)
                if off then
                    swatchBlock:Show()
                else
                    swatchBlock:Hide()
                end
            end
            RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
            UpdateHealAbsorbSwatchVis()
        end
        -- Sync icon: Heal Absorb Style + color swatch + cog settings across all frames
        if not CludesUI._prebuilding then
            local region = healAbsorbRow._leftRegion
            mod.UFO_UnitSync(region, "Heal Absorb Style, color and rendering", AbsorbSync(HEAL_ABSORB_SYNC_DEFS))
        end

        -- Row 3: Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
        local absorbBarRow
        absorbBarRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Absorb Bar",
            values = {
                none = "None",
                aboveRight = "Above Frame Right",
                aboveLeft = "Above Frame Left",
                topRight = "Top Right",
                topLeft = "Top Left",
                bottomRight = "Bottom Right",
                bottomLeft = "Bottom Left",
            },
            order = { "none", "aboveRight", "aboveLeft", "topRight", "topLeft", "bottomRight", "bottomLeft" },
            getValue = SValSupportedRow("absorbBarPosition", "none"),
            setValue = function(val)
                SSetSupported("absorbBarPosition", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Bar Height",
            min = 1,
            max = 20,
            step = 1,
            disabled = function()
                return SValSupported("absorbBarPosition", "none") == "none"
            end,
            disabledTooltip = "Absorb Bar",
            getValue = SValSupportedRow("absorbBarHeight", 4),
            setValue = SSetSupportedRow("absorbBarHeight"),
        })
        cursorY = cursorY - height
        SApplySupport(absorbBarRow._leftRegion, "absorbBarPosition")
        SApplySupport(absorbBarRow._rightRegion, "absorbBarHeight")
        if not CludesUI._prebuilding then
            local region = absorbBarRow._rightRegion
            local colorSwatch = CludesUI.BuildColorSwatch(region, absorbBarRow:GetFrameLevel() + 3, function()
                local color = SGetSupported("absorbBarColor")
                if color then
                    return color.r, color.g, color.b, color.a or 1
                end
                return 1, 1, 1, 1
            end, function(red, green, blue, a)
                UNIT_DB_MAP[optionState.selectedUnit]().absorbBarColor = { r = red, g = green, b = blue, a = a }
                ReloadAndUpdate()
                UpdatePreview()
            end, true, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local function UpdateAbsorbBarSwatchVis()
                colorSwatch:SetAlpha(SValSupported("absorbBarPosition", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
            UpdateAbsorbBarSwatchVis()
        end

        -- Row 4: Heal Absorb Bar (position dropdown) | Bar Height (+ alpha swatch)
        local healAbsorbBarRow
        healAbsorbBarRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Heal Absorb Bar",
            values = {
                none = "None",
                aboveAbsorb = "Above Absorb Bar",
                belowAbsorb = "Below Absorb Bar",
                aboveRight = "Above Frame Right",
                aboveLeft = "Above Frame Left",
                topRight = "Top Right",
                topLeft = "Top Left",
                bottomRight = "Bottom Right",
                bottomLeft = "Bottom Left",
            },
            order = {
                "none",
                "aboveAbsorb",
                "belowAbsorb",
                "aboveRight",
                "aboveLeft",
                "topRight",
                "topLeft",
                "bottomRight",
                "bottomLeft",
            },
            getValue = SValSupportedRow("healAbsorbBarPosition", "none"),
            setValue = function(val)
                SSetSupported("healAbsorbBarPosition", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Bar Height",
            min = 1,
            max = 20,
            step = 1,
            disabled = function()
                return SValSupported("healAbsorbBarPosition", "none") == "none"
            end,
            disabledTooltip = "Heal Absorb Bar",
            getValue = SValSupportedRow("healAbsorbBarHeight", 4),
            setValue = SSetSupportedRow("healAbsorbBarHeight"),
        })
        cursorY = cursorY - height
        SApplySupport(healAbsorbBarRow._leftRegion, "healAbsorbBarPosition")
        SApplySupport(healAbsorbBarRow._rightRegion, "healAbsorbBarHeight")
        if not CludesUI._prebuilding then
            local region = healAbsorbBarRow._rightRegion
            local colorSwatch = CludesUI.BuildColorSwatch(
                region,
                healAbsorbBarRow:GetFrameLevel() + 3,
                function()
                    local color = SGetSupported("healAbsorbBarColor")
                    if color then
                        return color.r, color.g, color.b, color.a or 1
                    end
                    return 200 / 255, 29 / 255, 29 / 255, 1
                end,
                function(red, green, blue, a)
                    UNIT_DB_MAP[optionState.selectedUnit]().healAbsorbBarColor =
                        { r = red, g = green, b = blue, a = a }
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
                true,
                20
            )
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local function UpdateHealAbsorbBarSwatchVis()
                colorSwatch:SetAlpha(SValSupported("healAbsorbBarPosition", "none") == "none" and 0.3 or 1)
            end
            RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
            UpdateHealAbsorbBarSwatchVis()
        end

        -- Max Health Style (+ eyeball, backing cog, swatch) | Max Health Opacity: Raid Frames
        -- parity; the overlay is always on the bar's far end. Boss frames use Target's.
        local maxHealthRow
        maxHealthRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Max Health Style",
            values = absorbStyleValues,
            order = maxHealthStyleOrder,
            getValue = SValSupportedRow("maxHealthStyle", "none"),
            setValue = function(val)
                SSetSupported("maxHealthStyle", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Max Health Opacity",
            min = 5,
            max = 100,
            step = 1,
            disabled = function()
                return SValSupported("maxHealthStyle", "none") == "none"
            end,
            disabledTooltip = "Max Health Style",
            getValue = SValSupportedRow("maxHealthOpacity", 100),
            setValue = SSetSupportedRow("maxHealthOpacity"),
        })
        cursorY = cursorY - height
        SApplySupport(maxHealthRow._leftRegion, "maxHealthStyle")
        SApplySupport(maxHealthRow._rightRegion, "maxHealthOpacity")
        -- Inline order as on the Heal Absorb row: the eyeball, the cog, then the swatch.
        if not CludesUI._prebuilding then
            local region = maxHealthRow._leftRegion
            -- Eyeball: shows a reduced maximum on the preview (session-only flag).
            CludesUI.AddPreviewEye(region, optionState, "showMaxHealthPreview", "max health", UpdatePreview)
            CludesUI.BuildInlineCog(region, {
                title = "Max Health Rendering",
                disabled = function()
                    return SValSupported("maxHealthStyle", "none") == "none"
                end,
                disabledTooltip = "Max Health Style",
                rows = {
                    {
                        type = "slider",
                        label = "Backing Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("maxHealthBgOpacity", 100),
                        set = SSetSupportedRow("maxHealthBgOpacity"),
                    },
                },
            })
            -- Swatch tints the texture; blocked for None and the pre-colored styles.
            local colorSwatch = CludesUI.BuildColorSwatch(region, maxHealthRow:GetFrameLevel() + 3, function()
                local color = SGetSupported("maxHealthColor")
                if color then
                    return color.r or 0.7, color.g or 0.1, color.b or 0.1, 1
                end
                return 0.7, 0.1, 0.1, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().maxHealthColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
            swatchBlock:Hide()
            local function UpdateMaxHealthSwatchVis()
                local state = SValSupported("maxHealthStyle", "none")
                local off = (state == "none" or state == "largeOutlinedStripes" or state == "largeOutlinedStripesR")
                colorSwatch:SetAlpha(off and 0.3 or 1)
                swatchBlock:SetShown(off)
            end
            RegisterWidgetRefresh(UpdateMaxHealthSwatchVis)
            UpdateMaxHealthSwatchVis()
        end

        -- Row 5: Heal Prediction (+ your / others' color swatches) | Prediction Opacity
        local healPredRow
        healPredRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Heal Prediction",
            tooltip = "Shows incoming heals past the health bar: yours, then other players'.",
            getValue = function()
                return SValSupported("healPrediction", false) == true
            end,
            setValue = function(val)
                SSetSupported("healPrediction", val)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Prediction Opacity",
            min = 5,
            max = 100,
            step = 1,
            disabled = function()
                return SValSupported("healPrediction", false) ~= true
            end,
            disabledTooltip = "Heal Prediction",
            getValue = SValSupportedRow("healPredOpacity", 60),
            setValue = SSetSupportedRow("healPredOpacity"),
        })
        cursorY = cursorY - height
        SApplySupport(healPredRow._leftRegion, "healPrediction")
        SApplySupport(healPredRow._rightRegion, "healPredOpacity")
        -- Inline eyeball: preview heal prediction on the live preview. Session-only.
        if not CludesUI._prebuilding then
            local region = healPredRow._leftRegion
            CludesUI.AddPreviewEye(region, mod, "_ufShowHealPredPreview", "heal prediction", UpdatePreview)
        end
        if not CludesUI._prebuilding then
            local region = healPredRow._leftRegion
            local function PredSwatch(settingKey, default, tipText)
                local colorSwatch = CludesUI.BuildColorSwatch(region, healPredRow:GetFrameLevel() + 3, function()
                    local c = SGetSupported(settingKey) or default
                    return c.r, c.g, c.b, 1
                end, function(red, green, blue)
                    UNIT_DB_MAP[optionState.selectedUnit]()[settingKey] = { r = red, g = green, b = blue }
                    ReloadAndUpdate()
                    UpdatePreview()
                end, false, 20)
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = colorSwatch
                colorSwatch:HookScript("OnEnter", function(sw)
                    CludesUI.ShowWidgetTooltip(sw, tipText)
                end)
                colorSwatch:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateVis()
                    colorSwatch:SetAlpha(SValSupported("healPrediction", false) == true and 1 or 0.3)
                end
                RegisterWidgetRefresh(UpdateVis)
                UpdateVis()
            end
            -- Each swatch lands left of the last, so build others' first: reads yours, others'.
            PredSwatch(
                "healPredOtherColor",
                mod.UF_HEAL_PRED_OTHER or { r = 40 / 255, g = 170 / 255, b = 40 / 255 },
                "Other players' heals"
            )
            PredSwatch(
                "healPredColor",
                mod.UF_HEAL_PRED_MY or { r = 102 / 255, g = 243 / 255, b = 102 / 255 },
                "Your heals"
            )
        end
        -- Row 6: Overheal (how far heal prediction may run past the bar's end) | Texture
        -- (Health Bar follows the frame's own health texture; no absorb stripes:
        -- stripes read as absorbs on these frames).
        local healPredTexValues = { health = "Health Bar", flat = "Flat" }
        local healPredTexOrder = { "health", "flat", "---" }
        for _, keyName in ipairs(mod.healthBarTextureOrder or {}) do
            if keyName ~= "none" and keyName ~= "---" and not healPredTexValues[keyName] then
                healPredTexValues[keyName] = (mod.healthBarTextureNames and mod.healthBarTextureNames[keyName]) or keyName
                healPredTexOrder[#healPredTexOrder + 1] = keyName
            end
        end
        healPredTexValues._menuOpts = {
            itemHeight = 28,
            background = function(settingKey)
                if not settingKey or settingKey == "---" or settingKey == "health" then
                    return nil
                end
                if settingKey == "flat" then
                    return "Interface\\Buttons\\WHITE8X8"
                end
                return CludesUI.ResolveTexturePath(mod.healthBarTextures, settingKey, nil)
            end,
        }
        local overhealRow
        overhealRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Overheal",
            min = 0,
            max = 50,
            step = 1,
            tooltip = "How far incoming heals can extend past the end of the health bar, as a percent of its length. 0 keeps them inside the bar.",
            disabled = function()
                return SValSupported("healPrediction", false) ~= true
            end,
            disabledTooltip = "Heal Prediction",
            getValue = SValSupportedRow("healPredOverheal", 0),
            setValue = SSetSupportedRow("healPredOverheal"),
        }, {
            type = "dropdown",
            text = "Heal Prediction Texture",
            values = healPredTexValues,
            order = healPredTexOrder,
            disabled = function()
                return SValSupported("healPrediction", false) ~= true
            end,
            disabledTooltip = "Heal Prediction",
            getValue = SValSupportedRow("healPredTexture", "health"),
            setValue = function(val)
                SSetSupported("healPredTexture", val)
                UpdatePreview()
            end,
        })
        cursorY = cursorY - height
        SApplySupport(overhealRow._leftRegion, "healPredOverheal")
        SApplySupport(overhealRow._rightRegion, "healPredTexture")

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
    end -- _supportsAbsorbs

    return cursorY, sharedAbsorbsHeader, absorbRow, healAbsorbRow
end
