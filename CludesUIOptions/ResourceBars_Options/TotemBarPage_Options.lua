if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\TotemBarPage_Options.lua
--  Resource Bars options: Totem Bar page ("Totem Bars" on WoW Forever, where a
--  shaman's Call Totem Bar section follows the active totem bar's). Both sections
--  come from one builder over their own settings table. Definitions only; the
--  shared helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIResourceBars"]
if not mod then
    return
end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- WoW Forever shamans get the Call Totem Bar section (and its preview group);
-- the runtime file loads for no other class.
function mod.ERB_HasCallTotemSection()
    return (CludesUI.IS_FOREVER and select(2, UnitClass("player")) == "SHAMAN") and true or false
end

-- One totem bar section. S: title, key (the profile table), unlockKey, off()
-- (the section's controls grey while it returns true) with its disabled
-- tooltip (req, raw), and enableRow(y, sizeCfg, RefreshTotem) -> row, h: the
-- first row, whose left slot turns the bar on and whose right slot is sizeCfg
-- (Icon Size). mapIcon / mapTimer: the preview's click mapping keys.
local function BuildTotemSection(hostFrame, cursorY, S)
    local environ = mod._CURB_OptEnv
    local DB = environ.DB
    local _clickMappings = environ._clickMappings
    local W = CludesUI.Widgets
    local _, height

    local function T()
        local p = DB()
        return p and p[S.key]
    end

    local function RefreshTotem()
        if _G._CURB_Apply then
            _G._CURB_Apply()
        end
        if CludesUI.NotifyElementResized then
            CludesUI.NotifyElementResized(S.unlockKey)
        end
        environ.UpdateTotemPreview()
    end

    local totemOff = S.off
    local timerOff = function()
        local t = T()
        return totemOff() or (t and not t.showTimer)
    end
    local req, raw = S.req, S.raw

    local section
    section, height = W:SectionHeader(hostFrame, S.title, cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(
        section,
        { key = S.unlockKey, disabled = totemOff, disabledTooltip = req, rawTooltip = raw }
    )

    -- Row 1: the section's on switch | Icon Size (+ spacing cog)
    local row1
    row1, height = S.enableRow(cursorY, {
        type = "slider",
        text = "Icon Size",
        min = 16,
        max = 60,
        step = 1,
        disabled = totemOff,
        disabledTooltip = req,
        rawTooltip = raw,
        getValue = function()
            local t = T()
            return t and (t.iconSize or 30)
        end,
        setValue = function(val)
            local t = T()
            if not t then
                return
            end
            t.iconSize = val
            RefreshTotem()
        end,
    }, RefreshTotem)
    cursorY = cursorY - height

    -- Spacing cog on Icon Size (right region)
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(row1._rightRegion, {
            title = "Icon Settings",
            rows = {
                {
                    type = "slider",
                    pixel = true,
                    label = "Spacing",
                    min = 0,
                    max = 20,
                    step = 1,
                    get = function()
                        local t = T()
                        return t and (t.spacing or 2)
                    end,
                    set = function(val)
                        local t = T()
                        if not t then
                            return
                        end
                        t.spacing = val
                        RefreshTotem()
                    end,
                },
            },
        })
    end

    -- Row 2: Timer Size | Show Timer
    local timerRow
    timerRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Timer Size",
        min = 6,
        max = 24,
        step = 1,
        disabled = timerOff,
        disabledTooltip = "Show Timer",
        getValue = function()
            local t = T()
            return t and (t.timerSize or 11)
        end,
        setValue = function(val)
            local t = T()
            if not t then
                return
            end
            t.timerSize = val
            RefreshTotem()
        end,
    }, {
        type = "toggle",
        text = "Show Timer",
        disabled = totemOff,
        disabledTooltip = req,
        rawTooltip = raw,
        getValue = function()
            local t = T()
            return t and t.showTimer ~= false
        end,
        setValue = function(val)
            local t = T()
            if not t then
                return
            end
            t.showTimer = val
            RefreshTotem()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    -- Row 3: Border Style | Border Size (+ inline swatch + offset cog)
    do
        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "dropdown",
                text = "Border Style",
                disabled = totemOff,
                disabledTooltip = req,
                rawTooltip = raw,
                values = texValues,
                order = texOrder,
                getValue = function()
                    local t = T()
                    return t and (t.borderTexture or "solid")
                end,
                setValue = function(val)
                    local t = T()
                    if not t then
                        return
                    end
                    t.borderTexture = val
                    t.borderTextureOffset = nil
                    t.borderTextureOffsetY = nil
                    t.borderTextureShiftX = nil
                    t.borderTextureShiftY = nil
                    local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(val)
                    t.borderR = _bcol.r
                    t.borderG = _bcol.g
                    t.borderB = _bcol.b
                    t.borderA = 1
                    t.borderBehind = _bbehind
                    local defSz = CludesUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then
                        t.borderSize = defSz
                    end
                    if t.borderSizePx then
                        t.borderSizePx = false
                    end
                    RefreshTotem()
                    CludesUI:RefreshPage(true)
                end,
            },
            CludesUI.BorderPxSliderCfg({
                text = "Border Size",
                disabled = totemOff,
                disabledTooltip = req,
                rawTooltip = raw,
                getStep = function()
                    local t = T()
                    return t and (t.borderSize or 0) or 0
                end,
                setStep = function(val)
                    local t = T()
                    if t then
                        t.borderSize = val
                    end
                end,
                getTex = function()
                    local t = T()
                    return t and (t.borderTexture or "solid") or "solid"
                end,
                getPx = function()
                    local t = T()
                    return t and t.borderSizePx
                end,
                setPx = function(val)
                    local t = T()
                    if t then
                        t.borderSizePx = val
                    end
                end,
                apply = function()
                    RefreshTotem()
                    CludesUI:RefreshPage()
                end,
            })
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local t = T()
            local texture = t and t.borderTexture or "solid"
            if texture ~= "solid" and texture ~= "" then
                local function step()
                    local t2 = T()
                    return t2 and (t2.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = totemOff,
                    disabledTooltip = req,
                    rawTooltip = raw,
                    getTex = function()
                        local t2 = T()
                        return t2 and (t2.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local t2 = T()
                        return t2 and t2.borderSizePx
                    end,
                    getX = function()
                        local t2 = T()
                        return t2 and t2.borderTextureOffset
                    end,
                    setX = function(val)
                        local t2 = T()
                        if t2 then
                            t2.borderTextureOffset = val
                        end
                    end,
                    getY = function()
                        local t2 = T()
                        return t2 and t2.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local t2 = T()
                        if t2 then
                            t2.borderTextureOffsetY = val
                        end
                    end,
                    apply = function()
                        RefreshTotem()
                        CludesUI:RefreshPage()
                    end,
                })
                _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                cursorY = cursorY - height
            end
        end

        -- Inline border color swatch on Border Size slider; none in the search
        -- pre-build (it indexes nothing, and the row is a stand-in there)
        if not CludesUI._prebuilding then
            local region = bsRow._rightRegion
            local control = region._control
            local Pix = CludesUI.PP
            local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                region,
                bsRow:GetFrameLevel() + 3,
                function()
                    local t = T()
                    return (t and t.borderR or 0),
                        (t and t.borderG or 0),
                        (t and t.borderB or 0),
                        (t and t.borderA or 1)
                end,
                function(r, g, b, a)
                    local t = T()
                    if not t then
                        return
                    end
                    t.borderR = r
                    t.borderG = g
                    t.borderB = b
                    t.borderA = a
                    RefreshTotem()
                    CludesUI:RefreshPage()
                end,
                true,
                20
            )
            Pix.Point(borderSwatch, "RIGHT", control, "LEFT", -8, 0)
            -- Disable swatch when border size is 0
            local borderSwatchBlock = CludesUI.NewSwatchBlocker(borderSwatch)
            borderSwatchBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    borderSwatch,
                    CludesUI.DisabledTooltip("This option requires a Border Size above 0.")
                )
            end)
            borderSwatchBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateBorderSwatchState()
                local t = T()
                local noBorder = not t or (t.borderSize or 0) == 0
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

        -- Border Options cog on Border Style (left region): hidden for "solid",
        -- disabled with the section's controls while the bar is off
        if not CludesUI._prebuilding then
            local region = bsRow._leftRegion
            local cogBtn = CludesUI.BuildInlineCog(region, {
                disabled = totemOff,
                disabledTooltip = req,
                rawTooltip = raw,
                title = "Border Options",
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local t = T()
                            if not t then
                                return 0
                            end
                            local val = t.borderTextureShiftX
                            if val then
                                return val
                            end
                            local _, _, dsx = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                t.borderTexture or "solid",
                                t.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local t = T()
                            if not t then
                                return
                            end
                            t.borderTextureShiftX = val == 0 and nil or val
                            RefreshTotem()
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
                            local t = T()
                            if not t then
                                return 0
                            end
                            local val = t.borderTextureShiftY
                            if val then
                                return val
                            end
                            local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                "resourcebars",
                                t.borderTexture or "solid",
                                t.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local t = T()
                            if not t then
                                return
                            end
                            t.borderTextureShiftY = val == 0 and nil or val
                            RefreshTotem()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local t = T()
                            return t and t.borderBehind or false
                        end,
                        set = function(val)
                            local t = T()
                            if not t then
                                return
                            end
                            t.borderBehind = val == false and nil or val
                            RefreshTotem()
                            CludesUI:RefreshPage()
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                local t = T()
                local texture = t and t.borderTexture or "solid"
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

    -- Row 4: Frame Strata | Orientation
    local tmStrataValues = CludesUI.FRAME_STRATA_LABELS
    local tmStrataOrder = CludesUI.FRAME_STRATA_ORDER_BASE
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = totemOff,
        disabledTooltip = req,
        rawTooltip = raw,
        values = tmStrataValues,
        order = tmStrataOrder,
        getValue = function()
            local t = T()
            return t and t.frameStrata or "MEDIUM"
        end,
        setValue = function(val)
            local t = T()
            if not t then
                return
            end
            t.frameStrata = val
            RefreshTotem()
        end,
    }, {
        type = "segmented",
        text = "Orientation",
        disabled = totemOff,
        disabledTooltip = req,
        rawTooltip = raw,
        values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
        order = { "HORIZONTAL", "VERTICAL" },
        getValue = function()
            local t = T()
            return t and (t.orientation or "HORIZONTAL")
        end,
        setValue = function(val)
            local t = T()
            if not t then
                return
            end
            t.orientation = val
            RefreshTotem()
        end,
    })
    cursorY = cursorY - height

    -- Click mappings for the preview's hit overlays (never from a hidden pre-build)
    if not CludesUI._prebuilding then
        _clickMappings[S.mapIcon] = { section = section, target = row1, slotSide = "right" }
        _clickMappings[S.mapTimer] = { section = section, target = timerRow, slotSide = "left" }
    end

    return cursorY
