if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ResourceBars_Options\ClassResourceSection_Options.lua
--  Resource Bars options: CLASS RESOURCE BAR section builder. Definitions only; the shared
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

-- Blizzard Class Resource Art stands in for the class resource bar: the CLASS
-- RESOURCE BAR controls that only style our own bar (texture, colours, pips,
-- text, borders) grey out and are blocked with a disabled tooltip while it
-- does; the ones that still drive the art or its slot stay live (see the
-- keep-list in ns.ERB_BuildClassResourceSection). One block per half-row region
-- (the Unit Frames Dark Mode block pattern), so blocks ride their rows through
-- the inline search. Built on the first active state only and tracked live by
-- one widget refresh per call (the toggle refreshes without a rebuild).
mod.ERB_BlizzArtBlockRegions = function(regions)
    if CludesUI._prebuilding or not regions or #regions == 0 then
        return
    end
    local blocks
    local function Update()
        local on = (mod.ERB_BlizzArtActiveNow and mod.ERB_BlizzArtActiveNow()) and true or false
        if on and not blocks then
            blocks = {}
            for idx = 1, #regions do
                local region = regions[idx]
                local widget = CreateFrame("Frame", nil, region)
                widget:SetAllPoints()
                widget:SetFrameLevel(region:GetFrameLevel() + 50)
                widget:EnableMouse(true)
                widget:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        widget,
                        CludesUI.DisabledTooltip("Blizzard Class Resource Art", "disabled")
                    )
                end)
                widget:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                blocks[#blocks + 1] = widget
            end
        end
        if not blocks then
            return
        end
        for idx = 1, #blocks do
            local widget = blocks[idx]
            widget:GetParent():SetAlpha(on and 0.3 or 1)
            widget:SetShown(on)
        end
    end
    Update()
    CludesUI.RegisterWidgetRefresh(Update)
end

-- Shared, context-aware CLASS RESOURCE (secondary) section builder. ctx.cfg() ->
-- secondary table. The Guardian/Prot special-bar rows show in both modes for the
-- relevant spec (global storage). The Hide-Power cog is Simple-only. The Threshold &
-- Hash Lines row hosts the shared editor (env.BuildThresholdSettingsButton).
function mod.ERB_BuildClassResourceSection(hostFrame, cursorY, context)
    local environ = mod._CURB_OptEnv
    local DB, Pix, SmoothRefresh, RefreshClass =
        environ.DB, environ.PP, environ.SmoothRefresh, environ.RefreshClass
    local RebuildClass, RebuildPower, AddFormBarBtn, AddFormTextBtn =
        environ.RebuildClass, environ.RebuildPower, environ.AddFormBarBtn, environ.AddFormTextBtn
    local BuildThresholdSettingsButton, BAND_REPLACES_TIP, STAGGER_PCT_TIP =
        environ.BuildThresholdSettingsButton, environ.BAND_REPLACES_TIP, environ.STAGGER_PCT_TIP
    -- Every half-row this section builds is recorded (a thin wrapper over the
    -- widget factory) so Blizzard Class Resource Art can block the controls
    -- that only style our own bar while it stands in (ns.ERB_BlizzArtBlockRegions).
    -- Kept live: showing the resource at all (with its per-form and power-bar
    -- controls), the slot size, the opacity and fade the art follows, and the
    -- special bars that pick which resource is drawn.
    local artKeep = {
        ["Show Class Resource"] = true,
        ["Height"] = true,
        ["Width"] = true,
        ["Opacity"] = true,
        ["Guardian Druid Ironfur Bar"] = true,
        ["Show Hash Lines"] = true,
        ["Prot Warrior Ignore Pain Bar"] = true,
        ["Show Hash Line"] = true,
        ["Arms Warrior Sweeping Strikes Bar"] = true,
    }
    local artRegions = {}
    local W = setmetatable({
        DualRow = function(_, p, yy, l, r, ...)
            local row, rh = CludesUI.Widgets:DualRow(p, yy, l, r, ...)
            if row then
                if l and l.text and l.text ~= "" and not artKeep[l.text] and row._leftRegion then
                    artRegions[#artRegions + 1] = row._leftRegion
                end
                if r and r.text and r.text ~= "" and not artKeep[r.text] and row._rightRegion then
                    artRegions[#artRegions + 1] = row._rightRegion
                end
            end
            return row, rh
        end,
    }, { __index = CludesUI.Widgets })

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
    local function classBarOff()
        local rowCfg = rowConf()
        return not (rowCfg and rowCfg.enabled)
    end

    local heading
    heading, height = W:SectionHeader(hostFrame, "CLASS RESOURCE BAR", cursorY)
    cursorY = cursorY - height
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "ERB_ClassResource", disabled = classBarOff, disabledTooltip = "Class Resource" }
    )

    local _advTop = cursorY -- content top; also used by the Simple override overlay
    -- Guardian Ironfur + Prot Ignore Pain special bars stay global at runtime (stored on
    -- DB().secondary, not per-spec); the row shows for the active spec.
    -- Retail only: WoW Forever has none of these specs.
    if not CludesUI.IS_FOREVER then
        local function _IsGuardianDruid()
            local _, castFrame = UnitClass("player")
            if castFrame ~= "DRUID" then
                return false
            end
            local s = C_SpecializationInfo.GetSpecialization()
            local spellRef = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return spellRef == 104
        end
        if _IsGuardianDruid() then
            local _ifOff = function()
                local profile = DB()
                return profile and not profile.secondary.guardianIronfurBar
            end
            local _, hh = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Guardian Druid Ironfur Bar",
                tooltip = "Replaces the class resource bar with an Ironfur tracker. Each Ironfur cast adds a hash line that slides from right to left as its buff decays. Duration is talent-aware (Ursoc's Endurance and Guardian of Elune).",
                getValue = function()
                    local profile = DB()
                    return profile and profile.secondary.guardianIronfurBar
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.guardianIronfurBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Show Hash Lines",
                disabled = _ifOff,
                disabledTooltip = "Guardian Druid Ironfur Bar",
                getValue = function()
                    local profile = DB()
                    return profile and profile.secondary.guardianShowHashLines ~= false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.guardianShowHashLines = val
                    SmoothRefresh()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - hh
        end
        local function _IsProtWarrior()
            local _, castFrame = UnitClass("player")
            if castFrame ~= "WARRIOR" then
                return false
            end
            local s = C_SpecializationInfo.GetSpecialization()
            local spellRef = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return spellRef == 73
        end
        if _IsProtWarrior() then
            -- Translated in halves so the CDM sentence keeps its existing locale
            -- entries; ShowWidgetTooltip L()s the joined string, a harmless miss.
            -- The first half stays a variable: its escaped quotes would come back
            -- truncated from the static key extractor.
            local ipBarTipCDM =
                'Creates a class resource bar for Ignore Pain tracking. To see stack text, you must have Ignore Pain tracked in your Blizzard CDM "Tracked Buffs" or "Tracked Bars" section.'
            local ipBarTip = CludesUI.L(ipBarTipCDM)
                .. " "
                .. CludesUI.L(
                    "Tracking it also makes the fill show Ignore Pain alone; without it the fill shows your total absorb, so other shields can add to it."
                )
            local ipHashTip =
                "Draws a hash line that resets to the right edge when you cast Ignore Pain and slides left as the buff runs out."
            local ipRow
            ipRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Prot Warrior Ignore Pain Bar",
                tooltip = ipBarTip,
                getValue = function()
                    local profile = DB()
                    return profile and profile.secondary.protIgnorePainBar
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.protIgnorePainBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Show Hash Line",
                tooltip = ipHashTip,
                disabled = function()
                    local profile = DB()
                    return not (profile and profile.secondary.protIgnorePainBar)
                end,
                disabledTooltip = "Prot Warrior Ignore Pain Bar",
                getValue = function()
                    local profile = DB()
                    return profile and profile.secondary.protIgnorePainHashLine ~= false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.protIgnorePainHashLine = val
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height
            local function IPControlTip(region, tipText)
                local c = region and region._control
                if not c or not c.HookScript then
                    return
                end
                c:HookScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, tipText)
                end)
                c:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end
            IPControlTip(ipRow._leftRegion, ipBarTip)
            IPControlTip(ipRow._rightRegion, ipHashTip)
        end
        local function _IsArmsWarrior()
            local _, castFrame = UnitClass("player")
            if castFrame ~= "WARRIOR" then
                return false
            end
            local s = C_SpecializationInfo.GetSpecialization()
            local spellRef = s and C_SpecializationInfo.GetSpecializationInfo(s)
            return spellRef == 71
        end
        if _IsArmsWarrior() then
            local ssBarTip =
                "Shows Sweeping Strikes charges on the resource bar; Unit Frames and the personal Nameplate show them regardless."
            local ssRow
            ssRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Arms Warrior Sweeping Strikes Bar",
                tooltip = ssBarTip,
                getValue = function()
                    local profile = DB()
                    return profile and profile.secondary.armsSweepingStrikesBar
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.armsSweepingStrikesBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height
        end
    end

    -- Row 1: Show Class Resource | Orientation
    local classEnableRow
    classEnableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Class Resource",
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
            RebuildClass()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "dropdown",
        text = "Orientation",
        disabled = classBarOff,
        disabledTooltip = "Class Resource",
        values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
        order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
        getValue = function()
            local rowCfg = rowConf()
            if not rowCfg then
                return "HORIZONTAL"
            end
            local val = rowCfg.pipOrientation or "HORIZONTAL"
            if val == "VERTICAL" then
                val = "VERTICAL_DOWN"
            end
            return val
        end,
        setValue = ConfSetter("pipOrientation", SmoothRefresh, true),
    })
    cursorY = cursorY - height
    -- Class Resource cog: Simple only (Hide Power Bar if Resource is a row of
    -- the Bar Display page's BAR SHIFTING section)
    if not context.advanced then
        if not CludesUI._prebuilding then
            local region = classEnableRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                disabled = classBarOff,
                disabledTooltip = "Class Resource",
                title = "Class Resource",
                rows = {
                    -- Draw Above Other Bars: the class resource slot above the health,
                    -- power and GCD borders (ns.ERB_ClassRaise).
                    {
                        type = "toggle",
                        label = "Draw Above Other Bars",
                        tooltip = "Draws the class resource bar above the health, power and GCD bar borders.",
                        get = ConfGetter("raiseLevel", false),
                        set = function(val)
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return
                            end
                            rowCfg.raiseLevel = val and true or false
                            RebuildClass()
                        end,
                    },
                },
            })
        end
        -- Per-spec class-resource enables live in Spec Overrides: "Show Class Resource" is captured while editing as a group.
    end
    -- Chains left of the Class Resource cog in Simple mode (rgn._lastInline), or of the toggle itself in Advanced
    if not CludesUI._prebuilding then
        AddFormBarBtn(classEnableRow._leftRegion, rowConf, RebuildClass)
    end

    -- Everything below Row 1 is hidden entirely while the bar is off. classColorRow is
    -- hoisted above the gate: the section returns it for the Simple page's count-text
    -- click mapping (nil while hidden).
    local classColorRow
    if not classBarOff() then
        -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only).
        -- Orientation-aware: this bar has its OWN orientation key and its renderer treats
        -- anything not HORIZONTAL as vertical, so the value is normalized before the shared helper sees it.
        local function classOri()
            local rowCfg = rowConf()
            local o = (rowCfg and rowCfg.pipOrientation) or "HORIZONTAL"
            return o ~= "HORIZONTAL" and "VERTICAL_UP" or "HORIZONTAL"
        end
        local function classGuard(propKey)
            return mod.OrientedMatchGuard("ERB_ClassResource", propKey, classOri, classBarOff, "Class Resource")
        end
        local chDis, chTip, chRaw = classGuard("Height")
        local cwDis, cwTip, cwRaw = classGuard("Width")
        local classSizeRow
        classSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Height",
            min = 1,
            max = 60,
            step = 1,
            disabled = chDis,
            disabledTooltip = chTip,
            rawTooltip = chRaw,
            getValue = ConfGetter("pipHeight", 20),
            setValue = ConfSetter("pipHeight", SmoothRefresh, true),
        }, {
            type = "slider",
            text = "Width",
            min = 10,
            max = 800,
            step = 1,
            disabled = cwDis,
            disabledTooltip = cwTip,
            rawTooltip = cwRaw,
            getValue = ConfGetter("pipWidth", 214),
            setValue = ConfSetter("pipWidth", SmoothRefresh, true),
        })
        cursorY = cursorY - height
        if not context.advanced and context.syncRows then
            context.syncRows.classHeight = classSizeRow._leftRegion
            context.syncRows.classWidth = classSizeRow._rightRegion
            if not CludesUI._prebuilding then
                local region = classSizeRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Height to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local val = profile.secondary.pipHeight or 20
                        profile.primary.height = val
                        profile.health.height = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local val = profile.secondary.pipHeight or 20
                        return (profile.primary.height or 16) == val and (profile.health.height or 20) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.classHeight,
                            context.syncRows.powerHeight,
                            context.syncRows.healthHeight,
                        }
                    end,
                })
            end
            if not CludesUI._prebuilding then
                local region = classSizeRow._rightRegion
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Width to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local totalW = profile.secondary.pipWidth or 214
                        profile.primary.width = totalW
                        profile.health.width = totalW
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local totalW = profile.secondary.pipWidth or 214
                        return (profile.primary.width or 220) == totalW and (profile.health.width or 220) == totalW
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.classWidth,
                            context.syncRows.powerWidth,
                            context.syncRows.healthWidth,
                        }
                    end,
                })
            end
        end

        -- Border Style dropdown + inline offset cog
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local classBsRow
            classBsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("resourcebars", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = classBarOff,
                    disabledTooltip = "Class Resource",
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
                        RebuildClass()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                mod.ERB_ClassicBorderRow()
                        and mod.ERB_ClassicBorderSizeCfg(
                            rowConf,
                            classBarOff,
                            "Class Resource",
                            RebuildClass,
                            "ERB_ClassResource"
                        )
                    or CludesUI.BlizzStyle.Gate(
                        "resourcebars",
                        CludesUI.BorderPxSliderCfg({
                            text = "Border Size",
                            disabled = classBarOff,
                            disabledTooltip = "Class Resource",
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
                                RebuildClass()
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
                        disabled = classBarOff,
                        disabledTooltip = "Class Resource",
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
                            RebuildClass()
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
            if not context.advanced and context.syncRows then
                context.syncRows.classBorder = classBsRow._rightRegion
            end
            if not CludesUI._prebuilding and not mod.ERB_ClassicBorderRow() then
                local region = classBsRow._rightRegion
                local control = region._control
                -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
                -- border size control. The stock styles keep the bars square.
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(classBsRow._rightRegion, {
                        title = "Corner Radius",
                        tip = "Corner Radius",
                        disabled = function()
                            if classBarOff() or CludesUI.BlizzStyle.Get("resourcebars") then
                                return true
                            end
                            local rowCfg = rowConf()
                            return not CludesUI.RoundedStyleOK(rowCfg and rowCfg.borderTexture)
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("resourcebars") then
                                return CludesUI.BlizzStyle.Label("resourcebars")
                            end
                            if classBarOff() then
                                return "Class Resource"
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
                                set = ConfSetter("cornerRadius", RebuildClass),
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
                            RebuildClass()
                        end),
                    })
                end
                local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                    region,
                    classBsRow:GetFrameLevel() + 3,
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
            end
            if not CludesUI._prebuilding then
                local region = classBsRow._leftRegion
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
                                RebuildClass()
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
                                RebuildClass()
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
                                RebuildClass()
                                CludesUI:RefreshPage()
                            end,
                        },
                        -- Border extensions: the full-bar border only, which pip and
                        -- rune resources drop under Border on individual pips (bar types keep it).
                        {
                            type = "slider",
                            label = "Extend Top",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Grows the border past the bar's top edge on screen without resizing the bar.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.borderOnPips and not mod.IsBarTypeSecondary()) and true
                                    or false
                            end,
                            disabledTooltip = "This option can't be used while Border on individual pips is enabled.",
                            rawTooltip = true,
                            get = ConfGetter("borderExtendTop", 0),
                            set = ConfSetter("borderExtendTop", RebuildClass, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Bottom",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Grows the border past the bar's bottom edge on screen without resizing the bar.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.borderOnPips and not mod.IsBarTypeSecondary()) and true
                                    or false
                            end,
                            disabledTooltip = "This option can't be used while Border on individual pips is enabled.",
                            rawTooltip = true,
                            get = ConfGetter("borderExtendBottom", 0),
                            set = ConfSetter("borderExtendBottom", RebuildClass, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Left",
                            min = 0,
                            max = 300,
                            step = 1,
                            tooltip = "Grows the border past the bar's left edge on screen without resizing the bar.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.borderOnPips and not mod.IsBarTypeSecondary()) and true
                                    or false
                            end,
                            disabledTooltip = "This option can't be used while Border on individual pips is enabled.",
                            rawTooltip = true,
                            get = ConfGetter("borderExtendLeft", 0),
                            set = ConfSetter("borderExtendLeft", RebuildClass, true),
                        },
                        {
                            type = "slider",
                            label = "Extend Right",
                            min = 0,
                            max = 300,
                            step = 1,
                            tooltip = "Grows the border past the bar's right edge on screen without resizing the bar.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.borderOnPips and not mod.IsBarTypeSecondary()) and true
                                    or false
                            end,
                            disabledTooltip = "This option can't be used while Border on individual pips is enabled.",
                            rawTooltip = true,
                            get = ConfGetter("borderExtendRight", 0),
                            set = ConfSetter("borderExtendRight", RebuildClass, true),
                        },
                        -- Separators: None = off (edgeSep false); an art entry turns them on
                        -- with that art. The rows below pick its lines; Bar Spacing and the
                        -- gap colour stay the user's own (never written here).
                        {
                            type = "dropdown",
                            label = "Separators",
                            values = sepValues,
                            order = sepOrder,
                            tooltip = "Draws separator lines along the bar edge and between the pips.",
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
                                RebuildClass()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Horizontal Separator",
                            tooltip = "Draws the line along the bar's bottom edge.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return not (rowCfg and rowCfg.edgeSep)
                            end,
                            disabledTooltip = "Separators",
                            get = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.edgeSepH ~= false
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.edgeSepH = val and true or false
                                RebuildClass()
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
                                return not (rowCfg and rowCfg.edgeSep and rowCfg.edgeSepH ~= false)
                            end,
                            disabledTooltip = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.edgeSep) and "Horizontal Separator" or "Separators"
                            end,
                            get = ConfGetter("edgeSepY", 0),
                            set = ConfSetter("edgeSepY", RebuildClass, true),
                        },
                        {
                            type = "toggle",
                            label = "Vertical Separators",
                            tooltip = "Draws a line in each gap between the pips.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (not (rowCfg and rowCfg.edgeSep)) or mod.IsBarTypeSecondary()
                            end,
                            disabledTooltip = function()
                                local rowCfg = rowConf()
                                if not (rowCfg and rowCfg.edgeSep) then
                                    return "Separators"
                                end
                                return "This option applies to pip and rune resources only."
                            end,
                            rawTooltip = function()
                                local rowCfg = rowConf()
                                return (rowCfg and rowCfg.edgeSep) and true or false
                            end,
                            get = function()
                                local rowCfg = rowConf()
                                return rowCfg and rowCfg.edgeSepV ~= false
                            end,
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.edgeSepV = val and true or false
                                RebuildClass()
                                CludesUI:RefreshPage()
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
                CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Cross-bar sync icons: Simple page only
            if
                not context.advanced
                and context.syncRows
                and not CludesUI._prebuilding
                and mod.ERB_ClassicBorderRow()
            then
                mod.ERB_ClassicBorderSync(classBsRow._rightRegion, DB, "secondary", SmoothRefresh, function()
                    return {
                        context.syncRows.classBorder,
                        context.syncRows.powerBorder,
                        context.syncRows.healthBorder,
                    }
                end)
            elseif not context.advanced and context.syncRows and not CludesUI._prebuilding then
                -- Border Style: class -> primary + health
                CludesUI.BuildSyncIcon({
                    region = classBsRow._leftRegion,
                    tooltip = "Apply Border Style to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local was = mod.ERB_TexturedBars(profile)
                        local cfg = profile.secondary
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
                        apply(profile.primary)
                        apply(profile.health)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local bt = profile.secondary.borderTexture or "solid"
                        local bh = profile.secondary.borderBehind or false
                        return (profile.primary.borderTexture or "solid") == bt
                            and (profile.health.borderTexture or "solid") == bt
                            and (profile.primary.borderBehind or false) == bh
                            and (profile.health.borderBehind or false) == bh
                    end,
                    flashTargets = function()
                        return { classBsRow._leftRegion }
                    end,
                })
                -- Border: right region of the Border Style row
                CludesUI.BuildSyncIcon({
                    region = classBsRow._rightRegion,
                    tooltip = "Apply Border to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local was = mod.ERB_TexturedBars(profile)
                        local red, green, blue, a =
                            profile.secondary.borderR, profile.secondary.borderG, profile.secondary.borderB, profile.secondary.borderA
                        local sz = profile.secondary.borderSize or 1
                        local bt = profile.secondary.borderTexture or "solid"
                        local cr, cm = profile.secondary.cornerRadius or 0, profile.secondary.cornerMask
                        profile.primary.borderR, profile.primary.borderG, profile.primary.borderB, profile.primary.borderA =
                            red, green, blue, a
                        profile.primary.borderSize = sz
                        profile.primary.borderTexture = bt
                        profile.primary.cornerRadius = cr
                        profile.primary.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.primary, profile.secondary)
                        profile.health.borderR, profile.health.borderG, profile.health.borderB, profile.health.borderA = red, green, blue, a
                        profile.health.borderSize = sz
                        profile.health.borderTexture = bt
                        profile.health.cornerRadius = cr
                        profile.health.cornerMask = cm
                        mod.ERB_CopyBorderPx(profile.health, profile.secondary)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(profile) ~= was)
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local sr, sg, scrollBar, sa, ssz =
                            profile.secondary.borderR,
                            profile.secondary.borderG,
                            profile.secondary.borderB,
                            profile.secondary.borderA,
                            profile.secondary.borderSize or 1
                        local sbt, scr, scm =
                            profile.secondary.borderTexture or "solid",
                            profile.secondary.cornerRadius or 0,
                            profile.secondary.cornerMask or 15
                        local function eq(tbl)
                            return tbl.borderR == sr
                                and tbl.borderG == sg
                                and tbl.borderB == scrollBar
                                and tbl.borderA == sa
                                and (tbl.borderSize or 1) == ssz
                                and (tbl.borderTexture or "solid") == sbt
                                and (tbl.cornerRadius or 0) == scr
                                and (tbl.cornerMask or 15) == scm
                                and mod.ERB_SameBorderPx(tbl, profile.secondary)
                        end
                        return eq(profile.primary) and eq(profile.health)
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.classBorder,
                            context.syncRows.powerBorder,
                            context.syncRows.healthBorder,
                        }
                    end,
                })
            end

            -- Pip Border cog on Border Style (left region): per-pip borders
            -- instead of one border around the whole bar.
            if not CludesUI._prebuilding then
                local region = classBsRow._leftRegion
                local lastInline = region._lastInline or region._control
                local cogBtn = CludesUI.BuildInlineCog(region, {
                    title = "Pip Border",
                    rows = {
                        {
                            type = "toggle",
                            label = "Border on individual pips",
                            tooltip = "Draws a border around each pip instead of the bar as a whole.",
                            get = ConfGetter("borderOnPips"),
                            set = ConfSetter("borderOnPips", RebuildClass, true),
                        },
                        -- Background on individual pips: each pip's own backdrop in place of
                        -- the full-bar one, so the gaps stay clear (pip and rune resources;
                        -- Blizzard Style stands it down at runtime).
                        {
                            type = "toggle",
                            label = "Background on individual pips",
                            tooltip = "Draws the class resource background inside each pip so the gaps between pips stay clear.",
                            disabled = function()
                                local rowCfg = rowConf()
                                return (not (rowCfg and rowCfg.borderOnPips)) or mod.IsBarTypeSecondary()
                            end,
                            disabledTooltip = function()
                                if mod.IsBarTypeSecondary() then
                                    return "This option applies to pip and rune resources only."
                                end
                                return "Border on individual pips"
                            end,
                            rawTooltip = function()
                                return mod.IsBarTypeSecondary() and true or false
                            end,
                            get = ConfGetter("pipBgOnPips", false),
                            set = function(val)
                                local rowCfg = rowConf()
                                if not rowCfg then
                                    return
                                end
                                rowCfg.pipBgOnPips = val and true or false
                                RebuildClass()
                                CludesUI:RefreshPage()
                            end,
                        },
                    },
                })

                cogBtn:Show()

                -- Position only: the texture-style dropdown adds/removes its own
                -- inline elements, so the cog re-seats beside whichever is last.
                local function UpdateCogPos()
                    local rowCfg = rowConf()
                    local texture = rowCfg and rowCfg.borderTexture or "solid"
                    if texture == "solid" then
                        Pix.Point(cogBtn, "RIGHT", region._control, "LEFT", -8, 0)
                    else
                        Pix.Point(cogBtn, "RIGHT", lastInline, "LEFT", -8, 0)
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateCogPos)
                UpdateCogPos()
            end
        end

        -- Row: Bar Spacing | Empty Bar Overlay. Empty Bar Overlay exposes bgR/G/B/A, the
        -- overlay tint on empty pip backgrounds. Bar Spacing's color is opt-in: the inline
        -- gapColorEnabled toggle activates a gap-only fill layer (gapR/G/B/A).
        do
            local classGapRow
            classGapRow, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                pixel = true,
                text = "Bar Spacing",
                min = 0,
                max = 20,
                step = 1,
                disabled = classBarOff,
                disabledTooltip = "Class Resource",
                getValue = ConfGetter("pipSpacing", 3),
                setValue = ConfSetter("pipSpacing", SmoothRefresh),
            }, {
                type = "slider",
                text = "Empty Bar Overlay",
                min = 0,
                max = 100,
                step = 5,
                disabled = classBarOff,
                disabledTooltip = "Class Resource",
                getValue = function()
                    local rowCfg = rowConf()
                    return math.floor(((rowCfg and rowCfg.bgA) or 0.1) * 100 + 0.5)
                end,
                setValue = function(val)
                    local rowCfg = rowConf()
                    if not rowCfg then
                        return
                    end
                    rowCfg.bgA = val / 100
                    RefreshClass()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height
            -- Bar Spacing inline enable toggle + gap-color swatch
            if not CludesUI._prebuilding then
                local region = classGapRow._leftRegion
                local control = region._control
                local gapSwatch, updateGapSwatch = CludesUI.BuildColorSwatch(
                    region,
                    classGapRow:GetFrameLevel() + 3,
                    function()
                        local rowCfg = rowConf()
                        return (rowCfg and rowCfg.gapR or 0),
                            (rowCfg and rowCfg.gapG or 0),
                            (rowCfg and rowCfg.gapB or 0),
                            (rowCfg and rowCfg.gapA or 1)
                    end,
                    function(red, green, blue, a)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.gapR, rowCfg.gapG, rowCfg.gapB, rowCfg.gapA = red, green, blue, a
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    true,
                    20
                )
                Pix.Point(gapSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
                region._lastInline = gapSwatch
                CludesUI.RegisterWidgetRefresh(function()
                    updateGapSwatch()
                end)
                local gapBlock = CludesUI.NewSwatchBlocker(gapSwatch)
                gapBlock:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(gapSwatch, "Enable the toggle to set a custom gap color")
                end)
                gapBlock:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateGapSwatchState()
                    local rowCfg = rowConf()
                    if rowCfg and rowCfg.gapColorEnabled then
                        gapSwatch:SetAlpha(1)
                        gapBlock:Hide()
                    else
                        gapSwatch:SetAlpha(0.3)
                        gapBlock:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateGapSwatchState)
                UpdateGapSwatchState()
                CludesUI.BuildInlineToggle({
                    region = region,
                    getValue = ConfGetter("gapColorEnabled"),
                    setValue = function(val)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.gapColorEnabled = val and true or nil
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                })
            end
            -- Empty Bar Overlay inline color swatch (RGB only)
            if not CludesUI._prebuilding then
                local region = classGapRow._rightRegion
                local control = region._control
                local ovSwatch, updateOvSwatch = CludesUI.BuildColorSwatch(
                    region,
                    classGapRow:GetFrameLevel() + 3,
                    function()
                        local rowCfg = rowConf()
                        return (rowCfg and rowCfg.bgR or 1), (rowCfg and rowCfg.bgG or 1), (rowCfg and rowCfg.bgB or 1), 1
                    end,
                    function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.bgR, rowCfg.bgG, rowCfg.bgB = red, green, blue
                        RefreshClass()
                        CludesUI:RefreshPage()
                    end,
                    false,
                    20
                )
                Pix.Point(ovSwatch, "RIGHT", control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    updateOvSwatch()
                end)
            end
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local classBorderRow
        classBorderRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 5,
            disabled = classBarOff,
            disabledTooltip = "Class Resource",
            getValue = function()
                local rowCfg = rowConf()
                return math.floor(((rowCfg and rowCfg.barAlpha) or 1) * 100 + 0.5)
            end,
            setValue = function(val)
                local rowCfg = rowConf()
                if not rowCfg then
                    return
                end
                rowCfg.barAlpha = val / 100
                RefreshClass()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Fill Color",
            min = 0,
            max = 100,
            step = 1,
            trackWidth = 120,
            tooltip = "Opacity of the resource fill; below 100 the world shows through the fill instead of the background.",
            disabled = classBarOff,
            disabledTooltip = "Class Resource",
            getValue = function()
                local rowCfg = rowConf()
                return (rowCfg and rowCfg.fillOpacity) or 100
            end,
            setValue = function(val)
                local rowCfg = rowConf()
                if not rowCfg then
                    return
                end
                rowCfg.fillOpacity = val
                RebuildClass()
                SmoothRefresh()
            end,
        })
        cursorY = cursorY - height
        -- Fill Color inline cog: Charged Combo Point color
        if not CludesUI._prebuilding then
            local region = classBorderRow._rightRegion
            CludesUI.BuildInlineCog(region, {
                disabled = classBarOff,
                disabledTooltip = "Class Resource",
                title = "Fill Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Darken Partially Filled Resources",
                        tooltip = "Makes partially filled Soul Shards and Essence darker than completed ones.",
                        get = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.darkenPartialPips ~= false
                        end,
                        set = ConfSetter("darkenPartialPips", RefreshClass),
                    },
                    {
                        type = "colorpicker",
                        label = "Charged Color",
                        hasAlpha = false,
                        get = function()
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return 0.44, 0.77, 1.00, 1
                            end
                            return rowCfg.chargedR or 0.44, rowCfg.chargedG or 0.77, rowCfg.chargedB or 1.00, rowCfg.chargedA or 1
                        end,
                        set = function(cr, cg, checkBtn, ca)
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return
                            end
                            rowCfg.chargedR, rowCfg.chargedG = cr, cg
                            rowCfg.chargedB, rowCfg.chargedA = checkBtn, ca
                            RebuildClass()
                            SmoothRefresh()
                        end,
                    },
                },
                footer = false,
            })
        end
        -- Fill Color inline swatches: custom / class / resource
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineSwatches(classBorderRow._rightRegion, {
                {
                    tooltip = "Custom Colored",
                    hasAlpha = false,
                    getValue = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return 0xDB / 255, 0xCF / 255, 0x37 / 255, 1
                        end
                        return rowCfg.fillR, rowCfg.fillG, rowCfg.fillB, 1
                    end,
                    setValue = function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.fillR, rowCfg.fillG, rowCfg.fillB = red, green, blue
                        RebuildClass()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        local inCustom = (not rowCfg.resourceColored) and (rowCfg.classColored == false)
                        if not inCustom then
                            -- false, never nil: a removed key harvests into
                            -- spec overrides as a key-removal marker the apply
                            -- guard can never re-apply (the soul-bar colour
                            -- revert); the runtime only tests truthiness, so
                            -- false is behaviourally identical.
                            rowCfg.resourceColored = false
                            rowCfg.classColored = false
                            RebuildClass()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local inCustom = rowCfg and not rowCfg.resourceColored and (rowCfg.classColored == false)
                        return inCustom and 1 or 0.3
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
                        return 1, 0.82, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.resourceColored = false -- false, never nil (see Custom swatch)
                        rowCfg.classColored = true
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        local isClassMode = rowCfg and not rowCfg.resourceColored and (rowCfg.classColored ~= false)
                        return isClassMode and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Class Resource Color",
                    getValue = function()
                        local gsr = _G._CURB_GetSecondaryResource
                        local rslv = _G._CURB_ResolveSecondaryResourceColor
                        if gsr and rslv then
                            local details = gsr()
                            if details and details.power ~= nil then
                                local rr, rg, rb = rslv(details.power)
                                if rr then
                                    return rr, rg, rb, 1
                                end
                            end
                        end
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then
                            return classColor.r, classColor.g, classColor.b, 1
                        end
                        return 1, 0.82, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.resourceColored = true
                        rowCfg.classColored = true
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local rowCfg = rowConf()
                        return (rowCfg and rowCfg.resourceColored) and 1 or 0.3
                    end,
                },
            }, {
                size = 20,
                disabled = function()
                    local rowCfg = rowConf()
                    return (not rowCfg) or not rowCfg.enabled or rowCfg.darkTheme
                end,
                disabledTooltip = function()
                    local rowCfg = rowConf()
                    if rowCfg and rowCfg.darkTheme then
                        return "This option requires Class Resource Bar Dark Mode to be off. Dark Mode colors can be adjusted in Global Settings -> Colors."
                    end
                    return "Class Resource"
                end,
            })
        end
        if not context.advanced and context.syncRows then
            context.syncRows.classOpacity = classBorderRow._leftRegion
            if not CludesUI._prebuilding then
                local region = classBorderRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply Opacity to all Bars",
                    onClick = function()
                        local profile = DB()
                        if not profile then
                            return
                        end
                        local val = profile.secondary.barAlpha or 1
                        profile.primary.barAlpha = val
                        profile.health.barAlpha = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        local val = profile.secondary.barAlpha or 1
                        return (profile.primary.barAlpha or 1) == val and (profile.health.barAlpha or 1) == val
                    end,
                    flashTargets = function()
                        return {
                            context.syncRows.classOpacity,
                            context.syncRows.powerOpacity,
                            context.syncRows.healthOpacity,
                        }
                    end,
                })
            end
        end

        -- Out of Combat Opacity cog: dims the Class Resource bar to this alpha out of combat (100 = no fade); applied by ns.ResolveBarAlpha in UpdateVisibility, which reacts to combat.
        if not CludesUI._prebuilding then
            local region = classBorderRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local rowCfg = rowConf()
                    return rowCfg and not rowCfg.enabled
                end,
                disabledTooltip = "Class Resource",
                title = "Out of Combat Opacity",
                rows = {
                    {
                        type = "toggle",
                        label = "Fade Out of Combat",
                        get = function()
                            local rowCfg = rowConf()
                            return rowCfg and rowCfg.oocFadeEnabled == true
                        end,
                        set = ConfSetter("oocFadeEnabled", RefreshClass),
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
                            RefreshClass()
                        end,
                    },
                },
            })
        end

        -- Resource Text and the Hunter Focus row below touch only the class-resource
        -- (secondary) config. DB() is shadowed in this scope so DB().secondary resolves to
        -- cfg() without rewriting every access path; it returns nil while cfg() does, so the
        -- `if not p` guards short-circuit.
        local DB = function()
            local rowCfg = rowConf()
            if not rowCfg then
                return nil
            end
            return { secondary = rowCfg }
        end

        -- Row 5: Resource Text | Threshold & Hash Lines
        classColorRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Resource Text",
            disabled = classBarOff,
            disabledTooltip = "Class Resource",
            getValue = function()
                local profile = DB()
                return profile and profile.secondary.showText
            end,
            setValue = function(val)
                local profile = DB()
                if not profile then
                    return
                end
                profile.secondary.showText = val
                RebuildClass()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "Threshold & Hash Lines" })
        cursorY = cursorY - height
        -- Resource Text inline cog: size + position
        if not CludesUI._prebuilding then
            local region = classColorRow._leftRegion
            local resTextRows = {
                {
                    type = "toggle",
                    label = "Show %",
                    get = function()
                        local profile = DB()
                        return (not profile) or profile.secondary.showPercent ~= false
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.showPercent = val
                        RefreshClass()
                    end,
                },
                {
                    type = "toggle",
                    label = "Only if Power Bar Hidden",
                    tooltip = 'Show the resource text only while the power bar is hidden - disabled, filtered off for this spec, a spec with no power, or hidden by "Hide Power Bar if Resource". Off = always show the text.',
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.showTextOnlyIfNoPower
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.showTextOnlyIfNoPower = val
                        RebuildClass()
                    end,
                },
                {
                    type = "toggle",
                    label = "Hide at Zero",
                    tooltip = "Hide the resource text while the resource is at zero.",
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.hideTextAtZero
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        -- Rebuild: the build path installs or removes the filter.
                        profile.secondary.hideTextAtZero = val
                        RebuildClass()
                    end,
                },
                {
                    type = "slider",
                    label = "Size",
                    min = 8,
                    max = 64,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.textSize or 11
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.textSize = val
                        RefreshClass()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Anchor",
                    values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                    order = { "LEFT", "CENTER", "RIGHT" },
                    tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.textAnchor or "CENTER"
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.textAnchor = val
                        RefreshClass()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.textXOffset or 0
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.textXOffset = val
                        RefreshClass()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local profile = DB()
                        return profile and profile.secondary.textYOffset or 0
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.textYOffset = val
                        RefreshClass()
                    end,
                },
            }
            -- Devourer (DH soul fragments) only: hides the "/ max" suffix on the count text; inserted above "Show %"
            do
                local gsr = _G._CURB_GetSecondaryResource
                local secInfo = gsr and gsr()
                if secInfo and secInfo.power == "SOUL_FRAGMENTS_DEVOURER" then
                    table.insert(resTextRows, 1, {
                        type = "toggle",
                        label = "Show Max Stacks",
                        get = function()
                            local profile = DB()
                            return (not profile) or profile.secondary.showMaxStacks ~= false
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then
                                return
                            end
                            profile.secondary.showMaxStacks = val
                            RefreshClass()
                        end,
                    })
                end
            end
            CludesUI.BuildInlineCog(region, {
                disabled = function()
                    local profile = DB()
                    return not profile or not profile.secondary.enabled or not profile.secondary.showText
                end,
                disabledTooltip = "Resource Text",
                title = "Resource Text",
                rows = resTextRows,
                footer = false,
            })
        end
        -- Resource Text inline color swatch, left of the cog; the druid per-form
        -- button left of it
        if not CludesUI._prebuilding then
            local region = classColorRow._leftRegion
            local control = region._control
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                classColorRow:GetFrameLevel() + 3,
                function()
                    local profile = DB()
                    if not profile then
                        return 1, 1, 1, 1
                    end
                    return profile.secondary.textR or 1, profile.secondary.textG or 1, profile.secondary.textB or 1, 1
                end,
                function(red, green, blue)
                    local profile = DB()
                    if not profile then
                        return
                    end
                    profile.secondary.textR, profile.secondary.textG, profile.secondary.textB = red, green, blue
                    RefreshClass()
                end,
                false,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local swatchDis = CludesUI.NewSwatchBlocker(colorSwatch)
            swatchDis:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip("Resource Text"))
            end)
            swatchDis:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateSwatchDis()
                updateSwatch()
                local profile = DB()
                local off = not profile or not profile.secondary.enabled or not profile.secondary.showText
                if off then
                    colorSwatch:SetAlpha(0.3)
                    swatchDis:Show()
                else
                    colorSwatch:SetAlpha(1)
                    swatchDis:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateSwatchDis)
            UpdateSwatchDis()
            AddFormTextBtn(region, colorSwatch, function()
                return DB() and DB().secondary
            end, RefreshClass)
        end

        -- class settings [start]
        -- Threshold & Hash Lines (row 5 slot 2): the shared editor, given the class resource's own rules
        if not CludesUI._prebuilding then
            local settingsRgn = classColorRow._rightRegion
            -- Thresholds have their own per-spec system, so lock the slot during a Spec Overrides editing session.
            CludesUI.SpecOverrides_AttachEditLock(
                settingsRgn,
                "Thresholds have their own per-spec system and can't be edited while editing a spec group"
            )

            -- Vengeance soul fragments and the Prot Ignore Pain bar are SECRET values, so recoloring text cannot work there
            local TI_BLOCK_TIP =
                "Not available for this spec: Vengeance soul fragments and the Protection Ignore Pain bar use secret values that can't be read into a text color, so recoloring the text would have no effect."
            local function HasSpec(ent, ident)
                local ids = ent and ent.specIDs
                if ids then
                    for idx = 1, #ids do
                        if ids[idx] == ident then
                            return true
                        end
                    end
                end
                return false
            end

            BuildThresholdSettingsButton({
                parentRgn = settingsRgn,
                getBarData = rowConf,
                -- The page appends an "Anchor to Cursor" row after this section, so the editor covers one row more
                pageParent = hostFrame,
                pageTopY = _advTop,
                pageBotY = function()
                    return cursorY
                end,
                pageBotExtra = 50,
                refreshFn = RefreshClass,
                rebuildFn = RebuildClass,
                swatchRefreshFn = SmoothRefresh,
                disabledFn = classBarOff,
                disabledTip = "Class Resource",
                defaultR = 0x0c / 255,
                defaultG = 0xd2 / 255,
                defaultB = 0x9d / 255,
                defaultA = 1,
                thresholdField = "thresholdCount",
                hashModeDefault = "value",
                hashWidthMax = 4,
                hashValueHint = CludesUI.L("(Ex: 25,50,75)"),
                showBuffs = true,
                showSpenders = true,
                -- Brewmaster stagger ceiling: the stagger bar fills to this % of max health (lower = fills
                -- sooner); the color % thresholds still use REAL max health
                barInput = {
                    label = "Stagger Full %",
                    field = "staggerCeilingPercent",
                    min = 1,
                    max = 500,
                    default = 100,
                    letters = 3,
                },

                -- A count threshold: 30 (%) for bar-type resources, 3 for pips, 7 for the Enhance five-bar style
                newEntry = function(ids, cfg)
                    local entryIsBar = mod.IsSpecBarType(ids[1])
                    local enhAdd = false
                    if cfg.enhanceFiveBar then
                        for _, spellRef in ipairs(ids) do
                            if spellRef == 263 then
                                enhAdd = true
                                break
                            end
                        end
                    end
                    local newEntry = {
                        specIDs = ids,
                        hashValues = "",
                        hashWidth = 1,
                        hashColorR = 1,
                        hashColorG = 1,
                        hashColorB = 1,
                        hashColorA = 0.7,
                        thresholdEnabled = true,
                        thresholdCount = enhAdd and 7 or (entryIsBar and 30 or 3),
                        thresholdPartialOnly = false,
                        thresholdR = cfg.thresholdR or 0x0c / 255,
                        thresholdG = cfg.thresholdG or 0xd2 / 255,
                        thresholdB = cfg.thresholdB or 0x9d / 255,
                        thresholdA = cfg.thresholdA or 1,
                    }
                    -- Default for "Threshold color below value": the only bar-type spender class resource is Hunter
                    -- Focus, so it starts ON (warn when low); builders (Maelstrom/Insanity/Astral) start OFF.
                    -- Only when the entry covers the current spec (resource readable).
                    if entryIsBar then
                        local curIdx = C_SpecializationInfo.GetSpecialization()
                        local curSpecID = curIdx and C_SpecializationInfo.GetSpecializationInfo(curIdx)
                        -- WoW Forever: the entry covers the player when it names a spec of the class.
                        if curSpecID or CludesUI.IS_FOREVER then
                            for _, spellRef in ipairs(ids) do
                                if
                                    spellRef == curSpecID
                                    or (CludesUI.IS_FOREVER and CludesUI.IsPlayerSpec(spellRef))
                                then
                                    local gsr = _G._CURB_GetSecondaryResource
                                    local details = gsr and gsr()
                                    if details and details.power == "FOCUS_BAR" then
                                        newEntry.thresholdReverse = true
                                    end
                                    break
                                end
                            end
                        end
                    end
                    return newEntry
                end,

                -- Threshold options cog: per-entry gating mirrors the detail pane so Threshold as / Direction / Only color at-above grey correctly
                thresholdCog = {
                    title = "Threshold Options",
                    minWidth = 320,
                    rows = function(current, redraw)
                        local function entryIsBar()
                            local entry = current()
                            return (entry and mod.IsEntryBarType(entry)) and true or false
                        end
                        local function isStagger()
                            return HasSpec(current(), 268)
                        end
                        local function isEnhance()
                            local rowCfg = rowConf()
                            return (rowCfg and rowCfg.enhanceFiveBar == true and HasSpec(current(), 263)) and true
                                or false
                        end
                        local function enabled()
                            local entry = current()
                            if not entry then
                                return false
                            end
                            local val = entry.thresholdEnabled
                            if val == nil then
                                val = true
                            end
                            return val
                        end
                        local function multiOn()
                            local entry = current()
                            return (entry and entry.multiBandEnabled and not isEnhance()) and true or false
                        end
                        local function usable()
                            return enabled() and not multiOn()
                        end
                        local function offTip()
                            if multiOn() then
                                return BAND_REPLACES_TIP
                            end
                            return "Enable the Threshold toggle to use these options."
                        end
                        local function isUpTo()
                            local entry = current()
                            return (entry and entry.thresholdReverse) and true or false
                        end
                        local function isWarrCharge()
                            -- Arms/Fury class-bar thresholds render on the engine-fed
                            -- Whirlwind/Sweeping Strikes charge bar, whose only
                            -- threshold display is range coloring at/above the count
                            -- (no Lua count exists to flip the whole fill).
                            if (select(2, UnitClass("player"))) ~= "WARRIOR" then
                                return false
                            end
                            local entry = current()
                            local ids = entry and entry.specIDs
                            if not ids then
                                return false
                            end
                            for idx = 1, #ids do
                                local ident = ids[idx]
                                if ident == 0 or ident == 71 or ident == 72 then
                                    return true
                                end
                            end
                            return false
                        end
                        local function changed()
                            RefreshClass()
                            redraw()
                        end
                        return {
                            {
                                type = "segmented",
                                label = "Threshold as",
                                keys = { "percent", "value" },
                                labels = { percent = "Percent", value = "Value" },
                                rawTooltip = true,
                                disabled = function()
                                    return (not usable()) or (not entryIsBar()) or isStagger()
                                end,
                                disabledTooltip = function()
                                    if not usable() then
                                        return offTip()
                                    end
                                    if not entryIsBar() then
                                        return "This option applies to bar-type resources only (pips use stack counts)."
                                    end
                                    return STAGGER_PCT_TIP
                                end,
                                get = function()
                                    local entry = current()
                                    return (entry and entry.thresholdMode) or "percent"
                                end,
                                set = function(val)
                                    local entry = current()
                                    if not entry then
                                        return
                                    end
                                    entry.thresholdMode = val
                                    changed()
                                end,
                            },
                            {
                                type = "segmented",
                                label = "Direction",
                                keys = { "upto", "from" },
                                labels = { upto = "Up to", from = "From" },
                                rawTooltip = true,
                                disabled = function()
                                    return (not usable()) or isWarrCharge()
                                end,
                                disabledTooltip = function()
                                    if isWarrCharge() and usable() then
                                        return "Whirlwind and Sweeping Strikes thresholds only support the 'From' direction."
                                    end
                                    return offTip()
                                end,
                                get = function()
                                    if isWarrCharge() then
                                        return "from"
                                    end
                                    local entry = current()
                                    return (entry and entry.thresholdReverse) and "upto" or "from"
                                end,
                                set = function(val)
                                    local entry = current()
                                    if not entry then
                                        return
                                    end
                                    entry.thresholdReverse = (val == "upto")
                                    changed()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Only color at/above threshold",
                                rawTooltip = true,
                                disabled = function()
                                    return (not usable()) or entryIsBar() or isUpTo() or isWarrCharge()
                                end,
                                disabledTooltip = function()
                                    if isWarrCharge() and usable() then
                                        return "Always on for Whirlwind and Sweeping Strikes charges: range coloring at/above the threshold is the only way these bars can display thresholds."
                                    end
                                    if not usable() then
                                        return offTip()
                                    end
                                    if entryIsBar() then
                                        return "This option applies to pip-type resources only."
                                    end
                                    return "Only available with the 'From' direction -- it highlights the pips at/above the threshold."
                                end,
                                get = function()
                                    if isWarrCharge() then
                                        return true
                                    end
                                    local entry = current()
                                    return (entry and entry.thresholdPartialOnly) and true or false
                                end,
                                set = function(val)
                                    local entry = current()
                                    if not entry then
                                        return
                                    end
                                    entry.thresholdPartialOnly = val
                                    changed()
                                end,
                            },
                        }
                    end,
                },

                -- Per-entry rules, keyed off the SELECTED entry's specs rather than the live spec, so
                -- editing another spec's entry while playing that spec stays unlocked
                entryRules = function(ent, r, cfg)
                    local entryIsBar = mod.IsEntryBarType(ent)
                    local isGuardian, isIgnorePain, isVengeance, isStagger, isEnhance
                    if ent.specIDs then
                        for _, spec in ipairs(ent.specIDs) do
                            -- WoW Forever: the Druid class resource there is combo points, which
                            -- draw the card's hash lines, so the Ironfur bar exception is retail only.
                            -- Retail keeps the row while the card holds hash lines, so lines saved
                            -- on WoW Forever can be cleared.
                            if
                                spec == 104
                                and not CludesUI.IS_FOREVER
                                and (ent.hashValues == nil or ent.hashValues == "")
                            then
                                isGuardian = true
                            end
                            if spec == 73 then
                                isIgnorePain = true
                            end
                            if spec == 581 then
                                isVengeance = true
                            end
                            if spec == 268 then
                                isStagger = true
                            end
                            if spec == 263 and cfg.enhanceFiveBar == true then
                                isEnhance = true
                            end
                        end
                    end
                    -- Brewmaster stagger reads its threshold as a percent only
                    if isStagger and ent.thresholdMode == "value" then
                        ent.thresholdMode = "percent"
                    end
                    -- Bar-type reads the threshold as % (max 100) or an absolute value (higher cap); pips count stacks
                    local isValue = entryIsBar and not isStagger and ent.thresholdMode == "value"
                    r.pips = not entryIsBar
                    -- The Guardian Ironfur and Prot Ignore Pain bars draw their own hash lines
                    r.hideHash = (isGuardian or isIgnorePain) and true or false
                    r.thrMin = isEnhance and 7 or 1
                    r.thrMax = isStagger and 500 or (entryIsBar and (isValue and 1000 or 100) or 20)
                    r.thrDef = isEnhance and 7 or (entryIsBar and 30 or 3)
                    r.thrLabel = CludesUI.L("Threshold") .. ((entryIsBar and not isValue) and " %" or "")
                    if isEnhance then
                        r.thrTip = CludesUI.L(
                            "Enhance 5 Bar minimum is %d (if you want less just change 5 bar color)"
                        )
                            :format(7)
                        r.multiBlock = CludesUI.L("Unavailable with Enhancement 5-bar style.")
                    end
                    r.bandPctCap = isStagger and 500 or nil
                    -- "Recolor text instead" no-ops for secret resources (Vengeance soul fragments, Prot Ignore Pain bar)
                    if isVengeance or (isIgnorePain and cfg.protIgnorePainBar) then
                        r.textBlock = CludesUI.L(TI_BLOCK_TIP)
                    end
                    r.barInput = isStagger
                end,
            })
        end
        -- class settings [end]
        -- Class-specific rows: DK runes, Shaman Enhance, Hunter Focus. DK rune and Shaman enhance fields
        -- resolve per-spec at runtime, so they route through cfg(). Hunter "Focus as Power" is read
        -- globally (power-type resolution), so it stays a Simple-page global toggle.
        do
            local _, playerClass = UnitClass("player")
            if playerClass == "DEATHKNIGHT" then
                local simpleRuneRow
                simpleRuneRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Custom Recharge Color",
                    tooltip = "Choose the color of recharging runes instead of a dimmed version of the rune color.",
                    disabled = classBarOff,
                    disabledTooltip = "Class Resource",
                    getValue = ConfGetter("runesCustomRecharge"),
                    setValue = ConfSetter("runesCustomRecharge", RebuildClass, true),
                }, {
                    type = "toggle",
                    text = "Simple Runes",
                    tooltip = "Show rune count in center and remove recharge text/animation",
                    disabled = classBarOff,
                    disabledTooltip = "Class Resource",
                    getValue = ConfGetter("runesSimple"),
                    setValue = ConfSetter("runesSimple", RebuildClass),
                })
                cursorY = cursorY - height
                -- Custom recharge color inline swatch
                if not CludesUI._prebuilding then
                    local region = simpleRuneRow._leftRegion
                    local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                        region,
                        simpleRuneRow:GetFrameLevel() + 3,
                        function()
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return 0.5, 0.5, 0.5, 1
                            end
                            return rowCfg.runesRechargeR or 0.5,
                                rowCfg.runesRechargeG or 0.5,
                                rowCfg.runesRechargeB or 0.5,
                                rowCfg.runesRechargeA or 1
                        end,
                        function(red, green, blue, a)
                            local rowCfg = rowConf()
                            if not rowCfg then
                                return
                            end
                            rowCfg.runesRechargeR = red
                            rowCfg.runesRechargeG = green
                            rowCfg.runesRechargeB = blue
                            rowCfg.runesRechargeA = a
                            SmoothRefresh()
                        end,
                        true,
                        20
                    )
                    colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                    local swatchBlock = CludesUI.NewSwatchBlocker(colorSwatch)
                    swatchBlock:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(
                            colorSwatch,
                            CludesUI.DisabledTooltip("Custom Recharge Color")
                        )
                    end)
                    swatchBlock:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                    local function UpdateRechargeSwatch()
                        local rowCfg = rowConf()
                        local off = not (rowCfg and rowCfg.enabled) or not rowCfg.runesCustomRecharge
                        if off then
                            colorSwatch:SetAlpha(0.3)
                            swatchBlock:Show()
                        else
                            colorSwatch:SetAlpha(1)
                            swatchBlock:Hide()
                        end
                    end
                    CludesUI.RegisterWidgetRefresh(function()
                        if updateSwatch then
                            updateSwatch()
                        end
                        UpdateRechargeSwatch()
                    end)
                    UpdateRechargeSwatch()
                end
            end
            -- Retail only: WoW Forever hunters use mana and have no BM/MM specs.
            if playerClass == "HUNTER" and not context.advanced and not CludesUI.IS_FOREVER then
                _, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Show Focus as Power Bar (BM/MM)",
                    tooltip = "When enabled, BM and MM specs show Focus as the standard power bar instead of a class resource bar.",
                    getValue = function()
                        local profile = DB()
                        if not profile then
                            return false
                        end
                        return profile.secondary.hunterFocusAsPower or false
                    end,
                    setValue = function(val)
                        local profile = DB()
                        if not profile then
                            return
                        end
                        profile.secondary.hunterFocusAsPower = val
                        RebuildPower()
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "" })
                cursorY = cursorY - height
            end
            -- Retail only: WoW Forever has no Enhancement spec.
            if playerClass == "SHAMAN" and not CludesUI.IS_FOREVER then
                -- Enhance 5-bar applies to Enhancement (specID 263) only, gated on the active spec
                local function _enhSpecOK()
                    return C_SpecializationInfo.GetSpecialization() == 2
                end
                local enhRow
                enhRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "toggle",
                    text = "Enhance 5 Bar Style",
                    disabled = function()
                        local rowCfg = rowConf()
                        return not (rowCfg and rowCfg.enabled) or not _enhSpecOK()
                    end,
                    disabledTooltip = "Requires Enhancement Shaman with Class Resource enabled.",
                    rawTooltip = true,
                    getValue = ConfGetter("enhanceFiveBar"),
                    setValue = ConfSetter("enhanceFiveBar", RebuildClass, true),
                }, { type = "label", text = "" })
                cursorY = cursorY - height
                -- Overflow color inline swatch
                if not CludesUI._prebuilding then
                    local region = enhRow._leftRegion
                    local colorSwatch = CludesUI.BuildColorSwatch(region, enhRow:GetFrameLevel() + 3, function()
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return 1, 0.6, 0.2, 1
                        end
                        return rowCfg.enhanceOverflowR or 1,
                            rowCfg.enhanceOverflowG or 0.6,
                            rowCfg.enhanceOverflowB or 0.2,
                            1
                    end, function(red, green, blue)
                        local rowCfg = rowConf()
                        if not rowCfg then
                            return
                        end
                        rowCfg.enhanceOverflowR = red
                        rowCfg.enhanceOverflowG = green
                        rowCfg.enhanceOverflowB = blue
                        SmoothRefresh()
                    end, false, 20)
                    colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                    region._lastInline = colorSwatch
                    local function UpdateEnhSwatchVis()
                        local rowCfg = rowConf()
                        local off = not (rowCfg and rowCfg.enabled) or not rowCfg.enhanceFiveBar or not _enhSpecOK()
                        colorSwatch:SetAlpha(off and 0.3 or 1)
                    end
                    CludesUI.RegisterWidgetRefresh(UpdateEnhSwatchVis)
                    UpdateEnhSwatchVis()
                end
            end
        end
    end -- close Class Resource hidden-while-disabled gate

    -- Simple page: cover these controls when the current spec overrides the Class Resource in Advanced, so edits here aren't silently ignored.
    if not context.advanced then
        mod.ERB_SimpleOverrideOverlay(hostFrame, _advTop, cursorY, "secondary")
    end

    -- Blizzard Class Resource Art stands in for this bar: block the styling rows above.
    mod.ERB_BlizzArtBlockRegions(artRegions)

    -- Header + row frames go back so the Simple page can wire its preview click-mappings (classSection/classEnableRow, and the Resource Text row for the count-text overlay).
    return cursorY, heading, classEnableRow, classColorRow, unlockJump
end
--- [class resource end]
