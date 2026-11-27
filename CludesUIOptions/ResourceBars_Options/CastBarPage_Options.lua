if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ResourceBars_Options\CastBarPage_Options.lua
--  Resource Bars options: Cast Bar page. Definitions only; the shared
--  helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIResourceBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- Cast Bar page
function mod.ERB_BuildCastBarPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix, CLASS_COLORS, _clickMappings =
        environ.DB, environ.PP, environ.CLASS_COLORS, environ._clickMappings
    local ShuffleCastBarIcons, UpdateCastBarPreview, _castBarPreviewBuilder =
        environ.ShuffleCastBarIcons, environ.UpdateCastBarPreview, environ._castBarPreviewBuilder
    local TexBgRowCfg = environ.TexBgRowCfg
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    environ.SetCastBarPreviewFill(math.random(30, 85) / 100)
    ShuffleCastBarIcons()
    CUI:SetContentHeader(_castBarPreviewBuilder)

    -- Clear this page's own click mappings (the table is shared with the display page, whose
    -- cached preview keeps its own; never from a hidden pre-build -- see the matching guard in
    -- BuildBarDisplayPage)
    if not CUI._prebuilding then
        _clickMappings.castBar, _clickMappings.castIcon, _clickMappings.castSpellText, _clickMappings.castTimer =
            nil, nil, nil, nil
    end

    -- Re-append SharedMedia textures for cast bar (catches lazy-registered SM packs)
    CUI.AppendSharedMediaTextures(
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
            if key ~= "---" then texValues[key] = nameList[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return lookup[key] end,
        }
    end

    local castBarOff = function()
        local profile = DB()
        return profile and not profile.castBar.enabled
    end

    local function ApplyCastBar()
        if _G._CURB_Apply then _G._CURB_Apply() end
        if CUI.NotifyElementResized then CUI.NotifyElementResized("ERB_CastBar") end
        UpdateCastBarPreview()
    end
    -- A setting row's getter for one cast bar key: its value, or default when
    -- it is unset (no default: the value as stored, nil without a profile).
    local function Getter(key, default)
        return function()
            local profile = DB()
            if default == nil then return profile and profile.castBar[key] end
            return profile and profile.castBar[key] or default
        end
    end
    -- A setting row's setter for one cast bar key: written (when the profile
    -- exists), the cast bar redrawn, and with alsoPage the page rebuilt too.
    local function Setter(key, alsoPage)
        return function(val)
            local profile = DB()
            if not profile then return end
            profile.castBar[key] = val
            ApplyCastBar()
            if alsoPage then CUI:RefreshPage() end
        end
    end

    local castSection
    castSection, height = W:SectionHeader(hostFrame, "LAYOUT", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(
        castSection,
        { key = "ERB_CastBar", disabled = castBarOff, disabledTooltip = "Player Cast Bar" }
    )

    -- Strata dropdown values for the Cast Bar Frame Strata control.
    local cbStrataValues = CUI.FRAME_STRATA_LABELS
    local cbStrataOrder = CUI.FRAME_STRATA_ORDER_BASE

    -- Row 1: Enable Player Cast Bar | Frame Strata
    local castEnableRow
    castEnableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Player Cast Bar",
        tooltip = "Shows your own cast bar.",
        getValue = Getter("enabled"),
        setValue = Setter("enabled", true),
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        values = cbStrataValues,
        order = cbStrataOrder,
        getValue = Getter("frameStrata", "MEDIUM"),
        setValue = Setter("frameStrata"),
    })
    cursorY = cursorY - height
    -- (No position cog here: the cast bar is positioned via Unlock Mode; the old X/Y offset cog wrote anchor keys the runtime never reads.)

    -- Row 2: Height | Width (sync icons push to power + health bars)
    local classSizeRow
    local cbhDis, cbhTip, cbhRaw = CUI.MatchGuard("ERB_CastBar", "Height", castBarOff, "Player Cast Bar")
    local cbwDis, cbwTip, cbwRaw = CUI.MatchGuard("ERB_CastBar", "Width", castBarOff, "Player Cast Bar")
    classSizeRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Height",
        min = 1,
        max = 60,
        step = 1,
        disabled = cbhDis,
        disabledTooltip = cbhTip,
        rawTooltip = cbhRaw,
        getValue = Getter("height", 20),
        setValue = Setter("height"),
    }, {
        type = "slider",
        text = "Width",
        min = 50,
        max = 800,
        step = 1,
        disabled = cbwDis,
        disabledTooltip = cbwTip,
        rawTooltip = cbwRaw,
        getValue = Getter("width", 220),
        setValue = Setter("width"),
    })
    cursorY = cursorY - height

    -- Row 3: Show Spell Icon (cog: side, divider, size, offsets) | Show Spark
    local iconRow
    iconRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Spell Icon",
        tooltip = "Shows the spell's icon.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local profile = DB()
            return profile and profile.castBar.showIcon ~= false
        end,
        setValue = Setter("showIcon", true),
    }, {
        type = "toggle",
        text = "Show Spark",
        tooltip = "A bright spark at the cast bar's moving edge.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = Getter("showSpark"),
        setValue = Setter("showSpark"),
    })
    cursorY = cursorY - height
    -- Inline cog on Show Spell Icon
    if not CUI._prebuilding then
        local region = iconRow._leftRegion
        local FREE_TIP = "This option requires the icon at bar size with no offset."
        local function IconFree()
            local profile = DB()
            return profile and mod.ERB_CastIconFree(profile.castBar)
        end
        local function CastIconOnPortrait()
            local profile = DB()
            return profile and mod.ERB_CastIconPortrait(profile.castBar) ~= nil
        end
        -- Embed in Player Portrait: nil while a player portrait can take the icon, else why
        -- not ("uf": the Unit Frames player cast bar already shows its icon there).
        local function PortraitBlockReason()
            local uf = CUI._ModuleNS["CludesUIUnitFrames"]
            if not (uf and uf.UF_GetPlayerCastPortrait) then return "portrait" end
            local edge, _, why = uf.UF_GetPlayerCastPortrait()
            if edge then return nil end
            return why or "portrait"
        end
        local function PlayerPortraitOff() return PortraitBlockReason() ~= nil end
        local function IconSlider(key, labelText, lo, hi, tooltip)
            return {
                type = "slider",
                label = labelText,
                min = lo,
                max = hi,
                step = 1,
                tooltip = tooltip,
                disabled = function() return CastIconOnPortrait() or CUI.BlizzStyle.Get("castbar") end,
                disabledTooltip = function()
                    if CastIconOnPortrait() then return "Embed in Player Portrait" end
                    return CUI.BlizzStyle.Label("castbar")
                end,
                requireState = "disabled",
                get = function()
                    local profile = DB()
                    return profile and profile.castBar[key] or 0
                end,
                set = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.castBar[key] = val
                    ApplyCastBar()
                end,
            }
        end
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and (not profile.castBar.enabled or profile.castBar.showIcon == false)
            end,
            disabledTooltip = function()
                local profile = DB()
                return (profile and not profile.castBar.enabled) and "Player Cast Bar" or "Show Spell Icon"
            end,
            title = "Spell Icon Settings",
            rows = {
                {
                    type = "toggle",
                    label = "Embed in Player Portrait",
                    tooltip = "Show the spell icon over the player portrait while casting.",
                    disabled = PlayerPortraitOff,
                    disabledTooltip = function()
                        if PortraitBlockReason() == "uf" then
                            return "This option can't be used while the Unit Frames player cast bar shows its icon on the portrait."
                        end
                        return "This option requires an enabled player portrait in Unit Frames."
                    end,
                    rawTooltip = true,
                    get = function()
                        local profile = DB()
                        return profile and profile.castBar.iconOnPortrait == true
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile or (val and PlayerPortraitOff()) then return end
                        profile.castBar.iconOnPortrait = val
                        ApplyCastBar()
                    end,
                },
                {
                    type = "toggle",
                    label = "Icon on Right",
                    tooltip = "Attach the spell icon to the right of the cast bar instead of the left.",
                    disabled = CastIconOnPortrait,
                    disabledTooltip = "Embed in Player Portrait",
                    requireState = "disabled",
                    get = Getter("iconOnRight"),
                    set = Setter("iconOnRight"),
                },
                {
                    type = "toggle",
                    label = "Show Icon Divider",
                    tooltip = "Draw a 1px divider between the spell icon and the cast bar, matching the border color.",
                    disabled = function() return CastIconOnPortrait() or IconFree() end,
                    disabledTooltip = function()
                        if CastIconOnPortrait() then
                            return CUI.DisabledTooltip("Embed in Player Portrait", "disabled")
                        end
                        return FREE_TIP
                    end,
                    rawTooltip = true,
                    get = Getter("showIconDivider"),
                    set = Setter("showIconDivider"),
                },
                -- Border Art Divider: the divider in the border style's own art (the
                -- Pixels styles); any other style keeps the solid line.
                {
                    type = "toggle",
                    label = "Border Art Divider",
                    tooltip = "Draws the icon divider in the border style's art instead of a solid line.",
                    disabled = function()
                        local profile = DB()
                        if not profile then return true end
                        local checkBtn = profile.castBar
                        return CastIconOnPortrait()
                            or not checkBtn.showIconDivider
                            or CUI.BlizzStyle.Get("castbar")
                            or not CUI.GetBorderCompanion(checkBtn.borderTexture, "sepV")
                    end,
                    disabledTooltip = function()
                        if CastIconOnPortrait() then return "Embed in Player Portrait" end
                        if CUI.BlizzStyle.Get("castbar") then
                            return CUI.DisabledTooltip(CUI.BlizzStyle.Label("castbar"), "disabled")
                        end
                        local profile = DB()
                        if not (profile and profile.castBar.showIconDivider) then
                            return "Show Icon Divider"
                        end
                        return "This option requires a border style with matching art, such as Pixels."
                    end,
                    rawTooltip = function()
                        if CUI.BlizzStyle.Get("castbar") then return true end
                        local profile = DB()
                        return (profile and profile.castBar.showIconDivider) and true or false
                    end,
                    get = Getter("iconDividerArt", false),
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        profile.castBar.iconDividerArt = val and true or false
                        ApplyCastBar()
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
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Always Show",
        tooltip = "Keep the cast bar visible (sitting empty) when you are not casting, instead of hiding it.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = Getter("alwaysShow"),
        setValue = Setter("alwaysShow"),
    }, {
        type = "toggle",
        text = "Smooth Bar Animation",
        tooltip = "Eases the cast fill between updates. Turn off for a raw, uneased fill.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = function()
            local profile = DB()
            return not (profile and profile.castBar.smoothFill == false)
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            if val then
                profile.castBar.smoothFill = nil
            else
                profile.castBar.smoothFill = false
            end
            ApplyCastBar()
        end,
    })
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    local displaySection
    displaySection, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height
    cursorY = CUI.BlizzStyle.Note(hostFrame, cursorY, "castbar")

    -- Row: Cast Bar Border Style dropdown (+ inline offset cog)
    do
        local texValues, texOrder = CUI.GetBorderTextureDropdown()
        local cbBsRow
        cbBsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CUI.BlizzStyle.Gate("castbar", {
                type = "dropdown",
                text = "Border Style",
                disabled = castBarOff,
                disabledTooltip = "Player Cast Bar",
                values = texValues,
                order = texOrder,
                getValue = Getter("borderTexture", "solid"),
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.castBar.borderTexture = val
                    profile.castBar.borderTextureOffset = nil
                    profile.castBar.borderTextureOffsetY = nil
                    profile.castBar.borderTextureShiftX = nil
                    profile.castBar.borderTextureShiftY = nil
                    local _bcol, _bbehind = CUI.GetBorderStyleSelectDefaults(val)
                    profile.castBar.borderR = _bcol.r
                    profile.castBar.borderG = _bcol.g
                    profile.castBar.borderB = _bcol.b
                    profile.castBar.borderA = 1
                    profile.castBar.borderBehind = _bbehind
                    local defSz = CUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then profile.castBar.borderSize = defSz end
                    if profile.castBar.borderSizePx then profile.castBar.borderSizePx = false end
                    ApplyCastBar()
                    CUI:RefreshPage(true)
                end,
            }),
            -- Classic WoW UI: the slot sizes the vanilla frame instead.
            (CUI.BlizzStyle.Active("castbar") == "classic")
                    and CUI.BlizzStyle.ClassicBorderSizeCfg(function()
                        local profile = DB()
                        return profile and profile.castBar.stockBorderScale
                    end, function(val)
                        local profile = DB()
                        if not profile then return end
                        profile.castBar.stockBorderScale = val
                        ApplyCastBar()
                        CUI.ReapplyMatchPads("ERB_CastBar")
                    end, { disabled = castBarOff, disabledTooltip = "Player Cast Bar" })
                or CUI.BlizzStyle.Gate(
                    "castbar",
                    CUI.BorderPxSliderCfg({
                        text = "Border Size",
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
                        getStep = function()
                            local profile = DB()
                            return profile and (profile.castBar.borderSize or 0) or 0
                        end,
                        setStep = function(val)
                            local profile = DB()
                            if profile then profile.castBar.borderSize = val end
                        end,
                        getTex = function()
                            local profile = DB()
                            return profile and (profile.castBar.borderTexture or "solid") or "solid"
                        end,
                        getPx = function()
                            local profile = DB()
                            return profile and profile.castBar.borderSizePx
                        end,
                        setPx = function(val)
                            local profile = DB()
                            if profile then profile.castBar.borderSizePx = val end
                        end,
                        apply = function()
                            ApplyCastBar()
                            CUI:RefreshPage()
                        end,
                    })
                )
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: own row while a textured style is selected (stock styles gate it away).
        do
            local profile = DB()
            local texture = profile and profile.castBar.borderTexture or "solid"
            if texture ~= "solid" and texture ~= "" then
                local function step()
                    local profile = DB()
                    return profile and (profile.castBar.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = castBarOff,
                    disabledTooltip = "Player Cast Bar",
                    getTex = function()
                        local profile = DB()
                        return profile and (profile.castBar.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local profile = DB()
                        return profile and profile.castBar.borderSizePx
                    end,
                    getX = function()
                        local profile = DB()
                        return profile and profile.castBar.borderTextureOffset
                    end,
                    setX = function(val)
                        local profile = DB()
                        if profile then profile.castBar.borderTextureOffset = val end
                    end,
                    getY = function()
                        local profile = DB()
                        return profile and profile.castBar.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local profile = DB()
                        if profile then profile.castBar.borderTextureOffsetY = val end
                    end,
                    apply = function()
                        ApplyCastBar()
                        CUI:RefreshPage()
                    end,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CUI.BlizzStyle.Gate("castbar", ocfgL),
                    CUI.BlizzStyle.Gate("castbar", ocfgR)
                )
                cursorY = cursorY - height
            end
        end
        -- Inline border color swatch on Border slider (right region); none
        -- under Classic WoW UI, whose slider sizes the vanilla frame.
        if not CUI._prebuilding and CUI.BlizzStyle.Active("castbar") ~= "classic" then
            local region = cbBsRow._rightRegion
            local control = region._control
            local borderSwatch, updateBorderSwatch = CUI.BuildColorSwatch(
                region,
                cbBsRow:GetFrameLevel() + 3,
                function()
                    local profile = DB()
                    return (profile and profile.castBar.borderR or 0),
                        (profile and profile.castBar.borderG or 0),
                        (profile and profile.castBar.borderB or 0),
                        (profile and profile.castBar.borderA or 1)
                end,
                function(red, green, blue, a)
                    local profile = DB()
                    if not profile then return end
                    profile.castBar.borderR, profile.castBar.borderG, profile.castBar.borderB, profile.castBar.borderA =
                        red, green, blue, a
                    ApplyCastBar()
                    CUI:RefreshPage()
                end,
                true,
                20
            )
            Pix.Point(borderSwatch, "RIGHT", control, "LEFT", -8, 0)
            -- Disable swatch when border size is 0
            local borderSwatchBlock = CUI.NewSwatchBlocker(borderSwatch)
            borderSwatchBlock:SetScript("OnEnter", function()
                if CUI.BlizzStyle.Get("castbar") then
                    CUI.ShowWidgetTooltip(
                        borderSwatch,
                        CUI.DisabledTooltip("Blizzard Style", "disabled")
                    )
                else
                    CUI.ShowWidgetTooltip(
                        borderSwatch,
                        CUI.DisabledTooltip("This option requires a Border Size above 0.")
                    )
                end
            end)
            borderSwatchBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function FadeCastBorderSwatch()
                local profile = DB()
                local noBorder = not profile
                    or (profile.castBar.borderSize or 0) == 0
                    or CUI.BlizzStyle.Get("castbar")
                if noBorder then
                    borderSwatch:SetAlpha(0.3)
                    borderSwatchBlock:Show()
                else
                    borderSwatch:SetAlpha(1)
                    borderSwatchBlock:Hide()
                end
            end
            CUI.RegisterWidgetRefresh(function()
                updateBorderSwatch()
                FadeCastBorderSwatch()
            end)
            FadeCastBorderSwatch()
        end
        if not CUI._prebuilding then
            local region = cbBsRow._leftRegion
            local sepValues, sepOrder = mod.ERB_SeparatorArtValues(true)
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
                            local profile = DB()
                            if not profile then return 0 end
                            local val = profile.castBar.borderTextureShiftX
                            if val then return val end
                            local _, _, dsx = CUI.GetBorderDefaults(
                                "resourcebars",
                                profile.castBar.borderTexture or "solid",
                                profile.castBar.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            profile.castBar.borderTextureShiftX = val == 0 and nil or val
                            ApplyCastBar()
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
                            local profile = DB()
                            if not profile then return 0 end
                            local val = profile.castBar.borderTextureShiftY
                            if val then return val end
                            local _, _, _, dsy = CUI.GetBorderDefaults(
                                "resourcebars",
                                profile.castBar.borderTexture or "solid",
                                profile.castBar.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            profile.castBar.borderTextureShiftY = val == 0 and nil or val
                            ApplyCastBar()
                            CUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = Getter("borderBehind", false),
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            profile.castBar.borderBehind = val == false and nil or val
                            ApplyCastBar()
                            CUI:RefreshPage()
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
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
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
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
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
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
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
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
                        get = Getter("borderExtendRight", 0),
                        set = Setter("borderExtendRight", true),
                    },
                    -- Bottom Separator: None = off (edgeSep false); an art entry turns it
                    -- on with that art. Across the whole bar, icon included.
                    {
                        type = "dropdown",
                        label = "Bottom Separator",
                        values = sepValues,
                        order = sepOrder,
                        tooltip = "Draws a separator line along the bar's bottom edge.",
                        disabled = castBarOff,
                        disabledTooltip = "Player Cast Bar",
                        get = function()
                            local profile = DB()
                            if not (profile and profile.castBar.edgeSep) then return "none" end
                            return profile.castBar.edgeSepArt or "match"
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            if val == "none" then
                                profile.castBar.edgeSep = false
                            else
                                profile.castBar.edgeSep = true
                                profile.castBar.edgeSepArt = val
                            end
                            ApplyCastBar()
                            CUI:RefreshPage()
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
                            return castBarOff() or not (profile and profile.castBar.edgeSep)
                        end,
                        disabledTooltip = function()
                            return castBarOff() and "Player Cast Bar" or "Bottom Separator"
                        end,
                        get = Getter("edgeSepY", 0),
                        set = Setter("edgeSepY", true),
                    },
                },
            })
            local function UpdateCogVis()
                local profile = DB()
                local texture = profile and profile.castBar.borderTexture or "solid"
                if texture == "solid" or CUI.BlizzStyle.Get("castbar") then
                    cogBtn:Hide()
                else
                    cogBtn:Show()
                end
            end
            CUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row 2: Fill Color (opacity slider + cog: gradient + inline swatches) | Background
    local castColorRow
    castColorRow, height = W:DualRow(
        hostFrame,
        cursorY,
        {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
            disabled = castBarOff,
            disabledTooltip = "Player Cast Bar",
            getValue = function()
                local profile = DB()
                return profile and (profile.castBar.fillOpacity or 100) or 100
            end,
            setValue = Setter("fillOpacity"),
        },
        mod.ERB_CastBlizzOnlyGate({
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            disabled = castBarOff,
            disabledTooltip = "Player Cast Bar",
            getValue = function()
                local profile = DB()
                return math.floor(((profile and profile.castBar.bgA or 0.7) * 100) + 0.5)
            end,
            setValue = function(val)
                local profile = DB()
                if not profile then return end
                profile.castBar.bgA = val / 100
                ApplyCastBar()
            end,
        })
    )
    cursorY = cursorY - height
    local castFillBlizz = CUI.BlizzStyle.Active("castbar") == "blizzard"
    -- Inline cog on Fill Color: the gradient and the channel / uninterruptible
    -- color overrides (not under Blizzard Style, whose fill art is stock) and Out
    -- of Range Gray (every style).
    if not CUI._prebuilding then
        local region = castColorRow._leftRegion
        local function gradientOff() return castFillBlizz end
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and not profile.castBar.enabled
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
                    get = Getter("gradientEnabled"),
                    set = Setter("gradientEnabled", true),
                },
                {
                    type = "dropdown",
                    label = "Gradient Direction",
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                    order = { "HORIZONTAL", "VERTICAL" },
                    get = Getter("gradientDir", "HORIZONTAL"),
                    set = Setter("gradientDir"),
                },
                {
                    type = "toggle",
                    label = "Gray When Out of Range",
                    tooltip = "Grays the fill while your target is out of range of the spell being cast.",
                    get = function()
                        local profile = DB()
                        return profile and profile.castBar.outOfRangeGray == true
                    end,
                    set = Setter("outOfRangeGray"),
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
                        local profile = DB()
                        return profile and profile.castBar.channelOverride == true
                    end,
                    set = Setter("channelOverride"),
                },
                {
                    type = "colorpicker",
                    label = "Channel Color",
                    hidden = function()
                        local profile = DB()
                        return not (profile and profile.castBar.channelOverride)
                    end,
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local profile = DB()
                        local c = profile and profile.castBar
                        return c and c.channelR or 0.3, c and c.channelG or 0.8, c and c.channelB or 0.3
                    end,
                    set = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        local c = profile.castBar
                        c.channelR, c.channelG, c.channelB = red, green, blue
                        ApplyCastBar()
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
                        local profile = DB()
                        return profile and profile.castBar.uninterruptibleOverride == true
                    end,
                    set = Setter("uninterruptibleOverride"),
                },
                {
                    type = "colorpicker",
                    label = "Uninterruptible Color",
                    hidden = function()
                        local profile = DB()
                        return not (profile and profile.castBar.uninterruptibleOverride)
                    end,
                    disabled = gradientOff,
                    disabledTooltip = "Blizzard Style",
                    requireState = "disabled",
                    get = function()
                        local profile = DB()
                        local c = profile and profile.castBar
                        return c and c.uninterruptibleR or 0.5,
                            c and c.uninterruptibleG or 0.5,
                            c and c.uninterruptibleB or 0.5
                    end,
                    set = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        local c = profile.castBar
                        c.uninterruptibleR, c.uninterruptibleG, c.uninterruptibleB = red, green, blue
                        ApplyCastBar()
                    end,
                },
            },
        })
    end
    -- Fill Color inline swatches: gradient end / custom / class. Blizzard Style
    -- keeps the stock fill art, so the colour swatches are inert there; the
    -- Classic WoW UI fill is the user's, so they stay live under it.
    CUI.BuildInlineSwatches(castColorRow._leftRegion, {
        {
            tooltip = "Gradient End Color",
            hasAlpha = true,
            disabled = function()
                local profile = DB()
                if not profile or not profile.castBar.enabled then return true end
                return not profile.castBar.gradientEnabled
            end,
            disabledTooltip = function()
                if castFillBlizz then return "This option requires Blizzard Style to be disabled" end
                local profile = DB()
                if not profile or not profile.castBar.enabled then return "Player Cast Bar" end
                return "Gradient"
            end,
            getValue = function()
                local profile = DB()
                if not profile then return 0.20, 0.20, 0.80, 1 end
                return profile.castBar.gradientR,
                    profile.castBar.gradientG,
                    profile.castBar.gradientB,
                    profile.castBar.gradientA
            end,
            setValue = function(red, green, blue, a)
                local profile = DB()
                if not profile then return end
                profile.castBar.gradientR, profile.castBar.gradientG, profile.castBar.gradientB, profile.castBar.gradientA =
                    red, green, blue, a
                ApplyCastBar()
            end,
        },
        {
            tooltip = "Custom Colored",
            hasAlpha = false,
            getValue = function()
                local profile = DB()
                if not profile then
                    local _, castFrame = UnitClass("player")
                    local classColor = CLASS_COLORS[castFrame]
                    return classColor and classColor[1] or 1,
                        classColor and classColor[2] or 0.70,
                        classColor and classColor[3] or 0,
                        1
                end
                return profile.castBar.fillR, profile.castBar.fillG, profile.castBar.fillB, 1
            end,
            setValue = function(red, green, blue)
                local profile = DB()
                if not profile then return end
                profile.castBar.fillR, profile.castBar.fillG, profile.castBar.fillB = red, green, blue
                if profile.castBar.classColored then profile.castBar.classColored = false end
                ApplyCastBar()
                CUI:RefreshPage()
            end,
            onClick = function(self)
                local profile = DB()
                if not profile then return end
                if profile.castBar.classColored then
                    profile.castBar.classColored = false
                    ApplyCastBar()
                    CUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end,
            refreshAlpha = function()
                local profile = DB()
                return (profile and not profile.castBar.classColored) and 1 or 0.3
            end,
        },
        {
            tooltip = "Class Colored",
            getValue = function()
                local _, class = UnitClass("player")
                local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if classColor then return classColor.r, classColor.g, classColor.b, 1 end
                return 1, 0.70, 0, 1
            end,
            setValue = function() end,
            onClick = function()
                local profile = DB()
                if not profile then return end
                profile.castBar.classColored = true
                ApplyCastBar()
                CUI:RefreshPage()
            end,
            refreshAlpha = function()
                local profile = DB()
                return (not profile or profile.castBar.classColored == true) and 1 or 0.3
            end,
        },
    }, {
        size = 20,
        disabled = function() return castFillBlizz or castBarOff() end,
        disabledTooltip = function()
            if castFillBlizz then return "This option requires Blizzard Style to be disabled" end
            return "Player Cast Bar"
        end,
    })

    -- Inline color swatch on Background (right region)
    if not CUI._prebuilding then
        local region = castColorRow._rightRegion
        local control = region._control
        local bgSwatch, bgUpdateSwatch = CUI.BuildColorSwatch(
            region,
            castColorRow:GetFrameLevel() + 3,
            function()
                local profile = DB()
                return (profile and profile.castBar.bgR or 0),
                    (profile and profile.castBar.bgG or 0),
                    (profile and profile.castBar.bgB or 0)
            end,
            function(red, green, blue)
                local profile = DB()
                if not profile then return end
                profile.castBar.bgR, profile.castBar.bgG, profile.castBar.bgB = red, green, blue
                ApplyCastBar()
            end,
            nil,
            20
        )
        Pix.Point(bgSwatch, "RIGHT", control, "LEFT", -8, 0)
        local function UpdateBgSwatch()
            local profile = DB()
            -- Gated with the Background slider beside it: Blizzard Style
            -- paints the stock background art; the classic bar keeps this colour.
            if CUI.BlizzStyle.Active("castbar") == "blizzard" then
                bgSwatch:SetAlpha(0.15)
                bgSwatch:Disable()
                bgSwatch._disabledTooltip = CUI.BlizzStyle.Label("castbar")
            elseif not profile or not profile.castBar.enabled then
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
        CUI.RegisterWidgetRefresh(UpdateBgSwatch)
    end

    -- Row 3: Bar Texture | Spell Text (cog RESIZE: text size + x/y)
    -- Bar Texture is gated under Blizzard Style only (the stock fill art);
    -- the Classic WoW UI fill is the user's texture, so the row stays live.
    local castTexCfg = {
        type = "dropdown",
        text = "Bar Texture",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        values = texValues,
        order = texOrder,
        getValue = Getter("texture", "none"),
        setValue = Setter("texture"),
    }
    if CUI.BlizzStyle.Active("castbar") == "blizzard" then
        CUI.BlizzStyle.Gate("castbar", castTexCfg)
    end
    local textRow
    textRow, height = W:DualRow(hostFrame, cursorY, castTexCfg, {
        type = "dropdown",
        text = "Spell Text",
        tooltip = "Shows the spell's name.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        values = { none = "None", left = "Left", right = "Right", center = "Center" },
        order = { "none", "left", "right", "center" },
        getValue = function()
            local profile = DB()
            if not profile or not profile.castBar.showSpellText then return "none" end
            return profile.castBar.spellTextSide or "left"
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            if val == "none" then
                profile.castBar.showSpellText = false
            else
                profile.castBar.showSpellText = true
                profile.castBar.spellTextSide = val
            end
            ApplyCastBar()
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    -- Inline cog on Bar Texture: Textured Background (greyed while the cast bar
    -- is off, and under Blizzard Style, whose own background art stays).
    if not CUI._prebuilding then
        CUI.BuildInlineCog(textRow._leftRegion, {
            disabled = function() return castBarOff() or CUI.BlizzStyle.Active("castbar") == "blizzard" end,
            disabledTooltip = function()
                if castBarOff() then return "Player Cast Bar" end
                return CUI.BlizzStyle.Label("castbar")
            end,
            requireState = function()
                if not castBarOff() then return "disabled" end
            end,
            title = "Texture Settings",
            rows = { TexBgRowCfg("cast", ApplyCastBar) },
        })
    end
    -- Inline cog (RESIZE) on Spell Text for text size + x/y
    if not CUI._prebuilding then
        local region = textRow._rightRegion
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and (not profile.castBar.enabled or not profile.castBar.showSpellText)
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
                    get = Getter("spellTextSize", 11),
                    set = Setter("spellTextSize"),
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = Getter("spellTextX", 0),
                    set = Setter("spellTextX"),
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = Getter("spellTextY", 0),
                    set = Setter("spellTextY"),
                },
                {
                    type = "toggle",
                    label = "Show Full Spell Name",
                    tooltip = "Long spell names shrink to fit beside the duration instead of being cut off.",
                    get = Getter("fitSpellName"),
                    set = Setter("fitSpellName"),
                },
            },
        })
    end
    -- Spell Text colour (RGBA; white = the untinted text), left of the
    -- Spell Text Settings cog above. Dimmed and blocked while the cast bar
    -- is off or Spell Text is None.
    if not CUI._prebuilding then
        CUI.BuildInlineSwatches(textRow._rightRegion, {
            {
                tooltip = "Spell Text Color",
                hasAlpha = true,
                disabled = function()
                    local profile = DB()
                    return not (profile and profile.castBar.enabled and profile.castBar.showSpellText)
                end,
                disabledTooltip = function() return castBarOff() and "Player Cast Bar" or "Spell Text" end,
                getValue = function()
                    local profile = DB()
                    if not profile then return 1, 1, 1, 1 end
                    local c = profile.castBar
                    return c.spellTextR or 1, c.spellTextG or 1, c.spellTextB or 1, c.spellTextA or 1
                end,
                setValue = function(red, green, blue, a)
                    local profile = DB()
                    if not profile then return end
                    local c = profile.castBar
                    c.spellTextR, c.spellTextG, c.spellTextB, c.spellTextA = red, green, blue, a
                    ApplyCastBar()
                    CUI:RefreshPage()
                end,
            },
        }, { size = 20 })
    end
    -- Row 4: Duration Text (cog RESIZE: timer size + x/y) | Show Total Duration
    local timerRow
    timerRow, height = W:DualRow(hostFrame, cursorY, {
        type = "segmented",
        text = "Duration Text",
        tooltip = "Shows the time left on the cast.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        values = { none = "None", right = "Right", left = "Left" },
        order = { "none", "right", "left" },
        getValue = function()
            local profile = DB()
            if not profile or not profile.castBar.showTimer then return "none" end
            return profile.castBar.timerSide or "right"
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            if val == "none" then
                profile.castBar.showTimer = false
            else
                profile.castBar.showTimer = true
                profile.castBar.timerSide = val
            end
            ApplyCastBar()
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Total Duration",
        tooltip = "Shows elapsed / total duration (e.g. 0.4 / 2.0) instead of counting down from the total.",
        disabled = function()
            local profile = DB()
            return castBarOff() or not (profile and profile.castBar.showTimer)
        end,
        disabledTooltip = "Duration Text",
        getValue = Getter("showTotalDuration"),
        setValue = Setter("showTotalDuration"),
    })
    cursorY = cursorY - height
    -- Inline cog (RESIZE) on Duration Text for timer size + x/y
    if not CUI._prebuilding then
        local region = timerRow._leftRegion
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and (not profile.castBar.enabled or not profile.castBar.showTimer)
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
                    get = Getter("timerSize", 11),
                    set = Setter("timerSize"),
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = Getter("timerX", 0),
                    set = Setter("timerX"),
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = Getter("timerY", 0),
                    set = Setter("timerY"),
                },
            },
        })
    end
    -- Duration Text colour (RGBA; white = the untinted text), left of the
    -- Timer Settings cog above. Dimmed and blocked while the cast bar is off
    -- or Duration Text is None.
    if not CUI._prebuilding then
        CUI.BuildInlineSwatches(timerRow._leftRegion, {
            {
                tooltip = "Duration Text Color",
                hasAlpha = true,
                disabled = function()
                    local profile = DB()
                    return not (profile and profile.castBar.enabled and profile.castBar.showTimer)
                end,
                disabledTooltip = function() return castBarOff() and "Player Cast Bar" or "Duration Text" end,
                getValue = function()
                    local profile = DB()
                    if not profile then return 1, 1, 1, 1 end
                    local c = profile.castBar
                    return c.timerR or 1, c.timerG or 1, c.timerB or 1, c.timerA or 1
                end,
                setValue = function(red, green, blue, a)
                    local profile = DB()
                    if not profile then return end
                    local c = profile.castBar
                    c.timerR, c.timerG, c.timerB, c.timerA = red, green, blue, a
                    ApplyCastBar()
                    CUI:RefreshPage()
                end,
            },
        }, { size = 20 })
    end

    -- Row 5: Craft Batches, plus Show Spell Rank (spell ranks exist only on WoW Forever)
    -- Craft Batches is stored as fullCraftTime (text) and mergeCrafts (bar + text).
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Craft Batches",
        tooltip = "How the cast bar shows a batch of crafts.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        values = { off = "Off", text = "Full Time Text", merge = "Merge Bar" },
        order = { "off", "text", "merge" },
        getValue = function()
            local profile = DB()
            if not profile then return "off" end
            return profile.castBar.mergeCrafts and "merge"
                or profile.castBar.fullCraftTime and "text"
                or "off"
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            profile.castBar.fullCraftTime = val == "text"
            profile.castBar.mergeCrafts = val == "merge"
        end,
    }, CUI.IS_FOREVER and {
        type = "toggle",
        text = "Show Spell Rank",
        tooltip = "Appends the spell's rank to the spell name, for spells that have one.",
        disabled = function()
            local profile = DB()
            return castBarOff() or not (profile and profile.castBar.showSpellText)
        end,
        disabledTooltip = "Spell Text",
        getValue = Getter("showSpellRank"),
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            profile.castBar.showSpellRank = val
        end,
    } or CUI.BlankRowCfg())
    cursorY = cursorY - height

    -- MARKS section
    _, height = W:SectionHeader(hostFrame, "TICK MARKERS", cursorY)
    cursorY = cursorY - height

    local marksOff = function()
        local profile = DB()
        return castBarOff() or not (profile and profile.castBar.showChannelTicks)
    end

    -- Helper: attach an inline color swatch to a region with disabled overlay
    local function AttachInlineSwatch(region, getFunc, setFunc, disabledFunc, disabledTooltip)
        if CUI._prebuilding then return end
        local colorSwatch, updateSwatch =
            CUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, getFunc, setFunc, true, 20)
        Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -12, 0)

        local block = CUI.NewSwatchBlocker(colorSwatch)
        block:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(colorSwatch, CUI.DisabledTooltip(disabledTooltip)) end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

        CUI.RegisterWidgetRefresh(function()
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
    marksRow1, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Tick Markers",
        tooltip = "Marks each tick of channelled spells.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = Getter("showChannelTicks"),
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            profile.castBar.showChannelTicks = val
            if val and not (profile.castBar.showTickMarks or profile.castBar.showLastTick) then
                profile.castBar.showTickMarks = true
            end
            ApplyCastBar()
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Channel Ticks",
        tooltip = "Shows tick marks on channeled spells. Only supported spells are shown.",
        disabled = marksOff,
        disabledTooltip = "Tick Markers",
        getValue = Getter("showTickMarks"),
        setValue = Setter("showTickMarks", true),
    })
    cursorY = cursorY - height

    AttachInlineSwatch(marksRow1._rightRegion, function()
        local profile = DB()
        if not profile then return 1, 1, 1, 0.7 end
        return profile.castBar.tickMarksR or 1,
            profile.castBar.tickMarksG or 1,
            profile.castBar.tickMarksB or 1,
            profile.castBar.tickMarksA or 0.7
    end, function(red, green, blue, a)
        local profile = DB()
        if not profile then return end
        profile.castBar.tickMarksR = red
        profile.castBar.tickMarksG = green
        profile.castBar.tickMarksB = blue
        profile.castBar.tickMarksA = a
        ApplyCastBar()
    end, function() return marksOff() or not (DB() and DB().castBar.showTickMarks) end, "Channel Ticks")

    -- Marks Row 2: Last Tick (+ color) | Colored Empowered Stages
    local marksRow2
    marksRow2, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Last Tick",
        tooltip = "Highlights the final damage tick. Requires a supported channeled spell.",
        disabled = marksOff,
        disabledTooltip = "Tick Markers",
        getValue = Getter("showLastTick"),
        setValue = Setter("showLastTick", true),
    }, {
        type = "toggle",
        text = "Colored Empowered Stages",
        tooltip = "Changes the cast bar color based on the current empower stage. Colors transition from red (stage 1) through yellow to green (max stage).",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = Getter("coloredEmpowerStages"),
        setValue = Setter("coloredEmpowerStages"),
    })
    cursorY = cursorY - height

    AttachInlineSwatch(marksRow2._leftRegion, function()
        local profile = DB()
        if not profile then return 1, 0.82, 0, 0.95 end
        return profile.castBar.lastTickR or 1,
            profile.castBar.lastTickG or 0.82,
            profile.castBar.lastTickB or 0,
            profile.castBar.lastTickA or 0.95
    end, function(red, green, blue, a)
        local profile = DB()
        if not profile then return end
        profile.castBar.lastTickR = red
        profile.castBar.lastTickG = green
        profile.castBar.lastTickB = blue
        profile.castBar.lastTickA = a
        ApplyCastBar()
    end, function() return marksOff() or not (DB() and DB().castBar.showLastTick) end, "Last Tick")

    -- LATENCY section
    _, height = W:SectionHeader(hostFrame, "LATENCY", cursorY)
    cursorY = cursorY - height

    local latOff = function()
        local profile = DB()
        return castBarOff() or not (profile and profile.castBar.latencyEnabled)
    end

    -- Latency Row 1: Enable Latency Overlay (+ color) | Show Latency Text
    local latRow1
    latRow1, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Latency Overlay",
        tooltip = "Shows a colored overlay at the end of the cast bar representing your network latency for each spell. Helps you time spell queuing.",
        disabled = castBarOff,
        disabledTooltip = "Player Cast Bar",
        getValue = Getter("latencyEnabled"),
        setValue = Setter("latencyEnabled", true),
    }, {
        type = "toggle",
        text = "Show Latency Text",
        tooltip = "Appends your latency in milliseconds to the cast timer, e.g. 1.8 (42ms).",
        disabled = latOff,
        disabledTooltip = "Latency Overlay",
        getValue = Getter("latencyShowText"),
        setValue = Setter("latencyShowText"),
    })
    cursorY = cursorY - height

    AttachInlineSwatch(latRow1._leftRegion, function()
        local profile = DB()
        if not profile then return 0.835, 0.290, 0.290, 1 end
        return profile.castBar.latencyR or 0.835,
            profile.castBar.latencyG or 0.290,
            profile.castBar.latencyB or 0.290,
            profile.castBar.latencyA or 1
    end, function(red, green, blue, a)
        local profile = DB()
        if not profile then return end
        profile.castBar.latencyR = red
        profile.castBar.latencyG = green
        profile.castBar.latencyB = blue
        profile.castBar.latencyA = a
        ApplyCastBar()
    end, latOff, "Latency Overlay")

    -- Wire up click mappings for cast bar preview hit overlays (never from a hidden pre-build: the shared live table would end up pointing at off-screen rows)
    if not CUI._prebuilding then
        _clickMappings.castBar = { section = castSection, target = classSizeRow }
        _clickMappings.castIcon = { section = castSection, target = iconRow, slotSide = "left" }
        _clickMappings.castSpellText = { section = displaySection, target = textRow, slotSide = "right" }
        _clickMappings.castTimer = { section = displaySection, target = timerRow, slotSide = "left" }
    end

    return math.abs(cursorY)
end