end

-- Totem Bar options page
function mod.ERB_BuildTotemBarPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix = environ.DB, environ.PP
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, height
    local forever = CludesUI.IS_FOREVER

    hostFrame._showRowDivider = true

    CludesUI:SetContentHeader(environ._totemPreviewBuilder)

    -- Clear this page's own click mappings (shared table; never from a hidden pre-build)
    if not CludesUI._prebuilding then
        local m = environ._clickMappings
        m.totemIcon, m.totemTimer, m.callTotemIcon, m.callTotemTimer = nil, nil, nil, nil
    end

    -- Blizzard's active totems (every class list). On WoW Forever it is the first
    -- of two totem bar sections.
    cursorY = BuildTotemSection(hostFrame, cursorY, {
        title = forever and "ACTIVE TOTEM BAR" or "LAYOUT",
        key = "totemBar",
        unlockKey = "ERB_TotemBar",
        mapIcon = "totemIcon",
        mapTimer = "totemTimer",
        off = function()
            local p = DB()
            return p and not p.totemBar.enabledClasses
        end,
        req = "Select a class above",
        raw = true,
        -- Enabled Classes dropdown (built over a blank label slot)
        enableRow = function(ry, sizeCfg, RefreshTotem)
            local ALL_CLASSES = CludesUI.CLASS_TOKEN_ORDER
            local classItems = {}
            classItems[#classItems + 1] = { key = "NONE", label = CludesUI.L("None (Disabled)") }
            -- WoW Forever lists only the classes that client has.
            local foreverOnly = forever and CludesUI.FOREVER_CLASS_SPEC
            for _, castFrame in ipairs(ALL_CLASSES) do
                if not foreverOnly or foreverOnly[castFrame] then
                    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[castFrame]
                    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[castFrame])
                        or (castFrame:sub(1, 1):upper() .. castFrame:sub(2):lower())
                    local hex = color and color.colorStr or "ffffffff"
                    classItems[#classItems + 1] = { key = castFrame, label = "|c" .. hex .. name .. "|r" }
                end
            end

            local row1, rh = W:DualRow(hostFrame, ry, { type = "label", text = "Enabled Classes" }, sizeCfg)

            -- Class dropdown on left region
            if not CludesUI._prebuilding then
                local leftRegion = row1._leftRegion
                local checkDrop, cbDDRefresh
                checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    leftRegion,
                    210,
                    leftRegion:GetFrameLevel() + 2,
                    classItems,
                    function(key)
                        local p = DB()
                        if not p then
                            return false
                        end
                        if key == "NONE" then
                            return not p.totemBar.enabledClasses
                        end
                        return p.totemBar.enabledClasses and p.totemBar.enabledClasses[key] or false
                    end,
                    function(key, val)
                        local p = DB()
                        if not p then
                            return
                        end
                        if key == "NONE" then
                            p.totemBar.enabledClasses = nil
                        else
                            if not p.totemBar.enabledClasses then
                                p.totemBar.enabledClasses = {}
                            end
                            p.totemBar.enabledClasses[key] = val or nil
                            if not next(p.totemBar.enabledClasses) then
                                p.totemBar.enabledClasses = nil
                            end
                        end
                        local ddMenu = checkDrop._ddMenu
                        if ddMenu then
                            for _, scrollFrame in ipairs({ ddMenu:GetChildren() }) do
                                local sc = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                                if sc then
                                    for _, row in ipairs({ sc:GetChildren() }) do
                                        if row._updateCheck then
                                            row._updateCheck()
                                        end
                                    end
                                end
                            end
                        end
                        RefreshTotem()
                        CludesUI:RefreshPage()
                    end,
                    nil,
                    8,
                    false
                )
                CludesUI.PanelPP.Point(checkDrop, "RIGHT", leftRegion, "RIGHT", -20, 0)
                leftRegion._control = checkDrop
                leftRegion._lastInline = nil
                CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            end
            return row1, rh
        end,
    })

    -- WoW Forever: Blizzard's call totem bar (Call of the Elements, the four
    -- element slots, Totemic Recall), reskinned and owned by Unlock Mode.
    -- Shamans only (the runtime file loads for no other class).
    if mod.ERB_HasCallTotemSection() then
        _, height = W:Spacer(hostFrame, cursorY, 16)
        cursorY = cursorY - height
        cursorY = BuildTotemSection(hostFrame, cursorY, {
            title = "CALL TOTEM BAR",
            key = "callTotemBar",
            unlockKey = "ERB_CallTotemBar",
            mapIcon = "callTotemIcon",
            mapTimer = "callTotemTimer",
            off = function()
                local p = DB()
                local c = p and p.callTotemBar
                return not (c and c.enabled)
            end,
            req = "Call Totem Bar",
            enableRow = function(ry, sizeCfg, RefreshTotem)
                return W:DualRow(hostFrame, ry, {
                    type = "toggle",
                    text = "Enable Call Totem Bar",
                    tooltip = "Reskins Blizzard's call totem bar in this look and moves it with Layout Mode instead of Edit Mode.",
                    getValue = function()
                        local p = DB()
                        local c = p and p.callTotemBar
                        return c and c.enabled == true or false
                    end,
                    setValue = function(val)
                        local p = DB()
                        local c = p and p.callTotemBar
                        if not c then
                            return
                        end
                        c.enabled = val
                        RefreshTotem()
                        CludesUI:RefreshPage()
                    end,
                }, sizeCfg)
            end,
        })
    end

    return math.abs(cursorY)
end
