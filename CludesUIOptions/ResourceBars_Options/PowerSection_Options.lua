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
function mod.ERB_BuildPowerSection(hostFrame, posY, context)
    local environ = mod._CURB_OptEnv
    local DB, Pix, Refresh, SmoothRefresh = environ.DB, environ.PP, environ.Refresh, environ.SmoothRefresh
    local RefreshPower, RebuildPower, AddFormBarBtn, AddFormTextBtn =
        environ.RefreshPower, environ.RebuildPower, environ.AddFormBarBtn, environ.AddFormTextBtn
    local BuildHashCog, BuildThresholdSettingsButton =
        environ.BuildHashCog, environ.BuildThresholdSettingsButton
    local W = CludesUI.Widgets
    local _, hgt
    local function conf()
        return context.cfg()
    end
    local function powerOff()
        local c = conf()
        return not (c and c.enabled)
    end
    local powerDisTip = "Power Bar"

    local heading
    heading, hgt = W:SectionHeader(hostFrame, "POWER BAR", posY)
    posY = posY - hgt
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "ERB_Power", disabled = powerOff, disabledTooltip = powerDisTip }
    )

    local _advTop = posY -- content top; also used by the Simple override overlay
    -- Row 1: Show Power Bar | Orientation
    local powerEnableRow
    powerEnableRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Power Bar",
        getValue = function()
            local c = conf()
            return c and c.enabled
        end,
        -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
        setValue = CludesUI.DependentSetValue(function()
            local c = conf()
            return c and c.enabled
        end, function(val)
            local c = conf()
            if not c then
                return
            end
            c.enabled = val
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
            local c = conf()
            local p = DB()
            return (c and c.orientation) or (p and p.general.orientation) or "HORIZONTAL"
        end,
        setValue = function(val)
            local c = conf()
            if not c then
                return
            end
            c.orientation = val
            Refresh()
        end,
    })
    posY = posY - hgt
    if not CludesUI._prebuilding then
        AddFormBarBtn(powerEnableRow._leftRegion, conf, RebuildPower)
    end

    -- Per-spec power enables live in Spec Overrides: "Show Power Bar" is captured while editing as a group.

    -- Everything below Row 1 is hidden entirely while the bar is off.
    if not powerOff() then
        -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only). Orientation-aware, as on the health bar above.
        local function powerOri()
            local c, p = conf(), DB()
            return (c and c.orientation) or (p and p.general and p.general.orientation)
        end
        local function guard(propKey)
            return mod.OrientedMatchGuard("ERB_Power", propKey, powerOri, powerOff, powerDisTip)
        end
        local phDis, phTip, phRaw = guard("Height")
        local pwDis, pwTip, pwRaw = guard("Width")
        local powerSizeRow
        powerSizeRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Height",
            min = 1,
            max = 100,
            step = 1,
            disabled = phDis,
            disabledTooltip = phTip,
            rawTooltip = phRaw,
            getValue = function()
                local c = conf()
                return c and c.height or 16
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.height = val
                SmoothRefresh()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Width",
            min = 50,
            max = 800,
            step = 1,
            disabled = pwDis,
            disabledTooltip = pwTip,
            rawTooltip = pwRaw,
            getValue = function()
                local c = conf()
                return c and c.width or 220
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.width = val
                SmoothRefresh()
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt
        if not context.advanced and context.syncRows then
            context.syncRows.powerHeight = powerSizeRow._leftRegion
            context.syncRows.powerWidth = powerSizeRow._rightRegion
            if not CludesUI._prebuilding then
                local rgn = powerSizeRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = "Apply Height to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local val = p.primary.height or 16
                        p.secondary.pipHeight = val
                        p.health.height = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local val = p.primary.height or 16
                        return (p.secondary.pipHeight or 20) == val and (p.health.height or 20) == val
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
                local rgn = powerSizeRow._rightRegion
                CludesUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = "Apply Width to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local val = p.primary.width or 220
                        p.secondary.pipWidth = val
                        p.health.width = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local val = p.primary.width or 220
                        return (p.secondary.pipWidth or 214) == val and (p.health.width or 220) == val
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
            pwrBsRow, hgt = W:DualRow(
                hostFrame,
                posY,
                CludesUI.BlizzStyle.Gate("resourcebars", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = powerOff,
                    disabledTooltip = powerDisTip,
                    values = texValues,
                    order = texOrder,
                    getValue = function()
                        local c = conf()
                        return c and c.borderTexture or "solid"
                    end,
                    setValue = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.borderTexture = val
                        c.borderTextureOffset = nil
                        c.borderTextureOffsetY = nil
                        c.borderTextureShiftX = nil
                        c.borderTextureShiftY = nil
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                        c.borderR = _bcol.r
                        c.borderG = _bcol.g
                        c.borderB = _bcol.b
                        c.borderA = 1
                        c.borderBehind = _bbehind
                        local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                        if defSz then
                            c.borderSize = defSz
                        end
                        if c.borderSizePx then
                            c.borderSizePx = false
                        end
                        RebuildPower()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                mod.ERB_ClassicBorderRow()
                        and mod.ERB_ClassicBorderSizeCfg(
                            conf,
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
                                local c = conf()
                                return c and c.borderSize or 1
                            end,
                            setStep = function(val)
                                local c = conf()
                                if c then
                                    c.borderSize = val
                                end
                            end,
                            getTex = function()
                                local c = conf()
                                return c and c.borderTexture or "solid"
                            end,
                            getPx = function()
                                local c = conf()
                                return c and c.borderSizePx
                            end,
                            setPx = function(val)
                                local c = conf()
                                if c then
                                    c.borderSizePx = val
                                end
                            end,
                            apply = function()
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        })
                    )
            )
            posY = posY - hgt
            -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
            do
                local c = conf()
                local texture = c and c.borderTexture or "solid"
                if texture ~= "solid" and texture ~= "" then
                    local function step()
                        local c = conf()
                        return c and c.borderSize or 1
                    end
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "resourcebars",
                        disabled = powerOff,
                        disabledTooltip = powerDisTip,
                        getTex = function()
                            local c = conf()
                            return c and c.borderTexture or "solid"
                        end,
                        getStep = step,
                        getSizeKey = step,
                        getPx = function()
                            local c = conf()
                            return c and c.borderSizePx
                        end,
                        getX = function()
                            local c = conf()
                            return c and c.borderTextureOffset
                        end,
                        setX = function(val)
                            local c = conf()
                            if c then
                                c.borderTextureOffset = val
                            end
                        end,
                        getY = function()
                            local c = conf()
                            return c and c.borderTextureOffsetY
                        end,
                        setY = function(val)
                            local c = conf()
                            if c then
                                c.borderTextureOffsetY = val
                            end
                        end,
                        apply = function()
                            RebuildPower()
                            CludesUI:RefreshPage()
                        end,
                    })
                    _, hgt = W:DualRow(
                        hostFrame,
                        posY,
                        CludesUI.BlizzStyle.Gate("resourcebars", ocfgL),
                        CludesUI.BlizzStyle.Gate("resourcebars", ocfgR)
                    )
                    posY = posY - hgt
                end
            end
            if not CludesUI._prebuilding and not mod.ERB_ClassicBorderRow() then
                local rgn = pwrBsRow._rightRegion
                local ctrl = rgn._control
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
                            local c = conf()
                            return not CludesUI.RoundedStyleOK(c and c.borderTexture)
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
                                get = function()
                                    local c = conf()
                                    return c and c.cornerRadius or 0
                                end,
                                set = function(val)
                                    local c = conf()
                                    if not c then
                                        return
                                    end
                                    c.cornerRadius = val
                                    RebuildPower()
                                end,
                            },
                        }, function()
                            local c = conf()
                            return c and c.cornerMask
                        end, function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.cornerMask = val
                            RebuildPower()
                        end),
                    })
                end
                local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    pwrBsRow:GetFrameLevel() + 3,
                    function()
                        local c = conf()
                        return (c and c.borderR or 0),
                            (c and c.borderG or 0),
                            (c and c.borderB or 0),
                            (c and c.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    true,
                    20
                )
                Pix.Point(borderSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
                rgn._lastInline = borderSwatch -- left of the Corner Radius cog
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
                local rgn = pwrBsRow._leftRegion
                local sepValues, sepOrder = mod.ERB_SeparatorArtValues(true)
                local cogBtn = CludesUI.BuildInlineCog(rgn, {
                    title = "Border Options",
                    rows = {
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local c = conf()
                                if not c then
                                    return 0
                                end
                                local val = c.borderTextureShiftX
                                if val then
                                    return val
                                end
                                local _, _, dsx = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    c.borderTexture or "solid",
                                    c.borderSize or 1
                                )
                                return dsx
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderTextureShiftX = val == 0 and nil or val
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
                                local c = conf()
                                if not c then
                                    return 0
                                end
                                local val = c.borderTextureShiftY
                                if val then
                                    return val
                                end
                                local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    c.borderTexture or "solid",
                                    c.borderSize or 1
                                )
                                return dsy
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderTextureShiftY = val == 0 and nil or val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = function()
                                local c = conf()
                                return c and c.borderBehind or false
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderBehind = val == false and nil or val
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
                                local p, c = DB(), conf()
                                return (powerOff() or not (p and p.gcdBar.enabled) or (c and c.borderBehind))
                                        and true
                                    or false
                            end,
                            disabledTooltip = function()
                                if powerOff() then
                                    return powerDisTip
                                end
                                local p = DB()
                                if not (p and p.gcdBar.enabled) then
                                    return "GCD Bar"
                                end
                                return "This option can't be used while Show Behind is enabled."
                            end,
                            rawTooltip = function()
                                local p = DB()
                                return not powerOff() and (p and p.gcdBar.enabled) and true or false
                            end,
                            get = function()
                                local c = conf()
                                return c and c.borderAboveGCD or false
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderAboveGCD = val and true or false
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
                            get = function()
                                local c = conf()
                                return c and c.borderExtendTop or 0
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderExtendTop = val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
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
                            get = function()
                                local c = conf()
                                return c and c.borderExtendBottom or 0
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderExtendBottom = val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
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
                            get = function()
                                local c = conf()
                                return c and c.borderExtendLeft or 0
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderExtendLeft = val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
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
                            get = function()
                                local c = conf()
                                return c and c.borderExtendRight or 0
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderExtendRight = val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
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
                                local c = conf()
                                if not (c and c.edgeSep) then
                                    return "none"
                                end
                                return c.edgeSepArt or "match"
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                if val == "none" then
                                    c.edgeSep = false
                                else
                                    c.edgeSep = true
                                    c.edgeSepArt = val
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
                                local c = conf()
                                return powerOff() or not (c and c.edgeSep)
                            end,
                            disabledTooltip = function()
                                return powerOff() and powerDisTip or "Bottom Separator"
                            end,
                            get = function()
                                local c = conf()
                                return c and c.edgeSepY or 0
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.edgeSepY = val
                                RebuildPower()
                                CludesUI:RefreshPage()
                            end,
                        },
                    },
                })
                local function UpdateCogVis()
                    local c = conf()
                    local texture = c and c.borderTexture or "solid"
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
                        local p = DB()
                        if not p then
                            return
                        end
                        local was = mod.ERB_TexturedBars(p)
                        local s = p.primary
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
                        apply(p.secondary)
                        apply(p.health)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(p) ~= was)
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local bt = p.primary.borderTexture or "solid"
                        local bh = p.primary.borderBehind or false
                        return (p.secondary.borderTexture or "solid") == bt
                            and (p.health.borderTexture or "solid") == bt
                            and (p.secondary.borderBehind or false) == bh
                            and (p.health.borderBehind or false) == bh
                    end,
                    flashTargets = function()
                        return { pwrBsRow._leftRegion }
                    end,
                })
                CludesUI.BuildSyncIcon({
                    region = pwrBsRow._rightRegion,
                    tooltip = "Apply Border to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local was = mod.ERB_TexturedBars(p)
                        local r, g, b, a =
                            p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA
                        local sz = p.primary.borderSize or 1
                        local bt = p.primary.borderTexture or "solid"
                        local cr, cm = p.primary.cornerRadius or 0, p.primary.cornerMask
                        p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA =
                            r, g, b, a
                        p.secondary.borderSize = sz
                        p.secondary.borderTexture = bt
                        p.secondary.cornerRadius = cr
                        p.secondary.cornerMask = cm
                        mod.ERB_CopyBorderPx(p.secondary, p.primary)
                        p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                        p.health.borderSize = sz
                        p.health.borderTexture = bt
                        p.health.cornerRadius = cr
                        p.health.cornerMask = cm
                        mod.ERB_CopyBorderPx(p.health, p.primary)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(p) ~= was)
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local sr, sg, scrollBar, sa, ssz =
                            p.primary.borderR,
                            p.primary.borderG,
                            p.primary.borderB,
                            p.primary.borderA,
                            p.primary.borderSize or 1
                        local sbt, scr, scm =
                            p.primary.borderTexture or "solid",
                            p.primary.cornerRadius or 0,
                            p.primary.cornerMask or 15
                        local function eq(t)
                            return t.borderR == sr
                                and t.borderG == sg
                                and t.borderB == scrollBar
                                and t.borderA == sa
                                and (t.borderSize or 1) == ssz
                                and (t.borderTexture or "solid") == sbt
                                and (t.cornerRadius or 0) == scr
                                and (t.cornerMask or 15) == scm
                                and mod.ERB_SameBorderPx(t, p.primary)
                        end
                        return eq(p.secondary) and eq(p.health)
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
        powerBorderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 5,
            disabled = powerOff,
            disabledTooltip = powerDisTip,
            getValue = function()
                local c = conf()
                return math.floor((c and c.barAlpha or 1) * 100 + 0.5)
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.barAlpha = val / 100
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
                local c = conf()
                return (c and c.fillOpacity) or 100
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.fillOpacity = val
                RebuildPower()
            end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            local rgn = powerBorderRow._rightRegion
            CludesUI.BuildInlineCog(rgn, {
                disabled = function()
                    local c = conf()
                    return c and not c.enabled
                end,
                disabledTooltip = powerDisTip,
                title = "Fill Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Enable Gradient",
                        get = function()
                            local c = conf()
                            return c and c.gradientEnabled
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.gradientEnabled = val
                            RebuildPower()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Gradient Direction",
                        values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                        order = { "HORIZONTAL", "VERTICAL" },
                        get = function()
                            local c = conf()
                            return c and c.gradientDir or "HORIZONTAL"
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.gradientDir = val
                            RebuildPower()
                        end,
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
                        local c = conf()
                        if not c then
                            return true
                        end
                        if not c.enabled then
                            return true
                        end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(c)
                        if tse and (tse.thresholdEnabled ~= false) then
                            return true
                        end
                        if SpendersFlatten(c, tse) then
                            return true
                        end
                        return not c.gradientEnabled
                    end,
                    disabledTooltip = function()
                        local c = conf()
                        if not c or not c.enabled then
                            return powerDisTip
                        end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(c)
                        if tse and (tse.thresholdEnabled ~= false) then
                            return "This option requires the threshold to be off in Threshold & Hash Lines"
                        end
                        if SpendersFlatten(c, tse) then
                            return "This option requires Spender Colors to be disabled"
                        end
                        return "Gradient"
                    end,
                    getValue = function()
                        local c = conf()
                        if not c then
                            return 0.20, 0.20, 0.80, 1
                        end
                        return c.gradientR, c.gradientG, c.gradientB, c.gradientA
                    end,
                    setValue = function(r, g, b, a)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.gradientR, c.gradientG, c.gradientB, c.gradientA = r, g, b, a
                        SmoothRefresh()
                    end,
                },
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local c = conf()
                        if not c then
                            return 0x23 / 255, 0x8F / 255, 0xE7 / 255, 1
                        end
                        return c.fillR, c.fillG, c.fillB, 1
                    end,
                    setValue = function(r, g, b)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.fillR, c.fillG, c.fillB = r, g, b
                        RebuildPower()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local c = conf()
                        if not c then
                            return
                        end
                        if not c.customColored then
                            c.customColored = true
                            RebuildPower()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local isPowerColored = not c or not c.customColored
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
                        local c = conf()
                        if not c then
                            return
                        end
                        c.customColored = false
                        RebuildPower()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local isPowerColored = not c or not c.customColored
                        return isPowerColored and 1 or 0.3
                    end,
                },
            }, { size = 20, disabled = powerOff, disabledTooltip = powerDisTip })
        end
        if not context.advanced and context.syncRows and not CludesUI._prebuilding then
            context.syncRows.powerOpacity = powerBorderRow._leftRegion
            local rgn = powerBorderRow._leftRegion
            CludesUI.BuildSyncIcon({
                region = rgn,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local p = DB()
                    if not p then
                        return
                    end
                    local val = p.primary.barAlpha or 1
                    p.secondary.barAlpha = val
                    p.health.barAlpha = val
                    SmoothRefresh()
                    CludesUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB()
                    if not p then
                        return false
                    end
                    local val = p.primary.barAlpha or 1
                    return (p.secondary.barAlpha or 1) == val and (p.health.barAlpha or 1) == val
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
            local rgn = powerBorderRow._leftRegion
            local rowList = {
                {
                    type = "toggle",
                    label = "Fade Out of Combat",
                    get = function()
                        local c = conf()
                        return c and c.oocFadeEnabled == true
                    end,
                    set = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.oocFadeEnabled = val
                        RefreshPower()
                    end,
                },
                {
                    type = "slider",
                    label = "Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    disabled = function()
                        local c = conf()
                        return not (c and c.oocFadeEnabled)
                    end,
                    get = function()
                        local c = conf()
                        return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5)
                    end,
                    set = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.oocAlpha = val / 100
                        RefreshPower()
                    end,
                },
            }
            -- Show When Missing rows for the resources the player's class shows on this bar:
            -- energy and focus share one setting (a class has one of them), mana has its
            -- own. WoW Forever hunters use mana.
            local _, cls = UnitClass("player")
            local fv = CludesUI.IS_FOREVER
            local restLabel, restTip
            if cls == "HUNTER" and not fv then
                restLabel = "Show When Focus Missing"
                restTip =
                    "Shows the Power bar while your focus is below full, even when its Visibility setting hides it."
            elseif cls == "ROGUE" or cls == "DRUID" or cls == "MONK" then
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
                        local c = conf()
                        return c and c.showWhenMissing == true
                    end,
                    set = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.showWhenMissing = val
                        RefreshPower()
                    end,
                }
            end
            if
                cls == "PALADIN"
                or cls == "PRIEST"
                or cls == "SHAMAN"
                or cls == "MAGE"
                or cls == "WARLOCK"
                or cls == "DRUID"
                or cls == "MONK"
                or cls == "EVOKER"
                or (cls == "HUNTER" and fv)
            then
                rowList[#rowList + 1] = {
                    type = "toggle",
                    label = "Show When Mana Missing",
                    tooltip = (fv and cls == "DRUID")
                            and "Shows the Power bar, or your shapeshifted mana bar, while your mana is below full, even when its Visibility setting hides it."
                        or "Shows the Power bar while your mana is below full, even when its Visibility setting hides it.",
                    get = function()
                        local c = conf()
                        return c and c.showManaWhenMissing == true
                    end,
                    set = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.showManaWhenMissing = val
                        RefreshPower()
                    end,
                }
            end
            CludesUI.BuildInlineCog(rgn, {
                disabled = function()
                    local c = conf()
                    return c and not c.enabled
                end,
                disabledTooltip = powerDisTip,
                title = (#rowList > 2) and "Out of Combat Opacity & Visibility" or "Out of Combat Opacity",
                rows = rowList,
            })
        end

        -- Text Color disables when the bar is off OR Power Text is None
        local function powerTextDis()
            local c = conf()
            if not c then
                return false
            end
            if not c.enabled then
                return true
            end
            return c.textFormat == "none"
        end
        local function powerTextDisTip()
            local c = conf()
            if c and not c.enabled then
                return powerDisTip
            end
            return "This option requires a Power Text format other than None"
        end

        local powerTextSizeRow
        powerTextSizeRow, hgt = W:DualRow(hostFrame, posY, {
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
                local c = conf()
                return CludesUI.PowerTextFormat(c and c.textFormat or "none")
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.textFormat = val
                RefreshPower()
                CludesUI:RefreshPage()
            end,
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
                        local c = conf()
                        if not c then
                            return 1, 1, 1, 1
                        end
                        return c.textFillR, c.textFillG, c.textFillB, c.textFillA
                    end,
                    setValue = function(r, g, b, a)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.textFillR, c.textFillG, c.textFillB, c.textFillA = r, g, b, a
                        RebuildPower()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local c = conf()
                        if not c then
                            return
                        end
                        if c.textCustomColored == false then
                            c.textCustomColored = true
                            RebuildPower()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local isPowerColored = c and c.textCustomColored == false
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
                        local c = conf()
                        if not c then
                            return
                        end
                        c.textCustomColored = false
                        RebuildPower()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local isPowerColored = c and c.textCustomColored == false
                        return isPowerColored and 1 or 0.3
                    end,
                },
            },
        })
        posY = posY - hgt

        -- Row 5: Text Size | Threshold & Hash Lines
        local powerColorRow
        powerColorRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 24,
            step = 1,
            disabled = powerTextDis,
            disabledTooltip = powerTextDisTip,
            getValue = function()
                local c = conf()
                return c and c.textSize or 11
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.textSize = val
                RefreshPower()
            end,
        }, { type = "label", text = "Threshold & Hash Lines" })
        posY = posY - hgt
        -- Power Text inline cog: percent sign, anchor, x/y offsets
        if not CludesUI._prebuilding then
            local rgn = powerTextSizeRow._leftRegion
            local cogBtn = CludesUI.BuildInlineCog(rgn, {
                disabled = function()
                    local c = conf()
                    return c and not c.enabled
                end,
                disabledTooltip = "Power Bar",
                title = "Power Text",
                rows = {
                    {
                        type = "toggle",
                        label = "Show %",
                        get = function()
                            local c = conf()
                            return (not c) or c.showPercent ~= false
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.showPercent = val
                            RefreshPower()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                        order = { "LEFT", "CENTER", "RIGHT" },
                        tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                        get = function()
                            local c = conf()
                            return c and c.textAnchor or "CENTER"
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.textAnchor = val
                            RefreshPower()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            local c = conf()
                            return c and c.textXOffset or 0
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.textXOffset = val
                            RefreshPower()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            local c = conf()
                            return c and c.textYOffset or 0
                        end,
                        set = function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.textYOffset = val
                            RefreshPower()
                        end,
                    },
                },
            })
            AddFormTextBtn(rgn, cogBtn, conf, RefreshPower)
        end
        if not CludesUI._prebuilding then
            local powerSettingsBtn = BuildThresholdSettingsButton({
                parentRgn = powerColorRow._rightRegion,
                getBarData = function()
                    return conf()
                end,
                pageParent = hostFrame,
                pageTopY = _advTop,
                pageBotY = function()
                    return posY
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
        mod.ERB_SimpleOverrideOverlay(hostFrame, _advTop, posY, "primary")
    end

    return posY, heading, powerEnableRow, unlockJump
end
