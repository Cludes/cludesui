if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\DisplayBars_Options.lua
--  Nameplates options: the Health and Cast Bar, Cast Colors and Effects,
--  Target/Focus/Hover Effects, Class Resource and General Text sections of the
--  Display page. Called by BuildDisplayPage after DisplayLayout_Options.lua;
--  returns y and the rows its click navigation maps to. Shared helpers come
--  from ns._NPO_OptEnv, the per-build helpers from ctx.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUINameplates"]
if not mod then
    return
end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): frames made under a
-- pooled page part are handed back to the page's next build.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolGen, PoolIsIdle = CludesUI._Pool.Gen, CludesUI._Pool.IsIdle

local function BuildDisplayBars(hostFrame, cursorY, context)
    local environ = mod._NPO_OptEnv
    local BAR_W, DB, DBColor, DBVal = environ.BAR_W, environ.DB, environ.DBColor, environ.DBVal
    local defaultSet, displayCastIcons, hbtOrder, hbtValues =
        environ.defaults, environ.displayCastIcons, environ.hbtOrder, environ.hbtValues
    local LazyColorPreviewBar, npImpCastGlowDesc, optionState, pairs =
        environ.LazyColorPreviewBar, environ.npImpCastGlowDesc, environ.optState, environ.pairs
    local plates, Pix, RefreshAllPlates, SECTION_CASTBAR =
        environ.plates, environ.PP, environ.RefreshAllPlates, environ.SECTION_CASTBAR
    local UpdatePreview, npCastTargetGlowDesc = environ.UpdatePreview, environ.npCastTargetGlowDesc
    local asFallback, atFallback, AuraDurationVal, CogPopupOpen =
        context.asFallback, context.atFallback, context.AuraDurationVal, context.CogPopupOpen
    local LiveApplyAuraText, RefreshAllTextures, ShowCogPopup =
        context.LiveApplyAuraText, context.RefreshAllTextures, context.ShowCogPopup
    local timerPosOrder, timerPosValues = context.timerPosOrder, context.timerPosValues
    local W = context.W
    local _, height

    -----------------------------------------------------------------------
    --  HEALTH BAR
    -----------------------------------------------------------------------
    local healthBarHeader
    healthBarHeader, height = W:SectionHeader(hostFrame, "HEALTH AND CAST BAR", cursorY)
    cursorY = cursorY - height

    local healthBarHeightRow
    healthBarHeightRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Health Bar Width",
        min = 100,
        max = BAR_W + 100,
        step = 1,
        getValue = function()
            return BAR_W + DBVal("healthBarWidth")
        end,
        setValue = function(val)
            local extra = val - BAR_W
            DB().healthBarWidth = extra
            -- Classic WoW UI: the cast bar's width and shift are derived
            -- from the footprint so the two borders stay edge to edge, so
            -- it re-lays out rather than taking the raw width.
            local classic = mod.NP_Classic and mod.NP_Classic()
            -- Pooled plates re-run their appearance pass at next spawn.
            mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
            for _, backing in pairs(plates) do
                Pix.Width(backing.health, val)
                Pix.Width(backing.absorb, val)
                Pix.Width(backing.absorbForward, val)
                if classic then
                    mod.LayoutCastBar(backing, val, mod.GetCastBarHeight())
                else
                    Pix.Width(backing.cast, val)
                end
                backing:UpdateNameWidth()
            end
            if mod.ApplyNamePlateClickArea then
                mod.ApplyNamePlateClickArea()
            end
            UpdatePreview()
        end,
    }, {
        type = "slider",
        text = "Health Bar Height",
        min = 6,
        max = 50,
        step = 1,
        getValue = function()
            return DBVal("healthBarHeight")
        end,
        setValue = function(val)
            DB().healthBarHeight = val
            -- Classic WoW UI: the border scales with the bar, and the cast
            -- bar's drop and width are derived from the health bar's
            -- height, so both re-run here.
            local classic = mod.NP_Classic and mod.NP_Classic()
            local forever = mod.NP_Forever()
            -- Pooled plates re-run their appearance pass (and with it
            -- the border and level box) at next spawn.
            mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
            for _, backing in pairs(plates) do
                Pix.Height(backing.health, val)
                if classic then
                    mod.NP_ApplyClassicHealthArt(backing, val)
                    mod.LayoutCastBar(backing, mod.GetHealthBarWidth(), mod.GetCastBarHeight())
                elseif forever then
                    -- WoW Forever: the level box follows the bar's height.
                    mod.NP_ApplyForeverLevelBox(backing, val)
                end
            end
            if mod.ApplyNamePlateClickArea then
                mod.ApplyNamePlateClickArea()
            end
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height

    local function castIconOff()
        return DB() and DB().showCastIcon == false
    end

    local castBarHeightRow
    castBarHeightRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Cast Bar Height",
        min = 10,
        max = 40,
        step = 1,
        getValue = function()
            return DBVal("castBarHeight") or defaultSet.castBarHeight
        end,
        setValue = function(val)
            DB().castBarHeight = val
            local barW = mod.GetHealthBarWidth()
            for _, backing in pairs(plates) do
                mod.LayoutCastBar(backing, barW, val)
                mod.LayoutCastIcon(backing, val)
                backing.castSpark:SetHeight(val)
            end
            UpdatePreview()
        end,
    }, {
        type = "toggle",
        text = "Spell Icon",
        getValue = function()
            local saved = DB()
            if saved and saved.showCastIcon ~= nil then
                return saved.showCastIcon
            end
            return defaultSet.showCastIcon
        end,
        setValue = function(val)
            DB().showCastIcon = val
            mod.RefreshAllSettings()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    local showCastIconRow = castBarHeightRow

    -- Inline cog on Spell Icon (right region) for Scale
    if not CludesUI._prebuilding then
        local rightRegion = castBarHeightRow._rightRegion
        CludesUI.BuildInlineCog(rightRegion, {
            anchorTo = rightRegion._control,
            disabled = castIconOff,
            disabledTooltip = "Spell Icon",
            title = "Spell Icon Settings",
            rows = {
                -- Classic WoW UI seats the icon in the vanilla border's own plate:
                -- size, side, in-width and full-size are the art's (offsets stay).
                {
                    type = "slider",
                    label = "Scale",
                    min = 0.5,
                    max = 2,
                    step = 0.1,
                    disabled = function()
                        return CludesUI.BlizzStyle.Active("nameplates") == "classic"
                    end,
                    disabledTooltip = function()
                        return CludesUI.BlizzStyle.Label("nameplates")
                    end,
                    requireState = "disabled",
                    get = function()
                        return DBVal("castIconScale") or defaultSet.castIconScale
                    end,
                    set = function(val)
                        DB().castIconScale = val
                        if not (DB() and DB().castIconFullSize) then
                            for _, backing in pairs(plates) do
                                backing.castIconFrame:SetScale(val)
                            end
                        end
                        UpdatePreview()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return DBVal("castIconOffsetX") or defaultSet.castIconOffsetX or 0
                    end,
                    set = function(val)
                        DB().castIconOffsetX = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return DBVal("castIconOffsetY") or defaultSet.castIconOffsetY or 0
                    end,
                    set = function(val)
                        DB().castIconOffsetY = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Make Icon Part of the Bar",
                    tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                    disabled = function()
                        return CludesUI.BlizzStyle.Active("nameplates") == "classic"
                    end,
                    disabledTooltip = function()
                        return CludesUI.BlizzStyle.Label("nameplates")
                    end,
                    requireState = "disabled",
                    get = function()
                        local saved = DB()
                        if saved and saved.castbarIconInWidth ~= nil then
                            return saved.castbarIconInWidth
                        end
                        return defaultSet.castbarIconInWidth
                    end,
                    set = function(val)
                        DB().castbarIconInWidth = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Icon on Right",
                    tooltip = "Place the cast bar spell icon on the right side of the bars instead of the left.",
                    disabled = function()
                        return CludesUI.BlizzStyle.Active("nameplates") == "classic"
                    end,
                    disabledTooltip = function()
                        return CludesUI.BlizzStyle.Label("nameplates")
                    end,
                    requireState = "disabled",
                    get = function()
                        local saved = DB()
                        if saved and saved.castIconOnRight ~= nil then
                            return saved.castIconOnRight
                        end
                        return defaultSet.castIconOnRight
                    end,
                    set = function(val)
                        DB().castIconOnRight = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Full Sized (Health + Cast Bar)",
                    tooltip = "Make the spell icon a large square the combined height of the health bar plus the cast bar, flush with the top of the health bar and the bottom of the cast bar.",
                    disabled = function()
                        return CludesUI.BlizzStyle.Active("nameplates") == "classic"
                    end,
                    disabledTooltip = function()
                        return CludesUI.BlizzStyle.Label("nameplates")
                    end,
                    requireState = "disabled",
                    get = function()
                        local saved = DB()
                        if saved and saved.castIconFullSize ~= nil then
                            return saved.castIconFullSize
                        end
                        return defaultSet.castIconFullSize
                    end,
                    set = function(val)
                        DB().castIconFullSize = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Hide Border",
                    tooltip = "Hide the 1-pixel border around the cast bar spell icon.",
                    disabled = function()
                        return CludesUI.BlizzStyle.Get("nameplates")
                    end,
                    get = function()
                        local saved = DB()
                        if saved and saved.hideCastIconBorder ~= nil then
                            return saved.hideCastIconBorder and true or false
                        end
                        return false
                    end,
                    set = function(val)
                        DB().hideCastIconBorder = val and true or false
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Use Target Border Color",
                    tooltip = "Colors your target's custom spell icon border, or a full-size wrapped 1-pixel one, with the target border color.",
                    get = function()
                        local saved = DB()
                        if saved and saved.castIconTargetBorder ~= nil then
                            return saved.castIconTargetBorder
                        end
                        return defaultSet.castIconTargetBorder
                    end,
                    set = function(val)
                        DB().castIconTargetBorder = val
                        mod.ApplyBorderWrapToAll()
                        -- The custom spell icon border (Icon Borders cog) takes the tint too.
                        if DBVal("castIconCustomBorder") == true then
                            for _, backing in pairs(plates) do
                                mod.ApplyCastIconBorder(backing)
                            end
                        end
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    -- Cast Background Opacity (+ swatch) | Cast Bar Border (+ swatch)
    local castBgRow
    castBgRow, height = W:DualRow(
        hostFrame,
        cursorY,
        mod.NP_BlizzOnlyGate({
            type = "slider",
            text = "Cast Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                return math.floor(((DBVal("castBgAlpha") or defaultSet.castBgAlpha) * 100) + 0.5)
            end,
            setValue = function(val)
                DB().castBgAlpha = val / 100
                local c = (DB() and DB().castBgColor) or defaultSet.castBgColor
                for _, backing in pairs(plates) do
                    backing.castBG:SetColorTexture(c.r, c.g, c.b, val / 100)
                end
                UpdatePreview()
            end,
        }),
        CludesUI.BlizzStyle.Gate("nameplates", {
            type = "slider",
            text = "Cast Bar Border",
            min = 0,
            max = 4,
            step = 1,
            tooltip = "Pixel-perfect border around the cast bar. Set to 0 for no border.",
            getValue = function()
                return DBVal("castBorderSize") or defaultSet.castBorderSize
            end,
            setValue = function(val)
                DB().castBorderSize = val
                mod.RefreshCastBorder()
                UpdatePreview()
            end,
        })
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local leftRegion = castBgRow._leftRegion
        local castBgColorGet = function()
            local c = (DB() and DB().castBgColor) or defaultSet.castBgColor
            return c.r, c.g, c.b
        end
        local castBgColorSet = function(r, g, b)
            DB().castBgColor = { r = r, g = g, b = b }
            local a = DBVal("castBgAlpha") or defaultSet.castBgAlpha
            for _, backing in pairs(plates) do
                backing.castBG:SetColorTexture(r, g, b, a)
            end
            UpdatePreview()
        end
        local castBgSwatch, castBgUpdateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            castBgColorGet,
            castBgColorSet,
            nil,
            20
        )
        Pix.Point(castBgSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
        leftRegion._lastInline = castBgSwatch
        CludesUI.RegisterWidgetRefresh(function()
            castBgUpdateSwatch()
        end)
        if mod.NP_BlizzOnly() then
            CludesUI.BlizzStyle.BlockInline("nameplates", castBgSwatch)
        end
    end
    -- Inline color swatch on Cast Bar Border (right region)
    if not CludesUI._prebuilding then
        local rightRegion = castBgRow._rightRegion
        local castBorderColorGet = function()
            local c = (DB() and DB().castBorderColor) or defaultSet.castBorderColor
            return c.r, c.g, c.b
        end
        local castBorderColorSet = function(r, g, b)
            DB().castBorderColor = { r = r, g = g, b = b }
            mod.RefreshCastBorderColor()
            UpdatePreview()
        end
        local cbSwatch, cbUpdateSwatch = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            castBorderColorGet,
            castBorderColorSet,
            nil,
            20
        )
        Pix.Point(cbSwatch, "RIGHT", rightRegion._control, "LEFT", -12, 0)
        rightRegion._lastInline = cbSwatch
        CludesUI.RegisterWidgetRefresh(function()
            cbUpdateSwatch()
        end)
        CludesUI.BlizzStyle.BlockInline("nameplates", cbSwatch)
    end

    -- Cast Timer: position dropdown (None/Right/Left), styled like the duration dropdowns. "None" hides it; Right/Left choose the side (reserving space, pushing shared-side cast text); Size/X/Y live in the inline cog.
    local castTimerRow
    castTimerRow, height = W:DualRow(hostFrame, cursorY, {
        type = "segmented",
        text = "Cast Timer",
        values = { none = "None", right = "Right", left = "Left" },
        order = { "none", "right", "left" },
        getValue = function()
            local saved = DB()
            local isShown = defaultSet.showCastTimer
            if saved and saved.showCastTimer ~= nil then
                isShown = saved.showCastTimer
            end
            if not isShown then
                return "none"
            end
            return (saved and saved.castTimerSide) or defaultSet.castTimerSide
        end,
        setValue = function(val)
            if val == "none" then
                DB().showCastTimer = false
            else
                DB().showCastTimer = true
                DB().castTimerSide = val
            end
            mod.RefreshAllSettings()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Cast Bar Y Offset",
        min = -25,
        max = 75,
        step = 1,
        tooltip = "Nudge the cast bar up or down from its default spot under the health bar.",
        getValue = function()
            return DBVal("castBarOffsetY") or defaultSet.castBarOffsetY
        end,
        setValue = function(val)
            DB().castBarOffsetY = val
            local barW = mod.GetHealthBarWidth()
            local castH = mod.GetCastBarHeight()
            for _, backing in pairs(plates) do
                mod.LayoutCastBar(backing, barW, castH)
            end
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local leftRegion = castTimerRow._leftRegion
        local ctColorGet = function()
            local c = (DB() and DB().castTimerColor) or defaultSet.castTimerColor
            return c.r, c.g, c.b
        end
        local ctColorSet = function(r, g, b)
            DB().castTimerColor = { r = r, g = g, b = b }
            for _, backing in pairs(plates) do
                if backing.castTimer then
                    backing.castTimer:SetTextColor(r, g, b, 1)
                end
            end
            UpdatePreview()
        end

        -- Inline cog for Cast Timer Size / X / Y
        CludesUI.BuildInlineCog(leftRegion, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = CludesUI.L("Cast Timer Settings"),
                    xGet = function()
                        return DBVal("castTimerOffsetX") or defaultSet.castTimerOffsetX
                    end,
                    xSet = function(val)
                        DB().castTimerOffsetX = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    yGet = function()
                        return DBVal("castTimerOffsetY") or defaultSet.castTimerOffsetY
                    end,
                    ySet = function(val)
                        DB().castTimerOffsetY = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeGet = function()
                        return DBVal("castTimerSize") or defaultSet.castTimerSize
                    end,
                    sizeSet = function(val)
                        DB().castTimerSize = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeMin = 6,
                    sizeMax = 20,
                    sizeLabel = CludesUI.L("Size"),
                    sizeFirst = true,
                })
            end,
        })
        local ctSwatch, ctUpdateSwatch =
            CludesUI.BuildColorSwatch(leftRegion, leftRegion:GetFrameLevel() + 5, ctColorGet, ctColorSet, nil, 20)
        Pix.Point(ctSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = ctSwatch
        CludesUI.RegisterWidgetRefresh(function()
            ctUpdateSwatch()
        end)
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  CAST COLORS AND EFFECTS
    -----------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, SECTION_CASTBAR, cursorY)
    cursorY = cursorY - height

    -- Cast Color ---- Kick Ready Mid-Cast Hint
    local kickHintValues = { none = "None", tick = "Tick", tickbar = "Tick + Bar" }
    local kickHintOrder = { "none", "tick", "tickbar" }
    local castColorRow
    castColorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Cast Color",
        swatches = {
            mod.NP_BlizzOnlyGate({
                tooltip = "Interruptible Cast",
                getValue = function()
                    return DBColor("castBar")
                end,
                setValue = function(r, g, b)
                    DB().castBar = { r = r, g = g, b = b }
                    RefreshAllPlates()
                    UpdatePreview()
                end,
            }),
            {
                tooltip = "Interrupt on CD",
                getValue = function()
                    return DBColor("interruptReady")
                end,
                setValue = function(r, g, b)
                    DB().interruptReady = { r = r, g = g, b = b }
                    RefreshAllPlates()
                end,
            },
            mod.NP_BlizzOnlyGate({
                tooltip = "Uninterruptible Cast",
                getValue = function()
                    return DBColor("castBarUninterruptible")
                end,
                setValue = function(r, g, b)
                    DB().castBarUninterruptible = { r = r, g = g, b = b }
                    RefreshAllPlates()
                end,
            }),
            {
                tooltip = "Important Cast",
                getValue = function()
                    return DBColor("castBarImportant")
                end,
                setValue = function(r, g, b)
                    DB().castBarImportant = { r = r, g = g, b = b }
                    RefreshAllPlates()
                end,
                disabled = function()
                    local saved = DB()
                    local enabled = saved and saved.importantCastColorEnabled
                    if enabled == nil then
                        enabled = defaultSet.importantCastColorEnabled
                    end
                    return not enabled
                end,
                disabledTooltip = "Important Cast Color",
            },
        },
    }, {
        type = "dropdown",
        text = "Kick Ready Mid-Cast Hint",
        values = kickHintValues,
        order = kickHintOrder,
        tooltip = 'Shows where your interrupt will be ready during an enemy cast. "Tick" marks the exact spot on the cast bar; "Tick + Bar" also colours the window during which your interrupt will be available.',
        getValue = function()
            -- View over two underlying toggles (kickTickEnabled + interruptMidCastEnabled) so nothing migrates: tick off -> None, tick on -> Tick, tick+bar on -> Tick + Bar. Tick defaults true, so a fresh user reads "Tick".
            local saved = DB()
            local tick = true
            if saved and saved.kickTickEnabled ~= nil then
                tick = saved.kickTickEnabled
            end
            local bar = defaultSet.interruptMidCastEnabled
            if saved and saved.interruptMidCastEnabled ~= nil then
                bar = saved.interruptMidCastEnabled
            end
            if not tick then
                return "none"
            end
            if bar then
                return "tickbar"
            end
            return "tick"
        end,
        setValue = function(val)
            local saved = DB()
            if val == "none" then
                saved.kickTickEnabled = false
                saved.interruptMidCastEnabled = false
            elseif val == "tickbar" then
                saved.kickTickEnabled = true
                saved.interruptMidCastEnabled = true
            else
                saved.kickTickEnabled = true
                saved.interruptMidCastEnabled = false
            end
            mod.RefreshAllSettings()
            -- Rebuild so the inline mid-cast colour swatch greys/ungreys.
            C_Timer.After(0, function()
                CludesUI:RefreshPage()
            end)
        end,
    })
    cursorY = cursorY - height

    -- Inline mid-cast colour swatch on the Hint dropdown; greys out unless "Tick + Bar" is selected, since the colour only applies to the bar.
    if not CludesUI._prebuilding then
        local rightRegion = castColorRow._rightRegion
        local control = rightRegion and rightRegion._control
        if control and CludesUI.BuildColorSwatch then
            local function midColorOff()
                local saved = DB()
                local enabled = saved and saved.interruptMidCastEnabled
                if enabled == nil then
                    enabled = defaultSet.interruptMidCastEnabled
                end
                return not enabled
            end
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                rightRegion,
                castColorRow:GetFrameLevel() + 3,
                function()
                    local c = DB().interruptMidCastColor or defaultSet.interruptMidCastColor
                    return c.r, c.g, c.b
                end,
                function(r, g, b)
                    DB().interruptMidCastColor = { r = r, g = g, b = b }
                    mod.RefreshAllSettings()
                end,
                nil,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -12, 0)
            rightRegion._lastInline = colorSwatch
            colorSwatch:SetScript("OnEnter", function(s)
                CludesUI.ShowWidgetTooltip(s, "Interrupt Ready Mid-Cast")
            end)
            colorSwatch:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            CludesUI.RegisterWidgetRefresh(function()
                local off = midColorOff()
                colorSwatch:SetAlpha(off and 0.15 or 1)
                colorSwatch:EnableMouse(not off)
                updateSwatch()
            end)
            colorSwatch:SetAlpha(midColorOff() and 0.15 or 1)
            colorSwatch:EnableMouse(not midColorOff())
        end
    end

    -- Inline cog beside the Cast Color swatches: Show Shield Icon
    if not CludesUI._prebuilding then
        local region = castColorRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            tip = "Cast Color Settings",
            title = "Cast Color",
            rows = {
                {
                    type = "toggle",
                    label = "Show Shield Icon",
                    tooltip = "Show a shield icon on the cast bar when an enemy's cast cannot be interrupted.",
                    get = function()
                        local saved = DB()
                        if saved and saved.castBarShieldEnabled ~= nil then
                            return saved.castBarShieldEnabled
                        end
                        return defaultSet.castBarShieldEnabled
                    end,
                    set = function(val)
                        DB().castBarShieldEnabled = val
                        RefreshAllPlates()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show Spark",
                    tooltip = "Show the bright spark at the leading edge of the cast bar fill.",
                    get = function()
                        local saved = DB()
                        if saved and saved.castBarSparkEnabled ~= nil then
                            return saved.castBarSparkEnabled
                        end
                        return defaultSet.castBarSparkEnabled ~= false
                    end,
                    set = function(val)
                        DB().castBarSparkEnabled = val
                        for _, backing in pairs(plates) do
                            if backing.castSpark then
                                backing.castSpark:SetShown(val ~= false)
                            end
                        end
                        UpdatePreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Important Cast Color",
                    tooltip = "Tint the cast bar with the Important colour when the enemy casts a spell the game flags as important.",
                    get = function()
                        local saved = DB()
                        if saved and saved.importantCastColorEnabled ~= nil then
                            return saved.importantCastColorEnabled
                        end
                        return defaultSet.importantCastColorEnabled
                    end,
                    set = function(val)
                        DB().importantCastColorEnabled = val
                        RefreshAllPlates()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "toggle",
                    label = "Interruptible While Kick Ready",
                    tooltip = "While your interrupt is ready, important casts keep the Interruptible color.",
                    get = function()
                        local saved = DB()
                        if saved and saved.importantCastKickReadyAsInterruptible ~= nil then
                            return saved.importantCastKickReadyAsInterruptible
                        end
                        return defaultSet.importantCastKickReadyAsInterruptible
                    end,
                    set = function(val)
                        DB().importantCastKickReadyAsInterruptible = val
                        RefreshAllPlates()
                    end,
                    disabled = function()
                        local saved = DB()
                        local enabled = saved and saved.importantCastColorEnabled
                        if enabled == nil then
                            enabled = defaultSet.importantCastColorEnabled
                        end
                        return not enabled
                    end,
                    disabledTooltip = "Important Cast Color",
                },
            },
        })
    end

    -- Important Cast Glow | Cast Targets You Glow: shared glow controls (cast bar = bar
    -- host) + preview
    do
        local GO = CludesUI.GlowOptions
        local impDesc = npImpCastGlowDesc

        local impGlowRow
        impGlowRow, height = W:DualRow(
            hostFrame,
            cursorY,
            GO.DropdownSpec(
                impDesc,
                "Important Cast Glow",
                "Show a glow on the cast bar when the enemy is casting a spell Blizzard marks as important."
            ),
            GO.DropdownSpec(
                npCastTargetGlowDesc,
                "Cast Targets You Glow",
                "Show a glow on the cast bar when the enemy's cast is targeting you."
            )
        )
        cursorY = cursorY - height

        if not CludesUI._prebuilding then
            -- Icon-sized preview in each inline chain; -12: the widest FlipBook
            -- styles overhang ~8px per side.
            local function AttachGlow(region, desc)
                GO.AttachInline(region, desc)
                local preview = GO.BuildPreview(region, desc, {
                    bar = false,
                    width = 26,
                    height = 26,
                    icon = function()
                        return displayCastIcons[optionState._previewCastIconIdx or 1]
                    end,
                    anchor = region._lastInline,
                    x = -12,
                })
                if preview then
                    preview:SetFrameLevel(region:GetFrameLevel() + 5)
                    region._lastInline = preview
                end
            end
            AttachGlow(impGlowRow._leftRegion, impDesc)
            AttachGlow(impGlowRow._rightRegion, npCastTargetGlowDesc)
        end
    end

    -- Row 3: Focus Text Reminders (CDM only, left) | Show Interrupted Flash Effect (always present, a core cast bar setting): when CDM is loaded, Focus Text Reminders fills the left slot and flash takes the right; otherwise flash takes the left slot itself.
    -- Casts In Front of Nameplates follows in the next free slot.
    do
        local inFrontCfg = {
            type = "toggle",
            text = "Casts In Front of Nameplates",
            tooltip = "Forces all casts to be shown in front of nameplates for visual clarity",
            getValue = function()
                return DBVal("castOverlayEnabled") == true
            end,
            setValue = function(val)
                DB().castOverlayEnabled = val
                mod.RefreshAllSettings()
            end,
        }
        local function flashOff()
            local saved = DB()
            local enabled = saved and saved.interruptedFlashEnabled
            if enabled == nil then
                enabled = defaultSet.interruptedFlashEnabled
            end
            return not enabled
        end
        local flashCfg = {
            type = "toggle",
            text = "Show Interrupted Flash Effect",
            tooltip = 'Flash the enemy\'s cast bar and show "Interrupted" for a moment when their cast is interrupted. Use the swatch to change the flash colour.',
            getValue = function()
                local saved = DB()
                if saved and saved.interruptedFlashEnabled ~= nil then
                    return saved.interruptedFlashEnabled
                end
                return defaultSet.interruptedFlashEnabled
            end,
            setValue = function(val)
                DB().interruptedFlashEnabled = val
                RefreshAllPlates()
                -- Rebuild so the inline flash colour swatch greys/ungreys.
                C_Timer.After(0, function()
                    CludesUI:RefreshPage()
                end)
            end,
        }

        local row3, swatchRegion
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("CludesUICooldownManager") then
            -- Access the FocusKick bar config in CDM's profile data
            local function GetFocusKickBar()
                local cdmDb = _G._CUCME_AceDB
                local p = cdmDb and cdmDb.profile
                local barList = p and p.cdmBars and p.cdmBars.bars
                if not barList then
                    return nil
                end
                for _, b in ipairs(barList) do
                    if b.key == "focuskick" then
                        return b
                    end
                end
                return nil
            end
            row3, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Focus Text Reminders",
                tooltip = 'Display the word "FOCUS" below caster/miniboss mobs in M+ if you have not set your focus. This is the same setting as in the FocusKick bar options. Disabled for specs with no kick.',
                getValue = function()
                    local fk = GetFocusKickBar()
                    return fk and fk.focusReminderEnabled == true
                end,
                setValue = function(val)
                    local fk = GetFocusKickBar()
                    if fk then
                        fk.focusReminderEnabled = val
                    end
                    if _G._CUCME_RefreshFocusReminders then
                        _G._CUCME_RefreshFocusReminders()
                    end
                    CludesUI:RefreshPage()
                end,
            }, flashCfg)
            cursorY = cursorY - height
            swatchRegion = row3._rightRegion
            _, height = W:DualRow(hostFrame, cursorY, inFrontCfg, CludesUI.BlankRowCfg())
            cursorY = cursorY - height
        else
            row3, height = W:DualRow(hostFrame, cursorY, flashCfg, inFrontCfg)
            cursorY = cursorY - height
            swatchRegion = row3._leftRegion
        end

        -- Inline flash colour swatch on the Show Interrupted Flash Effect toggle; greys out when disabled.
        if not CludesUI._prebuilding then
            local region = swatchRegion
            local control = region and region._control
            if control and CludesUI.BuildColorSwatch then
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    row3:GetFrameLevel() + 3,
                    function()
                        local c = DB().interruptedFlashColor or defaultSet.interruptedFlashColor
                        return c.r, c.g, c.b
                    end,
                    function(r, g, b)
                        DB().interruptedFlashColor = { r = r, g = g, b = b }
                        RefreshAllPlates()
                    end,
                    nil,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", region._lastInline or control, "LEFT", -12, 0)
                region._lastInline = colorSwatch
                colorSwatch:SetScript("OnEnter", function(s)
                    CludesUI.ShowWidgetTooltip(s, "Interrupted Flash Colour")
                end)
                colorSwatch:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                -- Blizzard Style uses the stock interrupted fill art, so the flash colour is
                -- inert there: the build and every refresh grey the swatch out alike.
                local function ApplyFlashSwatchState()
                    local off = flashOff() or mod.NP_BlizzOnly()
                    colorSwatch:SetAlpha(off and 0.15 or 1)
                    colorSwatch:EnableMouse(not off)
                end
                CludesUI.RegisterWidgetRefresh(function()
                    ApplyFlashSwatchState()
                    updateSwatch()
                end)
                ApplyFlashSwatchState()
            end
        end
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  TARGET, FOCUS & HOVER EFFECTS
    -----------------------------------------------------------------------
    local tfxHeader
    tfxHeader, height = W:SectionHeader(hostFrame, "TARGET, FOCUS & HOVER EFFECTS", cursorY)
    cursorY = cursorY - height

    local targetGlowRow
    -- Build the arrow-style dropdown options from the shared style table.
    local arrowVals = { none = "None" }
    local arrowOrd = { "none" }
    for _, keyName in ipairs(mod.TARGET_ARROW_ORDER) do
        arrowVals[keyName] = mod.TARGET_ARROW_STYLES[keyName].label
        arrowOrd[#arrowOrd + 1] = keyName
    end
    -- Preview the right-arrow texture on the right of each dropdown row.
    arrowVals._menuOpts = {
        itemHeight = 26,
        icon = function(key)
            local st = mod.TARGET_ARROW_STYLES[key]
            if not st then
                return nil
            end -- "none" has no preview
            return mod.TARGET_ARROW_DIR .. st.l .. ".png"
        end,
        iconWidth = function(key)
            local st = mod.TARGET_ARROW_STYLES[key]
            if not st then
                return nil
            end
            -- Match in-game aspect: drawn width is st.w at height 16, icon slot is itemHeight(32)-8=24 tall, so scale width by 24/16.
            return math.floor(st.w * 24 / 16 + 0.5)
        end,
    }
    targetGlowRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Target Effect",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    }, {
        type = "dropdown",
        text = "Target Arrows",
        values = arrowVals,
        order = arrowOrd,
        getValue = function()
            if DBVal("showTargetArrows") ~= true then
                return "none"
            end
            return DBVal("targetArrowStyle") or (DBVal("targetArrowDouble") and "double") or "simple"
        end,
        setValue = function(val)
            if val == "none" then
                DB().showTargetArrows = false
            else
                DB().showTargetArrows = true
                DB().targetArrowStyle = val
            end
            for _, backing in pairs(plates) do
                backing:ApplyTarget()
            end
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height

    -- Target Effect: multi-select checkbox dropdown (CUI Glow/Border Color/Highlight), independent toggles; data model live-converts from the legacy targetGlowStyle string (see ns.GetTargetGlow* in the core file).
    local refreshTargetBorderSwatch -- fwd decl; assigned when the swatch builds
    local refreshTargetGlowSwatch -- fwd decl; assigned when the glow swatch builds
    local refreshTargetHighlightCog -- fwd decl; assigned when the cog builds
    if not CludesUI._prebuilding then
        local leftRegion = targetGlowRow._leftRegion
        if leftRegion._control then
            leftRegion._control:Hide()
        end
        -- The WoW Forever style offers Highlight alone: the other three are
        -- locked there (their getters read off, so they draw nothing).
        local function fvLocked()
            return CludesUI.BlizzStyle.Forever("nameplates")
        end
        local function fvTip()
            return CludesUI.L("Not available in the WoW Forever style.")
        end
        local glowItems = {
            { key = "cludesui", label = "CUI Glow", lockedFn = fvLocked, lockedTooltip = fvTip },
            { key = "borderColor", label = "Border Color", lockedFn = fvLocked, lockedTooltip = fvTip },
            { key = "highlight", label = "Highlight" },
            {
                key = "borderSize",
                label = "Border Size",
                tooltip = "Change Size in the Cogwheel",
                lockedFn = fvLocked,
                lockedTooltip = fvTip,
            },
        }
        local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
            leftRegion,
            170,
            leftRegion:GetFrameLevel() + 2,
            glowItems,
            function(keyName)
                if keyName == "cludesui" then
                    return mod.GetTargetGlowCludesUI()
                end
                if keyName == "borderColor" then
                    return mod.GetTargetGlowBorderColor()
                end
                if keyName == "highlight" then
                    return mod.GetTargetGlowHighlight()
                end
                if keyName == "borderSize" then
                    return mod.GetTargetGlowBorderSize()
                end
                return false
            end,
            function(keyName, val)
                if keyName == "cludesui" then
                    DB().targetGlowCludesUI = val
                elseif keyName == "borderColor" then
                    DB().targetGlowBorderColor = val
                elseif keyName == "highlight" then
                    DB().targetGlowHighlight = val
                elseif keyName == "borderSize" then
                    DB().targetGlowBorderSize = val
                    -- First-enable snapshot: seed the cog slider with the user's CURRENT border size, so enabling changes nothing until they move it (one-time, never re-snapshots later).
                    if val and DB().targetBorderSizeValue == nil then
                        if mod.IsCustomBorderEnabled() then
                            DB().targetBorderSizeValue = DBVal("customBorderSize")
                                or defaultSet.customBorderSize
                        else
                            DB().targetBorderSizeValue = DBVal("borderSize") or defaultSet.borderSize
                        end
                    end
                end
                for _, backing in pairs(plates) do
                    backing:ApplyTarget()
                end
                for _, fp in pairs(mod.friendlyPlates) do
                    fp:ApplyTarget()
                end
                UpdatePreview()
                if refreshTargetBorderSwatch then
                    refreshTargetBorderSwatch()
                end
                if refreshTargetGlowSwatch then
                    refreshTargetGlowSwatch()
                end
                if refreshTargetHighlightCog then
                    refreshTargetHighlightCog()
                end
            end
        )
        Pix.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
        leftRegion._control = checkDrop
        leftRegion._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbDDRefresh)

        -- Inline cog "More Effects": Highlight color/opacity + Glow opacity; enabled when Highlight OR CUI Glow is on (Glow Opacity reachable whenever the glow is active).
        do
            local function highlightCogOff()
                return not (
                    mod.GetTargetGlowHighlight()
                    or mod.GetTargetGlowCludesUI()
                    or mod.GetTargetGlowBorderSize()
                )
            end
            local highlightCogBtn = CludesUI.BuildInlineCog(leftRegion, {
                disabled = highlightCogOff,
                disabledTooltip = "a Target Effect",
                title = "More Effects",
                rows = {
                    {
                        type = "colorpicker",
                        label = "Highlight Color",
                        hasAlpha = false,
                        get = function()
                            local c = mod.GetTargetHighlightColor()
                            return c.r, c.g, c.b
                        end,
                        set = function(r, g, b)
                            DB().targetHighlightColor = { r = r, g = g, b = b }
                            for _, backing in pairs(plates) do
                                backing:ApplyTarget()
                            end
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Highlight Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = function()
                            return math.floor((mod.GetTargetHighlightAlpha() * 100) + 0.5)
                        end,
                        set = function(val)
                            DB().targetHighlightAlpha = val / 100
                            for _, backing in pairs(plates) do
                                backing:ApplyTarget()
                            end
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Glow Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        disabled = fvLocked,
                        disabledTooltip = fvTip,
                        rawTooltip = true,
                        get = function()
                            return math.floor((mod.GetTargetGlowAlpha() * 100) + 0.5)
                        end,
                        set = function(val)
                            DB().targetGlowAlpha = val / 100
                            for _, backing in pairs(plates) do
                                backing:ApplyTarget()
                            end
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 0,
                        max = 4,
                        step = 1,
                        get = function()
                            local val = DBVal("targetBorderSizeValue")
                            if val ~= nil then
                                return val
                            end
                            -- Not snapshotted yet: show the current border size.
                            if mod.IsCustomBorderEnabled() then
                                return DBVal("customBorderSize") or defaultSet.customBorderSize
                            end
                            return DBVal("borderSize") or defaultSet.borderSize
                        end,
                        set = function(val)
                            DB().targetBorderSizeValue = val
                            for _, backing in pairs(plates) do
                                backing:ApplyTarget()
                            end
                            for _, fp in pairs(mod.friendlyPlates) do
                                fp:ApplyTarget()
                            end
                            UpdatePreview()
                        end,
                        disabled = function()
                            return not mod.GetTargetGlowBorderSize()
                        end,
                        disabledTooltip = function()
                            if fvLocked() then
                                return fvTip()
                            end
                            return "Border Size Target Effect"
                        end,
                        rawTooltip = fvLocked,
                    },
                },
            })
            refreshTargetHighlightCog = highlightCogBtn and highlightCogBtn._cuiCogState
        end

        -- Inline Border Color swatch: edits targetBorderColor (default white), tints the custom border; dimmed+non-interactive unless Border Color is checked.
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            function()
                local c = mod.GetTargetBorderColor()
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                DB().targetBorderColor = { r = r, g = g, b = b }
                for _, backing in pairs(plates) do
                    backing:ApplyTarget()
                end
                for _, fp in pairs(mod.friendlyPlates) do
                    fp:ApplyTarget()
                end
                UpdatePreview()
            end,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = colorSwatch
        -- Tooltip so the swatch's purpose is clear (shown while interactive, i.e. Border Color on).
        CludesUI.HoverTip(colorSwatch, "Border Color")
        refreshTargetBorderSwatch = function()
            local off = not mod.GetTargetGlowBorderColor()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end
        CludesUI.RegisterWidgetRefresh(refreshTargetBorderSwatch)
        refreshTargetBorderSwatch()

        -- Inline Glow Color swatch: edits targetGlowColor (default the signature blue), tints the CUI background glow; dimmed+non-interactive unless CUI Glow is checked.
        local glowSwatch, updateGlowSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            function()
                local c = mod.GetTargetGlowColor()
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                DB().targetGlowColor = { r = r, g = g, b = b }
                for _, backing in pairs(plates) do
                    backing:ApplyTarget()
                end
                UpdatePreview()
            end,
            nil,
            20
        )
        Pix.Point(glowSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = glowSwatch
        CludesUI.HoverTip(glowSwatch, "Glow Color")
        refreshTargetGlowSwatch = function()
            local off = not mod.GetTargetGlowCludesUI()
            glowSwatch:SetAlpha(off and 0.15 or 1)
            glowSwatch:EnableMouse(not off)
            updateGlowSwatch()
        end
        CludesUI.RegisterWidgetRefresh(refreshTargetGlowSwatch)
        refreshTargetGlowSwatch()
    end

    -- Inline cog (arrow scale), beside the control; the swatches sit left of it
    do
        local rightRegion = targetGlowRow._rightRegion
        local arrowOff = function()
            return DBVal("showTargetArrows") ~= true
        end
        CludesUI.BuildInlineCog(rightRegion, {
            disabled = arrowOff,
            disabledTooltip = "Target Arrows",
            title = "Arrow Scale",
            rows = {
                {
                    type = "slider",
                    label = "Scale",
                    min = 0.5,
                    max = 3.0,
                    step = 0.1,
                    get = function()
                        return DBVal("targetArrowScale") or defaultSet.targetArrowScale or 1.0
                    end,
                    set = function(val)
                        DB().targetArrowScale = val
                        local _scKey = DBVal("targetArrowStyle")
                            or (DBVal("targetArrowDouble") and "double")
                            or "simple"
                        local _scW = (mod.TARGET_ARROW_STYLES[_scKey] or mod.TARGET_ARROW_STYLES.simple).w
                        for _, backing in pairs(plates) do
                            local sc = val
                            local aw = math.floor(_scW * sc + 0.5)
                            local ah = math.floor(16 * sc + 0.5)
                            if backing.leftArrow then
                                Pix.Size(backing.leftArrow, aw, ah)
                            end
                            if backing.rightArrow then
                                Pix.Size(backing.rightArrow, aw, ah)
                            end
                        end
                        UpdatePreview()
                    end,
                },
            },
        })
    end

    -- Inline Custom + Class color swatches on Target Arrows (custom adjacent to the cog, class to its left); click to switch, inactive swatch dims, both gray out when arrows off.
    do
        local rightRegion = targetGlowRow._rightRegion
        local arrowOff = function()
            return DBVal("showTargetArrows") ~= true
        end
        local customSwatch, updateCustom, classSwatch, updateClass
        local function refreshArrowSwatches()
            if updateCustom then
                updateCustom()
            end
            if updateClass then
                updateClass()
            end
            local off = arrowOff()
            local useClass = DBVal("targetArrowClassColor") == true
            customSwatch:SetAlpha(off and 0.15 or (useClass and 0.3 or 1))
            classSwatch:SetAlpha(off and 0.15 or (useClass and 1 or 0.3))
            customSwatch:SetMouseClickEnabled(not off)
            classSwatch:SetMouseClickEnabled(not off)
        end
        customSwatch, updateCustom = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            function()
                local c = DBVal("targetArrowColor") or defaultSet.targetArrowColor
                return c.r, c.g, c.b
            end,
            function(r, g, b)
                DB().targetArrowColor = { r = r, g = g, b = b }
                DB().targetArrowClassColor = false
                for _, backing in pairs(plates) do
                    backing:ApplyTarget()
                end
                UpdatePreview()
                refreshArrowSwatches()
            end,
            nil,
            20
        )
        Pix.Point(customSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
        local origCustomClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            if arrowOff() then
                return
            end
            if DBVal("targetArrowClassColor") == true then
                DB().targetArrowClassColor = false
                for _, backing in pairs(plates) do
                    backing:ApplyTarget()
                end
                UpdatePreview()
                refreshArrowSwatches()
                return
            end
            if origCustomClick then
                origCustomClick(self, ...)
            end
        end)
        CludesUI.HoverTip(customSwatch, "Custom Color")
        classSwatch, updateClass = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            function()
                local _, ct = UnitClass("player")
                local classColor = ct and C_ClassColor and C_ClassColor.GetClassColor(ct)
                if classColor then
                    return classColor.r, classColor.g, classColor.b
                end
                return 1, 1, 1
            end,
            function() end,
            nil,
            20
        )
        Pix.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        rightRegion._lastInline = classSwatch
        classSwatch:SetScript("OnClick", function()
            if arrowOff() then
                return
            end
            DB().targetArrowClassColor = true
            for _, backing in pairs(plates) do
                backing:ApplyTarget()
            end
            UpdatePreview()
            refreshArrowSwatches()
        end)
        CludesUI.HoverTip(classSwatch, "Class Color")
        CludesUI.RegisterWidgetRefresh(refreshArrowSwatches)
        refreshArrowSwatches()
    end

    -- Eye icon to the left of the Target Glow Style dropdown to toggle glow on preview
    -- (none in the search pre-build: it indexes nothing, and the row is a stand-in there)
    if not CludesUI._prebuilding then
        local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
        local leftRegion = targetGlowRow._leftRegion
        local eyeButton = CreateFrame("Button", nil, leftRegion)
        eyeButton:SetSize(26, 26)
        eyeButton:SetPoint("RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        eyeButton:SetFrameLevel(leftRegion:GetFrameLevel() + 5)
        CludesUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function RefreshTargetGlowEye()
            if optionState.showTargetGlowPreview then
                eyeTex:SetTexture(EYE_INVISIBLE)
            else
                eyeTex:SetTexture(EYE_VISIBLE)
            end
        end
        RefreshTargetGlowEye()
        eyeButton:SetScript("OnClick", function()
            optionState.showTargetGlowPreview = not optionState.showTargetGlowPreview
            RefreshTargetGlowEye()
            UpdatePreview()
        end)
        eyeButton:SetScript("OnEnter", function(self)
            CludesUI.SetGlyphAlpha(self, 0.7)
        end)
        eyeButton:SetScript("OnLeave", function(self)
            CludesUI.SetGlyphAlpha(self, 0.4)
        end)
    end

    -- Enable Target Color ---- Target Texture
    local isTargetColorDisabled = function()
        local saved = DB()
        if saved and saved.targetColorEnabled ~= nil then
            return not saved.targetColorEnabled
        end
        return not defaultSet.targetColorEnabled
    end
    local isTargetTextureNone = function()
        return (DBVal("targetOverlayTexture") or defaultSet.targetOverlayTexture) == "none"
    end
    -- No Tint: the target texture pattern becomes the bar's own fill texture (SetStatusBarTexture) instead of a tinted overlay, so the color swatch/opacity below stop applying.
    local isTargetNoTint = function()
        local val = DBVal("targetOverlayNoTint")
        if val == nil then
            return defaultSet.targetOverlayNoTint
        end
        return val
    end
    local isFocusColorDisabled = function()
        local saved = DB()
        if saved and saved.focusColorEnabled ~= nil then
            return not saved.focusColorEnabled
        end
        return not defaultSet.focusColorEnabled
    end
    local isFocusTextureNone = function()
        return (DBVal("focusOverlayTexture") or defaultSet.focusOverlayTexture) == "none"
    end
    local isFocusNoTint = function()
        local val = DBVal("focusOverlayNoTint")
        if val == nil then
            return defaultSet.focusOverlayNoTint
        end
        return val
    end

    local targetPrev, focusPrev
    local function RefreshFocusPreview()
        RefreshAllPlates()
        if focusPrev and focusPrev.UpdateOverlay then
            focusPrev.UpdateOverlay()
        end
    end

    local targetColorRow
    targetColorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Target Color",
        getValue = function()
            local saved = DB()
            if saved and saved.targetColorEnabled ~= nil then
                return saved.targetColorEnabled
            end
            return defaultSet.targetColorEnabled
        end,
        setValue = function(val)
            DB().targetColorEnabled = val
            RefreshAllPlates()
            if targetPrev then
                if val then
                    targetPrev.SetColorOverride(nil)
                else
                    targetPrev.SetColorOverride(function()
                        return DBColor("enemyInCombat")
                    end)
                end
                targetPrev.UpdateColor()
                targetPrev.SetDisabled(not val)
            end
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Enable Focus Color",
        getValue = function()
            local saved = DB()
            if saved and saved.focusColorEnabled ~= nil then
                return saved.focusColorEnabled
            end
            return defaultSet.focusColorEnabled
        end,
        setValue = function(val)
            DB().focusColorEnabled = val
            RefreshAllPlates()
            if focusPrev then
                if val then
                    focusPrev.SetColorOverride(nil)
                else
                    focusPrev.SetColorOverride(function()
                        return DBColor("enemyInCombat")
                    end)
                end
                focusPrev.UpdateColor()
                focusPrev.SetDisabled(not val)
            end
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    -- Inline Target Color swatch
    if not CludesUI._prebuilding then
        local leftRegion = targetColorRow._leftRegion
        local targetColorGet = function()
            return DBColor("target")
        end
        local targetColorSet = function(r, g, b)
            DB().target = { r = r, g = g, b = b }
            RefreshAllPlates()
            if targetPrev then
                targetPrev.UpdateColor()
            end
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            targetColorGet,
            targetColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", leftRegion._control, "LEFT", -12, 0)
        CludesUI.RegisterWidgetRefresh(function()
            local off = isTargetColorDisabled()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetColorDisabled()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Inline Focus Color swatch
    if not CludesUI._prebuilding then
        local rightRegion = targetColorRow._rightRegion
        local focusColorGet = function()
            return DBColor("focus")
        end
        local focusColorSet = function(r, g, b)
            DB().focus = { r = r, g = g, b = b }
            RefreshAllPlates()
            if focusPrev then
                focusPrev.UpdateColor()
            end
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            focusColorGet,
            focusColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", rightRegion._control, "LEFT", -12, 0)
        CludesUI.RegisterWidgetRefresh(function()
            local off = isFocusColorDisabled()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusColorDisabled()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Target Texture ---- Focus Texture
    -- Both dropdowns list the special stripe overlays first, then the full bar texture set (CUI + SharedMedia) shared with the main Bar Texture dropdown; stripe keys resolve to nameplate Media, bar keys resolve through the health-bar lookup at render time (ns.ResolveOverlayTexPath).
    local ovtValues, ovtOrder = {}, {}
    do
        local STRIPE_ORDER = {
            "striped-v2",
            "striped-wide-v2",
            "stripes-medium",
            "stripes-small-close",
            "stripes-small-spread",
            "striped-tiny",
        }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes",
            ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes",
            ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes",
            ["striped-tiny"] = "Tiny Stripes",
        }
        for _, keyName in ipairs(STRIPE_ORDER) do
            ovtValues[keyName] = STRIPE_NAMES[keyName]
            ovtOrder[#ovtOrder + 1] = keyName
        end
        ovtOrder[#ovtOrder + 1] = "---"
        for _, keyName in ipairs(hbtOrder) do
            ovtOrder[#ovtOrder + 1] = keyName
            if keyName ~= "---" then
                ovtValues[keyName] = hbtValues[keyName]
            end
        end
        ovtValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then
                    return nil
                end
                if mod.OVERLAY_STRIPE_KEYS and mod.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\CludesUINameplates\\Media\\" .. key .. ".png"
                end
                return mod.healthBarTextures and mod.healthBarTextures[key]
            end,
        }
    end
    local textureDualRow
    textureDualRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Target Texture",
        values = ovtValues,
        getValue = function()
            return DBVal("targetOverlayTexture") or defaultSet.targetOverlayTexture
        end,
        setValue = function(val)
            DB().targetOverlayTexture = val
            RefreshAllPlates()
            if targetPrev and targetPrev.UpdateOverlay then
                targetPrev.UpdateOverlay()
            end
            CludesUI:RefreshPage()
        end,
        order = ovtOrder,
    }, {
        type = "dropdown",
        text = "Focus Texture",
        values = ovtValues,
        getValue = function()
            return DBVal("focusOverlayTexture") or defaultSet.focusOverlayTexture
        end,
        setValue = function(val)
            DB().focusOverlayTexture = val
            RefreshAllPlates()
            if focusPrev and focusPrev.UpdateOverlay then
                focusPrev.UpdateOverlay()
            end
            CludesUI:RefreshPage()
        end,
        order = ovtOrder,
    })
    cursorY = cursorY - height

    -- Inline Target Texture cog (Opacity + No Tint), beside the control; the swatch sits left of it
    if not CludesUI._prebuilding then
        local leftRegion = textureDualRow._leftRegion
        CludesUI.BuildInlineCog(leftRegion, {
            disabled = isTargetTextureNone,
            disabledTooltip = "a Target Texture",
            title = "Target Texture",
            rows = {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 5,
                    max = 100,
                    step = 1,
                    get = function()
                        return math.floor(
                            ((DBVal("targetOverlayAlpha") or defaultSet.targetOverlayAlpha) * 100) + 0.5
                        )
                    end,
                    set = function(val)
                        DB().targetOverlayAlpha = val / 100
                        RefreshAllPlates()
                        if targetPrev and targetPrev.UpdateOverlay then
                            targetPrev.UpdateOverlay()
                        end
                    end,
                },
                {
                    type = "toggle",
                    label = "Full alpha on empty part of bar",
                    get = function()
                        local val = DBVal("targetOverlayFullBgAlpha")
                        if val == nil then
                            return defaultSet.targetOverlayFullBgAlpha
                        end
                        return val
                    end,
                    set = function(val)
                        DB().targetOverlayFullBgAlpha = val
                        RefreshAllPlates()
                        if targetPrev and targetPrev.UpdateOverlay then
                            targetPrev.UpdateOverlay()
                        end
                    end,
                },
                {
                    type = "toggle",
                    label = "Don't tint (keep bar's own color)",
                    tooltip = "Tints the pattern with the bar's current color instead of the custom overlay color.",
                    get = isTargetNoTint,
                    set = function(val)
                        DB().targetOverlayNoTint = val
                        RefreshAllTextures()
                        if targetPrev and targetPrev.UpdateOverlay then
                            targetPrev.UpdateOverlay()
                        end
                    end,
                },
            },
        })
    end

    -- Inline Target Texture color swatch
    if not CludesUI._prebuilding then
        local leftRegion = textureDualRow._leftRegion
        local targetTexColorGet = function()
            local c = (DB() and DB().targetOverlayColor) or defaultSet.targetOverlayColor
            return c.r, c.g, c.b
        end
        local targetTexColorSet = function(r, g, b)
            DB().targetOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            if targetPrev and targetPrev.UpdateOverlay then
                targetPrev.UpdateOverlay()
            end
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            leftRegion:GetFrameLevel() + 5,
            targetTexColorGet,
            targetTexColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(function()
            local off = isTargetTextureNone() or isTargetNoTint()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isTargetTextureNone() or isTargetNoTint()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Inline Focus Texture cog (Opacity + No Tint), beside the control; the swatch sits left of it
    if not CludesUI._prebuilding then
        local rightRegion = textureDualRow._rightRegion
        CludesUI.BuildInlineCog(rightRegion, {
            disabled = isFocusTextureNone,
            disabledTooltip = "a Focus Texture",
            title = "Focus Texture",
            rows = {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 5,
                    max = 100,
                    step = 1,
                    get = function()
                        return math.floor(
                            ((DBVal("focusOverlayAlpha") or defaultSet.focusOverlayAlpha) * 100) + 0.5
                        )
                    end,
                    set = function(val)
                        DB().focusOverlayAlpha = val / 100
                        RefreshFocusPreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Full alpha on empty part of bar",
                    get = function()
                        local val = DBVal("focusOverlayFullBgAlpha")
                        if val == nil then
                            return defaultSet.focusOverlayFullBgAlpha
                        end
                        return val
                    end,
                    set = function(val)
                        DB().focusOverlayFullBgAlpha = val
                        RefreshFocusPreview()
                    end,
                },
                {
                    type = "toggle",
                    label = "Don't tint (keep bar's own color)",
                    tooltip = "Tints the pattern with the bar's current color instead of the custom overlay color.",
                    get = isFocusNoTint,
                    set = function(val)
                        DB().focusOverlayNoTint = val
                        RefreshAllTextures()
                        RefreshFocusPreview()
                    end,
                },
            },
        })
    end

    -- Inline Focus Texture color swatch
    if not CludesUI._prebuilding then
        local rightRegion = textureDualRow._rightRegion
        local focusTexColorGet = function()
            local c = (DB() and DB().focusOverlayColor) or defaultSet.focusOverlayColor
            return c.r, c.g, c.b
        end
        local focusTexColorSet = function(r, g, b)
            DB().focusOverlayColor = { r = r, g = g, b = b }
            RefreshAllPlates()
            if focusPrev and focusPrev.UpdateOverlay then
                focusPrev.UpdateOverlay()
            end
        end
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            focusTexColorGet,
            focusTexColorSet,
            nil,
            20
        )
        Pix.Point(colorSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
        rightRegion._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(function()
            local off = isFocusTextureNone() or isFocusNoTint()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
            updateSwatch()
        end)
        local off = isFocusTextureNone() or isFocusNoTint()
        colorSwatch:SetAlpha(off and 0.15 or 1)
        colorSwatch:EnableMouse(not off)
    end

    -- Target Preview ---- Focus Preview
    local previewDualRow
    previewDualRow, height = W:DualRow(
        hostFrame,
        cursorY,
        { type = "label", text = "Target Preview" },
        { type = "label", text = "Focus Preview" }
    )
    cursorY = cursorY - height

    -- The two bars sit at their half's right edge: the row's child anchored to that
    -- half, moved. Page reuse: the row's children of its earlier dresses stay among
    -- them, idle, and the deferred pass stops once the row was dressed again.
    local previewRowGen = PoolGen(previewDualRow)
    if not CludesUI._prebuilding then
        targetPrev = LazyColorPreviewBar(previewDualRow, "health", "target", previewDualRow._leftRegion)
        do
            local function RepositionTargetBar()
                if PoolGen(previewDualRow) ~= previewRowGen then
                    return
                end
                local region = previewDualRow._leftRegion
                for _, childFrame in ipairs({ previewDualRow:GetChildren() }) do
                    if
                        childFrame.GetNumPoints
                        and childFrame:GetNumPoints() > 0
                        and not PoolIsIdle(childFrame)
                    then
                        local _, rel = childFrame:GetPoint(1)
                        if rel == region then
                            childFrame:ClearAllPoints()
                            Pix.Point(childFrame, "RIGHT", region, "RIGHT", -20, 0)
                            return
                        end
                    end
                end
            end
            previewDualRow:HookScript("OnShow", RepositionTargetBar)
            C_Timer.After(0, RepositionTargetBar)
        end
        if isTargetColorDisabled() then
            targetPrev.SetColorOverride(function()
                return DBColor("enemyInCombat")
            end)
        end
        targetPrev.SetDisabled(isTargetColorDisabled())
        targetPrev.UpdateColor()
    end

    if not CludesUI._prebuilding then
        focusPrev = LazyColorPreviewBar(previewDualRow, "health", "focus", previewDualRow._rightRegion)
        do
            local function RepositionFocusBar()
                if PoolGen(previewDualRow) ~= previewRowGen then
                    return
                end
                local region = previewDualRow._rightRegion
                for _, childFrame in ipairs({ previewDualRow:GetChildren() }) do
                    if
                        childFrame.GetNumPoints
                        and childFrame:GetNumPoints() > 0
                        and not PoolIsIdle(childFrame)
                    then
                        local _, rel = childFrame:GetPoint(1)
                        if rel == region then
                            childFrame:ClearAllPoints()
                            Pix.Point(childFrame, "RIGHT", region, "RIGHT", -20, 0)
                            return
                        end
                    end
                end
            end
            previewDualRow:HookScript("OnShow", RepositionFocusBar)
            C_Timer.After(0, RepositionFocusBar)
        end
        if isFocusColorDisabled() then
            focusPrev.SetColorOverride(function()
                return DBColor("enemyInCombat")
            end)
        end
        focusPrev.SetDisabled(isFocusColorDisabled())
        focusPrev.UpdateColor()
    end

    -- Hover Texture (+ Hover Effect opacity slider + color swatch): the mouseover highlight overlay and its opacity/color, at the bottom of this section.
    local hoverOverlayValues, hoverOverlayOrder = {}, {}
    do
        local STRIPE_ORDER = {
            "striped-v2",
            "striped-wide-v2",
            "stripes-medium",
            "stripes-small-close",
            "stripes-small-spread",
            "striped-tiny",
        }
        local STRIPE_NAMES = {
            ["striped-v2"] = "Stripes",
            ["striped-wide-v2"] = "Wide Stripes",
            ["stripes-medium"] = "Medium Stripes",
            ["stripes-small-close"] = "Small Dense Stripes",
            ["stripes-small-spread"] = "Small Spread Stripes",
            ["striped-tiny"] = "Tiny Stripes",
        }
        hoverOverlayValues.none = "None"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "none"
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, keyName in ipairs(STRIPE_ORDER) do
            hoverOverlayValues[keyName] = STRIPE_NAMES[keyName]
            hoverOverlayOrder[#hoverOverlayOrder + 1] = keyName
        end
        hoverOverlayOrder[#hoverOverlayOrder + 1] = "---"
        for _, keyName in ipairs(hbtOrder) do
            -- "none" is already prepended above; skip the copy from hbtOrder (which starts with "none") so it shows only once.
            if keyName ~= "none" then
                hoverOverlayOrder[#hoverOverlayOrder + 1] = keyName
                if keyName ~= "---" then
                    hoverOverlayValues[keyName] = hbtValues[keyName]
                end
            end
        end
        hoverOverlayValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                if not key or key == "none" or key == "---" then
                    return nil
                end
                if mod.OVERLAY_STRIPE_KEYS and mod.OVERLAY_STRIPE_KEYS[key] then
                    return "Interface\\AddOns\\CludesUINameplates\\Media\\" .. key .. ".png"
                end
                return mod.healthBarTextures and mod.healthBarTextures[key]
            end,
        }
    end
    do
        local hoverRow
        hoverRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Hover Texture",
            tooltip = "Uses the Hover Effect color and opacity. Set to None for the flat hover highlight.",
            values = hoverOverlayValues,
            order = hoverOverlayOrder,
            getValue = function()
                return DBVal("hoverOverlayTexture") or defaultSet.hoverOverlayTexture
            end,
            setValue = function(val)
                DB().hoverOverlayTexture = val
                mod.RefreshHoverEffect()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Hover Effect",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            -- Hover Effect: the Target Effect model copied onto mouseover
            -- (user-directed 2026-08-16, no preview integration). Highlight is
            -- the only default-on channel and rides the legacy
            -- hoverColor/hoverAlpha keys, so every profile keeps its exact
            -- pre-rework hover visuals until other channels are opted in.
            local rightRegion = hoverRow._rightRegion
            if rightRegion._control then
                rightRegion._control:Hide()
            end
            local refreshHoverBorderSwatch
            local refreshHoverGlowSwatch
            local refreshHoverCog
            local hoverItems = {
                { key = "cludesui", label = "CUI Glow" },
                { key = "borderColor", label = "Border Color" },
                { key = "highlight", label = "Highlight" },
                {
                    key = "borderSize",
                    label = "Border Size",
                    tooltip = "Change Size in the Cogwheel",
                },
            }
            local hvDD, hvDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                rightRegion,
                170,
                rightRegion:GetFrameLevel() + 2,
                hoverItems,
                function(keyName)
                    if keyName == "cludesui" then
                        return mod.GetHoverGlowCludesUI()
                    end
                    if keyName == "borderColor" then
                        return mod.GetHoverGlowBorderColor()
                    end
                    if keyName == "highlight" then
                        return mod.GetHoverGlowHighlight()
                    end
                    if keyName == "borderSize" then
                        return mod.GetHoverGlowBorderSize()
                    end
                    return false
                end,
                function(keyName, val)
                    if keyName == "cludesui" then
                        DB().hoverGlowCludesUI = val
                    elseif keyName == "borderColor" then
                        DB().hoverGlowBorderColor = val
                    elseif keyName == "highlight" then
                        DB().hoverGlowHighlight = val
                    elseif keyName == "borderSize" then
                        DB().hoverGlowBorderSize = val
                        -- First-enable snapshot: seed the cog slider with the user's
                        -- CURRENT border size, so enabling changes nothing until they
                        -- move it (one-time, never re-snapshots later).
                        if val and DB().hoverBorderSizeValue == nil then
                            if mod.IsCustomBorderEnabled() then
                                DB().hoverBorderSizeValue = DBVal("customBorderSize")
                                    or defaultSet.customBorderSize
                            else
                                DB().hoverBorderSizeValue = DBVal("borderSize") or defaultSet.borderSize
                            end
                        end
                    end
                    mod.RefreshHoverEffect()
                    if refreshHoverBorderSwatch then
                        refreshHoverBorderSwatch()
                    end
                    if refreshHoverGlowSwatch then
                        refreshHoverGlowSwatch()
                    end
                    if refreshHoverCog then
                        refreshHoverCog()
                    end
                end
            )
            Pix.Point(hvDD, "RIGHT", rightRegion, "RIGHT", -20, 0)
            rightRegion._control = hvDD
            rightRegion._lastInline = nil
            CludesUI.RegisterWidgetRefresh(hvDDRefresh)

            -- Inline cog "More Effects": Highlight color/opacity (the legacy
            -- hoverColor/hoverAlpha keys) + Glow Opacity + Border Size.
            do
                local function hoverCogOff()
                    return not (
                        mod.GetHoverGlowHighlight()
                        or mod.GetHoverGlowCludesUI()
                        or mod.GetHoverGlowBorderSize()
                    )
                end
                local hoverCogBtn = CludesUI.BuildInlineCog(rightRegion, {
                    disabled = hoverCogOff,
                    disabledTooltip = "a Hover Effect",
                    title = "More Effects",
                    rows = {
                        {
                            type = "colorpicker",
                            label = "Highlight Color",
                            hasAlpha = false,
                            get = function()
                                local c = (DB() and DB().hoverColor) or defaultSet.hoverColor
                                return c.r, c.g, c.b
                            end,
                            set = function(r, g, b)
                                DB().hoverColor = { r = r, g = g, b = b }
                                mod.RefreshHoverEffect()
                                UpdatePreview()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Highlight Opacity",
                            min = 0,
                            max = 100,
                            step = 1,
                            get = function()
                                return math.floor(
                                    ((DBVal("hoverAlpha") or defaultSet.hoverAlpha) * 100) + 0.5
                                )
                            end,
                            set = function(val)
                                DB().hoverAlpha = val / 100
                                mod.RefreshHoverEffect()
                                UpdatePreview()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Glow Opacity",
                            min = 0,
                            max = 100,
                            step = 1,
                            get = function()
                                return math.floor((mod.GetHoverGlowAlpha() * 100) + 0.5)
                            end,
                            set = function(val)
                                DB().hoverGlowAlpha = val / 100
                                mod.RefreshHoverEffect()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Border Size",
                            min = 0,
                            max = 4,
                            step = 1,
                            get = function()
                                local val = DBVal("hoverBorderSizeValue")
                                if val ~= nil then
                                    return val
                                end
                                if mod.IsCustomBorderEnabled() then
                                    return DBVal("customBorderSize") or defaultSet.customBorderSize
                                end
                                return DBVal("borderSize") or defaultSet.borderSize
                            end,
                            set = function(val)
                                DB().hoverBorderSizeValue = val
                                mod.RefreshHoverEffect()
                            end,
                            disabled = function()
                                return not mod.GetHoverGlowBorderSize()
                            end,
                            disabledTooltip = "Border Size Hover Effect",
                        },
                    },
                })
                refreshHoverCog = hoverCogBtn and hoverCogBtn._cuiCogState
            end

            -- Inline Border Color swatch: dimmed unless Border Color is checked.
            local hvBSwatch, hvUpdateBSwatch = CludesUI.BuildColorSwatch(
                rightRegion,
                rightRegion:GetFrameLevel() + 5,
                function()
                    local c = mod.GetHoverBorderColor()
                    return c.r, c.g, c.b
                end,
                function(r, g, b)
                    DB().hoverBorderColor = { r = r, g = g, b = b }
                    mod.RefreshHoverEffect()
                end,
                nil,
                20
            )
            Pix.Point(hvBSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
            rightRegion._lastInline = hvBSwatch
            CludesUI.HoverTip(hvBSwatch, "Border Color")
            refreshHoverBorderSwatch = function()
                local off = not mod.GetHoverGlowBorderColor()
                hvBSwatch:SetAlpha(off and 0.15 or 1)
                hvBSwatch:EnableMouse(not off)
                hvUpdateBSwatch()
            end
            CludesUI.RegisterWidgetRefresh(refreshHoverBorderSwatch)
            refreshHoverBorderSwatch()

            -- Inline Glow Color swatch: dimmed unless CUI Glow is checked.
            local hvGSwatch, hvUpdateGSwatch = CludesUI.BuildColorSwatch(
                rightRegion,
                rightRegion:GetFrameLevel() + 5,
                function()
                    local c = mod.GetHoverGlowColor()
                    return c.r, c.g, c.b
                end,
                function(r, g, b)
                    DB().hoverGlowColor = { r = r, g = g, b = b }
                    mod.RefreshHoverEffect()
                end,
                nil,
                20
            )
            Pix.Point(hvGSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
            rightRegion._lastInline = hvGSwatch
            CludesUI.HoverTip(hvGSwatch, "Glow Color")
            refreshHoverGlowSwatch = function()
                local off = not mod.GetHoverGlowCludesUI()
                hvGSwatch:SetAlpha(off and 0.15 or 1)
                hvGSwatch:EnableMouse(not off)
                hvUpdateGSwatch()
            end
            CludesUI.RegisterWidgetRefresh(refreshHoverGlowSwatch)
            refreshHoverGlowSwatch()

            -- Inline Hover Texture cog (Full alpha on empty part of bar), left of the dropdown; disabled while set to None.
            local leftRegion = hoverRow._leftRegion
            local isHoverTextureNone = function()
                return (DBVal("hoverOverlayTexture") or defaultSet.hoverOverlayTexture) == "none"
            end
            CludesUI.BuildInlineCog(leftRegion, {
                disabled = isHoverTextureNone,
                disabledTooltip = "a Hover Texture",
                title = "Hover Texture",
                rows = {
                    {
                        type = "toggle",
                        label = "Full alpha on empty part of bar",
                        get = function()
                            local val = DBVal("hoverOverlayFullBgAlpha")
                            if val == nil then
                                return defaultSet.hoverOverlayFullBgAlpha
                            end
                            return val
                        end,
                        set = function(val)
                            DB().hoverOverlayFullBgAlpha = val
                            mod.RefreshHoverEffect()
                            UpdatePreview()
                        end,
                    },
                },
            })
        end
    end

    -----------------------------------------------------------------------
    --  CLASS RESOURCE
    -----------------------------------------------------------------------
    local classResourceHeader
    classResourceHeader, height = W:SectionHeader(hostFrame, "CLASS RESOURCE", cursorY)
    cursorY = cursorY - height

    local function classPowerDisabled()
        return DBVal("showClassPower") ~= true
    end

    local classResourceSectionTop = cursorY -- track top of content rows

    local classResourceToggleRow
    classResourceToggleRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Class Resource",
        getValue = function()
            return DBVal("showClassPower") == true
        end,
        -- DependentSetValue: Rows 2-4 below are hidden while class resource is off; the flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return DBVal("showClassPower") == true
        end, function(val)
            DB().showClassPower = val
            mod.ApplyClassPowerSetting()
            UpdatePreview()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "multiSwatch",
        text = "Fill Color",
        disabled = classPowerDisabled,
        disabledTooltip = "Show Class Resource",
        swatches = {
            {
                tooltip = "Custom Color",
                disabled = classPowerDisabled,
                disabledTooltip = "Show Class Resource",
                getValue = function()
                    local c = (DB() and DB().classPowerCustomColor) or defaultSet.classPowerCustomColor
                    return c.r, c.g, c.b
                end,
                setValue = function(r, g, b)
                    DB().classPowerCustomColor = { r = r, g = g, b = b }
                    mod.RefreshClassPower()
                    UpdatePreview()
                end,
                onClick = function(self)
                    local val = DBVal("classPowerClassColors")
                    if val == nil then
                        val = defaultSet.classPowerClassColors
                    end
                    if val then
                        DB().classPowerClassColors = false
                        mod.RefreshClassPower()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    local val = DBVal("classPowerClassColors")
                    if val == nil then
                        val = defaultSet.classPowerClassColors
                    end
                    return val and 0.3 or 1
                end,
            },
            {
                tooltip = "Class Color",
                disabled = classPowerDisabled,
                disabledTooltip = "Show Class Resource",
                getValue = function()
                    local _, ct = UnitClass("player")
                    if ct and RAID_CLASS_COLORS[ct] then
                        local classColor = RAID_CLASS_COLORS[ct]
                        return classColor.r, classColor.g, classColor.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                setValue = function() end,
                onClick = function()
                    DB().classPowerClassColors = true
                    mod.RefreshClassPower()
                    UpdatePreview()
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local val = DBVal("classPowerClassColors")
                    if val == nil then
                        val = defaultSet.classPowerClassColors
                    end
                    return val and 1 or 0.3
                end,
            },
        },
    })
    cursorY = cursorY - height

    -- Rows 2-4 are HIDDEN entirely while Show Class Resource is off (the toggle's DependentSetValue forces the rebuild on flips).
    if not classPowerDisabled() then
        -- Row 2: Position (with inline cog for X/Y) | Size
        local classResourceRow2
        classResourceRow2, height = W:DualRow(hostFrame, cursorY, {
            type = "segmented",
            text = "Position",
            values = { top = "Top", bottom = "Bottom" },
            getValue = function()
                return DBVal("classPowerPos") or defaultSet.classPowerPos
            end,
            setValue = function(val)
                DB().classPowerPos = val
                mod.RefreshClassPower()
                UpdatePreview()
            end,
            order = { "top", "bottom" },
        }, {
            type = "slider",
            text = "Size",
            min = 0.5,
            max = 4.0,
            step = 0.1,
            getValue = function()
                return DBVal("classPowerScale") or defaultSet.classPowerScale
            end,
            setValue = function(val)
                DB().classPowerScale = val
                mod.RefreshClassPower()
                UpdatePreview()
            end,
        })
        cursorY = cursorY - height

        -- Inline cog on Position dropdown (X/Y offset settings)
        if not CludesUI._prebuilding then
            local leftRegion = classResourceRow2._leftRegion
            CludesUI.BuildInlineCog(leftRegion, {
                anchorTo = leftRegion._control,
                disabled = classPowerDisabled,
                disabledTooltip = "Show Class Resource",
                isOpen = CogPopupOpen,
                show = function(self)
                    ShowCogPopup(self, {
                        title = "Position Settings",
                        xGet = function()
                            return DBVal("classPowerXOffset") or defaultSet.classPowerXOffset
                        end,
                        xSet = function(val)
                            DB().classPowerXOffset = val
                            mod.RefreshClassPower()
                            UpdatePreview()
                        end,
                        yGet = function()
                            return DBVal("classPowerYOffset") or defaultSet.classPowerYOffset
                        end,
                        ySet = function(val)
                            DB().classPowerYOffset = val
                            mod.RefreshClassPower()
                            UpdatePreview()
                        end,
                    })
                end,
            })
        end

        -- Row 3: Bar Spacing + Background Color (with alpha)
        local classResourceRow3
        classResourceRow3, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            pixel = true,
            text = "Bar Spacing",
            min = -5,
            max = 10,
            step = 1,
            getValue = function()
                return DBVal("classPowerGap") or defaultSet.classPowerGap
            end,
            setValue = function(val)
                DB().classPowerGap = val
                mod.RefreshClassPower()
                UpdatePreview()
            end,
        }, {
            type = "colorpicker",
            text = "Background Color",
            hasAlpha = true,
            getValue = function()
                local c = (DB() and DB().classPowerBgColor) or defaultSet.classPowerBgColor
                return c.r, c.g, c.b, c.a
            end,
            setValue = function(r, g, b, a)
                DB().classPowerBgColor = { r = r, g = g, b = b, a = a }
                mod.RefreshClassPower()
                UpdatePreview()
            end,
        })
        cursorY = cursorY - height

        -- Row 4: Shape | Border (inline thickness cog + color swatch on Border)
        local classResourceRow4
        classResourceRow4, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Shape",
            values = {
                rectangle = "Rectangle",
                square = "Square",
                circle = "Circle",
                diamond = "Diamond",
                hexagon = "Hexagon",
                shield = "Shield",
                rune = "Rune",
                holypower = "Holy Power",
                shard = "Soul Shard",
                combo = "Combo Points",
                chi = "Chi",
                arcane = "Arcane Charges",
                essence = "Essence",
            },
            order = {
                "rectangle",
                "square",
                "circle",
                "diamond",
                "hexagon",
                "shield",
                "rune",
                "holypower",
                "shard",
                "combo",
                "chi",
                "arcane",
                "essence",
            },
            getValue = function()
                return DBVal("classPowerShape") or defaultSet.classPowerShape
            end,
            setValue = function(val)
                DB().classPowerShape = val
                mod.RefreshClassPower()
                UpdatePreview()
            end,
        }, {
            type = "toggle",
            text = "Border",
            getValue = function()
                return DBVal("classPowerBorder") == true
            end,
            setValue = function(val)
                DB().classPowerBorder = val
                mod.RefreshClassPower()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Inline thickness cog + border color swatch on the Border toggle
        if not CludesUI._prebuilding then
            local region = classResourceRow4._rightRegion
            local function borderOff()
                return classPowerDisabled() or DBVal("classPowerBorder") ~= true
            end
            local colorGet = function()
                local c = (DB() and DB().classPowerBorderColor) or defaultSet.classPowerBorderColor
                return c.r, c.g, c.b
            end
            local colorSet = function(r, g, b)
                DB().classPowerBorderColor = { r = r, g = g, b = b, a = 1 }
                mod.RefreshClassPower()
                UpdatePreview()
            end

            CludesUI.BuildInlineCog(region, {
                disabled = borderOff,
                disabledTooltip = "Border",
                title = "Border Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Thickness",
                        min = 1,
                        max = 4,
                        step = 1,
                        get = function()
                            return DBVal("classPowerBorderSize") or defaultSet.classPowerBorderSize
                        end,
                        set = function(val)
                            DB().classPowerBorderSize = val
                            mod.RefreshClassPower()
                            UpdatePreview()
                        end,
                    },
                },
            })

            local colorSwatch, updateSwatch =
                CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, colorGet, colorSet, nil, 20)
            Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            CludesUI.RegisterWidgetRefresh(function()
                local off = borderOff()
                colorSwatch:SetAlpha(off and 0.15 or 1)
                colorSwatch:EnableMouse(not off)
                updateSwatch()
            end)
            local off = borderOff()
            colorSwatch:SetAlpha(off and 0.15 or 1)
            colorSwatch:EnableMouse(not off)
        end
    end -- close Class Resource hidden-while-disabled gate

    -- Invisible frame spanning the entire CLASS RESOURCE section for glow targeting
    -- (none in the search pre-build, which wires no click navigation)
    local classResourceSection
    if not CludesUI._prebuilding then
        classResourceSection = CreateFrame("Frame", nil, hostFrame)
        local crPad = CludesUI.CONTENT_PAD or 20
        classResourceSection:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", crPad, classResourceSectionTop)
        classResourceSection:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -crPad, classResourceSectionTop)
        classResourceSection:SetHeight(math.abs(classResourceSectionTop - cursorY))
        classResourceSection._isSpacer = true -- hide from search layout
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -----------------------------------------------------------------------
    --  GENERAL TEXT
    -----------------------------------------------------------------------
    local generalTextHeader
    generalTextHeader, height = W:SectionHeader(hostFrame, "GENERAL TEXT", cursorY)
    cursorY = cursorY - height

    -- Duration controls are per aura type. "None" is the show/hide switch.
    local auraDurPosRow
    local auraTimerStackRow
    do
        local durationTypes = {
            debuff = {
                text = "Debuff Duration",
                title = "Debuff Duration Settings",
                key = "debuffTimerPosition",
            },
            buff = { text = "Buff Duration", title = "Buff Duration Settings", key = "buffTimerPosition" },
            cc = { text = "CC Duration", title = "CC Duration Settings", key = "ccTimerPosition" },
        }
        local function DurationDropdown(kind)
            local rowConf = durationTypes[kind]
            return {
                type = "dropdown",
                text = rowConf.text,
                values = timerPosValues,
                getValue = function()
                    return DBVal(rowConf.key) or atFallback
                end,
                setValue = function(val)
                    DB()[rowConf.key] = val
                    LiveApplyAuraText()
                    UpdatePreview()
                end,
                order = timerPosOrder,
            }
        end
        local function RefreshDuration()
            LiveApplyAuraText()
            UpdatePreview()
        end
        local function AttachDurationTools(regionFrame, kind)
            local rowConf = durationTypes[kind]
            local colorGet = function()
                local c = AuraDurationVal(kind, "Color")
                return c.r, c.g, c.b
            end
            local colorSet = function(r, g, b)
                DB()[kind .. "DurationTextColor"] = { r = r, g = g, b = b }
                RefreshDuration()
            end

            CludesUI.BuildInlineCog(regionFrame, {
                title = rowConf.title,
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function()
                            return AuraDurationVal(kind, "Size")
                        end,
                        set = function(val)
                            DB()[kind .. "DurationTextSize"] = val
                            RefreshDuration()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return AuraDurationVal(kind, "X")
                        end,
                        set = function(val)
                            DB()[kind .. "DurationTextX"] = val
                            RefreshDuration()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return AuraDurationVal(kind, "Y")
                        end,
                        set = function(val)
                            DB()[kind .. "DurationTextY"] = val
                            RefreshDuration()
                        end,
                    },
                },
            })
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                regionFrame,
                regionFrame:GetFrameLevel() + 5,
                colorGet,
                colorSet,
                nil,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", regionFrame._lastInline or regionFrame._control, "LEFT", -8, 0)
            regionFrame._lastInline = colorSwatch
            CludesUI.RegisterWidgetRefresh(function()
                updateSwatch()
            end)
        end

        local durationRow1
        durationRow1, height = W:DualRow(hostFrame, cursorY, DurationDropdown("debuff"), DurationDropdown("buff"))
        cursorY = cursorY - height
        auraDurPosRow = durationRow1
        if not CludesUI._prebuilding then
            AttachDurationTools(durationRow1._leftRegion, "debuff")
            AttachDurationTools(durationRow1._rightRegion, "buff")
        end

        local durationRow2
        durationRow2, height = W:DualRow(hostFrame, cursorY, DurationDropdown("cc"), {
            type = "dropdown",
            text = "Aura Stacks",
            values = timerPosValues,
            getValue = function()
                return DBVal("auraStackTextPosition") or asFallback
            end,
            setValue = function(val)
                DB().auraStackTextPosition = val
                LiveApplyAuraText()
                UpdatePreview()
            end,
            order = timerPosOrder,
        })
        cursorY = cursorY - height
        auraTimerStackRow = durationRow2
        if not CludesUI._prebuilding then
            AttachDurationTools(durationRow2._leftRegion, "cc")
        end

        if not CludesUI._prebuilding then
            -- RIGHT: Aura Stacks inline color swatch
            local rightRegion = durationRow2._rightRegion
            local asColorGet = function()
                local c = (DB() and DB().auraStackTextColor) or defaultSet.auraStackTextColor
                return c.r, c.g, c.b
            end
            local asColorSet = function(r, g, b)
                DB().auraStackTextColor = { r = r, g = g, b = b }
                LiveApplyAuraText()
                UpdatePreview()
            end

            -- RIGHT: Aura Stacks inline cog (Size / X / Y)
            CludesUI.BuildInlineCog(rightRegion, {
                title = "Aura Stacks Settings",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = function()
                            return DBVal("auraStackTextSize") or defaultSet.auraStackTextSize
                        end,
                        set = function(val)
                            DB().auraStackTextSize = val
                            LiveApplyAuraText()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return DBVal("auraStackTextX") or defaultSet.auraStackTextX
                        end,
                        set = function(val)
                            DB().auraStackTextX = val
                            LiveApplyAuraText()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return DBVal("auraStackTextY") or defaultSet.auraStackTextY
                        end,
                        set = function(val)
                            DB().auraStackTextY = val
                            LiveApplyAuraText()
                            UpdatePreview()
                        end,
                    },
                },
            })
            local asSwatch, asUpdateSwatch = CludesUI.BuildColorSwatch(
                rightRegion,
                rightRegion:GetFrameLevel() + 5,
                asColorGet,
                asColorSet,
                nil,
                20
            )
            Pix.Point(asSwatch, "RIGHT", rightRegion._lastInline or rightRegion._control, "LEFT", -8, 0)
            rightRegion._lastInline = asSwatch
            CludesUI.RegisterWidgetRefresh(function()
                asUpdateSwatch()
            end)
        end
    end

    -- Spell Name | Spell Target: position dropdowns (None/Left/Right/Center), styled like the duration dropdowns. Name and target can't share a side (setting one onto the other's side bumps it to None); Size/X/Y live in each row's inline cog.
    local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
    local castTextPosOrder = { "none", "left", "right", "center" }
    local spellNameRow
    spellNameRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Spell Name",
        values = castTextPosValues,
        order = castTextPosOrder,
        getValue = function()
            return (DB() and DB().castNameSide) or defaultSet.castNameSide
        end,
        setValue = function(val)
            DB().castNameSide = val
            if val ~= "none" then
                local ts = (DB() and DB().castTargetSide) or defaultSet.castTargetSide
                if ts == val then
                    DB().castTargetSide = "none"
                end
            end
            mod.RefreshAllSettings()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "dropdown",
        text = "Spell Target",
        values = castTextPosValues,
        order = castTextPosOrder,
        disabled = function()
            return DBVal("castCombineNameTarget") == true
        end,
        disabledTooltip = "This option requires Combine Spell Name and Target to be disabled.",
        getValue = function()
            return (DB() and DB().castTargetSide) or defaultSet.castTargetSide
        end,
        setValue = function(val)
            DB().castTargetSide = val
            if val ~= "none" then
                local nss = (DB() and DB().castNameSide) or defaultSet.castNameSide
                if nss == val then
                    DB().castNameSide = "none"
                end
            end
            mod.RefreshAllSettings()
            UpdatePreview()
            CludesUI:RefreshPage()
        end,
    })
    if not CludesUI._prebuilding then
        -- LEFT: Spell Name inline color swatch
        local leftRegion = spellNameRow._leftRegion
        local snColorGet = function()
            return DBColor("castNameColor")
        end
        local snColorSet = function(r, g, b)
            DB().castNameColor = { r = r, g = g, b = b }
            for _, backing in pairs(plates) do
                if backing.castName then
                    backing.castName:SetTextColor(r, g, b, 1)
                end
            end
            UpdatePreview()
        end

        -- LEFT: Spell Name inline cog for X/Y offset
        CludesUI.BuildInlineCog(leftRegion, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = CludesUI.L("Spell Name Settings"),
                    xGet = function()
                        return DBVal("castNameOffsetX") or defaultSet.castNameOffsetX
                    end,
                    xSet = function(val)
                        DB().castNameOffsetX = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    yGet = function()
                        return DBVal("castNameOffsetY") or defaultSet.castNameOffsetY
                    end,
                    ySet = function(val)
                        DB().castNameOffsetY = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeGet = function()
                        return DBVal("castNameSize") or defaultSet.castNameSize
                    end,
                    sizeSet = function(val)
                        DB().castNameSize = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeMin = 6,
                    sizeMax = 20,
                    sizeLabel = CludesUI.L("Size"),
                    sizeFirst = true,
                    -- Combined text has its own width; the name's applies while separate.
                    widthGet = function()
                        if DBVal("castCombineNameTarget") == true then
                            return DBVal("castCombinedWidthPct") or defaultSet.castCombinedWidthPct
                        end
                        return DBVal("castNameWidthPct") or defaultSet.castNameWidthPct
                    end,
                    widthSet = function(val)
                        if DBVal("castCombineNameTarget") == true then
                            DB().castCombinedWidthPct = val
                        else
                            DB().castNameWidthPct = val
                        end
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    wrapGet = function()
                        return DBVal("castNameWrap") == true
                    end,
                    wrapSet = function(val)
                        DB().castNameWrap = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    toggleLabel = "Combine Spell Name and Target",
                    toggleGet = function()
                        return DBVal("castCombineNameTarget") == true
                    end,
                    toggleSet = function(val)
                        DB().castCombineNameTarget = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                        CludesUI:RefreshPage()
                    end,
                })
            end,
        })
        local snSwatch, snUpdateSwatch =
            CludesUI.BuildColorSwatch(leftRegion, leftRegion:GetFrameLevel() + 5, snColorGet, snColorSet, nil, 20)
        Pix.Point(snSwatch, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
        leftRegion._lastInline = snSwatch
        CludesUI.RegisterWidgetRefresh(function()
            snUpdateSwatch()
        end)

        -- RIGHT: Spell Target inline double swatch (custom + class colored)
        local rightRegion = spellNameRow._rightRegion
        local control = rightRegion._control

        -- RIGHT: Spell Target inline cog for X/Y offset
        CludesUI.BuildInlineCog(rightRegion, {
            isOpen = CogPopupOpen,
            show = function(self)
                ShowCogPopup(self, {
                    title = CludesUI.L("Spell Target Settings"),
                    xGet = function()
                        return DBVal("castTargetOffsetX") or defaultSet.castTargetOffsetX
                    end,
                    xSet = function(val)
                        DB().castTargetOffsetX = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    yGet = function()
                        return DBVal("castTargetOffsetY") or defaultSet.castTargetOffsetY
                    end,
                    ySet = function(val)
                        DB().castTargetOffsetY = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeGet = function()
                        return DBVal("castTargetSize") or defaultSet.castTargetSize
                    end,
                    sizeSet = function(val)
                        DB().castTargetSize = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    sizeMin = 6,
                    sizeMax = 20,
                    sizeLabel = CludesUI.L("Size"),
                    sizeFirst = true,
                    widthGet = function()
                        return DBVal("castTargetWidthPct") or defaultSet.castTargetWidthPct
                    end,
                    widthSet = function(val)
                        DB().castTargetWidthPct = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                    wrapGet = function()
                        return DBVal("castTargetWrap") == true
                    end,
                    wrapSet = function(val)
                        DB().castTargetWrap = val
                        mod.RefreshAllSettings()
                        UpdatePreview()
                    end,
                })
            end,
        })

        -- Class colored swatch (beside the cog)
        local ccGet = function()
            local _, ct = UnitClass("player")
            if ct and RAID_CLASS_COLORS[ct] then
                local classColor = RAID_CLASS_COLORS[ct]
                return classColor.r, classColor.g, classColor.b
            end
            return 1, 1, 1
        end
        local ccSwatch, ccUpdate = CludesUI.BuildColorSwatch(
            rightRegion,
            rightRegion:GetFrameLevel() + 5,
            ccGet,
            function() end,
            nil,
            20
        )
        Pix.Point(ccSwatch, "RIGHT", rightRegion._lastInline or control, "LEFT", -8, 0)
        ccSwatch:SetScript("OnClick", function()
            DB().castTargetClassColor = true
            for _, backing in pairs(plates) do
                backing:UpdateHealth()
            end
            UpdatePreview()
            CludesUI:RefreshPage()
        end)
        CludesUI.HoverTip(ccSwatch, "Class Color")

        -- Custom color swatch (to the left of class swatch)
        local stColorGet = function()
            return DBColor("castTargetColor")
        end
        local stColorSet = function(r, g, b)
            DB().castTargetColor = { r = r, g = g, b = b }
            for _, backing in pairs(plates) do
                backing:UpdateHealth()
            end
            UpdatePreview()
        end
        local stSwatch, stUpdate =
            CludesUI.BuildColorSwatch(rightRegion, rightRegion:GetFrameLevel() + 5, stColorGet, stColorSet, nil, 20)
        Pix.Point(stSwatch, "RIGHT", ccSwatch, "LEFT", -9, 0)
        rightRegion._lastInline = stSwatch
        stSwatch._eabOrigClick = stSwatch:GetScript("OnClick")
        stSwatch:SetScript("OnClick", function(self)
            local saved = DB()
            local classColor = saved and saved.castTargetClassColor
            if classColor == nil then
                classColor = defaultSet.castTargetClassColor
            end
            if classColor then
                DB().castTargetClassColor = false
                for _, backing in pairs(plates) do
                    backing:UpdateHealth()
                end
                UpdatePreview()
                CludesUI:RefreshPage()
                return
            end
            if self._eabOrigClick then
                self._eabOrigClick(self)
            end
        end)
        CludesUI.HoverTip(stSwatch, "Custom Color")

        CludesUI.RegisterWidgetRefresh(function()
            local saved = DB()
            local isCC = saved and saved.castTargetClassColor
            if isCC == nil then
                isCC = defaultSet.castTargetClassColor
            end
            stSwatch:SetAlpha(isCC and 0.3 or 1)
            ccSwatch:SetAlpha(isCC and 1 or 0.3)
            stUpdate()
            ccUpdate()
        end)
        local isCC = (DB() and DB().castTargetClassColor)
        if isCC == nil then
            isCC = defaultSet.castTargetClassColor
        end
        stSwatch:SetAlpha(isCC and 0.3 or 1)
        ccSwatch:SetAlpha(isCC and 1 or 0.3)
    end
    cursorY = cursorY - height

    return cursorY,
        healthBarHeader,
        healthBarHeightRow,
        castBarHeightRow,
        showCastIconRow,
        castTimerRow,
        tfxHeader,
        targetGlowRow,
        classResourceHeader,
        classResourceSection,
        generalTextHeader,
        auraDurPosRow,
        auraTimerStackRow,
        spellNameRow
end

-- Used by CUI_Nameplates_Options.lua
mod.NPO_BuildDisplayBars = BuildDisplayBars
