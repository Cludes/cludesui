if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\PowerSection_Options.lua
--  Resource Bars options: POWER BAR section builder. Definitions only; the shared
--  helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIResourceBars"]
if not mod then
    return
end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- Shared, context-aware POWER section builder; mirrors the health one. ctx.cfg() -> power table (DB().primary Simple, per-spec override Advanced).
function mod.ERB_BuildPowerSection(hostFrame, cursorY, context)
    local environ = mod._CURB_OptEnv
    local DB, Pix, Refresh, SmoothRefresh = environ.DB, environ.PP, environ.Refresh, environ.SmoothRefresh
    local RefreshPower, RebuildPower, AddFormBarBtn, AddFormTextBtn =
        environ.RefreshPower, environ.RebuildPower, environ.AddFormBarBtn, environ.AddFormTextBtn
    local BuildHashCog, BuildThresholdSettingsButton =
        environ.BuildHashCog, environ.BuildThresholdSettingsButton
    local W = CludesUI.Widgets
    local _, height
    local function rowConf()
        return context.cfg()
    end
    -- A row's getter and setter for one key of this section's settings: the
    -- getter gives its value, or default when unset (no default: the value as
    -- stored); the setter writes it when the settings exist, then runs after
    -- and, with alsoPage, rebuilds the page.
    local function ConfGetter(key, default)
        return function()
            local rowCfg = rowConf()
            if default == nil then
                return rowCfg and rowCfg[key]
            end
            return rowCfg and rowCfg[key] or default
        end
    end
    local function ConfSetter(key, after, alsoPage)
        return function(val)
            local rowCfg = rowConf()
            if not rowCfg then
                return
            end
            rowCfg[key] = val
            after()
            if alsoPage then
                CludesUI:RefreshPage()
            end
        end
    end
    local function powerOff()
        local rowCfg = rowConf()
        return not (rowCfg and rowCfg.enabled)
    end
    local powerDisTip = "Power Bar"

    local heading
    heading, height = W:SectionHeader(hostFrame, "POWER BAR", cursorY)
    cursorY = cursorY - height
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "ERB_Power", disabled = powerOff, disabledTooltip = powerDisTip }
    )

    local _advTop = cursorY -- content top; also used by the Simple override overlay
    -- Row 1: Show Power Bar | Orientation
    local powerEnableRow
    powerEnableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Power Bar",
        getValue = ConfGetter("enabled"),
        -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
        setValue = CludesUI.DependentSetValue(function()
            local rowCfg = rowConf()
            return rowCfg and rowCfg.enabled
        end, function(val)
            local rowCfg = rowConf()
            if not rowCfg then
                return
            end
            rowCfg.enabled = val
            RebuildPower()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "dropdown",
        text = "Orientation",
        disabled = powerOff,
        disabledTooltip = powerDisTip,
        values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
        order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
        getValue = function()
            local rowCfg = rowConf()
            local profile = DB()
            return (rowCfg and rowCfg.orientation) or (profile and profile.general.orientation) or "HORIZONTAL"
        end,
        setValue = ConfSetter("orientation", Refresh),
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        AddFormBarBtn(powerEnableRow._leftRegion, rowConf, RebuildPower)
    end

    -- Per-spec power enables live in Spec Overrides: "Show Power Bar" is captured while editing as a group.

    -- Everything below Row 1 is hidden entirely while the bar is off.
    if not powerOff() then
        -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only). Orientation-aware, as on the health bar above.
        local function powerOri()
            local c, p = rowConf(), DB()
            return (c and c.orientation) or (p and p.general and p.general.orientation)
        end
        local function guard(propKey)
            return mod.OrientedMatchGuard("ERB_Power", propKey, powerOri, powerOff, powerDisTip)
        end
        local phDis, phTip, phRaw = guard("Height")
        local pwDis, pwTip, pwRaw = guard("Width")
        local powerSizeRow
        powerSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Height",
            min = 1,
            max = 100,
            step = 1,
            disabled = phDis,
            disabledTooltip = phTip,
            rawTooltip = phRaw,
            getValue = ConfGetter("height", 16),
            setValue = ConfSetter("height", SmoothRefresh, true),
        }, {
            type = "slider",
            text = "Width",
            min = 50,
            max = 800,
            step = 1,
            disabled = pwDis,
            disabledTooltip = pwTip,
            rawTooltip = pwRaw,
            getValue = ConfGetter("width", 220),
            setValue = ConfSetter("width", SmoothRefresh, true),
        })
        cursorY = cursorY - height
        if not context.advanced and context.syncRows then
            context.syncRows.powerHeight = powerSizeRow._leftRegion
            context.syncRows.powerWidth = powerSizeRow._rightRegion
            if not CludesUI._prebuilding then
                local region = powerSizeRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Height to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local val = profile.primary.height or 16
                        profile.secondary.pipHeight = val
                        profile.health.height = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local val = profile.primary.height or 16
                        return (profile.secondary.pipHeight or 20) == val and (profile.health.height or 20) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.powerHeight,
                            context.syncRows.classHeight,
                            context.syncRows.healthHeight,
                        }
                    end,
                })
            end
            if not CludesUI._prebuilding then
                local region = powerSizeRow._rightRegion
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Width to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local val = profile.primary.width or 220
                        profile.secondary.pipWidth = val
                        profile.health.width = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local val = profile.primary.width or 220
                        return (profile.secondary.pipWidth or 214) == val and (profile.health.width or 220) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.powerWidth,
                            context.syncRows.classWidth,
                            context.syncRows.healthWidth,
                        }
                    end,
                })
            end
        end

        -- Power Border Style dropdown + inline offset cog
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local pwrBsRow
            pwrBsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("resourcebars", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = powerOff,
                    disabledTooltip = powerDisTip,
                    values = texValues,
                    order = texOrder,
                    getValue = ConfGetter("borderTexture", "solid"),
                    setValue = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.borderTexture = val
                        rowCfg.borderTextureOffset = nil
                        rowCfg.borderTextureOffsetY = nil
                        rowCfg.borderTextureShiftX = nil
                        rowCfg.borderTextureShiftY = nil
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                        rowCfg.borderR = _bcol.r
                        rowCfg.borderG = _bcol.g
                        rowCfg.borderB = _bcol.b
                        rowCfg.borderA = 1
                        rowCfg.borderBehind = _bbehind
                        local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                        if defSz then
                            rowCfg.borderSize = defSz
                        end
                        if rowCfg.borderSizePx then
                            rowCfg.borderSizePx = false
                        end
                        RebuildPower()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                mod.ERB_ClassicBorderRow()
                        and mod.ERB_ClassicBorderSizeCfg(
                            rowConf,
                            powerOff,
                            powerDisTip,
                            RebuildPower,
                            "ERB_Power"
                        )
                    or CludesUI.BlizzStyle.Gate(
                        "resourcebars",
                        CludesUI.BorderPxSliderCfg({
                            text = "Border Size",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            getStep = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.borderSize or 1
                            end,
                            setStep = function(val)
                                local rowCfg = rowConf()
                                if rowCfg then
                                    rowCfg.borderSize = val
                                end
                            end,
                            getTex = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.borderTexture or "solid"
                            end,
                            getPx = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.borderSizePx
                            end,
                            setPx = function(val)
                                local rowCfg = rowConf()
                                if rowCfg then
                                    rowCfg.borderSizePx = val
                                end
                            end,
                            apply = function()
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        })
                    )
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
            do
                local rowCfg = rowConf()
                local texture = rowCfg and rowCfg.borderTexture or "solid"
                if texture ~= "solid" and texture ~= "" then
                    local function step()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg.borderSize or 1
                    end
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "resourcebars",
                        disabled = powerOff,
                        disabledTooltip = powerDisTip,
                        getTex = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.borderTexture or "solid"
                        end,
                        getStep = step,
                        getSizeKey = step,
                        getPx = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.borderSizePx
                        end,
                        getX = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.borderTextureOffset
                        end,
                        setX = function(val)
                            local rowCfg = rowConf()
                            if rowCfg then
                                rowCfg.borderTextureOffset = val
                            end
                        end,
                        getY = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.borderTextureOffsetY
                        end,
                        setY = function(val)
                            local rowCfg = rowConf()
                            if rowCfg then
                                rowCfg.borderTextureOffsetY = val
                            end
                        end,
                        apply = function()
                            RebuildPower()
                            CludesUI:RefreshPage()
                        end,
                    })
                    _, height = W:DualRow(
                        hostFrame,
                        cursorY,
                        CludesUI.BlizzStyle.Gate("resourcebars", ocfgL),
                        CludesUI.BlizzStyle.Gate("resourcebars", ocfgR)
                    )
                    cursorY = cursorY - height
                end
            end
            if not CludesUI._prebuilding and not mod.ERB_ClassicBorderRow() then
                local region = pwrBsRow._rightRegion
                local control = region._control
                -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
                -- border size control. The stock styles keep the bars square.
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(pwrBsRow._rightRegion, {
                        title = "Corner Radius",
                        tip = "Corner Radius",
                        disabled = function()
                            if powerOff() or CludesUI.BlizzStyle.Get("resourcebars") then
                                return true
                            end
                            local rowCfg = rowConf()
                            return not CludesUI.RoundedStyleOK(rowCfg and rowCfg.borderTexture)
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("resourcebars") then
                                return CludesUI.BlizzStyle.Label("resourcebars")
                            end
                            if powerOff() then
                                return powerDisTip
                            end
                            return "This option requires the Solid, Glow or Shadow border style."
                        end,
                        requireState = function()
                            return CludesUI.BlizzStyle.Get("resourcebars") and "disabled" or "enabled"
                        end,
                        rows = CludesUI.RoundedCornerRows({
                            {
                                type = "slider",
                                label = "Corner Radius",
                                min = 0,
                                max = CludesUI.ROUNDED_MAX_RADIUS,
                                step = 1,
                                get = ConfGetter("cornerRadius", 0),
                                set = ConfSetter("cornerRadius", RebuildPower),
                            },
                        }, function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.cornerMask
                        end, function(val)
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return
                            end
                            rowCfg.cornerMask = val
                            RebuildPower()
                        end),
                    })
                end
                local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                    region,
                    pwrBsRow:GetFrameLevel() + 3,
                    function()
                        local rowCfg = rowConf()
                        return (rowCfg and rowCfg.borderR or 0),
                            (rowCfg and rowCfg.borderG or 0),
                            (rowCfg and rowCfg.borderB or 0),
                            (rowCfg and rowCfg.borderA or 1)
                    end,
                    function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.borderR, rowCfg.borderG, rowCfg.borderB, rowCfg.borderA = red, green, blue, a
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    true,
                    20
                )
                Pix.Point(borderSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
                region._lastInline = borderSwatch -- left of the Corner Radius cog
                CludesUI.RegisterWidgetRefresh(function()
                    updateBorderSwatch()
                end)
                local swBlock = CludesUI.NewSwatchBlocker(borderSwatch)
                swBlock:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(borderSwatch, CludesUI.DisabledTooltip(powerDisTip))
                end)
                swBlock:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateBorderSwDis()
                    if powerOff() then
                        borderSwatch:SetAlpha(0.3)
                        swBlock:Show()
                    else
                        borderSwatch:SetAlpha(1)
                        swBlock:Hide()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateBorderSwDis)
                UpdateBorderSwDis()
            end
            if not CludesUI._prebuilding then
                local region = pwrBsRow._leftRegion
                local sepValues, sepOrder = mod.ERB_SeparatorArtValues(true)
                local cogBtn = CludesUI.BuildInlineCog(region, {
                    title = "Border Options",
                    rows = {
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return 0
                                end
                                local val = rowCfg.borderTextureShiftX
                                if val then
                                    return val
                                end
                                local _, _, dsx = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    rowCfg.borderTexture or "solid",
                                    rowCfg.borderSize or 1
                                )
                                return dsx
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.borderTextureShiftX = val == 0 and nil or val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return 0
                                end
                                local val = rowCfg.borderTextureShiftY
                                if val then
                                    return val
                                end
                                local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    rowCfg.borderTexture or "solid",
                                    rowCfg.borderSize or 1
                                )
                                return dsy
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.borderTextureShiftY = val == 0 and nil or val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = ConfGetter("borderBehind", false),
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.borderBehind = val == false and nil or val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        -- Draw Above GCD Bar: this border over a GCD bar that overlaps the power
                        -- bar (ns.ERB_PowerLift). Kept out of the Border Style syncs. Show
                        -- Behind keeps the border under its own fill, so it greys this out.
                        {
                            type = "toggle",
                            label = "Draw Above GCD Bar",
                            tooltip = "Draws the power bar's border above the GCD bar where the two overlap.",
                            disabled = function()
                                local p, c = DB(), rowConf()
                                return (powerOff() or not (p and p.gcdBar.enabled) or (c and c.borderBehind))
                                        and true
                                    or false
                            end,
                            disabledTooltip = function()
                                if powerOff() then
                                    return powerDisTip
                                end
                                local profile = DB()
                                if not (profile and profile.gcdBar.enabled) then
                                    return "GCD Bar"
                                end
                                return "This option can't be used while Show Behind is enabled."
                            end,
                            rawTooltip = function()
                                local profile = DB()
                                return not powerOff() and (profile and profile.gcdBar.enabled) and true or false
                            end,
                            get = ConfGetter("borderAboveGCD", false),
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.borderAboveGCD = val and true or false
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        -- Border extensions: 0 = off, stored explicitly (mirror sync
                        -- never carries a nil). Screen axes, so a vertical bar too.
                        {
                            type = "slider",
                            label = "Extend Top",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            get = ConfGetter("borderExtendTop", 0),
                            set = ConfSetter("borderExtendTop", RebuildPower, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Bottom",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            get = ConfGetter("borderExtendBottom", 0),
                            set = ConfSetter("borderExtendBottom", RebuildPower, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Left",
                            min = 0,
                            max = 300,
                            step = 1,
                            tooltip = "Grows the border past the bar's left edge on screen without resizing the bar.",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            get = ConfGetter("borderExtendLeft", 0),
                            set = ConfSetter("borderExtendLeft", RebuildPower, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Right",
                            min = 0,
                            max = 300,
                            step = 1,
                            tooltip = "Grows the border past the bar's right edge on screen without resizing the bar.",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            get = ConfGetter("borderExtendRight", 0),
                            set = ConfSetter("borderExtendRight", RebuildPower, true),
                        },
                        -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                        -- on with that art (edgeSepArt). Out of the Border Style syncs.
                        {
                            type = "dropdown",
                            label = "Bottom Separator",
                            values = sepValues,
                            order = sepOrder,
                            tooltip = "Draws a separator line along the bar's bottom edge.",
                            disabled = powerOff,
                            disabledTooltip = powerDisTip,
                            get = function()
                                local rowCfg = rowConf()
                                if not (rowCfg and rowCfg.edgeSep) then
                                    return "none"
                                end
                                return rowCfg.edgeSepArt or "match"
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                if val == "none" then
                                    rowCfg.edgeSep = false
                                else
                                    rowCfg.edgeSep = true
                                    rowCfg.edgeSepArt = val
                                end
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Separator Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            disabled = function()
                                local rowCfg = rowConf()
                                return powerOff() or not (rowCfg and rowCfg.edgeSep)
                            end,
                            disabledTooltip = function()
                                return powerOff() and powerDisTip or "Bottom Separator"
                            end,
                            get = ConfGetter("edgeSepY", 0),
                            set = ConfSetter("edgeSepY", RebuildPower, true),
                        },
                    },
                })
                local function UpdateCogVis()
                    local rowCfg = rowConf()
                    local texture = rowCfg and rowCfg.borderTexture or "solid"
                    if texture == "solid" or mod.ERB_ClassicBorderRow() then
                        cogBtn:Hide()
                    else
                        cogBtn:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            if
                not context.advanced
                and context.syncRows
                and not CludesUI._prebuilding
                and mod.ERB_ClassicBorderRow()
            then
                context.syncRows.powerBorder = pwrBsRow._rightRegion
                mod.ERB_ClassicBorderSync(pwrBsRow._rightRegion, DB, "primary", SmoothRefresh, function()
                    return {
                        context.syncRows.powerBorder,
                        context.syncRows.classBorder,
                        context.syncRows.healthBorder,
                    }
                end)
            elseif not context.advanced and context.syncRows and not CludesUI._prebuilding then
                context.syncRows.powerBorder = pwrBsRow._rightRegion
                CludesUI.BuildSyncIcon({
                    region = pwrBsRow._leftRegion,
                    tooltip = "Apply Border Style to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local was = mod.ERB_TexturedBars(profile)
                        local s = profile.primary
                        local function apply(t)
                            t.borderTexture = s.borderTexture
                            t.borderTextureOffset = s.borderTextureOffset
                            t.borderTextureOffsetY = s.borderTextureOffsetY
                            t.borderTextureShiftX = s.borderTextureShiftX
                            t.borderTextureShiftY = s.borderTextureShiftY
                            t.borderR = s.borderR
                            t.borderG = s.borderG
                            t.borderB = s.borderB
                            t.borderA = s.borderA
                            t.borderSize = s.borderSize
                            mod.ERB_CopyBorderPx(t, s)
                            t.borderBehind = s.borderBehind
                        end
                        apply(profile.secondary)
                        apply(profile.health)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local bt = profile.primary.borderTexture or "solid"
                        local bh = profile.primary.borderBehind or false
                        return (profile.secondary.borderTexture or "solid") == bt
                            and (profile.health.borderTexture or "solid") == bt
                            and (profile.secondary.borderBehind or false) == bh
                            and (profile.health.borderBehind or false) == bh
                    end,
                    flashTargets = function()
                        return { pwrBsRow._leftRegion }
                    end,
                })
                CludesUI.BuildSyncIcon({
                    region = pwrBsRow._rightRegion,
                    tooltip = "Apply Border to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local was = mod.ERB_TexturedBars(profile)
                        local red, green, blue, a =
                            profile.primary.borderR, profile.primary.borderG, profile.primary.borderB, profile.primary.borderA
                        local sz = profile.primary.borderSize or 1
                        local bt = profile.primary.borderTexture or "solid"
                        local cr, cm = profile.primary.cornerRadius or 0, profile.primary.cornerMask
                        profile.secondary.borderR, profile.secondary.borderG, profile.secondary.borderB, profile.secondary.borderA =
                            red, green, blue, a
                        profile.secondary.borderSize = sz
                        profile.secondary.borderTexture = bt
                        profile.secondary.cornerRadius = cr
                        profile.secondary.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.secondary, profile.primary)
                        profile.health.borderR, profile.health.borderG, profile.health.borderB, profile.health.borderA = red, green, blue, a
                        profile.health.borderSize = sz
                        profile.health.borderTexture = bt
                        profile.health.cornerRadius = cr
                        profile.health.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.health, profile.primary)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local sr, sg, scrollBar, sa, ssz =
                            profile.primary.borderR,
                            profile.primary.borderG,
                            profile.primary.borderB,
                            profile.primary.borderA,
                            profile.primary.borderSize or 1
                        local sbt, scr, scm =
                            profile.primary.borderTexture or "solid",
                            profile.primary.cornerRadius or 0,
                            profile.primary.cornerMask or 15
                        local function eq(t)
                            return t.borderR == sr
                                and t.borderG == sg
                                and t.borderB == scrollBar
                                and t.borderA == sa
                                and (t.borderSize or 1) == ssz
                                and (t.borderTexture or "solid") == sbt
                                and (t.cornerRadius or 0) == scr
                                and (t.cornerMask or 15) == scm
                                and mod.ERB_SameBorderPx(t, profile.primary)
                        end
                        return eq(profile.secondary) and eq(profile.health)
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.powerBorder,
                            context.syncRows.classBorder,
                            context.syncRows.healthBorder,
                        }
                    end,
                })
            end
        end

        -- Row 4: Opacity | Fill Color (gradient/custom/power-colored)
        local powerBorderRow
        powerBorderRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 5,
            disabled = powerOff,
            disabledTooltip = powerDisTip,
            getValue = function()
                local rowCfg = rowConf()
                return math.floor((rowCfg and rowCfg.barAlpha or 1) * 100 + 0.5)
            end,
            setValue = function(val)
                local rowCfg = rowConf()
                if not rowCfg then
                    return
                end
                rowCfg.barAlpha = val / 100
                RefreshPower()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
            disabled = powerOff,
            disabledTooltip = powerDisTip,
            getValue = function()
                local rowCfg = rowConf()
                return (rowCfg and rowCfg.fillOpacity) or 100
            end,
            setValue = ConfSetter("fillOpacity", RebuildPower),
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = powerBorderRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = powerDisTip,
                title = "Fill Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Enable Gradient",
                        get = ConfGetter("gradientEnabled"),
                        set = ConfSetter("gradientEnabled", RebuildPower, true),
                    },
                    {
                        type = "dropdown",
                        label = "Gradient Direction",
                        values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                        order = { "HORIZONTAL", "VERTICAL" },
                        get = ConfGetter("gradientDir", "HORIZONTAL"),
                        set = ConfSetter("gradientDir", RebuildPower),
                    },
                },
            })
        end
        -- Fill Color inline swatches: gradient end / custom / power
        if not CludesUI._prebuilding then
            -- Spender Colors paint the fill flat once a row names a spell, as the bar does
            -- (unless they recolor the text instead).
            local function SpendersFlatten(c, tse)
                if not (tse and tse.spenderColorEnabled) then
                    return false
                end
                if tse.thresholdTextInstead and c.textFormat ~= "none" then
                    return false
                end
                local entries = tse.spenderColors
                if entries then
                    for idx = 1, #entries do
                        if entries[idx].spellID then
                            return true
                        end
                    end
                end
                return false
            end
            CludesUI.BuildInlineSwatches(powerBorderRow._rightRegion, {
                {
                    tooltip = "Gradient End Color",
                    hasAlpha = true,
                    disabled = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return true
                        end
                        if not rowCfg.enabled then
                            return true
                        end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(rowCfg)
                        if tse and (tse.thresholdEnabled ~= false) then
                            return true
                        end
                        if SpendersFlatten(rowCfg, tse) then
                            return true
                        end
                        return not rowCfg.gradientEnabled
                    end,
                    disabledTooltip = function()
                        local rowCfg = rowConf()
                        if not rowCfg or not rowCfg.enabled then
                            return powerDisTip
                        end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(rowCfg)
                        if tse and (tse.thresholdEnabled ~= false) then
                            return "This option requires the threshold to be off in Threshold & Hash Lines"
                        end
                        if SpendersFlatten(rowCfg, tse) then
                            return "This option requires Spender Colors to be disabled"
                        end
                        return "Gradient"
                    end,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return 0.20, 0.20, 0.80, 1
                        end
                        return rowCfg.gradientR, rowCfg.gradientG, rowCfg.gradientB, rowCfg.gradientA
                    end,
                    setValue = function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.gradientR, rowCfg.gradientG, rowCfg.gradientB, rowCfg.gradientA = red, green, blue, a
                        SmoothRefresh()
                    end,
                },
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return 0x23 / 255, 0x8F / 255, 0xE7 / 255, 1
                        end
                        return rowCfg.fillR, rowCfg.fillG, rowCfg.fillB, 1
                    end,
                    setValue = function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.fillR, rowCfg.fillG, rowCfg.fillB = red, green, blue
                        RebuildPower()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        if not rowCfg.customColored then
                            rowCfg.customColored = true
                            RebuildPower()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isPowerColored = not rowCfg or not rowCfg.customColored
                        return isPowerColored and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Power Colored",
                    getValue = function()
                        -- gpp() is nil for specs with no primary power (BM/MM
                        -- hunter: Focus is the class resource bar) -- fall to
                        -- the default swatch color rather than index with nil.
                        local gpp = _G._CURB_GetPrimaryPowerType
                        local pt = gpp and gpp()
                        local pc = pt and _G._CURB_PowerColors and _G._CURB_PowerColors[pt]
                        if pc then
                            return pc[1], pc[2], pc[3], 1
                        end
                        return 0x23 / 255, 0x8F / 255, 0xE7 / 255, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.customColored = false
                        RebuildPower()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isPowerColored = not rowCfg or not rowCfg.customColored
                        return isPowerColored and 1 or 0.3
                    end,
                },
            }, { size = 20, disabled = powerOff, disabledTooltip = powerDisTip })
        end
        if not context.advanced and context.syncRows and not CludesUI._prebuilding then
            context.syncRows.powerOpacity = powerBorderRow._leftRegion
            local region = powerBorderRow._leftRegion
            CludesUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local profile = DB()
                    if not profile then
                        return
                    end
                    local val = profile.primary.barAlpha or 1
                    profile.secondary.barAlpha = val
                    profile.health.barAlpha = val
                    SmoothRefresh()
                    CludesUI:RefreshPage()
                end,
                isSynced = function()
                    local profile = DB()
                    if not profile then
                        return false
                    end
                    local val = profile.primary.barAlpha or 1
                    return (profile.secondary.barAlpha or 1) == val and (profile.health.barAlpha or 1) == val
                end,
                flashTargets = function()
                    return {
                        context.syncRows.powerOpacity,
                        context.syncRows.classOpacity,
                        context.syncRows.healthOpacity,
                    }
                end,
            })
        end

        -- Out of Combat Opacity & Visibility cog: Fade Out of Combat dims the Power bar to this alpha out of combat (100 = no fade; ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat). Show When Energy / Focus / Mana Missing show the bar at its normal opacity while that resource is below full, a rule-hidden bar and a faded one alike (ns.ERB_MissingWanted / ns.ERB_MissingLiftFloor, same pass); Mana also covers a WoW Forever druid's Mana Bar while Shapeshifted.
        if not CludesUI._prebuilding then
            local region = powerBorderRow._leftRegion
            local rowList = {
                {
                    type = "toggle",
                    label = "Fade Out of Combat",
                    get = function()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg.oocFadeEnabled == true
                    end,
                    set = ConfSetter("oocFadeEnabled", RefreshPower),
                },
                {
                    type = "slider",
                    label = "Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    disabled = function()
                        local rowCfg = rowConf()
                        return not (rowCfg and rowCfg.oocFadeEnabled)
                    end,
                    get = function()
                        local rowCfg = rowConf()
                        return math.floor(((rowCfg and rowCfg.oocAlpha) or 0.5) * 100 + 0.5)
                    end,
                    set = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.oocAlpha = val / 100
                        RefreshPower()
                    end,
                },
            }
            -- Show When Missing rows for the resources the player's class shows on this bar:
            -- energy and focus share one setting (a class has one of them), mana has its
            -- own. WoW Forever hunters use mana.
            local _, classTok = UnitClass("player")
            local fv = CludesUI.IS_FOREVER
            local restLabel, restTip
            if classTok == "HUNTER" and not fv then
                restLabel = "Show When Focus Missing"
                restTip =
                    "Shows the Power bar while your focus is below full, even when its Visibility setting hides it."
            elseif classTok == "ROGUE" or classTok == "DRUID" or classTok == "MONK" then
                restLabel = "Show When Energy Missing"
                restTip =
                    "Shows the Power bar while your energy is below full, even when its Visibility setting hides it."
            end
            if restLabel then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = restLabel,
                    tooltip = restTip,
                    get = function()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg.showWhenMissing == true
                    end,
                    set = ConfSetter("showWhenMissing", RefreshPower),
                }
            end
            if
                classTok == "PALADIN"
                or classTok == "PRIEST"
                or classTok == "SHAMAN"
                or classTok == "MAGE"
                or classTok == "WARLOCK"
                or classTok == "DRUID"
                or classTok == "MONK"
                or classTok == "EVOKER"
                or (classTok == "HUNTER" and fv)
            then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Show When Mana Missing",
                    tooltip = (fv and classTok == "DRUID")
                            and "Shows the Power bar, or your shapeshifted mana bar, while your mana is below full, even when its Visibility setting hides it."
                        or "Shows the Power bar while your mana is below full, even when its Visibility setting hides it.",
                    get = function()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg.showManaWhenMissing == true
                    end,
                    set = ConfSetter("showManaWhenMissing", RefreshPower),
                }
            end
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = powerDisTip,
                title = (#rowList > 2) and "Out of Combat Opacity & Visibility" or "Out of Combat Opacity",
                rows = rowList,
            })
        end

        -- Text Color disables when the bar is off OR Power Text is None
        local function powerTextDis()
            local rowCfg = rowConf()
            if not rowCfg then
                return false
            end
            if not rowCfg.enabled then
                return true
            end
            return rowCfg.textFormat == "none"
        end
        local function powerTextDisTip()
            local rowCfg = rowConf()
            if rowCfg and not rowCfg.enabled then
                return powerDisTip
            end
            return "This option requires a Power Text format other than None"
        end

        local powerTextSizeRow
        powerTextSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Power Text",
            disabled = powerOff,
            disabledTooltip = powerDisTip,
            values = {
                none = "None",
                smart = "Smart Text",
                curpp = "Power Value",
                curmaxpp = "Power Value / Max",
                perpp = "Power %",
                both = "Power Value | Power %",
            },
            -- WoW Forever lists no Smart Text (CludesUI.PowerTextFormat).
            order = CludesUI.PowerTextFormatOrder({ "none", "smart", "curpp", "curmaxpp", "perpp", "both" }),
            getValue = function()
                local rowCfg = rowConf()
                return CludesUI.PowerTextFormat(rowCfg and rowCfg.textFormat or "none")
            end,
            setValue = ConfSetter("textFormat", RefreshPower, true),
        }, {
            type = "multiSwatch",
            text = "Text Color",
            disabled = powerTextDis,
            disabledTooltip = powerTextDisTip,
            swatches = {
                {
                    tooltip = "Custom Colored",
                    hasAlpha = true,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return 1, 1, 1, 1
                        end
                        return rowCfg.textFillR, rowCfg.textFillG, rowCfg.textFillB, rowCfg.textFillA
                    end,
                    setValue = function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.textFillR, rowCfg.textFillG, rowCfg.textFillB, rowCfg.textFillA = red, green, blue, a
                        RebuildPower()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        if rowCfg.textCustomColored == false then
                            rowCfg.textCustomColored = true
                            RebuildPower()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isPowerColored = rowCfg and rowCfg.textCustomColored == false
                        return isPowerColored and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Power Colored",
                    getValue = function()
                        -- gpp() is nil for specs with no primary power (BM/MM
                        -- hunter: Focus is the class resource bar) -- fall to
                        -- the default swatch color rather than index with nil.
                        local gpp = _G._CURB_GetPrimaryPowerType
                        local pt = gpp and gpp()
                        local pc = pt and _G._CURB_PowerColors and _G._CURB_PowerColors[pt]
                        if pc then
                            return pc[1], pc[2], pc[3], 1
                        end
                        return 0x23 / 255, 0x8F / 255, 0xE7 / 255, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.textCustomColored = false
                        RebuildPower()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isPowerColored = rowCfg and rowCfg.textCustomColored == false
                        return isPowerColored and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height

        -- Row 5: Text Size | Threshold & Hash Lines
        local powerColorRow
        powerColorRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 24,
            step = 1,
            disabled = powerTextDis,
            disabledTooltip = powerTextDisTip,
            getValue = ConfGetter("textSize", 11),
            setValue = ConfSetter("textSize", RefreshPower),
        }, { type = "label", text = "Threshold & Hash Lines" })
        cursorY = cursorY - height
        -- Power Text inline cog: percent sign, anchor, x/y offsets
        if not CludesUI._prebuilding then
            local region = powerTextSizeRow._leftRegion
            local cogBtn = CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = "Power Bar",
                title = "Power Text",
                rows = {
                    {
                        type = "toggle",
                        label = "Show %",
                        get = function()
                            local rowCfg = rowConf()
                            return (not rowCfg) or rowCfg.showPercent ~= false
                        end,
                        set = ConfSetter("showPercent", RefreshPower),
                    },
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                        order = { "LEFT", "CENTER", "RIGHT" },
                        tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                        get = ConfGetter("textAnchor", "CENTER"),
                        set = ConfSetter("textAnchor", RefreshPower),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = ConfGetter("textXOffset", 0),
                        set = ConfSetter("textXOffset", RefreshPower),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = ConfGetter("textYOffset", 0),
                        set = ConfSetter("textYOffset", RefreshPower),
                    },
                },
            })
            AddFormTextBtn(region, cogBtn, rowConf, RefreshPower)
        end
        if not CludesUI._prebuilding then
            local powerSettingsBtn = BuildThresholdSettingsButton({
                parentRgn = powerColorRow._rightRegion,
                getBarData = function()
                    return rowConf()
                end,
                pageParent = hostFrame,
                pageTopY = _advTop,
                pageBotY = function()
                    return cursorY
                end,
                refreshFn = function()
                    RefreshPower()
                    SmoothRefresh()
                end,
                rebuildFn = function()
                    RebuildPower()
                end,
                disabledFn = powerOff,
                disabledTip = "Power Bar",
                roleShortcuts = true,
                partialDefault = true,
                thresholdCog = {
                    title = "Threshold Coloring",
                    minWidth = 280,
                    rows = function(current)
                        return {
                            {
                                type = "toggle",
                                label = "Threshold color below value",
                                rawTooltip = true,
                                disabled = function()
                                    local ent = current()
                                    return (ent and ent.multiBandEnabled) and true or false
                                end,
                                disabledTooltip = "Single-threshold options don't apply while Multi-band coloring is on.",
                                get = function()
                                    local ent = current()
                                    return ent and ent.thresholdPartialOnly
                                end,
                                set = function(val)
                                    local ent = current()
                                    if ent then
                                        ent.thresholdPartialOnly = val
                                        RefreshPower()
                                        SmoothRefresh()
                                    end
                                end,
                            },
                        }
                    end,
                },
                showSpenders = true,
                spenderTip = "Choose the spells and their colors.",
                spenderToggleTip = "Colors the bar while a chosen spell is ready.",
                textInsteadTip = "Also applies to Spender Colors.",
                thresholdLabel = "Threshold %",
                threshMin = 1,
                threshMax = 99,
                defaultR = 1.0,
                defaultG = 0.2,
                defaultB = 0.2,
                defaultA = 1,
            })

            -- Bar-wide hash lines (the fallback when the active threshold entry has none of its own).
            BuildHashCog({
                parentRgn = powerColorRow._rightRegion,
                anchorTo = powerSettingsBtn,
                getBarData = function()
                    return DB().primary
                end,
                refreshFn = function()
                    RebuildPower()
                end,
                popupTitle = CludesUI.L("Power Bar Hash Lines"),
            })
        end
        -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
        if CludesUI.SpecOverrides_AttachEditLock and not CludesUI._prebuilding then
            CludesUI.SpecOverrides_AttachEditLock(
                powerColorRow._rightRegion,
                "Thresholds have their own per-spec system and can't be edited while editing a spec group"
            )
        end
    end -- close Power Bar hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides Power in Advanced, so edits here aren't silently ignored.
    if not context.advanced then
        mod.ERB_SimpleOverrideOverlay(hostFrame, _advTop, cursorY, "primary")
    end

    return cursorY, heading, powerEnableRow, unlockJump
end
