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
    local posY = yOffset
    local _, hgt

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
        local p = DB()
        return p and not p.gcdBar.enabled
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
    -- A setting row's setter for one GCD bar key: written (when the profile
    -- exists), the GCD bar redrawn, and with alsoPage the page rebuilt too.
    local function Setter(key, alsoPage)
        return function(val)
            local p = DB()
            if not p then
                return
            end
            p.gcdBar[key] = val
            RefreshGCD()
            if alsoPage then
                CludesUI:RefreshPage()
            end
        end
    end

    local _sec
    _sec, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
    posY = posY - hgt
    CludesUI.BuildSectionUnlockJump(
        _sec,
        { key = "ERB_GCDBar", disabled = gcdOff, disabledTooltip = "GCD Bar" }
    )
    local layoutSection = _sec

    local gStrataValues = CludesUI.FRAME_STRATA_LABELS
    local gStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE

    -- Row: Enable GCD Bar (+ position cog) | Frame Strata
    local enableRow
    enableRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable GCD Bar",
        tooltip = "Shows a bar that fills over the global cooldown.",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.enabled
        end,
        setValue = Setter("enabled", true),
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        values = gStrataValues,
        order = gStrataOrder,
        getValue = function()
            local p = DB()
            return p and p.gcdBar.frameStrata or "MEDIUM"
        end,
        setValue = Setter("frameStrata"),
    })
    posY = posY - hgt
    -- Inline position cog (X/Y + unlock) on Enable
    if not CludesUI._prebuilding then
        local region = enableRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and not p.gcdBar.enabled
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
                        local p = DB()
                        if not p then
                            return 0
                        end
                        local g = p.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            return g.unlockPos.x or 0
                        end
                        return g.anchorX or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        local g = p.gcdBar
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
                        local p = DB()
                        if not p then
                            return 0
                        end
                        local g = p.gcdBar
                        if g.unlockPos and g.unlockPos.point then
                            return g.unlockPos.y or 0
                        end
                        return g.anchorY or -78
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        local g = p.gcdBar
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
        local p = DB()
        return p and p.gcdBar and p.gcdBar.orientation
    end
    local ghDis, ghTip, ghRaw = mod.OrientedMatchGuard("ERB_GCDBar", "Height", gcdOri, gcdOff, "GCD Bar")
    local gwDis, gwTip, gwRaw = mod.OrientedMatchGuard("ERB_GCDBar", "Width", gcdOri, gcdOff, "GCD Bar")
    local sizeRow
    sizeRow, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Height",
        min = 1,
        max = 60,
        step = 1,
        disabled = ghDis,
        disabledTooltip = ghTip,
        rawTooltip = ghRaw,
        getValue = function()
            local p = DB()
            return p and p.gcdBar.height or 12
        end,
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
        getValue = function()
            local p = DB()
            return p and p.gcdBar.width or 220
        end,
        setValue = Setter("width"),
    })
    posY = posY - hgt

    -- Row: Orientation | Instance Only
    _, hgt = W:DualRow(hostFrame, posY, {
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
        getValue = function()
            local p = DB()
            return p and p.gcdBar.orientation or "HORIZONTAL"
        end,
        setValue = Setter("orientation", true),
    }, {
        type = "toggle",
        text = "Instance Only",
        tooltip = "Only show the GCD bar while in a dungeon, raid, arena or battleground.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.instanceOnly
        end,
        setValue = Setter("instanceOnly"),
    })
    posY = posY - hgt

    -- Row: Only Instant Casts | Always Show (+ idle fill cog)
    local gcdShowRow
    gcdShowRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Only Instant Casts",
        tooltip = "Only show the GCD bar for instant-cast abilities. While hard-casting or channeling a spell, the bar stays hidden (the cast bar already shows that progress).",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.instantOnly
        end,
        setValue = Setter("instantOnly"),
    }, {
        type = "toggle",
        text = "Always Show",
        tooltip = "Keep the GCD bar visible (sitting empty) when no global cooldown is running, instead of hiding it.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.alwaysShow
        end,
        setValue = Setter("alwaysShow"),
    })
    posY = posY - hgt
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
                        local p = DB()
                        return (p and p.gcdBar.idleShowFill) == true
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        if val then
                            p.gcdBar.idleShowFill = true
                        else
                            p.gcdBar.idleShowFill = nil
                        end
                        RefreshGCD()
                    end,
                },
            },
        })
    end

    _, hgt = W:Spacer(hostFrame, posY, 16)
    posY = posY - hgt

    _sec, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - hgt

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog)
    do
        local btValues, btOrder = CludesUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "dropdown",
                text = "Border Style",
                disabled = gcdOff,
                disabledTooltip = "GCD Bar",
                values = btValues,
                order = btOrder,
                getValue = function()
                    local p = DB()
                    return p and p.gcdBar.borderTexture or "solid"
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.gcdBar.borderTexture = val
                    p.gcdBar.borderTextureOffset = nil
                    p.gcdBar.borderTextureOffsetY = nil
                    p.gcdBar.borderTextureShiftX = nil
                    p.gcdBar.borderTextureShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                    p.gcdBar.borderR = _bcol.r
                    p.gcdBar.borderG = _bcol.g
                    p.gcdBar.borderB = _bcol.b
                    p.gcdBar.borderA = 1
                    p.gcdBar.borderBehind = _bbehind
                    local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then
                        p.gcdBar.borderSize = defSz
                    end
                    if p.gcdBar.borderSizePx then
                        p.gcdBar.borderSizePx = false
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
                    local p = DB()
                    return p and (p.gcdBar.borderSize or 0) or 0
                end,
                setStep = function(val)
                    local p = DB()
                    if p then
                        p.gcdBar.borderSize = val
                    end
                end,
                getTex = function()
                    local p = DB()
                    return p and (p.gcdBar.borderTexture or "solid") or "solid"
                end,
                getPx = function()
                    local p = DB()
                    return p and p.gcdBar.borderSizePx
                end,
                setPx = function(val)
                    local p = DB()
                    if p then
                        p.gcdBar.borderSizePx = val
                    end
                end,
                apply = function()
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
            })
        )
        posY = posY - hgt
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local p = DB()
            local tex = p and p.gcdBar.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step()
                    local p = DB()
                    return p and (p.gcdBar.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = gcdOff,
                    disabledTooltip = "GCD Bar",
                    getTex = function()
                        local p = DB()
                        return p and (p.gcdBar.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local p = DB()
                        return p and p.gcdBar.borderSizePx
                    end,
                    getX = function()
                        local p = DB()
                        return p and p.gcdBar.borderTextureOffset
                    end,
                    setX = function(val)
                        local p = DB()
                        if p then
                            p.gcdBar.borderTextureOffset = val
                        end
                    end,
                    getY = function()
                        local p = DB()
                        return p and p.gcdBar.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local p = DB()
                        if p then
                            p.gcdBar.borderTextureOffsetY = val
                        end
                    end,
                    apply = function()
                        RefreshGCD()
                        CludesUI:RefreshPage()
                    end,
                })
                _, hgt = W:DualRow(hostFrame, posY, ocfgL, ocfgR)
                posY = posY - hgt
            end
        end
        -- Border color swatch on the size slider (right region); none in the
        -- search pre-build (it indexes nothing, and the row is a stand-in there)
        if not CludesUI._prebuilding then
            local region = bsRow._rightRegion
            local ctrl = region._control
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                bsRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.gcdBar.borderR or 0),
                        (p and p.gcdBar.borderG or 0),
                        (p and p.gcdBar.borderB or 0),
                        (p and p.gcdBar.borderA or 1)
                end,
                function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.gcdBar.borderR, p.gcdBar.borderG, p.gcdBar.borderB, p.gcdBar.borderA = r, g, b, a
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
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
                local p = DB()
                local noBorder = not p or (p.gcdBar.borderSize or 0) == 0
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
                            local p = DB()
                            if not p then
                                return 0
                            end
                            local val = p.gcdBar.borderTextureShiftX
                            if val then
                                return val
                            end
                            local _, _, dsx = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                p.gcdBar.borderTexture or "solid",
                                p.gcdBar.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.gcdBar.borderTextureShiftX = val == 0 and nil or val
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
                            local p = DB()
                            if not p then
                                return 0
                            end
                            local val = p.gcdBar.borderTextureShiftY
                            if val then
                                return val
                            end
                            local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                p.gcdBar.borderTexture or "solid",
                                p.gcdBar.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.gcdBar.borderTextureShiftY = val == 0 and nil or val
                            RefreshGCD()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.borderBehind or false
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.gcdBar.borderBehind = val == false and nil or val
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
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.borderExtendTop or 0
                        end,
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
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.borderExtendBottom or 0
                        end,
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
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.borderExtendLeft or 0
                        end,
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
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.borderExtendRight or 0
                        end,
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
                            local p = DB()
                            if not (p and p.gcdBar.edgeSep) then
                                return "none"
                            end
                            return p.gcdBar.edgeSepArt or "match"
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            if val == "none" then
                                p.gcdBar.edgeSep = false
                            else
                                p.gcdBar.edgeSep = true
                                p.gcdBar.edgeSepArt = val
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
                            local p = DB()
                            return gcdOff() or not (p and p.gcdBar.edgeSep)
                        end,
                        disabledTooltip = function()
                            return gcdOff() and "GCD Bar" or "Bottom Separator"
                        end,
                        get = function()
                            local p = DB()
                            return p and p.gcdBar.edgeSepY or 0
                        end,
                        set = Setter("edgeSepY", true),
                    },
                },
            })
            local function UpdateCogVis()
                local p = DB()
                local tex = p and p.gcdBar.borderTexture or "solid"
                if tex == "solid" then
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
    colorRow, hgt = W:DualRow(hostFrame, posY, {
        type = "multiSwatch",
        text = "Color",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        swatches = {
            {
                tooltip = "Gradient End Color",
                hasAlpha = true,
                getValue = function()
                    local p = DB()
                    if not p then
                        return 0.20, 0.20, 0.80, 1
                    end
                    return p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA
                end,
                setValue = function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA =
                        r, g, b, a
                    RefreshGCD()
                end,
            },
            {
                tooltip = "Custom Colored",
                hasAlpha = true,
                getValue = function()
                    local p = DB()
                    if not p then
                        local _, castFrame = UnitClass("player")
                        local cc = CLASS_COLORS[castFrame]
                        return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1
                    end
                    return p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA
                end,
                setValue = function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA = r, g, b, a
                    if p.gcdBar.classColored then
                        p.gcdBar.classColored = false
                    end
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                onClick = function(self)
                    local p = DB()
                    if not p then
                        return
                    end
                    if p.gcdBar.classColored then
                        p.gcdBar.classColored = false
                        RefreshGCD()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    local p = DB()
                    return (p and not p.gcdBar.classColored) and 1 or 0.3
                end,
            },
            {
                tooltip = "Class Colored",
                getValue = function()
                    local _, class = UnitClass("player")
                    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                    if cc then
                        return cc.r, cc.g, cc.b, 1
                    end
                    return 1, 0.70, 0, 1
                end,
                setValue = function() end,
                onClick = function()
                    local p = DB()
                    if not p then
                        return
                    end
                    p.gcdBar.classColored = true
                    RefreshGCD()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local p = DB()
                    return (not p or p.gcdBar.classColored == true) and 1 or 0.3
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
            local p = DB()
            return math.floor(((p and p.gcdBar.bgA or 0.7) * 100) + 0.5)
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.gcdBar.bgA = val / 100
            RefreshGCD()
        end,
    })
    posY = posY - hgt
    -- Gradient cog on Color
    if not CludesUI._prebuilding then
        local region = colorRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and not p.gcdBar.enabled
            end,
            disabledTooltip = "GCD Bar",
            title = "Gradient Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Enable Gradient",
                    get = function()
                        local p = DB()
                        return p and p.gcdBar.gradientEnabled
                    end,
                    set = Setter("gradientEnabled", true),
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = function()
                        local p = DB()
                        return p and p.gcdBar.gradientDir or "HORIZONTAL"
                    end,
                    set = Setter("gradientDir"),
                },
            },
        })
    end
    -- Gradient end-color swatch enable/disable
    do
        local colorSwatch = colorRow._leftRegion._control
        local function UpdateGradientSwatch()
            local p = DB()
            if not p or not p.gcdBar.enabled then
                colorSwatch:SetAlpha(0.15)
                colorSwatch:Disable()
                colorSwatch._disabledTooltip = "GCD Bar"
            elseif not p.gcdBar.gradientEnabled then
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
        local ctrl = region._control
        local bgSwatch, bgUpdateSwatch = CludesUI.BuildColorSwatch(
            region,
            colorRow:GetFrameLevel() + 3,
            function()
                local p = DB()
                return (p and p.gcdBar.bgR or 0), (p and p.gcdBar.bgG or 0), (p and p.gcdBar.bgB or 0)
            end,
            function(r, g, b)
                local p = DB()
                if not p then
                    return
                end
                p.gcdBar.bgR, p.gcdBar.bgG, p.gcdBar.bgB = r, g, b
                RefreshGCD()
            end,
            nil,
            20
        )
        Pix.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local p = DB()
            if not p or not p.gcdBar.enabled then
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
    gcdTexRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Bar Texture",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        values = texValues,
        order = texOrder,
        getValue = function()
            local p = DB()
            return p and p.gcdBar.texture or "none"
        end,
        setValue = Setter("texture"),
    }, {
        type = "toggle",
        text = "Show Spark",
        tooltip = "Show a small glowing spark that moves along the leading edge of the fill.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.showSpark
        end,
        setValue = Setter("showSpark"),
    })
    posY = posY - hgt
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
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Deplete Fill",
        tooltip = "Start the bar full and drain it as the global cooldown elapses, instead of filling it up.",
        disabled = gcdOff,
        disabledTooltip = "GCD Bar",
        getValue = function()
            local p = DB()
            return p and p.gcdBar.depleteFill
        end,
        setValue = Setter("depleteFill"),
    }, { type = "spacer" })
    posY = posY - hgt

    -- Click mapping for the preview's hit overlay (never from a hidden pre-build)
    if not CludesUI._prebuilding then
        _clickMappings.gcdBar = { section = layoutSection, target = sizeRow }
    end

    return math.abs(posY)
end
