if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\GCDBarPage_Options.lua
--  Resource Bars options: GCD Bar page. Definitions only; the shared
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

-- GCD Bar page
function mod.ERB_BuildGCDBarPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix, CLASS_COLORS, _clickMappings =
        environ.DB, environ.PP, environ.CLASS_COLORS, environ._clickMappings
    local UpdateGCDPreview = environ.UpdateGCDPreview
    local TexBgRowCfg = environ.TexBgRowCfg
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    environ.SetGCDPreviewFill(math.random(30, 85) / 100)
    CludesUI:SetContentHeader(environ._gcdPreviewBuilder)

    -- Clear this page's own click mapping (shared table; never from a hidden pre-build)
    if not CludesUI._prebuilding then
        _clickMappings.gcdBar = nil
    end

    -- Re-append SharedMedia textures (catches lazy-registered SM packs)
    CludesUI.AppendSharedMediaTextures(
        _G._CURB_BarTextureNames or {},
        _G._CURB_BarTextureOrder or {},
        nil,
        _G._CURB_BarTextures
    )
    -- Bar texture dropdown values (same set the renderer uses)
    local texValues, texOrder = {}, {}
    do
        local texNames = _G._CURB_BarTextureNames or {}
        local texOrder2 = _G._CURB_BarTextureOrder or {}
        local texLookup = _G._CURB_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                texValues[key] = texNames[key] or key
            end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texLookup[key]
            end,
        }
    end

    local gcdOff = function()
        local profile = DB()
        return profile and not profile.gcdBar.enabled
    end

    local function RefreshGCD()
        if _G._CURB_Apply then
            _G._CURB_Apply()
        end
        if CludesUI.NotifyElementResized then
            CludesUI.NotifyElementResized("ERB_GCDBar")
        end
        UpdateGCDPreview()
    end
    -- A setting row's getter for one GCD bar key: its value, or default when
    -- it is unset (no default: the value as stored, nil without a profile).
    local function Getter(key, default)
        return function()
            local profile = DB()
            if default == nil then
                return profile and profile.gcdBar[key]
            end
            return profile and profile.gcdBar[key] or default
        end
    end
    -- A setting row's setter for one GCD bar key: written (when the profile
    -- exists), the GCD bar redrawn, and with alsoPage the page rebuilt too.
    local function Setter(key, alsoPage)
        return function(val)
            local profile = DB()
            if not profile then
                return
            end
            profile.gcdBar[key] = val
            RefreshGCD()
            if alsoPage then
                CludesUI:RefreshPage()
            end
        end
    end

    local _sec
    _sec, height = W:SectionHeader(hostFrame, "LAYOUT", cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(
        _sec,
        { key = "ERB_GCDBar", disabled = gcdOff, disabledTooltip = "GCD Bar" }
    )
    local layoutSection = _sec

    local gStrataValues = CludesUI.FRAME_STRATA_LABELS
    local gStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE

    -- Row: Enable GCD Bar (+ position cog) | Frame Strata
    local enableRow
    enableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable GCD Bar",
        tooltip = "Shows a bar that fills over the global cooldown.",
        getValue = Getter("enabled"),
        setValue = Setter("enabled", true),
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        values = gStrataValues,
        order = gStrataOrder,
        getValue = Getter("frameStrata", "MEDIUM"),
        setValue = Setter("frameStrata"),
    })
    cursorY = cursorY - height
    -- Inline position cog (X/Y + unlock) on Enable
    if not CludesUI._prebuilding then
        local region = enableRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and not profile.gcdBar.enabled
            end,
            disabledTooltip = "GCD Bar",
            title = "GCD Bar Position",
            rows = {
                -- X/Y edit whichever position is in effect: the saved unlock position takes priority in the renderer, so once it exists these sliders adjust it (otherwise the CENTER offset).
                {
                    type = "slider",
                    label = "X Offset",
                    min = -600,
                    max = 600,
                    step = 1,
                    get = function()
                        local profile = DB()
                        if not profile then
                            return 0
                        end
                        local g = profile.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            return g.unlockPos.x or 0
                        end
                        return g.anchorX or 0
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local g = profile.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            g.unlockPos.x = val
                        else
                            g.anchorX = val
                        end
                        RefreshGCD()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -600,
                    max = 600,
                    step = 1,
                    get = function()
                        local profile = DB()
                        if not profile then
                            return 0
                        end
                        local g = profile.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            return g.unlockPos.y or 0
                        end
                        return g.anchorY or -78
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local g = profile.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            g.unlockPos.y = val
                        else
                            g.anchorY = val
                        end
                        RefreshGCD()
                    end,
                },
            },
            footer = { unlockKey = "ERB_GCDBar" },
        })
    end

    -- Row: Height | Width. Orientation-aware: this bar's size callbacks report the drawn axes, so its sliders must be guarded on the matching axis for vertical orientations.
    local function gcdOri()
        local profile = DB()
        return profile and profile.gcdBar and profile.gcdBar.orientation
    end
    local ghDis, ghTip, ghRaw = mod.OrientedMatchGuard("ERB_GCDBar", "Height", gcdOri, gcdOff, "GCD Bar")
    local gwDis, gwTip, gwRaw = mod.OrientedMatchGuard("ERB_GCDBar", "Width", gcdOri, gcdOff, "GCD Bar")
    local sizeRow
    sizeRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Height",
        min = 1,
        max = 60,
        step = 1,
        disabled = ghDis,
        disabledTooltip = ghTip,
        rawTooltip = ghRaw,
        getValue = Getter("height", 12),
        setValue = Setter("height"),
    }, {
        type = "slider",
        text = "Width",
        min = 50,
        max = 800,
        step = 1,
        disabled = gwDis,
        disabledTooltip = gwTip,
        rawTooltip = gwRaw,
        getValue = Getter("width", 220),
        setValue = Setter("width"),
    })
    cursorY = cursorY - height

    -- Row: Orientation | Instance Only
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Orientation",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        values = {
            HORIZONTAL = "Horizontal (Right)",
            HORIZONTAL_LEFT = "Horizontal (Left)",
            VERTICAL_UP = "Vertical (Up)",
            VERTICAL_DOWN = "Vertical (Down)",
        },
        order = { "HORIZONTAL", "HORIZONTAL_LEFT", "VERTICAL_UP", "VERTICAL_DOWN" },
        getValue = Getter("orientation", "HORIZONTAL"),
        setValue = Setter("orientation", true),
    }, {
        type = "toggle",
        text = "Instance Only",
        tooltip = "Only show the GCD bar while in a dungeon, raid, arena or battleground.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = Getter("instanceOnly"),
        setValue = Setter("instanceOnly"),
    })
    cursorY = cursorY - height

    -- Row: Only Instant Casts | Always Show (+ idle fill cog)
    local gcdShowRow
    gcdShowRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Only Instant Casts",
        tooltip = "Only show the GCD bar for instant-cast abilities. While hard-casting or channeling a spell, the bar stays hidden (the cast bar already shows that progress).",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = Getter("instantOnly"),
        setValue = Setter("instantOnly"),
    }, {
        type = "toggle",
        text = "Always Show",
        tooltip = "Keep the GCD bar visible (sitting empty) when no global cooldown is running, instead of hiding it.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = Getter("alwaysShow"),
        setValue = Setter("alwaysShow"),
    })
    cursorY = cursorY - height
    -- Inline cog on Always Show: idle fill appearance
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(gcdShowRow._rightRegion, {
            title = "Always Show",
            rows = {
                {
                    type = "toggle",
                    label = "Show Fill Color When Idle",
                    tooltip = "Show the bar full of its fill color while no global cooldown is running, instead of the background color.",
                    get = function()
                        local profile = DB()
                        return (profile and profile.gcdBar.idleShowFill) == true
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        if val then
                            profile.gcdBar.idleShowFill = true
                        else
                            profile.gcdBar.idleShowFill = nil
                        end
                        RefreshGCD()
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    _sec, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog)
    do
        local btValues, btOrder = CludesUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Border Style",
                disabled = gcdOff,
                disabledTooltip = "GCD Bar",
                values = btValues,
                order = btOrder,
                getValue = Getter("borderTexture", "solid"),
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.gcdBar.borderTexture = val
                    profile.gcdBar.borderTextureOffset = nil
                    profile.gcdBar.borderTextureOffsetY = nil
                    profile.gcdBar.borderTextureShiftX = nil
                    profile.gcdBar.borderTextureShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                    profile.gcdBar.borderR = _bcol.r
                    profile.gcdBar.borderG = _bcol.g
                    profile.gcdBar.borderB = _bcol.b
                    profile.gcdBar.borderA = 1
                    profile.gcdBar.borderBehind = _bbehind
                    local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then
                        profile.gcdBar.borderSize = defSz
                    end
                    if profile.gcdBar.borderSizePx then
                        profile.gcdBar.borderSizePx = false
                    end
                    RefreshGCD()
                    CludesUI:RefreshPage(true)
                end,
            },
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = gcdOff,
                disabledTooltip = "GCD Bar",
                getStep = function()
                    local profile = DB()
                    return profile and (profile.gcdBar.borderSize or 0) or 0
                end,
                setStep = function(val)
                    local profile = DB()
                    if profile then
                        profile.gcdBar.borderSize = val
                    end
                end,
                getTex = function()
                    local profile = DB()
                    return profile and (profile.gcdBar.borderTexture or "solid") or "solid"
                end,
                getPx = function()
                    local profile = DB()
                    return profile and profile.gcdBar.borderSizePx
                end,
                setPx = function(val)
                    local profile = DB()
                    if profile then
                        profile.gcdBar.borderSizePx = val
                    end
                end,
                apply = function()
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
            })
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local profile = DB()
            local texture = profile and profile.gcdBar.borderTexture or "solid"
            if texture ~= "solid" and texture ~= "" then
                local function step()
                    local profile = DB()
                    return profile and (profile.gcdBar.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = gcdOff,
                    disabledTooltip = "GCD Bar",
                    getTex = function()
                        local profile = DB()
                        return profile and (profile.gcdBar.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local profile = DB()
                        return profile and profile.gcdBar.borderSizePx
                    end,
                    getX = function()
                        local profile = DB()
                        return profile and profile.gcdBar.borderTextureOffset
                    end,
                    setX = function(val)
                        local profile = DB()
                        if profile then
                            profile.gcdBar.borderTextureOffset = val
                        end
                    end,
                    getY = function()
                        local profile = DB()
                        return profile and profile.gcdBar.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local profile = DB()
                        if profile then
                            profile.gcdBar.borderTextureOffsetY = val
                        end
                    end,
                    apply = function()
                        RefreshGCD()
                        CludesUI:RefreshPage()
                    end,
                })
                _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                cursorY = cursorY - height
            end
        end
        -- Border color swatch on the size slider (right region); none in the
        -- search pre-build (it indexes nothing, and the row is a stand-in there)
        if not CludesUI._prebuilding then
            local region = bsRow._rightRegion
            local control = region._control
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                bsRow:GetFrameLevel() + 3,
                function()
                    local profile = DB()
                    return (profile and profile.gcdBar.borderR or 0),
                        (profile and profile.gcdBar.borderG or 0),
                        (profile and profile.gcdBar.borderB or 0),
                        (profile and profile.gcdBar.borderA or 1)
                end,
                function(red, green, blue, a)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.gcdBar.borderR, profile.gcdBar.borderG, profile.gcdBar.borderB, profile.gcdBar.borderA = red, green, blue, a
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
            local block = CludesUI.NewSwatchBlocker(colorSwatch)
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
                local profile = DB()
                local noBorder = not profile or (profile.gcdBar.borderSize or 0) == 0
                if noBorder then
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
        -- Offset cog on Border Style (left region), hidden for "solid"
        if not CludesUI._prebuilding then
            local region = bsRow._leftRegion
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
                            local profile = DB()
                            if not profile then
                                return 0
                            end
                            local val = profile.gcdBar.borderTextureShiftX
                            if val then
                                return val
                            end
                            local _, _, dsx = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                profile.gcdBar.borderTexture or "solid",
                                profile.gcdBar.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then
                                return
                            end
                            profile.gcdBar.borderTextureShiftX = val == 0 and nil or val
                            RefreshGCD()
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
                            local profile = DB()
                            if not profile then
                                return 0
                            end
                            local val = profile.gcdBar.borderTextureShiftY
                            if val then
                                return val
                            end
                            local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                profile.gcdBar.borderTexture or "solid",
                                profile.gcdBar.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then
                                return
                            end
                            profile.gcdBar.borderTextureShiftY = val == 0 and nil or val
                            RefreshGCD()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = Getter("borderBehind", false),
                        set = function(val)
                            local profile = DB()
                            if not profile then
                                return
                            end
                            profile.gcdBar.borderBehind = val == false and nil or val
                            RefreshGCD()
                            CludesUI:RefreshPage()
                        end,
                    },
                    -- Border extensions (0 = off); the cog has no bar-off block.
                    {
                        type = "slider",
                        label = "Extend Top",
                        min = 0,
                        max = 50,
                        step = 1,
                        tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                        disabled = gcdOff,
                        disabledTooltip = "GCD Bar",
                        get = Getter("borderExtendTop", 0),
                        set = Setter("borderExtendTop", true),
                    },
                    {
                        type = "slider",
                        label = "Extend Bottom",
                        min = 0,
                        max = 50,
                        step = 1,
                        tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                        disabled = gcdOff,
                        disabledTooltip = "GCD Bar",
                        get = Getter("borderExtendBottom", 0),
                        set = Setter("borderExtendBottom", true),
                    },
                    {
                        type = "slider",
                        label = "Extend Left",
                        min = 0,
                        max = 300,
                        step = 1,
                        tooltip = "Grows the border past the bar's left edge on screen without resizing the bar.",
                        disabled = gcdOff,
                        disabledTooltip = "GCD Bar",
                        get = Getter("borderExtendLeft", 0),
                        set = Setter("borderExtendLeft", true),
                    },
                    {
                        type = "slider",
                        label = "Extend Right",
                        min = 0,
                        max = 300,
                        step = 1,
                        tooltip = "Grows the border past the bar's right edge on screen without resizing the bar.",
                        disabled = gcdOff,
                        disabledTooltip = "GCD Bar",
                        get = Getter("borderExtendRight", 0),
                        set = Setter("borderExtendRight", true),
                    },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art.
                    {
                        type = "dropdown",
                        label = "Bottom Separator",
                        values = sepValues,
                        order = sepOrder,
                        tooltip = "Draws a separator line along the bar's bottom edge.",
                        disabled = gcdOff,
                        disabledTooltip = "GCD Bar",
                        get = function()
                            local profile = DB()
                            if not (profile and profile.gcdBar.edgeSep) then
                                return "none"
                            end
                            return profile.gcdBar.edgeSepArt or "match"
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then
                                return
                            end
                            if val == "none" then
                                profile.gcdBar.edgeSep = false
                            else
                                profile.gcdBar.edgeSep = true
                                profile.gcdBar.edgeSepArt = val
                            end
                            RefreshGCD()
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
                            local profile = DB()
                            return gcdOff() or not (profile and profile.gcdBar.edgeSep)
                        end,
                        disabledTooltip = function()
                            return gcdOff() and "GCD Bar" or "Bottom Separator"
                        end,
                        get = Getter("edgeSepY", 0),
                        set = Setter("edgeSepY", true),
                    },
                },
            })
            local function UpdateCogVis()
                local profile = DB()
                local texture = profile and profile.gcdBar.borderTexture or "solid"
                if texture == "solid" then
                    cogBtn:Hide()
                else
                    cogBtn:Show()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row: Color (gradient end / custom / class + gradient cog) | Background (+ bg swatch)
    local colorRow
    colorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Color",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        swatches = {
            {
                tooltip = "Gradient End Color",
                hasAlpha = true,
                getValue = function()
                    local profile = DB()
                    if not profile then
                        return 0.20, 0.20, 0.80, 1
                    end
                    return profile.gcdBar.gradientR, profile.gcdBar.gradientG, profile.gcdBar.gradientB, profile.gcdBar.gradientA
                end,
                setValue = function(red, green, blue, a)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.gcdBar.gradientR, profile.gcdBar.gradientG, profile.gcdBar.gradientB, profile.gcdBar.gradientA =
                        red, green, blue, a
                    RefreshGCD()
                end,
            },
            {
                tooltip = "Custom Colored",
                hasAlpha = true,
                getValue = function()
                    local profile = DB()
                    if not profile then
                        local _, castFrame = UnitClass("player")
                        local classColor = CLASS_COLORS[castFrame]
                        return classColor and classColor[1] or 1, classColor and classColor[2] or 0.70, classColor and classColor[3] or 0, 1
                    end
                    return profile.gcdBar.fillR, profile.gcdBar.fillG, profile.gcdBar.fillB, profile.gcdBar.fillA
                end,
                setValue = function(red, green, blue, a)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.gcdBar.fillR, profile.gcdBar.fillG, profile.gcdBar.fillB, profile.gcdBar.fillA = red, green, blue, a
                    if profile.gcdBar.classColored then
                        profile.gcdBar.classColored = false
                    end
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                onClick = function(self)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    if profile.gcdBar.classColored then
                        profile.gcdBar.classColored = false
                        RefreshGCD()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    local profile = DB()
                    return (profile and not profile.gcdBar.classColored) and 1 or 0.3
                end,
            },
            {
                tooltip = "Class Colored",
                getValue = function()
                    local _, class = UnitClass("player")
                    local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                    if classColor then
                        return classColor.r, classColor.g, classColor.b, 1
                    end
                    return 1, 0.70, 0, 1
                end,
                setValue = function() end,
                onClick = function()
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.gcdBar.classColored = true
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local profile = DB()
                    return (not profile or profile.gcdBar.classColored == true) and 1 or 0.3
                end,
            },
        },
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local profile = DB()
            return math.floor(((profile and profile.gcdBar.bgA or 0.7) * 100) + 0.5)
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then
                return
            end
            profile.gcdBar.bgA = val / 100
            RefreshGCD()
        end,
    })
    cursorY = cursorY - height
    -- Gradient cog on Color
    if not CludesUI._prebuilding then
        local region = colorRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and not profile.gcdBar.enabled
            end,
            disabledTooltip = "GCD Bar",
            title = "Gradient Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Enable Gradient",
                    get = Getter("gradientEnabled"),
                    set = Setter("gradientEnabled", true),
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = Getter("gradientDir", "HORIZONTAL"),
                    set = Setter("gradientDir"),
                },
            },
        })
    end
    -- Gradient end-color swatch enable/disable
    do
        local colorSwatch = colorRow._leftRegion._control
        local function UpdateGradientSwatch()
            local profile = DB()
            if not profile or not profile.gcdBar.enabled then
                colorSwatch:SetAlpha(0.15)
                colorSwatch:Disable()
                colorSwatch._disabledTooltip = "GCD Bar"
            elseif not profile.gcdBar.gradientEnabled then
                colorSwatch:SetAlpha(0.15)
                colorSwatch:Disable()
                colorSwatch._disabledTooltip = "Gradient"
            else
                colorSwatch:SetAlpha(1)
                colorSwatch:Enable()
                colorSwatch._disabledTooltip = nil
            end
        end
        UpdateGradientSwatch()
        CludesUI.RegisterWidgetRefresh(UpdateGradientSwatch)
    end
    -- Background color swatch on the Background slider (right region)
    if not CludesUI._prebuilding then
        local region = colorRow._rightRegion
        local control = region._control
        local bgSwatch, bgUpdateSwatch = CludesUI.BuildColorSwatch(
            region,
            colorRow:GetFrameLevel() + 3,
            function()
                local profile = DB()
                return (profile and profile.gcdBar.bgR or 0), (profile and profile.gcdBar.bgG or 0), (profile and profile.gcdBar.bgB or 0)
            end,
            function(red, green, blue)
                local profile = DB()
                if not profile then
                    return
                end
                profile.gcdBar.bgR, profile.gcdBar.bgG, profile.gcdBar.bgB = red, green, blue
                RefreshGCD()
            end,
            nil,
            20
        )
        Pix.Point(bgSwatch, "RIGHT", control, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local profile = DB()
            if not profile or not profile.gcdBar.enabled then
                bgSwatch:SetAlpha(0.15)
                bgSwatch:Disable()
                bgSwatch._disabledTooltip = "GCD Bar"
            else
                bgSwatch:SetAlpha(1)
                bgSwatch:Enable()
                bgSwatch._disabledTooltip = nil
            end
            bgUpdateSwatch()
        end
        UpdateBgSwatch()
        CludesUI.RegisterWidgetRefresh(UpdateBgSwatch)
    end

    -- Row: Bar Texture | Show Spark
    local gcdTexRow
    gcdTexRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        values = texValues,
        order = texOrder,
        getValue = Getter("texture", "none"),
        setValue = Setter("texture"),
    }, {
        type = "toggle",
        text = "Show Spark",
        tooltip = "Show a small glowing spark that moves along the leading edge of the fill.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = Getter("showSpark"),
        setValue = Setter("showSpark"),
    })
    cursorY = cursorY - height
    -- Inline cog on Bar Texture: Textured Background (greyed with the dropdown).
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(gcdTexRow._leftRegion, {
            disabled = gcdOff,
            disabledTooltip = "GCD Bar",
            title = "Texture Settings",
            rows = { TexBgRowCfg("gcd", RefreshGCD) },
        })
    end

    -- Row: Deplete Fill (left half only)
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Deplete Fill",
        tooltip = "Start the bar full and drain it as the global cooldown elapses, instead of filling it up.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = Getter("depleteFill"),
        setValue = Setter("depleteFill"),
    }, { type = "spacer" })
    cursorY = cursorY - height

    -- Click mapping for the preview's hit overlay (never from a hidden pre-build)
    if not CludesUI._prebuilding then
        _clickMappings.gcdBar = { section = layoutSection, target = sizeRow }
    end

    return math.abs(cursorY)
end
