if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\CastBarPage_Options.lua
--  Resource Bars options: Cast Bar page. Definitions only; the shared
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

-- Cast Bar page
function mod.ERB_BuildCastBarPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix, CLASS_COLORS, _clickMappings =
        environ.DB, environ.PP, environ.CLASS_COLORS, environ._clickMappings
    local ShuffleCastBarIcons, UpdateCastBarPreview, _castBarPreviewBuilder =
        environ.ShuffleCastBarIcons, environ.UpdateCastBarPreview, environ._castBarPreviewBuilder
    local TexBgRowCfg = environ.TexBgRowCfg
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, hgt

    hostFrame._showRowDivider = true

    environ.SetCastBarPreviewFill(math.random(30, 85) / 100)
    ShuffleCastBarIcons()
    CludesUI:SetContentHeader(_castBarPreviewBuilder)

    -- Clear this page's own click mappings (the table is shared with the display page, whose
    -- cached preview keeps its own; never from a hidden pre-build -- see the matching guard in
    -- BuildBarDisplayPage)
    if not CludesUI._prebuilding then
        _clickMappings.castBar, _clickMappings.castIcon, _clickMappings.castSpellText, _clickMappings.castTimer =
            nil, nil, nil, nil
    end

    -- Re-append SharedMedia textures for cast bar (catches lazy-registered SM packs)
    CludesUI.AppendSharedMediaTextures(
        _G._CURB_CastBarTextureNames or {},
        _G._CURB_CastBarTextureOrder or {},
        nil,
        _G._CURB_CastBarTextures
    )
    -- Texture dropdown values (same as nameplates)
    local texValues = {}
    local texOrder = {}
    do
        local nameList = _G._CURB_CastBarTextureNames or {}
        local sequence = _G._CURB_CastBarTextureOrder or {}
        local lookup = _G._CURB_CastBarTextures or {}
        for _, key in ipairs(sequence) do
            if key ~= "---" then
                texValues[key] = nameList[key] or key
            end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return lookup[key]
            end,
        }
    end

    local castOff = function()
        local p = DB()
        return p and not p.castBar.enabled
    end

    local function RefreshCast()
        if _G._CURB_Apply then
            _G._CURB_Apply()
        end
        if CludesUI.NotifyElementResized then
            CludesUI.NotifyElementResized("ERB_CastBar")
        end
        UpdateCastBarPreview()
    end

    local castSection
    castSection, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
    posY = posY - hgt
    CludesUI.BuildSectionUnlockJump(
        castSection,
        { key = "ERB_CastBar", disabled = castOff, disabledTooltip = "Player Cast Bar" }
    )

    -- Strata dropdown values for the Cast Bar Frame Strata control.
    local cbStrataValues = CludesUI.FRAME_STRATA_LABELS
    local cbStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE

    -- Row 1: Enable Player Cast Bar | Frame Strata
    local castEnableRow
    castEnableRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.enabled
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.enabled = val
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        values = cbStrataValues,
        order = cbStrataOrder,
        getValue = function()
            local p = DB()
            return p and p.castBar.frameStrata or "MEDIUM"
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.frameStrata = val
            RefreshCast()
        end,
    })
    posY = posY - hgt
    -- (No position cog here: the cast bar is positioned via Unlock Mode; the old X/Y offset cog wrote anchor keys the runtime never reads.)

    -- Row 2: Height | Width (sync icons push to power + health bars)
    local classSizeRow
    local cbhDis, cbhTip, cbhRaw = CludesUI.MatchGuard("ERB_CastBar", "Height", castOff, "Player Cast Bar")
    local cbwDis, cbwTip, cbwRaw = CludesUI.MatchGuard("ERB_CastBar", "Width", castOff, "Player Cast Bar")
    classSizeRow, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Height",
        min = 1,
        max = 60,
        step = 1,
        disabled = cbhDis,
        disabledTooltip = cbhTip,
        rawTooltip = cbhRaw,
        getValue = function()
            local p = DB()
            return p and p.castBar.height or 20
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.height = val
            RefreshCast()
        end,
    }, {
        type = "slider",
        text = "Width",
        min = 50,
        max = 800,
        step = 1,
        disabled = cbwDis,
        disabledTooltip = cbwTip,
        rawTooltip = cbwRaw,
        getValue = function()
            local p = DB()
            return p and p.castBar.width or 220
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.width = val
            RefreshCast()
        end,
    })
    posY = posY - hgt

    -- Row 3: Show Spell Icon (cog: side, divider, size, offsets) | Show Spark
    local iconRow
    iconRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Spell Icon",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.showIcon ~= false
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showIcon = val
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Spark",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.showSpark
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showSpark = val
            RefreshCast()
        end,
    })
    posY = posY - hgt
    -- Inline cog on Show Spell Icon
    if not CludesUI._prebuilding then
        local region = iconRow._leftRegion
        local FREE_TIP = "This option requires the icon at bar size with no offset."
        local function IconFree()
            local p = DB()
            return p and mod.ERB_CastIconFree(p.castBar)
        end
        local function IconOnPortrait()
            local p = DB()
            return p and mod.ERB_CastIconPortrait(p.castBar) ~= nil
        end
        -- Embed in Player Portrait: nil while a player portrait can take the icon, else why
        -- not ("uf": the Unit Frames player cast bar already shows its icon there).
        local function PortraitBlock()
            local uf = CludesUI._ModuleNS["CludesUIUnitFrames"]
            if not (uf and uf.UF_GetPlayerCastPortrait) then
                return "portrait"
            end
            local edge, _, why = uf.UF_GetPlayerCastPortrait()
            if edge then
                return nil
            end
            return why or "portrait"
        end
        local function PlayerPortraitOff()
            return PortraitBlock() ~= nil
        end
        local function IconSlider(key, labelText, lo, hi, tooltip)
            return {
                type = "slider",
                label = labelText,
                min = lo,
                max = hi,
                step = 1,
                tooltip = tooltip,
                disabled = function()
                    return IconOnPortrait() or CludesUI.BlizzStyle.Get("castbar")
                end,
                disabledTooltip = function()
                    if IconOnPortrait() then
                        return "Embed in Player Portrait"
                    end
                    return CludesUI.BlizzStyle.Label("castbar")
                end,
                requireState = "disabled",
                get = function()
                    local p = DB()
                    return p and p.castBar[key] or 0
                end,
                set = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.castBar[key] = val
                    RefreshCast()
                end,
            }
        end
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and (not p.castBar.enabled or p.castBar.showIcon == false)
            end,
            disabledTooltip = function()
                local p = DB()
                return (p and not p.castBar.enabled) and "Player Cast Bar" or "Show Spell Icon"
            end,
            title = "Spell Icon Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Embed in Player Portrait",
                    tooltip = "Show the spell icon over the player portrait while casting.",
                    disabled = PlayerPortraitOff,
                    disabledTooltip = function()
                        if PortraitBlock() == "uf" then
                            return "This option can't be used while the Unit Frames player cast bar shows its icon on the portrait."
                        end
                        return "This option requires an enabled player portrait in Unit Frames."
                    end,
                    rawTooltip = true,
                    get = function()
                        local p = DB()
                        return p and p.castBar.iconOnPortrait == true
                    end,
                    set = function(val)
                        local p = DB()
                        if not p or (val and PlayerPortraitOff()) then
                            return
                        end
                        p.castBar.iconOnPortrait = val
                        RefreshCast()
                    end,
                },
                {
                    type = "toggle",
                    label = "Icon on Right",
                    tooltip = "Attach the spell icon to the right of the cast bar instead of the left.",
                    disabled = IconOnPortrait,
                    disabledTooltip = "Embed in Player Portrait",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        return p and p.castBar.iconOnRight
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.iconOnRight = val
                        RefreshCast()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Icon Divider",
                    tooltip = "Draw a 1px divider between the spell icon and the cast bar, matching the border color.",
                    disabled = function()
                        return IconOnPortrait() or IconFree()
                    end,
                    disabledTooltip = function()
                        if IconOnPortrait() then
                            return CludesUI.DisabledTooltip("Embed in Player Portrait", "disabled")
                        end
                        return FREE_TIP
                    end,
                    rawTooltip = true,
                    get = function()
                        local p = DB()
                        return p and p.castBar.showIconDivider
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.showIconDivider = val
                        RefreshCast()
                    end,
                },
                -- Border Art Divider: the divider in the border style's own art (the
                -- Pixels styles); any other style keeps the solid line.
                {
                    type = "toggle",
                    label = "Border Art Divider",
                    tooltip = "Draws the icon divider in the border style's art instead of a solid line.",
                    disabled = function()
                        local p = DB()
                        if not p then
                            return true
                        end
                        local cb = p.castBar
                        return IconOnPortrait()
                            or not cb.showIconDivider
                            or CludesUI.BlizzStyle.Get("castbar")
                            or not CludesUI.GetBorderCompanion(cb.borderTexture, "sepV")
                    end,
                    disabledTooltip = function()
                        if IconOnPortrait() then
                            return "Embed in Player Portrait"
                        end
                        if CludesUI.BlizzStyle.Get("castbar") then
                            return CludesUI.DisabledTooltip(CludesUI.BlizzStyle.Label("castbar"), "disabled")
                        end
                        local p = DB()
                        if not (p and p.castBar.showIconDivider) then
                            return "Show Icon Divider"
                        end
                        return "This option requires a border style with matching art, such as Pixels."
                    end,
                    rawTooltip = function()
                        if CludesUI.BlizzStyle.Get("castbar") then
                            return true
                        end
                        local p = DB()
                        return (p and p.castBar.showIconDivider) and true or false
                    end,
                    get = function()
                        local p = DB()
                        return p and p.castBar.iconDividerArt or false
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.iconDividerArt = val and true or false
                        RefreshCast()
                    end,
                },
                IconSlider(
                    "iconSize",
                    "Icon Size",
                    0,
                    64,
                    "0 matches the bar height. Any other size or offset detaches the icon from the bar."
                ),
                IconSlider("iconOffsetX", "Offset X", -100, 100),
                IconSlider("iconOffsetY", "Offset Y", -100, 100),
            },
        })
    end

    -- Row 4: Always Show
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Always Show",
        tooltip = "Keep the cast bar visible (sitting empty) when you are not casting, instead of hiding it.",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.alwaysShow
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.alwaysShow = val
            RefreshCast()
        end,
    }, {
        type = "toggle",
        text = "Smooth Bar Animation",
        tooltip = "Eases the cast fill between updates. Turn off for a raw, uneased fill.",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return not (p and p.castBar.smoothFill == false)
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            if val then
                p.castBar.smoothFill = nil
            else
                p.castBar.smoothFill = false
            end
            RefreshCast()
        end,
    })
    posY = posY - hgt

    _, hgt = W:Spacer(hostFrame, posY, 16)
    posY = posY - hgt

    local displaySection
    displaySection, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
    posY = posY - hgt
    posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "castbar")

    -- Row: Cast Bar Border Style dropdown (+ inline offset cog)
    do
        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        local cbBsRow
        cbBsRow, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("castbar", {
                type = "dropdown",
                text = "Border Style",
                disabled = castOff,
                disabledTooltip = "Player Cast Bar",
                values = texValues,
                order = texOrder,
                getValue = function()
                    local p = DB()
                    return p and p.castBar.borderTexture or "solid"
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.castBar.borderTexture = val
                    p.castBar.borderTextureOffset = nil
                    p.castBar.borderTextureOffsetY = nil
                    p.castBar.borderTextureShiftX = nil
                    p.castBar.borderTextureShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                    p.castBar.borderR = _bcol.r
                    p.castBar.borderG = _bcol.g
                    p.castBar.borderB = _bcol.b
                    p.castBar.borderA = 1
                    p.castBar.borderBehind = _bbehind
                    local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then
                        p.castBar.borderSize = defSz
                    end
                    if p.castBar.borderSizePx then
                        p.castBar.borderSizePx = false
                    end
                    RefreshCast()
                    CludesUI:RefreshPage(true)
                end,
            }),
            -- Classic WoW UI: the slot sizes the vanilla frame instead.
            (CludesUI.BlizzStyle.Active("castbar") == "classic")
                    and CludesUI.BlizzStyle.ClassicBorderSizeCfg(function()
                        local p = DB()
                        return p and p.castBar.stockBorderScale
                    end, function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.stockBorderScale = val
                        RefreshCast()
                        CludesUI.ReapplyMatchPads("ERB_CastBar")
                    end, { disabled = castOff, disabledTooltip = "Player Cast Bar" })
                or CludesUI.BlizzStyle.Gate(
                    "castbar",
                    CludesUI.BorderPxSliderCfg({
                        text = "Border Size",
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        getStep = function()
                            local p = DB()
                            return p and (p.castBar.borderSize or 0) or 0
                        end,
                        setStep = function(val)
                            local p = DB()
                            if p then
                                p.castBar.borderSize = val
                            end
                        end,
                        getTex = function()
                            local p = DB()
                            return p and (p.castBar.borderTexture or "solid") or "solid"
                        end,
                        getPx = function()
                            local p = DB()
                            return p and p.castBar.borderSizePx
                        end,
                        setPx = function(val)
                            local p = DB()
                            if p then
                                p.castBar.borderSizePx = val
                            end
                        end,
                        apply = function()
                            RefreshCast()
                            CludesUI:RefreshPage()
                        end,
                    })
                )
        )
        posY = posY - hgt
        -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
        do
            local p = DB()
            local tex = p and p.castBar.borderTexture or "solid"
            if tex ~= "solid" and tex ~= "" then
                local function step()
                    local p = DB()
                    return p and (p.castBar.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = castOff,
                    disabledTooltip = "Player Cast Bar",
                    getTex = function()
                        local p = DB()
                        return p and (p.castBar.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local p = DB()
                        return p and p.castBar.borderSizePx
                    end,
                    getX = function()
                        local p = DB()
                        return p and p.castBar.borderTextureOffset
                    end,
                    setX = function(val)
                        local p = DB()
                        if p then
                            p.castBar.borderTextureOffset = val
                        end
                    end,
                    getY = function()
                        local p = DB()
                        return p and p.castBar.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local p = DB()
                        if p then
                            p.castBar.borderTextureOffsetY = val
                        end
                    end,
                    apply = function()
                        RefreshCast()
                        CludesUI:RefreshPage()
                    end,
                })
                _, hgt = W:DualRow(
                    hostFrame,
                    posY,
                    CludesUI.BlizzStyle.Gate("castbar", ocfgL),
                    CludesUI.BlizzStyle.Gate("castbar", ocfgR)
                )
                posY = posY - hgt
            end
        end
        -- Inline border color swatch on Border slider (right region); none
        -- under Classic WoW UI, whose slider sizes the vanilla frame.
        if not CludesUI._prebuilding and CludesUI.BlizzStyle.Active("castbar") ~= "classic" then
            local region = cbBsRow._rightRegion
            local ctrl = region._control
            local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                region,
                cbBsRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.castBar.borderR or 0),
                        (p and p.castBar.borderG or 0),
                        (p and p.castBar.borderB or 0),
                        (p and p.castBar.borderA or 1)
                end,
                function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.castBar.borderR, p.castBar.borderG, p.castBar.borderB, p.castBar.borderA = r, g, b, a
                    RefreshCast()
                    CludesUI:RefreshPage()
                end,
                true,
                20
            )
            Pix.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            -- Disable swatch when border size is 0
            local borderSwatchBlock = CludesUI.NewSwatchBlocker(borderSwatch)
            borderSwatchBlock:SetScript("OnEnter", function()
                if CludesUI.BlizzStyle.Get("castbar") then
                    CludesUI.ShowWidgetTooltip(
                        borderSwatch,
                        CludesUI.DisabledTooltip("Blizzard Style", "disabled")
                    )
                else
                    CludesUI.ShowWidgetTooltip(
                        borderSwatch,
                        CludesUI.DisabledTooltip("This option requires a Border Size above 0.")
                    )
                end
            end)
            borderSwatchBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateBorderSwatchState()
                local p = DB()
                local noBorder = not p
                    or (p.castBar.borderSize or 0) == 0
                    or CludesUI.BlizzStyle.Get("castbar")
                if noBorder then
                    borderSwatch:SetAlpha(0.3)
                    borderSwatchBlock:Show()
                else
                    borderSwatch:SetAlpha(1)
                    borderSwatchBlock:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateBorderSwatch()
                UpdateBorderSwatchState()
            end)
            UpdateBorderSwatchState()
        end
        if not CludesUI._prebuilding then
            local region = cbBsRow._leftRegion
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
                            local val = p.castBar.borderTextureShiftX
                            if val then
                                return val
                            end
                            local _, _, dsx = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                p.castBar.borderTexture or "solid",
                                p.castBar.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderTextureShiftX = val == 0 and nil or val
                            RefreshCast()
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
                            local val = p.castBar.borderTextureShiftY
                            if val then
                                return val
                            end
                            local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                p.castBar.borderTexture or "solid",
                                p.castBar.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderTextureShiftY = val == 0 and nil or val
                            RefreshCast()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local p = DB()
                            return p and p.castBar.borderBehind or false
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderBehind = val == false and nil or val
                            RefreshCast()
                            CludesUI:RefreshPage()
                        end,
                    },
                    -- Border extensions: the whole border host (bar + icon). This cog
                    -- has no bar-off block, so the rows carry their own.
                    {
                        type = "slider",
                        label = "Extend Top",
                        min = 0,
                        max = 50,
                        step = 1,
                        tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local p = DB()
                            return p and p.castBar.borderExtendTop or 0
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderExtendTop = val
                            RefreshCast()
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
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local p = DB()
                            return p and p.castBar.borderExtendBottom or 0
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderExtendBottom = val
                            RefreshCast()
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
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local p = DB()
                            return p and p.castBar.borderExtendLeft or 0
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderExtendLeft = val
                            RefreshCast()
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
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local p = DB()
                            return p and p.castBar.borderExtendRight or 0
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.borderExtendRight = val
                            RefreshCast()
                            CludesUI:RefreshPage()
                        end,
                    },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art. Across the whole bar, icon included.
                    {
                        type = "dropdown",
                        label = "Bottom Separator",
                        values = sepValues,
                        order = sepOrder,
                        tooltip = "Draws a separator line along the bar's bottom edge.",
                        disabled = castOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local p = DB()
                            if not (p and p.castBar.edgeSep) then
                                return "none"
                            end
                            return p.castBar.edgeSepArt or "match"
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            if val == "none" then
                                p.castBar.edgeSep = false
                            else
                                p.castBar.edgeSep = true
                                p.castBar.edgeSepArt = val
                            end
                            RefreshCast()
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
                            return castOff() or not (p and p.castBar.edgeSep)
                        end,
                        disabledTooltip = function()
                            return castOff() and "Player Cast Bar" or "Bottom Separator"
                        end,
                        get = function()
                            local p = DB()
                            return p and p.castBar.edgeSepY or 0
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.castBar.edgeSepY = val
                            RefreshCast()
                            CludesUI:RefreshPage()
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                local p = DB()
                local tex = p and p.castBar.borderTexture or "solid"
                if tex == "solid" or CludesUI.BlizzStyle.Get("castbar") then
                    cogBtn:Hide()
                else
                    cogBtn:Show()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row 2: Fill Color (opacity slider + cog: gradient + inline swatches) | Background
    local castColorRow
    castColorRow, hgt = W:DualRow(
        hostFrame,
        posY,
        {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
            disabled = castOff,
            disabledTooltip = "Player Cast Bar",
            getValue = function()
                local p = DB()
                return p and (p.castBar.fillOpacity or 100) or 100
            end,
            setValue = function(val)
                local p = DB()
                if not p then
                    return
                end
                p.castBar.fillOpacity = val
                RefreshCast()
            end,
        },
        mod.ERB_CastBlizzOnlyGate({
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            disabled = castOff,
            disabledTooltip = "Player Cast Bar",
            getValue = function()
                local p = DB()
                return math.floor(((p and p.castBar.bgA or 0.7) * 100) + 0.5)
            end,
            setValue = function(val)
                local p = DB()
                if not p then
                    return
                end
                p.castBar.bgA = val / 100
                RefreshCast()
            end,
        })
    )
    posY = posY - hgt
    local castFillBlizz = CludesUI.BlizzStyle.Active("castbar") == "blizzard"
    -- Inline cog on Fill Color: the gradient and the channel / uninterruptible
    -- color overrides (not under Blizzard Style, whose fill art is stock) and Out
    -- of Range Gray (every style).
    if not CludesUI._prebuilding then
        local region = castColorRow._leftRegion
        local function gradientOff()
            return castFillBlizz
        end
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and not p.castBar.enabled
            end,
            disabledTooltip = "Player Cast Bar",
            title = "Fill Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Enable Gradient",
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        return p and p.castBar.gradientEnabled
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.gradientEnabled = val
                        RefreshCast()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = function()
                        local p = DB()
                        return p and p.castBar.gradientDir or "HORIZONTAL"
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.gradientDir = val
                        RefreshCast()
                    end,
                },
                {
                    type = "toggle",
                    label = "Gray When Out of Range",
                    tooltip = "Grays the fill while your target is out of range of the spell being cast.",
                    get = function()
                        local p = DB()
                        return p and p.castBar.outOfRangeGray == true
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.outOfRangeGray = val
                        RefreshCast()
                    end,
                },
                -- Each override's color row shows only while that override is on.
                {
                    type = "toggle",
                    label = "Channel Color Override",
                    tooltip = "Channeled spells fill in their own color.",
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        return p and p.castBar.channelOverride == true
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.channelOverride = val
                        RefreshCast()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Channel Color",
                    hidden = function()
                        local p = DB()
                        return not (p and p.castBar.channelOverride)
                    end,
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        local c = p and p.castBar
                        return c and c.channelR or 0.3, c and c.channelG or 0.8, c and c.channelB or 0.3
                    end,
                    set = function(r, g, b)
                        local p = DB()
                        if not p then
                            return
                        end
                        local c = p.castBar
                        c.channelR, c.channelG, c.channelB = r, g, b
                        RefreshCast()
                    end,
                },
                {
                    type = "toggle",
                    label = "Uninterruptible Color Override",
                    tooltip = "Casts that cannot be interrupted fill in their own color.",
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        return p and p.castBar.uninterruptibleOverride == true
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.uninterruptibleOverride = val
                        RefreshCast()
                    end,
                },
                {
                    type = "colorpicker",
                    label = "Uninterruptible Color",
                    hidden = function()
                        local p = DB()
                        return not (p and p.castBar.uninterruptibleOverride)
                    end,
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local p = DB()
                        local c = p and p.castBar
                        return c and c.uninterruptibleR or 0.5,
                            c and c.uninterruptibleG or 0.5,
                            c and c.uninterruptibleB or 0.5
                    end,
                    set = function(r, g, b)
                        local p = DB()
                        if not p then
                            return
                        end
                        local c = p.castBar
                        c.uninterruptibleR, c.uninterruptibleG, c.uninterruptibleB = r, g, b
                        RefreshCast()
                    end,
                },
            },
        })
    end
    -- Fill Color inline swatches: gradient end / custom / class. Blizzard Style
    -- keeps the stock fill art, so the colour swatches are inert there; the
    -- Classic WoW UI fill is the user's, so they stay live under it.
    CludesUI.BuildInlineSwatches(castColorRow._leftRegion, {
        {
            tooltip = "Gradient End Color",
            hasAlpha = true,
            disabled = function()
                local p = DB()
                if not p or not p.castBar.enabled then
                    return true
                end
                return not p.castBar.gradientEnabled
            end,
            disabledTooltip = function()
                if castFillBlizz then
                    return "This option requires Blizzard Style to be disabled"
                end
                local p = DB()
                if not p or not p.castBar.enabled then
                    return "Player Cast Bar"
                end
                return "Gradient"
            end,
            getValue = function()
                local p = DB()
                if not p then
                    return 0.20, 0.20, 0.80, 1
                end
                return p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA
            end,
            setValue = function(r, g, b, a)
                local p = DB()
                if not p then
                    return
                end
                p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA =
                    r, g, b, a
                RefreshCast()
            end,
        },
        {
            tooltip = "Custom Colored",
            hasAlpha = false,
            getValue = function()
                local p = DB()
                if not p then
                    local _, castFrame = UnitClass("player")
                    local cc = CLASS_COLORS[castFrame]
                    return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1
                end
                return p.castBar.fillR, p.castBar.fillG, p.castBar.fillB, 1
            end,
            setValue = function(r, g, b)
                local p = DB()
                if not p then
                    return
                end
                p.castBar.fillR, p.castBar.fillG, p.castBar.fillB = r, g, b
                if p.castBar.classColored then
                    p.castBar.classColored = false
                end
                RefreshCast()
                CludesUI:RefreshPage()
            end,
            onClick = function(self)
                local p = DB()
                if not p then
                    return
                end
                if p.castBar.classColored then
                    p.castBar.classColored = false
                    RefreshCast()
                    CludesUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then
                    self._eabOrigClick(self)
                end
            end,
            refreshAlpha = function()
                local p = DB()
                return (p and not p.castBar.classColored) and 1 or 0.3
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
                p.castBar.classColored = true
                RefreshCast()
                CludesUI:RefreshPage()
            end,
            refreshAlpha = function()
                local p = DB()
                return (not p or p.castBar.classColored == true) and 1 or 0.3
            end,
        },
    }, {
        size = 20,
        disabled = function()
            return castFillBlizz or castOff()
        end,
        disabledTooltip = function()
            if castFillBlizz then
                return "This option requires Blizzard Style to be disabled"
            end
            return "Player Cast Bar"
        end,
    })

    -- Inline color swatch on Background (right region)
    if not CludesUI._prebuilding then
        local region = castColorRow._rightRegion
        local ctrl = region._control
        local bgSwatch, bgUpdateSwatch = CludesUI.BuildColorSwatch(
            region,
            castColorRow:GetFrameLevel() + 3,
            function()
                local p = DB()
                return (p and p.castBar.bgR or 0), (p and p.castBar.bgG or 0), (p and p.castBar.bgB or 0)
            end,
            function(r, g, b)
                local p = DB()
                if not p then
                    return
                end
                p.castBar.bgR, p.castBar.bgG, p.castBar.bgB = r, g, b
                RefreshCast()
            end,
            nil,
            20
        )
        Pix.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local p = DB()
            -- Gated with the Background slider beside it: Blizzard Style
            -- paints the stock background art; the classic bar keeps this colour.
            if CludesUI.BlizzStyle.Active("castbar") == "blizzard" then
                bgSwatch:SetAlpha(0.15)
                bgSwatch:Disable()
                bgSwatch._disabledTooltip = CludesUI.BlizzStyle.Label("castbar")
            elseif not p or not p.castBar.enabled then
                bgSwatch:SetAlpha(0.15)
                bgSwatch:Disable()
                bgSwatch._disabledTooltip = "Player Cast Bar"
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

    -- Row 3: Bar Texture | Spell Text (cog RESIZE: text size + x/y)
    -- Bar Texture is gated under Blizzard Style only (the stock fill art);
    -- the Classic WoW UI fill is the user's texture, so the row stays live.
    local castTexCfg = {
        type = "dropdown",
        text = "Bar Texture",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        values = texValues,
        order = texOrder,
        getValue = function()
            local p = DB()
            return p and p.castBar.texture or "none"
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.texture = val
            RefreshCast()
        end,
    }
    if CludesUI.BlizzStyle.Active("castbar") == "blizzard" then
        CludesUI.BlizzStyle.Gate("castbar", castTexCfg)
    end
    local textRow
    textRow, hgt = W:DualRow(hostFrame, posY, castTexCfg, {
        type = "dropdown",
        text = "Spell Text",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        values = { none = "None", left = "Left", right = "Right", center = "Center" },
        order = { "none", "left", "right", "center" },
        getValue = function()
            local p = DB()
            if not p or not p.castBar.showSpellText then
                return "none"
            end
            return p.castBar.spellTextSide or "left"
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            if val == "none" then
                p.castBar.showSpellText = false
            else
                p.castBar.showSpellText = true
                p.castBar.spellTextSide = val
            end
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt
    -- Inline cog on Bar Texture: Textured Background (greyed while the cast bar
    -- is off, and under Blizzard Style, whose own background art stays).
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(textRow._leftRegion, {
            disabled = function()
                return castOff() or CludesUI.BlizzStyle.Active("castbar") == "blizzard"
            end,
            disabledTooltip = function()
                if castOff() then
                    return "Player Cast Bar"
                end
                return CludesUI.BlizzStyle.Label("castbar")
            end,
            requireState = function()
                if not castOff() then
                    return "disabled"
                end
            end,
            title = "Texture Settings",
            rows = { TexBgRowCfg("cast", RefreshCast) },
        })
    end
    -- Inline cog (RESIZE) on Spell Text for text size + x/y
    if not CludesUI._prebuilding then
        local region = textRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and (not p.castBar.enabled or not p.castBar.showSpellText)
            end,
            disabledTooltip = "Player Cast Bar",
            title = "Spell Text Settings",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.spellTextSize or 11
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.spellTextSize = val
                        RefreshCast()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.spellTextX or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.spellTextX = val
                        RefreshCast()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.spellTextY or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.spellTextY = val
                        RefreshCast()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Full Spell Name",
                    tooltip = "Long spell names shrink to fit beside the duration instead of being cut off.",
                    get = function()
                        local p = DB()
                        return p and p.castBar.fitSpellName
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.fitSpellName = val
                        RefreshCast()
                    end,
                },
            },
        })
    end
    -- Spell Text colour (RGBA; white = the untinted text), left of the
    -- Spell Text Settings cog above. Dimmed and blocked while the cast bar
    -- is off or Spell Text is None.
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineSwatches(textRow._rightRegion, {
            {
                tooltip = "Spell Text Color",
                hasAlpha = true,
                disabled = function()
                    local p = DB()
                    return not (p and p.castBar.enabled and p.castBar.showSpellText)
                end,
                disabledTooltip = function()
                    return castOff() and "Player Cast Bar" or "Spell Text"
                end,
                getValue = function()
                    local p = DB()
                    if not p then
                        return 1, 1, 1, 1
                    end
                    local c = p.castBar
                    return c.spellTextR or 1, c.spellTextG or 1, c.spellTextB or 1, c.spellTextA or 1
                end,
                setValue = function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    local c = p.castBar
                    c.spellTextR, c.spellTextG, c.spellTextB, c.spellTextA = r, g, b, a
                    RefreshCast()
                    CludesUI:RefreshPage()
                end,
            },
        }, { size = 20 })
    end
    -- Row 4: Duration Text (cog RESIZE: timer size + x/y) | Show Total Duration
    local timerRow
    timerRow, hgt = W:DualRow(hostFrame, posY, {
        type = "segmented",
        text = "Duration Text",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        values = { none = "None", right = "Right", left = "Left" },
        order = { "none", "right", "left" },
        getValue = function()
            local p = DB()
            if not p or not p.castBar.showTimer then
                return "none"
            end
            return p.castBar.timerSide or "right"
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            if val == "none" then
                p.castBar.showTimer = false
            else
                p.castBar.showTimer = true
                p.castBar.timerSide = val
            end
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Total Duration",
        tooltip = "Shows elapsed / total duration (e.g. 0.4 / 2.0) instead of counting down from the total.",
        disabled = function()
            local p = DB()
            return castOff() or not (p and p.castBar.showTimer)
        end,
        disabledTooltip = "Duration Text",
        getValue = function()
            local p = DB()
            return p and p.castBar.showTotalDuration
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showTotalDuration = val
            RefreshCast()
        end,
    })
    posY = posY - hgt
    -- Inline cog (RESIZE) on Duration Text for timer size + x/y
    if not CludesUI._prebuilding then
        local region = timerRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                local p = DB()
                return p and (not p.castBar.enabled or not p.castBar.showTimer)
            end,
            disabledTooltip = "Player Cast Bar",
            title = "Timer Settings",
            rows = {
                {
                    type = "slider",
                    label = "Timer Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.timerSize or 11
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.timerSize = val
                        RefreshCast()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.timerX or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.timerX = val
                        RefreshCast()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local p = DB()
                        return p and p.castBar.timerY or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.castBar.timerY = val
                        RefreshCast()
                    end,
                },
            },
        })
    end
    -- Duration Text colour (RGBA; white = the untinted text), left of the
    -- Timer Settings cog above. Dimmed and blocked while the cast bar is off
    -- or Duration Text is None.
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineSwatches(timerRow._leftRegion, {
            {
                tooltip = "Duration Text Color",
                hasAlpha = true,
                disabled = function()
                    local p = DB()
                    return not (p and p.castBar.enabled and p.castBar.showTimer)
                end,
                disabledTooltip = function()
                    return castOff() and "Player Cast Bar" or "Duration Text"
                end,
                getValue = function()
                    local p = DB()
                    if not p then
                        return 1, 1, 1, 1
                    end
                    local c = p.castBar
                    return c.timerR or 1, c.timerG or 1, c.timerB or 1, c.timerA or 1
                end,
                setValue = function(r, g, b, a)
                    local p = DB()
                    if not p then
                        return
                    end
                    local c = p.castBar
                    c.timerR, c.timerG, c.timerB, c.timerA = r, g, b, a
                    RefreshCast()
                    CludesUI:RefreshPage()
                end,
            },
        }, { size = 20 })
    end

    -- Row 5: Craft Batches, plus Show Spell Rank (spell ranks exist only on WoW Forever)
    -- Craft Batches is stored as fullCraftTime (text) and mergeCrafts (bar + text).
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Craft Batches",
        tooltip = "How the cast bar shows a batch of crafts.",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        values = { off = "Off", text = "Full Time Text", merge = "Merge Bar" },
        order = { "off", "text", "merge" },
        getValue = function()
            local p = DB()
            if not p then
                return "off"
            end
            return p.castBar.mergeCrafts and "merge" or p.castBar.fullCraftTime and "text" or "off"
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.fullCraftTime = val == "text"
            p.castBar.mergeCrafts = val == "merge"
        end,
    }, CludesUI.IS_FOREVER and {
        type = "toggle",
        text = "Show Spell Rank",
        tooltip = "Appends the spell's rank to the spell name, for spells that have one.",
        disabled = function()
            local p = DB()
            return castOff() or not (p and p.castBar.showSpellText)
        end,
        disabledTooltip = "Spell Text",
        getValue = function()
            local p = DB()
            return p and p.castBar.showSpellRank
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showSpellRank = val
        end,
    } or CludesUI.BlankRowCfg())
    posY = posY - hgt

    -- MARKS section
    _, hgt = W:SectionHeader(hostFrame, "TICK MARKERS", posY)
    posY = posY - hgt

    local marksOff = function()
        local p = DB()
        return castOff() or not (p and p.castBar.showChannelTicks)
    end

    -- Helper: attach an inline color swatch to a region with disabled overlay
    local function AttachInlineSwatch(region, getFunc, setFunc, disabledFunc, disabledTooltip)
        if CludesUI._prebuilding then
            return
        end
        local colorSwatch, updateSwatch =
            CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, getFunc, setFunc, true, 20)
        Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -12, 0)

        local block = CludesUI.NewSwatchBlocker(colorSwatch)
        block:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip(disabledTooltip))
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)

        CludesUI.RegisterWidgetRefresh(function()
            local off = disabledFunc()
            colorSwatch:SetAlpha(off and 0.3 or 1)
            if off then
                block:Show()
            else
                block:Hide()
            end
            updateSwatch()
        end)
        local initOff = disabledFunc()
        colorSwatch:SetAlpha(initOff and 0.3 or 1)
        if initOff then
            block:Show()
        else
            block:Hide()
        end
    end

    -- Marks Row 1: Enable Tick Markers (master) | Channel Ticks (+ color)
    local marksRow1
    marksRow1, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Tick Markers",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.showChannelTicks
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showChannelTicks = val
            if val and not (p.castBar.showTickMarks or p.castBar.showLastTick) then
                p.castBar.showTickMarks = true
            end
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Channel Ticks",
        tooltip = "Shows tick marks on channeled spells. Only supported spells are shown.",
        disabled = marksOff,
        disabledTooltip = "Tick Markers",
        getValue = function()
            local p = DB()
            return p and p.castBar.showTickMarks
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showTickMarks = val
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt

    AttachInlineSwatch(marksRow1._rightRegion, function()
        local p = DB()
        if not p then
            return 1, 1, 1, 0.7
        end
        return p.castBar.tickMarksR or 1,
            p.castBar.tickMarksG or 1,
            p.castBar.tickMarksB or 1,
            p.castBar.tickMarksA or 0.7
    end, function(r, g, b, a)
        local p = DB()
        if not p then
            return
        end
        p.castBar.tickMarksR = r
        p.castBar.tickMarksG = g
        p.castBar.tickMarksB = b
        p.castBar.tickMarksA = a
        RefreshCast()
    end, function()
        return marksOff() or not (DB() and DB().castBar.showTickMarks)
    end, "Channel Ticks")

    -- Marks Row 2: Last Tick (+ color) | Colored Empowered Stages
    local marksRow2
    marksRow2, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Last Tick",
        tooltip = "Highlights the final damage tick. Requires a supported channeled spell.",
        disabled = marksOff,
        disabledTooltip = "Tick Markers",
        getValue = function()
            local p = DB()
            return p and p.castBar.showLastTick
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.showLastTick = val
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Colored Empowered Stages",
        tooltip = "Changes the cast bar color based on the current empower stage. Colors transition from red (stage 1) through yellow to green (max stage).",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.coloredEmpowerStages
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.coloredEmpowerStages = val
            RefreshCast()
        end,
    })
    posY = posY - hgt

    AttachInlineSwatch(marksRow2._leftRegion, function()
        local p = DB()
        if not p then
            return 1, 0.82, 0, 0.95
        end
        return p.castBar.lastTickR or 1,
            p.castBar.lastTickG or 0.82,
            p.castBar.lastTickB or 0,
            p.castBar.lastTickA or 0.95
    end, function(r, g, b, a)
        local p = DB()
        if not p then
            return
        end
        p.castBar.lastTickR = r
        p.castBar.lastTickG = g
        p.castBar.lastTickB = b
        p.castBar.lastTickA = a
        RefreshCast()
    end, function()
        return marksOff() or not (DB() and DB().castBar.showLastTick)
    end, "Last Tick")

    -- LATENCY section
    _, hgt = W:SectionHeader(hostFrame, "LATENCY", posY)
    posY = posY - hgt

    local latOff = function()
        local p = DB()
        return castOff() or not (p and p.castBar.latencyEnabled)
    end

    -- Latency Row 1: Enable Latency Overlay (+ color) | Show Latency Text
    local latRow1
    latRow1, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Latency Overlay",
        tooltip = "Shows a colored overlay at the end of the cast bar representing your network latency for each spell. Helps you time spell queuing.",
        disabled = castOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local p = DB()
            return p and p.castBar.latencyEnabled
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.latencyEnabled = val
            RefreshCast()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Latency Text",
        tooltip = "Appends your latency in milliseconds to the cast timer, e.g. 1.8 (42ms).",
        disabled = latOff,
        disabledTooltip = "Latency Overlay",
        getValue = function()
            local p = DB()
            return p and p.castBar.latencyShowText
        end,
        setValue = function(val)
            local p = DB()
            if not p then
                return
            end
            p.castBar.latencyShowText = val
            RefreshCast()
        end,
    })
    posY = posY - hgt

    AttachInlineSwatch(latRow1._leftRegion, function()
        local p = DB()
        if not p then
            return 0.835, 0.290, 0.290, 1
        end
        return p.castBar.latencyR or 0.835,
            p.castBar.latencyG or 0.290,
            p.castBar.latencyB or 0.290,
            p.castBar.latencyA or 1
    end, function(r, g, b, a)
        local p = DB()
        if not p then
            return
        end
        p.castBar.latencyR = r
        p.castBar.latencyG = g
        p.castBar.latencyB = b
        p.castBar.latencyA = a
        RefreshCast()
    end, latOff, "Latency Overlay")

    -- Wire up click mappings for cast bar preview hit overlays (never from a hidden pre-build: the shared live table would end up pointing at off-screen rows)
    if not CludesUI._prebuilding then
        _clickMappings.castBar = { section = castSection, target = classSizeRow }
        _clickMappings.castIcon = { section = castSection, target = iconRow, slotSide = "left" }
        _clickMappings.castSpellText = { section = displaySection, target = textRow, slotSide = "right" }
        _clickMappings.castTimer = { section = displaySection, target = timerRow, slotSide = "left" }
    end

    return math.abs(posY)
end
