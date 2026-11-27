if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ResourceBars_Options\HealthSection_Options.lua
--  Resource Bars options: HEALTH BAR section builder. Definitions only; the shared
--  helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIResourceBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- Shared, context-aware HEALTH section builder. ctx.cfg() -> health config table
-- (DB().health). Returns the y after the rendered rows. ctx.advanced is always
-- false: the Advanced per-spec page was retired.
function mod.ERB_BuildHealthSection(hostFrame, cursorY, context)
    local environ = mod._CURB_OptEnv
    local DB, Pix, Refresh, GentleRefresh = environ.DB, environ.PP, environ.Refresh, environ.SmoothRefresh
    local RefreshHealth, RebuildHealth, AddFormBarBtn, AddFormTextBtn =
        environ.RefreshHealth, environ.RebuildHealth, environ.AddFormBarBtn, environ.AddFormTextBtn
    local BuildHashCog, BuildThresholdSettingsButton =
        environ.BuildHashCog, environ.BuildThresholdSettingsButton
    local W = CUI.Widgets
    local _, height
    local function rowConf() return context.cfg() end
    -- A row's getter and setter for one key of this section's settings: the
    -- getter gives its value, or default when unset (no default: the value as
    -- stored); the setter writes it when the settings exist, then runs after
    -- and, with alsoPage, rebuilds the page.
    local function ConfGetter(key, default)
        return function()
            local rowCfg = rowConf()
            if default == nil then return rowCfg and rowCfg[key] end
            return rowCfg and rowCfg[key] or default
        end
    end
    local function ConfSetter(key, after, alsoPage)
        return function(val)
            local rowCfg = rowConf()
            if not rowCfg then return end
            rowCfg[key] = val
            after()
            if alsoPage then CUI:RefreshPage() end
        end
    end
    local function healthBarOff()
        local rowCfg = rowConf()
        return not (rowCfg and rowCfg.enabled)
    end

    local heading
    heading, height = W:SectionHeader(hostFrame, "HEALTH BAR", cursorY)
    cursorY = cursorY - height
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = CUI.BuildSectionUnlockJump(
        heading,
        { key = "ERB_Health", disabled = healthBarOff, disabledTooltip = "Health Bar" }
    )
    cursorY = CUI.BlizzStyle.Note(hostFrame, cursorY, "resourcebars")

    local _advTop = cursorY -- content top; also used by the Simple override overlay
    -- Row 1: Show Health Bar | Orientation
    local healthEnableRow
    healthEnableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Health Bar",
        tooltip = "Shows a health bar.",
        getValue = ConfGetter("enabled"),
        -- Rows below Row 1 are hidden while off, so the flip must force the full rebuild
        setValue = CUI.DependentSetValue(function()
            local rowCfg = rowConf()
            return rowCfg and rowCfg.enabled
        end, function(val)
            local rowCfg = rowConf()
            if not rowCfg then return end
            rowCfg.enabled = val
            RebuildHealth()
            CUI:RefreshPage()
        end),
    }, {
        type = "dropdown",
        text = "Orientation",
        disabled = healthBarOff,
        disabledTooltip = "Health Bar",
        values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
        order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
        getValue = function()
            local rowCfg = rowConf()
            local profile = DB()
            return (rowCfg and rowCfg.orientation)
                or (profile and profile.general.orientation)
                or "HORIZONTAL"
        end,
        setValue = ConfSetter("orientation", Refresh),
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then AddFormBarBtn(healthEnableRow._leftRegion, rowConf, RebuildHealth) end

    -- Texture lists for the health overlays (CUI_ResourceBars_HealthIndicators.lua): the shared
    -- absorb styles (copied: the SharedMedia tail is appended into the copies) then the
    -- SharedMedia bar textures. The absorb rows keep None (their off switch); the max health
    -- reduction has its own toggle, so its list drops it.
    local hiNames = CopyTable(CUI.ABSORB_STYLE_NAMES)
    local hiOrder = CopyTable(CUI.ABSORB_STYLE_ORDER)
    local hiHealOrder = CopyTable(CUI.HEAL_ABSORB_STYLE_ORDER)
    local hiLossOrder = {}
    for _, keyName in ipairs(hiOrder) do
        if keyName ~= "none" then hiLossOrder[#hiLossOrder + 1] = keyName end
    end
    do
        local smNames, smSep = _G._CURB_BarTextureNames or {}, false
        for _, keyName in ipairs(_G._CURB_BarTextureOrder or {}) do
            if type(keyName) == "string" and keyName:find("^sm:") then
                if not smSep then
                    smSep = true
                    hiOrder[#hiOrder + 1] = "---"
                    hiHealOrder[#hiHealOrder + 1] = "---"
                    hiLossOrder[#hiLossOrder + 1] = "---"
                end
                hiNames[keyName] = smNames[keyName] or keyName
                hiOrder[#hiOrder + 1] = keyName
                hiHealOrder[#hiHealOrder + 1] = keyName
                hiLossOrder[#hiLossOrder + 1] = keyName
            end
        end
    end
    -- Preview swatch behind each menu row, resolved exactly like the overlay.
    hiNames._menuOpts = {
        itemHeight = 28,
        background = function(keyName)
            if keyName and keyName ~= "---" and keyName ~= "none" then
                return mod.HealthIndicatorTex(keyName)
            end
        end,
    }

    -- Max health reduction overlay, off by default: its texture and colour are listed while it is on.
    if not CUI._prebuilding then
        local keyName = mod.HEALTH_INDICATORS[3]
        local function lossOff()
            local rowCfg = rowConf()
            return not (rowCfg and rowCfg[keyName.show] == true)
        end
        CUI.BuildInlineCog(healthEnableRow._leftRegion, {
            title = "Max Health Reduction",
            disabled = healthBarOff,
            disabledTooltip = "Health Bar",
            rows = {
                {
                    type = "toggle",
                    label = "Show Reduction",
                    get = function()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg[keyName.show] == true
                    end,
                    set = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg[keyName.show] = val or nil
                        RefreshHealth()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Texture",
                    hidden = lossOff,
                    values = hiNames,
                    order = hiLossOrder,
                    get = function()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg[keyName.style] or "striped"
                    end,
                    set = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg[keyName.style] = val
                        RefreshHealth()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Color",
                    hasAlpha = true,
                    hidden = lossOff,
                    get = function()
                        local rowCfg = rowConf()
                        local col = rowCfg and rowCfg[keyName.color]
                        if col then
                            return col.r or keyName.r,
                                col.g or keyName.g,
                                col.b or keyName.b,
                                col.a or keyName.a
                        end
                        return keyName.r, keyName.g, keyName.b, keyName.a
                    end,
                    set = function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg[keyName.color] = { r = red, g = green, b = blue, a = a }
                        RefreshHealth()
                    end,
                },
            },
        })
    end

    -- Per-spec health enables live in Spec Overrides: "Show Health Bar" is captured while editing as a group.

    -- Everything below Row 1 is hidden entirely while the bar is off.
    if not healthBarOff() then
        -- Absorb Style | Absorb Opacity, then Heal Absorb Style | Heal Absorb Opacity: None turns
        -- the overlay off, the inline swatch sets its colour and the slider its opacity.
        for _, def in ipairs({
            {
                k = mod.HEALTH_INDICATORS[1],
                styleText = "Absorb Style",
                opacityText = "Absorb Opacity",
                order = hiOrder,
            },
            {
                k = mod.HEALTH_INDICATORS[2],
                styleText = "Heal Absorb Style",
                opacityText = "Heal Absorb Opacity",
                order = hiHealOrder,
            },
        }) do
            local keyName, styleText = def.k, def.styleText
            local function styleOf()
                local rowCfg = rowConf()
                return rowCfg and rowCfg[keyName.style] or "none"
            end
            local function styleIsNone() return styleOf() == "none" end
            local absorbRow
            absorbRow, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = styleText,
                values = hiNames,
                order = def.order,
                getValue = styleOf,
                setValue = function(val)
                    local rowCfg = rowConf()
                    if not rowCfg then return end
                    rowCfg[keyName.style] = (val ~= "none") and val or nil
                    RefreshHealth()
                    CUI:RefreshPage()
                end,
            }, {
                type = "slider",
                text = def.opacityText,
                min = 5,
                max = 100,
                step = 1,
                disabled = styleIsNone,
                disabledTooltip = styleText,
                getValue = function()
                    local rowCfg = rowConf()
                    return rowCfg and rowCfg[keyName.opacity] or keyName.opacityDef
                end,
                setValue = function(val)
                    local rowCfg = rowConf()
                    if not rowCfg then return end
                    rowCfg[keyName.opacity] = val
                    RefreshHealth()
                end,
            })
            cursorY = cursorY - height
            if not CUI._prebuilding then
                local region = absorbRow._leftRegion
                do
                    local isHeal = keyName.key == "healAbsorb"
                    local edgeKey = isHeal and "healAbsorbEdgeMode" or "absorbEdgeMode"
                    local edgeDefault = isHeal and "overlay" or "overlayReverse"
                    local edgeLabels = { overlay = "Overlay" }
                    if not isHeal then
                        edgeLabels.overlayReverse = "Overlay Reverse"
                        edgeLabels.overlayReverseFull = "Overlay Reverse (Full)"
                    end
                    local lastVertical
                    local function isVertical()
                        local c, p = rowConf(), DB()
                        local ori = (c and c.orientation) or (p and p.general.orientation) or "HORIZONTAL"
                        return ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
                    end
                    local function syncEdgeLabels()
                        local vertical = isVertical()
                        if lastVertical == vertical then return false end
                        lastVertical = vertical
                        edgeLabels.right = vertical and "From Top Edge" or "From Right Edge"
                        edgeLabels.left = vertical and "From Bottom Edge" or "From Left Edge"
                        return true
                    end
                    local function readValue(key, fallback)
                        local rowCfg = rowConf()
                        if rowCfg and rowCfg[key] ~= nil then return rowCfg[key] end
                        return fallback
                    end
                    local function set(key, value)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg[key] = value
                        RefreshHealth()
                    end
                    local function glowUnavailable()
                        return styleIsNone()
                            or isVertical()
                            or readValue("absorbEdgeMode", "overlayReverse") == "left"
                    end
                    syncEdgeLabels()
                    local rowList = {
                        {
                            type = "dropdown",
                            label = "Placement",
                            values = edgeLabels,
                            ddWidth = 190,
                            order = isHeal and { "overlay", "right", "left" }
                                or { "overlay", "overlayReverse", "overlayReverseFull", "right", "left" },
                            disabled = isHeal and styleIsNone or nil,
                            disabledTooltip = styleText,
                            get = function()
                                syncEdgeLabels()
                                return readValue(edgeKey, edgeDefault)
                            end,
                            set = function(val) set(edgeKey, val) end,
                        },
                    }
                    if isHeal then
                        rowList[2] = {
                            type = "slider",
                            label = "Backing Opacity",
                            min = 0,
                            max = 100,
                            step = 1,
                            disabled = styleIsNone,
                            disabledTooltip = styleText,
                            get = function() return readValue("healAbsorbBgOpacity", 0) end,
                            set = function(val) set("healAbsorbBgOpacity", val) end,
                        }
                    else
                        rowList[2] = {
                            type = "dropdown",
                            label = "Show Overshield",
                            tooltip = "Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                            values = { never = "Never", always = "Always", fromleft = "From Left" },
                            order = { "never", "always", "fromleft" },
                            itemDisabled = function(val)
                                return val == "fromleft"
                                    and readValue("absorbEdgeMode", "overlayReverse") ~= "overlay"
                            end,
                            get = function() return readValue("overshieldMode", "always") end,
                            set = function(val) set("overshieldMode", val) end,
                        }
                        rowList[3] = {
                            type = "toggle",
                            label = "Blizzard Glow Line",
                            tooltip = "Adds the Blizzard shield glow line where the shield meets current health.",
                            disabled = glowUnavailable,
                            disabledTooltip = function()
                                if styleIsNone() then
                                    return "The glow line is not shown with Absorb Style None"
                                end
                                return "The glow line is not shown on a vertical fill or with the From Left Edge placement"
                            end,
                            rawTooltip = true,
                            get = function() return readValue("absorbGlowLine", false) == true end,
                            set = function(val) set("absorbGlowLine", val) end,
                        }
                        rowList[4] = {
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
                                return glowUnavailable() or readValue("absorbGlowLine", false) ~= true
                            end,
                            disabledTooltip = "Blizzard Glow Line",
                            get = function() return readValue("absorbGlowLineTexture", "blizzard") end,
                            set = function(val) set("absorbGlowLineTexture", val) end,
                        }
                    end
                    local _, cogShow = CUI.BuildInlineCog(region, {
                        title = isHeal and "Heal Absorb Rendering" or "Absorb Rendering",
                        rows = rowList,
                    })
                    CUI.RegisterWidgetRefresh(function()
                        if not syncEdgeLabels() then return end
                        local dialog = cogShow and cogShow._popupFrame
                        if dialog then
                            for _, childFrame in ipairs({ dialog:GetChildren() }) do
                                if childFrame._invalidateMenu and not CUI._Pool.IsIdle(childFrame) then
                                    childFrame._invalidateMenu()
                                end
                            end
                        end
                    end)
                end
                local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
                    region,
                    absorbRow:GetFrameLevel() + 3,
                    function()
                        local rowCfg = rowConf()
                        local col = rowCfg and rowCfg[keyName.color]
                        if col then return col.r or keyName.r, col.g or keyName.g, col.b or keyName.b, 1 end
                        return keyName.r, keyName.g, keyName.b, 1
                    end,
                    function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg[keyName.color] = { r = red, g = green, b = blue }
                        RefreshHealth()
                    end,
                    false,
                    20
                )
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                region._lastInline = colorSwatch
                CUI.RegisterWidgetRefresh(function() updateSwatch() end)
                -- Blocked while the style is None, and for the outlined stripes, which carry their own colours.
                local swBlock = CUI.NewSwatchBlocker(colorSwatch)
                swBlock:SetScript("OnEnter", function()
                    local tipText = styleIsNone() and CUI.DisabledTooltip(styleText)
                        or "This style uses its own colors"
                    CUI.ShowWidgetTooltip(colorSwatch, tipText)
                end)
                swBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                local function UpdateSwatchDis()
                    local st = styleOf()
                    local dis = st == "none" or st == "largeOutlinedStripes" or st == "largeOutlinedStripesR"
                    colorSwatch:SetAlpha(dis and 0.3 or 1)
                    if dis then
                        swBlock:Show()
                    else
                        swBlock:Hide()
                    end
                end
                CUI.RegisterWidgetRefresh(UpdateSwatchDis)
                UpdateSwatchDis()
            end
        end

        -- Row 2: Height | Width. A MatchGuard (dimension matched to ANOTHER element via
        -- Unlock Mode) is a global relationship and greys the slider in BOTH modes: a
        -- matched dimension cannot be per-spec overridden (only the "apply to all bars"
        -- sync icons below are Simple-only). Orientation-aware: a vertical bar swaps the
        -- drawn axes, so the Height slider controls what the match calls Width.
        local function healthOri()
            local c, p = rowConf(), DB()
            return (c and c.orientation) or (p and p.general and p.general.orientation)
        end
        local function guard(propKey)
            return mod.OrientedMatchGuard("ERB_Health", propKey, healthOri, healthBarOff, "Health Bar")
        end
        local hhDis, hhTip, hhRaw = guard("Height")
        local hwDis, hwTip, hwRaw = guard("Width")
        local healthSizeRow
        healthSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Height",
            min = 1,
            max = 40,
            step = 1,
            disabled = hhDis,
            disabledTooltip = hhTip,
            rawTooltip = hhRaw,
            getValue = ConfGetter("height", 20),
            setValue = ConfSetter("height", GentleRefresh, true),
        }, {
            type = "slider",
            text = "Width",
            min = 50,
            max = 800,
            step = 1,
            disabled = hwDis,
            disabledTooltip = hwTip,
            rawTooltip = hwRaw,
            getValue = ConfGetter("width", 220),
            setValue = ConfSetter("width", GentleRefresh, true),
        })
        cursorY = cursorY - height
        if not context.advanced and context.syncRows then
            context.syncRows.healthHeight = healthSizeRow._leftRegion
            context.syncRows.healthWidth = healthSizeRow._rightRegion
            if not CUI._prebuilding then
                local region = healthSizeRow._leftRegion
                CUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Height to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        local val = profile.health.height or 20
                        profile.secondary.pipHeight = val
                        profile.primary.height = val
                        GentleRefresh()
                        CUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then return false end
                        local val = profile.health.height or 20
                        return (profile.secondary.pipHeight or 20) == val
                            and (profile.primary.height or 16) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.healthHeight,
                            context.syncRows.classHeight,
                            context.syncRows.powerHeight,
                        }
                    end,
                })
            end
            if not CUI._prebuilding then
                local region = healthSizeRow._rightRegion
                CUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Width to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        local val = profile.health.width or 220
                        profile.secondary.pipWidth = val
                        profile.primary.width = val
                        GentleRefresh()
                        CUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then return false end
                        local val = profile.health.width or 220
                        return (profile.primary.width or 220) == val
                            and (profile.secondary.pipWidth or 214) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.healthWidth,
                            context.syncRows.classWidth,
                            context.syncRows.powerWidth,
                        }
                    end,
                })
            end
        end

        -- Health Border Style dropdown + inline offset cog. Style/size/colour/cog operate on cfg(); the cross-bar "apply to all" sync icons (+ _syncRows registration) are Simple-only.
        do
            local texValues, texOrder = CUI.GetBorderTextureDropdown()
            local hpBsRow
            hpBsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CUI.BlizzStyle.Gate("resourcebars", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = healthBarOff,
                    disabledTooltip = "Health Bar",
                    values = texValues,
                    order = texOrder,
                    getValue = ConfGetter("borderTexture", "solid"),
                    setValue = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.borderTexture = val
                        rowCfg.borderTextureOffset = nil
                        rowCfg.borderTextureOffsetY = nil
                        rowCfg.borderTextureShiftX = nil
                        rowCfg.borderTextureShiftY = nil
                        local _bcol, _bbehind = CUI.GetBorderStyleSelectDefaults(val)
                        rowCfg.borderR = _bcol.r
                        rowCfg.borderG = _bcol.g
                        rowCfg.borderB = _bcol.b
                        rowCfg.borderA = 1
                        rowCfg.borderBehind = _bbehind
                        local defSz = CUI.GetBorderDefaultSize("resourcebars", val)
                        if defSz then rowCfg.borderSize = defSz end
                        if rowCfg.borderSizePx then rowCfg.borderSizePx = false end
                        RebuildHealth()
                        CUI:RefreshPage(true)
                    end,
                }),
                mod.ERB_ClassicBorderRow()
                        and mod.ERB_ClassicBorderSizeCfg(
                            rowConf,
                            healthBarOff,
                            "Health Bar",
                            RebuildHealth,
                            "ERB_Health"
                        )
                    or CUI.BlizzStyle.Gate(
                        "resourcebars",
                        CUI.BorderPxSliderCfg({
                            text = "Border Size",
                            disabled = healthBarOff,
                            disabledTooltip = "Health Bar",
                            getStep = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.borderSize or 1
                            end,
                            setStep = function(val)
                                local rowCfg = rowConf()
                                if rowCfg then rowCfg.borderSize = val end
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
                                if rowCfg then rowCfg.borderSizePx = val end
                            end,
                            apply = function()
                                RebuildHealth()
                                CUI:RefreshPage()
                            end,
                        })
                    )
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: the textured border's outward offsets get their own row while a
            -- textured style is selected (the stock styles gate it away exactly like the row above).
            do
                local rowCfg = rowConf()
                local texture = rowCfg and rowCfg.borderTexture or "solid"
                if texture ~= "solid" and texture ~= "" then
                    local function step()
                        local rowCfg = rowConf()
                        return rowCfg and rowCfg.borderSize or 1
                    end
                    local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                        addonKey = "resourcebars",
                        disabled = healthBarOff,
                        disabledTooltip = "Health Bar",
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
                            if rowCfg then rowCfg.borderTextureOffset = val end
                        end,
                        getY = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.borderTextureOffsetY
                        end,
                        setY = function(val)
                            local rowCfg = rowConf()
                            if rowCfg then rowCfg.borderTextureOffsetY = val end
                        end,
                        apply = function()
                            RebuildHealth()
                            CUI:RefreshPage()
                        end,
                    })
                    _, height = W:DualRow(
                        hostFrame,
                        cursorY,
                        CUI.BlizzStyle.Gate("resourcebars", ocfgL),
                        CUI.BlizzStyle.Gate("resourcebars", ocfgR)
                    )
                    cursorY = cursorY - height
                end
            end
            if not CUI._prebuilding and not mod.ERB_ClassicBorderRow() then
                local region = hpBsRow._rightRegion
                local control = region._control
                -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
                -- border size control. The stock styles keep the bars square.
                if not CUI._prebuilding then
                    CUI.BuildInlineCog(hpBsRow._rightRegion, {
                        title = "Corner Radius",
                        tip = "Corner Radius",
                        disabled = function()
                            if healthBarOff() or CUI.BlizzStyle.Get("resourcebars") then return true end
                            local rowCfg = rowConf()
                            return not CUI.RoundedStyleOK(rowCfg and rowCfg.borderTexture)
                        end,
                        disabledTooltip = function()
                            if CUI.BlizzStyle.Get("resourcebars") then
                                return CUI.BlizzStyle.Label("resourcebars")
                            end
                            if healthBarOff() then return "Health Bar" end
                            return "This option requires the Solid, Glow or Shadow border style."
                        end,
                        requireState = function()
                            return CUI.BlizzStyle.Get("resourcebars") and "disabled" or "enabled"
                        end,
                        rows = CUI.RoundedCornerRows({
                            {
                                type = "slider",
                                label = "Corner Radius",
                                min = 0,
                                max = CUI.ROUNDED_MAX_RADIUS,
                                step = 1,
                                get = ConfGetter("cornerRadius", 0),
                                set = ConfSetter("cornerRadius", RebuildHealth),
                            },
                        }, function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.cornerMask
                        end, function(val)
                            local rowCfg = rowConf()
                            if not rowCfg then return end
                            rowCfg.cornerMask = val
                            RebuildHealth()
                        end),
                    })
                end
                local borderSwatch, updateBorderSwatch = CUI.BuildColorSwatch(
                    region,
                    hpBsRow:GetFrameLevel() + 3,
                    function()
                        local rowCfg = rowConf()
                        return (rowCfg and rowCfg.borderR or 0),
                            (rowCfg and rowCfg.borderG or 0),
                            (rowCfg and rowCfg.borderB or 0),
                            (rowCfg and rowCfg.borderA or 1)
                    end,
                    function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.borderR, rowCfg.borderG, rowCfg.borderB, rowCfg.borderA = red, green, blue, a
                        GentleRefresh()
                        CUI:RefreshPage()
                    end,
                    true,
                    20
                )
                Pix.Point(borderSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
                region._lastInline = borderSwatch -- left of the Corner Radius cog
                CUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
                local swBlock = CUI.NewSwatchBlocker(borderSwatch)
                swBlock:SetScript(
                    "OnEnter",
                    function()
                        CUI.ShowWidgetTooltip(borderSwatch, CUI.DisabledTooltip("Health Bar"))
                    end
                )
                swBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                local function UpdateBorderSwDis()
                    if healthBarOff() then
                        borderSwatch:SetAlpha(0.3)
                        swBlock:Show()
                    else
                        borderSwatch:SetAlpha(1)
                        swBlock:Hide()
                    end
                end
                CUI.RegisterWidgetRefresh(UpdateBorderSwDis)
                UpdateBorderSwDis()
            end
            if not CUI._prebuilding then
                local region = hpBsRow._leftRegion
                local cogBtn = CUI.BuildInlineCog(region, {
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
                                if not rowCfg then return 0 end
                                local val = rowCfg.borderTextureShiftX
                                if val then return val end
                                local _, _, dsx = CUI.GetBorderDefaults(
                                    "resourcebars",
                                    rowCfg.borderTexture or "solid",
                                    rowCfg.borderSize or 1
                                )
                                return dsx
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then return end
                                rowCfg.borderTextureShiftX = val == 0 and nil or val
                                RebuildHealth()
                                CUI:RefreshPage()
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
                                if not rowCfg then return 0 end
                                local val = rowCfg.borderTextureShiftY
                                if val then return val end
                                local _, _, _, dsy = CUI.GetBorderDefaults(
                                    "resourcebars",
                                    rowCfg.borderTexture or "solid",
                                    rowCfg.borderSize or 1
                                )
                                return dsy
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then return end
                                rowCfg.borderTextureShiftY = val == 0 and nil or val
                                RebuildHealth()
                                CUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = ConfGetter("borderBehind", false),
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then return end
                                rowCfg.borderBehind = val == false and nil or val
                                RebuildHealth()
                                CUI:RefreshPage()
                            end,
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
                CUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Cross-bar "apply to all" sync icons: Simple only
            if
                not context.advanced
                and context.syncRows
                and not CUI._prebuilding
                and mod.ERB_ClassicBorderRow()
            then
                context.syncRows.healthBorder = hpBsRow._rightRegion
                mod.ERB_ClassicBorderSync(
                    hpBsRow._rightRegion,
                    DB,
                    "health",
                    GentleRefresh,
                    function()
                        return {
                            context.syncRows.healthBorder,
                            context.syncRows.classBorder,
                            context.syncRows.powerBorder,
                        }
                    end
                )
            elseif not context.advanced and context.syncRows and not CUI._prebuilding then
                context.syncRows.healthBorder = hpBsRow._rightRegion
                CUI.BuildSyncIcon({
                    region = hpBsRow._leftRegion,
                    tooltip = "Apply Border Style to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        local was = mod.ERB_TexturedBars(profile)
                        local cfg = profile.health
                        local function apply(tbl)
                            tbl.borderTexture = cfg.borderTexture
                            tbl.borderTextureOffset = cfg.borderTextureOffset
                            tbl.borderTextureOffsetY = cfg.borderTextureOffsetY
                            tbl.borderTextureShiftX = cfg.borderTextureShiftX
                            tbl.borderTextureShiftY = cfg.borderTextureShiftY
                            tbl.borderR = cfg.borderR
                            tbl.borderG = cfg.borderG
                            tbl.borderB = cfg.borderB
                            tbl.borderA = cfg.borderA
                            tbl.borderSize = cfg.borderSize
                            mod.ERB_CopyBorderPx(tbl, cfg)
                            tbl.borderBehind = cfg.borderBehind
                        end
                        apply(profile.secondary)
                        apply(profile.primary)
                        GentleRefresh()
                        CUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then return false end
                        local bt = profile.health.borderTexture or "solid"
                        local bh = profile.health.borderBehind or false
                        return (profile.secondary.borderTexture or "solid") == bt
                            and (profile.primary.borderTexture or "solid") == bt
                            and (profile.secondary.borderBehind or false) == bh
                            and (profile.primary.borderBehind or false) == bh
                    end,
                    flashTargets = function() return { hpBsRow._leftRegion } end,
                })
                CUI.BuildSyncIcon({
                    region = hpBsRow._rightRegion,
                    tooltip = "Apply Border to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        local was = mod.ERB_TexturedBars(profile)
                        local red, green, blue, a =
                            profile.health.borderR,
                            profile.health.borderG,
                            profile.health.borderB,
                            profile.health.borderA
                        local sz = profile.health.borderSize or 1
                        local bt = profile.health.borderTexture or "solid"
                        local cr, cm = profile.health.cornerRadius or 0, profile.health.cornerMask
                        profile.secondary.borderR, profile.secondary.borderG, profile.secondary.borderB, profile.secondary.borderA =
                            red, green, blue, a
                        profile.secondary.borderSize = sz
                        profile.secondary.borderTexture = bt
                        profile.secondary.cornerRadius = cr
                        profile.secondary.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.secondary, profile.health)
                        profile.primary.borderR, profile.primary.borderG, profile.primary.borderB, profile.primary.borderA =
                            red, green, blue, a
                        profile.primary.borderSize = sz
                        profile.primary.borderTexture = bt
                        profile.primary.cornerRadius = cr
                        profile.primary.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.primary, profile.health)
                        GentleRefresh()
                        CUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then return false end
                        local sr, sg, scrollBar, sa, ssz =
                            profile.health.borderR,
                            profile.health.borderG,
                            profile.health.borderB,
                            profile.health.borderA,
                            profile.health.borderSize or 1
                        local sbt, scr, scm =
                            profile.health.borderTexture or "solid",
                            profile.health.cornerRadius or 0,
                            profile.health.cornerMask or 15
                        local function eq(tbl)
                            return tbl.borderR == sr
                                and tbl.borderG == sg
                                and tbl.borderB == scrollBar
                                and tbl.borderA == sa
                                and (tbl.borderSize or 1) == ssz
                                and (tbl.borderTexture or "solid") == sbt
                                and (tbl.cornerRadius or 0) == scr
                                and (tbl.cornerMask or 15) == scm
                                and mod.ERB_SameBorderPx(tbl, profile.health)
                        end
                        return eq(profile.secondary) and eq(profile.primary)
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.healthBorder,
                            context.syncRows.classBorder,
                            context.syncRows.powerBorder,
                        }
                    end,
                })
            end
        end

        -- Row 4: Opacity | Fill Color (gradient/custom/class). The Opacity "apply to all" sync icon is Simple-only; the gradient swatch disables while threshold coloring is on.
        local healthBorderRow
        healthBorderRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 5,
            disabled = healthBarOff,
            disabledTooltip = "Health Bar",
            getValue = function()
                local rowCfg = rowConf()
                return math.floor((rowCfg and rowCfg.barAlpha or 1) * 100 + 0.5)
            end,
            setValue = function(val)
                local rowCfg = rowConf()
                if not rowCfg then return end
                rowCfg.barAlpha = val / 100
                RefreshHealth()
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
            disabled = healthBarOff,
            disabledTooltip = "Health Bar",
            getValue = function()
                local rowCfg = rowConf()
                return (rowCfg and rowCfg.fillOpacity) or 100
            end,
            setValue = ConfSetter("fillOpacity", RebuildHealth),
        })
        cursorY = cursorY - height
        -- Fill Color inline cog: gradient settings
        if not CUI._prebuilding then
            local region = healthBorderRow._rightRegion
            CUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = "Health Bar",
                title = "Fill Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Enable Gradient",
                        get = ConfGetter("gradientEnabled"),
                        set = ConfSetter("gradientEnabled", RebuildHealth, true),
                    },
                    {
                        type = "dropdown",
                        label = "Gradient Direction",
                        values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                        order = { "HORIZONTAL", "VERTICAL" },
                        get = ConfGetter("gradientDir", "HORIZONTAL"),
                        set = ConfSetter("gradientDir", RebuildHealth),
                    },
                },
            })
        end
        -- Fill Color inline swatches: gradient end / custom / class
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(healthBorderRow._rightRegion, {
                {
                    tooltip = "Gradient End Color",
                    hasAlpha = true,
                    disabled = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return true end
                        if not rowCfg.enabled then return true end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(rowCfg)
                        if tse and (tse.thresholdEnabled ~= false) then return true end
                        return not rowCfg.gradientEnabled
                    end,
                    disabledTooltip = function()
                        local rowCfg = rowConf()
                        if not rowCfg or not rowCfg.enabled then return "Health Bar" end
                        local tse = _G._CURB_ResolveThresholdSpecEntry
                            and _G._CURB_ResolveThresholdSpecEntry(rowCfg)
                        if tse and (tse.thresholdEnabled ~= false) then
                            return "This option requires the threshold to be off in Threshold & Hash Lines"
                        end
                        return "Gradient"
                    end,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return 0.20, 0.20, 0.80, 1 end
                        return rowCfg.gradientR, rowCfg.gradientG, rowCfg.gradientB, rowCfg.gradientA
                    end,
                    setValue = function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.gradientR, rowCfg.gradientG, rowCfg.gradientB, rowCfg.gradientA =
                            red, green, blue, a
                        GentleRefresh()
                    end,
                },
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return 37 / 255, 193 / 255, 29 / 255, 1 end
                        return rowCfg.fillR, rowCfg.fillG, rowCfg.fillB, 1
                    end,
                    setValue = function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.fillR, rowCfg.fillG, rowCfg.fillB = red, green, blue
                        if not rowCfg.customColored then rowCfg.customColored = true end
                        GentleRefresh()
                        CUI:RefreshPage()
                    end,
                    onClick = function(self)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        if not rowCfg.customColored then
                            rowCfg.customColored = true
                            RebuildHealth()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isClassColored = not rowCfg or not rowCfg.customColored
                        return isClassColored and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    getValue = function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b, 1 end
                        return 37 / 255, 193 / 255, 29 / 255, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.customColored = false
                        RebuildHealth()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isClassColored = not rowCfg or not rowCfg.customColored
                        return isClassColored and 1 or 0.3
                    end,
                },
            }, { size = 20, disabled = healthBarOff, disabledTooltip = "Health Bar" })
        end
        if not context.advanced and context.syncRows and not CUI._prebuilding then
            context.syncRows.healthOpacity = healthBorderRow._leftRegion
            local region = healthBorderRow._leftRegion
            CUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local profile = DB()
                    if not profile then return end
                    local val = profile.health.barAlpha or 1
                    profile.secondary.barAlpha = val
                    profile.primary.barAlpha = val
                    GentleRefresh()
                    CUI:RefreshPage()
                end,
                isSynced = function()
                    local profile = DB()
                    if not profile then return false end
                    local val = profile.health.barAlpha or 1
                    return (profile.secondary.barAlpha or 1) == val and (profile.primary.barAlpha or 1) == val
                end,
                flashTargets = function()
                    return {
                        context.syncRows.healthOpacity,
                        context.syncRows.classOpacity,
                        context.syncRows.powerOpacity,
                    }
                end,
            })
        end

        -- Out of Combat Opacity & Visibility cog: Fade Out of Combat dims the Health bar to this alpha out of combat (100 = no fade; ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat). Show When Health Missing shows the bar at its normal opacity while health is below full, a rule-hidden bar and a faded one alike (ns.ERB_MissingWanted / ns.ERB_MissingLiftFloor, same pass).
        if not CUI._prebuilding then
            local region = healthBorderRow._leftRegion
            CUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = "Health Bar",
                title = "Out of Combat Opacity & Visibility",
                rows = {
                    {
                        type = "toggle",
                        label = "Fade Out of Combat",
                        get = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.oocFadeEnabled == true
                        end,
                        set = ConfSetter("oocFadeEnabled", RefreshHealth),
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
                            if not rowCfg then return end
                            rowCfg.oocAlpha = val / 100
                            RefreshHealth()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show When Health Missing",
                        tooltip = "Shows the Health bar while your health is below full, even when its Visibility setting hides it.",
                        get = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.showWhenMissing == true
                        end,
                        set = ConfSetter("showWhenMissing", RefreshHealth),
                    },
                },
            })
        end

        -- Text Color disables when the bar is off OR Health Text is None
        local function healthTextDis()
            local rowCfg = rowConf()
            if not rowCfg then return false end
            if not rowCfg.enabled then return true end
            return rowCfg.textFormat == "none"
        end
        local function healthTextDisTip()
            local rowCfg = rowConf()
            if rowCfg and not rowCfg.enabled then return "Health Bar" end
            return "This option requires a Health Text format other than None"
        end

        local healthTextSizeRow
        healthTextSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Health Text",
            disabled = healthBarOff,
            disabledTooltip = "Health Bar",
            values = {
                none = "None",
                perhp = "Health %",
                perhpnosign = "Health % (No Sign)",
                curhpshort = "Health #",
                curmaxhp = "Health # / Max #",
                perhpnum = "Health % | #",
                both = "Health # | %",
            },
            order = {
                "none",
                "---",
                "perhp",
                "perhpnosign",
                "curhpshort",
                "curmaxhp",
                "perhpnum",
                "both",
            },
            getValue = ConfGetter("textFormat", "none"),
            setValue = ConfSetter("textFormat", RefreshHealth, true),
        }, {
            type = "multiSwatch",
            text = "Text Color",
            tooltip = "The text's color.",
            disabled = healthTextDis,
            disabledTooltip = healthTextDisTip,
            swatches = {
                {
                    tooltip = "Custom Colored",
                    hasAlpha = true,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return 1, 1, 1, 1 end
                        return rowCfg.textFillR, rowCfg.textFillG, rowCfg.textFillB, rowCfg.textFillA
                    end,
                    setValue = function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.textFillR, rowCfg.textFillG, rowCfg.textFillB, rowCfg.textFillA =
                            red, green, blue, a
                        RebuildHealth()
                        GentleRefresh()
                    end,
                    onClick = function(self)
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        if rowCfg.textCustomColored == false then
                            rowCfg.textCustomColored = true
                            RebuildHealth()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isClassColored = rowCfg and rowCfg.textCustomColored == false
                        return isClassColored and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    getValue = function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b, 1 end
                        return 1, 1, 1, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then return end
                        rowCfg.textCustomColored = false
                        RebuildHealth()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isClassColored = rowCfg and rowCfg.textCustomColored == false
                        return isClassColored and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height
        -- Health Text inline cog: anchor + x/y offsets
        if not CUI._prebuilding then
            local region = healthTextSizeRow._leftRegion
            local cogBtn = CUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = "Health Bar",
                title = "Health Text",
                rows = {
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                        order = { "LEFT", "CENTER", "RIGHT" },
                        tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                        get = ConfGetter("textAnchor", "CENTER"),
                        set = ConfSetter("textAnchor", RefreshHealth),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = ConfGetter("textXOffset", 0),
                        set = ConfSetter("textXOffset", RefreshHealth),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = ConfGetter("textYOffset", 0),
                        set = ConfSetter("textYOffset", RefreshHealth),
                    },
                },
            })
            AddFormTextBtn(region, cogBtn, rowConf, RefreshHealth)
        end

        -- Row 5: Text Size | Threshold & Hash Lines
        local healthColorRow
        healthColorRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 24,
            step = 1,
            disabled = healthTextDis,
            disabledTooltip = healthTextDisTip,
            getValue = ConfGetter("textSize", 11),
            setValue = ConfSetter("textSize", RefreshHealth),
        }, { type = "label", text = "Threshold & Hash Lines" })
        cursorY = cursorY - height
        -- Threshold & Hash Lines editor: edits the health bar config (multi-spec, with the spec dropdown).

        if not CUI._prebuilding then
            local healthSettingsBtn = BuildThresholdSettingsButton({
                parentRgn = healthColorRow._rightRegion,
                getBarData = function() return rowConf() end,
                pageParent = hostFrame,
                pageTopY = _advTop,
                pageBotY = function() return cursorY end,
                refreshFn = function()
                    RefreshHealth()
                    GentleRefresh()
                end,
                rebuildFn = function() RebuildHealth() end,
                disabledFn = healthBarOff,
                disabledTip = "Health Bar",
                roleShortcuts = true,
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
                parentRgn = healthColorRow._rightRegion,
                anchorTo = healthSettingsBtn,
                getBarData = function() return DB().health end,
                refreshFn = function() RebuildHealth() end,
                popupTitle = CUI.L("Health Bar Hash Lines"),
            })
        end
        -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
        if CUI.SpecOverrides_AttachEditLock and not CUI._prebuilding then
            CUI.SpecOverrides_AttachEditLock(
                healthColorRow._rightRegion,
                "Thresholds have their own per-spec system and can't be edited while editing a spec group"
            )
        end
    end -- close Health Bar hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides Health in Advanced, so edits here aren't silently ignored.
    if not context.advanced then mod.ERB_SimpleOverrideOverlay(hostFrame, _advTop, cursorY, "health") end

    return cursorY, heading, healthEnableRow, unlockJump
end
