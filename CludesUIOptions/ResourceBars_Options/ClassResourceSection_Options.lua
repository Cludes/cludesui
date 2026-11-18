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
                local rgn = regions[idx]
                local b = CreateFrame("Frame", nil, rgn)
                b:SetAllPoints()
                b:SetFrameLevel(rgn:GetFrameLevel() + 50)
                b:EnableMouse(true)
                b:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        b,
                        CludesUI.DisabledTooltip("Blizzard Class Resource Art", "disabled")
                    )
                end)
                b:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                blocks[#blocks + 1] = b
            end
        end
        if not blocks then
            return
        end
        for idx = 1, #blocks do
            local b = blocks[idx]
            b:GetParent():SetAlpha(on and 0.3 or 1)
            b:SetShown(on)
        end
    end
    Update()
    CludesUI.RegisterWidgetRefresh(Update)
end

-- Shared, context-aware CLASS RESOURCE (secondary) section builder. ctx.cfg() ->
-- secondary table. The Guardian/Prot special-bar rows show in both modes for the
-- relevant spec (global storage). The Hide-Power cog is Simple-only. The Threshold &
-- Hash Lines row hosts the shared editor (env.BuildThresholdSettingsButton).
function mod.ERB_BuildClassResourceSection(hostFrame, posY, context)
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

    local _, hgt
    local function conf()
        return context.cfg()
    end
    -- A row's getter and setter for one key of this section's settings: the
    -- getter gives its value, or default when unset (no default: the value as
    -- stored); the setter writes it when the settings exist, then runs after
    -- and, with alsoPage, rebuilds the page.
    local function ConfGetter(key, default)
        return function()
            local c = conf()
            if default == nil then
                return c and c[key]
            end
            return c and c[key] or default
        end
    end
    local function ConfSetter(key, after, alsoPage)
        return function(val)
            local c = conf()
            if not c then
                return
            end
            c[key] = val
            after()
            if alsoPage then
                CludesUI:RefreshPage()
            end
        end
    end
    local function classOff()
        local c = conf()
        return not (c and c.enabled)
    end

    local heading
    heading, hgt = W:SectionHeader(hostFrame, "CLASS RESOURCE BAR", posY)
    posY = posY - hgt
    -- Move in Unlock Mode on the title; handed back so the page's preview eye sits after it.
    local unlockJump = CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "ERB_ClassResource", disabled = classOff, disabledTooltip = "Class Resource" }
    )

    local _advTop = posY -- content top; also used by the Simple override overlay
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
                local p = DB()
                return p and not p.secondary.guardianIronfurBar
            end
            local _, hh = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Guardian Druid Ironfur Bar",
                tooltip = "Replaces the class resource bar with an Ironfur tracker. Each Ironfur cast adds a hash line that slides from right to left as its buff decays. Duration is talent-aware (Ursoc's Endurance and Guardian of Elune).",
                getValue = function()
                    local p = DB()
                    return p and p.secondary.guardianIronfurBar
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.guardianIronfurBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Show Hash Lines",
                disabled = _ifOff,
                disabledTooltip = "Guardian Druid Ironfur Bar",
                getValue = function()
                    local p = DB()
                    return p and p.secondary.guardianShowHashLines ~= false
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.guardianShowHashLines = val
                    SmoothRefresh()
                    CludesUI:RefreshPage()
                end,
            })
            posY = posY - hh
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
            ipRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Prot Warrior Ignore Pain Bar",
                tooltip = ipBarTip,
                getValue = function()
                    local p = DB()
                    return p and p.secondary.protIgnorePainBar
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.protIgnorePainBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Show Hash Line",
                tooltip = ipHashTip,
                disabled = function()
                    local p = DB()
                    return not (p and p.secondary.protIgnorePainBar)
                end,
                disabledTooltip = "Prot Warrior Ignore Pain Bar",
                getValue = function()
                    local p = DB()
                    return p and p.secondary.protIgnorePainHashLine ~= false
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.protIgnorePainHashLine = val
                    CludesUI:RefreshPage()
                end,
            })
            posY = posY - hgt
            local function IPControlTip(rgn, tipText)
                local c = rgn and rgn._control
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
            ssRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Arms Warrior Sweeping Strikes Bar",
                tooltip = ssBarTip,
                getValue = function()
                    local p = DB()
                    return p and p.secondary.armsSweepingStrikesBar
                end,
                setValue = function(val)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.armsSweepingStrikesBar = val
                    RebuildClass()
                    CludesUI:RefreshPage()
                end,
            }, { type = "label", text = "" })
            posY = posY - hgt
        end
    end

    -- Row 1: Show Class Resource | Orientation
    local classEnableRow
    classEnableRow, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Show Class Resource",
        getValue = ConfGetter("enabled"),
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
            RebuildClass()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "dropdown",
        text = "Orientation",
        disabled = classOff,
        disabledTooltip = "Class Resource",
        values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
        order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
        getValue = function()
            local c = conf()
            if not c then
                return "HORIZONTAL"
            end
            local val = c.pipOrientation or "HORIZONTAL"
            if val == "VERTICAL" then
                val = "VERTICAL_DOWN"
            end
            return val
        end,
        setValue = ConfSetter("pipOrientation", SmoothRefresh, true),
    })
    posY = posY - hgt
    -- Class Resource cog: Simple only (Hide Power Bar if Resource is a row of
    -- the Bar Display page's BAR SHIFTING section)
    if not context.advanced then
        if not CludesUI._prebuilding then
            local rgn = classEnableRow._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                disabled = classOff,
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
                            local c = conf()
                            if not c then
                                return
                            end
                            c.raiseLevel = val and true or false
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
        AddFormBarBtn(classEnableRow._leftRegion, conf, RebuildClass)
    end

    -- Everything below Row 1 is hidden entirely while the bar is off. classColorRow is
    -- hoisted above the gate: the section returns it for the Simple page's count-text
    -- click mapping (nil while hidden).
    local classColorRow
    if not classOff() then
        -- Row 2: Height | Width (MatchGuard in both modes, sync icons Simple-only).
        -- Orientation-aware: this bar has its OWN orientation key and its renderer treats
        -- anything not HORIZONTAL as vertical, so the value is normalized before the shared helper sees it.
        local function classOri()
            local c = conf()
            local o = (c and c.pipOrientation) or "HORIZONTAL"
            return o ~= "HORIZONTAL" and "VERTICAL_UP" or "HORIZONTAL"
        end
        local function classGuard(propKey)
            return mod.OrientedMatchGuard("ERB_ClassResource", propKey, classOri, classOff, "Class Resource")
        end
        local chDis, chTip, chRaw = classGuard("Height")
        local cwDis, cwTip, cwRaw = classGuard("Width")
        local classSizeRow
        classSizeRow, hgt = W:DualRow(hostFrame, posY, {
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
        posY = posY - hgt
        if not context.advanced and context.syncRows then
            context.syncRows.classHeight = classSizeRow._leftRegion
            context.syncRows.classWidth = classSizeRow._rightRegion
            if not CludesUI._prebuilding then
                local rgn = classSizeRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = "Apply Height to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local val = p.secondary.pipHeight or 20
                        p.primary.height = val
                        p.health.height = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local val = p.secondary.pipHeight or 20
                        return (p.primary.height or 16) == val and (p.health.height or 20) == val
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
                local rgn = classSizeRow._rightRegion
                CludesUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = "Apply Width to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local totalW = p.secondary.pipWidth or 214
                        p.primary.width = totalW
                        p.health.width = totalW
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local totalW = p.secondary.pipWidth or 214
                        return (p.primary.width or 220) == totalW and (p.health.width or 220) == totalW
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
            classBsRow, hgt = W:DualRow(
                hostFrame,
                posY,
                CludesUI.BlizzStyle.Gate("resourcebars", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = classOff,
                    disabledTooltip = "Class Resource",
                    values = texValues,
                    order = texOrder,
                    getValue = ConfGetter("borderTexture", "solid"),
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
                        RebuildClass()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                mod.ERB_ClassicBorderRow()
                        and mod.ERB_ClassicBorderSizeCfg(
                            conf,
                            classOff,
                            "Class Resource",
                            RebuildClass,
                            "ERB_ClassResource"
                        )
                    or CludesUI.BlizzStyle.Gate(
                        "resourcebars",
                        CludesUI.BorderPxSliderCfg({
                            text = "Border Size",
                            disabled = classOff,
                            disabledTooltip = "Class Resource",
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
                                RebuildClass()
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
                        disabled = classOff,
                        disabledTooltip = "Class Resource",
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
                            RebuildClass()
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
            if not context.advanced and context.syncRows then
                context.syncRows.classBorder = classBsRow._rightRegion
            end
            if not CludesUI._prebuilding and not mod.ERB_ClassicBorderRow() then
                local rgn = classBsRow._rightRegion
                local ctrl = rgn._control
                -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
                -- border size control. The stock styles keep the bars square.
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(classBsRow._rightRegion, {
                        title = "Corner Radius",
                        tip = "Corner Radius",
                        disabled = function()
                            if classOff() or CludesUI.BlizzStyle.Get("resourcebars") then
                                return true
                            end
                            local c = conf()
                            return not CludesUI.RoundedStyleOK(c and c.borderTexture)
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("resourcebars") then
                                return CludesUI.BlizzStyle.Label("resourcebars")
                            end
                            if classOff() then
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
                            local c = conf()
                            return c and c.cornerMask
                        end, function(val)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.cornerMask = val
                            RebuildClass()
                        end),
                    })
                end
                local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    classBsRow:GetFrameLevel() + 3,
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
            end
            if not CludesUI._prebuilding then
                local rgn = classBsRow._leftRegion
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
                                RebuildClass()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = ConfGetter("borderBehind", false),
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.borderBehind = val == false and nil or val
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
                                local c = conf()
                                return (c and c.borderOnPips and not mod.IsBarTypeSecondary()) and true
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
                                local c = conf()
                                return (c and c.borderOnPips and not mod.IsBarTypeSecondary()) and true
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
                                local c = conf()
                                return (c and c.borderOnPips and not mod.IsBarTypeSecondary()) and true
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
                                local c = conf()
                                return (c and c.borderOnPips and not mod.IsBarTypeSecondary()) and true
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
                                RebuildClass()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Horizontal Separator",
                            tooltip = "Draws the line along the bar's bottom edge.",
                            disabled = function()
                                local c = conf()
                                return not (c and c.edgeSep)
                            end,
                            disabledTooltip = "Separators",
                            get = function()
                                local c = conf()
                                return c and c.edgeSepH ~= false
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.edgeSepH = val and true or false
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
                                local c = conf()
                                return not (c and c.edgeSep and c.edgeSepH ~= false)
                            end,
                            disabledTooltip = function()
                                local c = conf()
                                return (c and c.edgeSep) and "Horizontal Separator" or "Separators"
                            end,
                            get = ConfGetter("edgeSepY", 0),
                            set = ConfSetter("edgeSepY", RebuildClass, true),
                        },
                        {
                            type = "toggle",
                            label = "Vertical Separators",
                            tooltip = "Draws a line in each gap between the pips.",
                            disabled = function()
                                local c = conf()
                                return (not (c and c.edgeSep)) or mod.IsBarTypeSecondary()
                            end,
                            disabledTooltip = function()
                                local c = conf()
                                if not (c and c.edgeSep) then
                                    return "Separators"
                                end
                                return "This option applies to pip and rune resources only."
                            end,
                            rawTooltip = function()
                                local c = conf()
                                return (c and c.edgeSep) and true or false
                            end,
                            get = function()
                                local c = conf()
                                return c and c.edgeSepV ~= false
                            end,
                            set = function(val)
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.edgeSepV = val and true or false
                                RebuildClass()
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
                        local p = DB()
                        if not p then
                            return
                        end
                        local was = mod.ERB_TexturedBars(p)
                        local s = p.secondary
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
                        apply(p.primary)
                        apply(p.health)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(p) ~= was)
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local bt = p.secondary.borderTexture or "solid"
                        local bh = p.secondary.borderBehind or false
                        return (p.primary.borderTexture or "solid") == bt
                            and (p.health.borderTexture or "solid") == bt
                            and (p.primary.borderBehind or false) == bh
                            and (p.health.borderBehind or false) == bh
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
                        local p = DB()
                        if not p then
                            return
                        end
                        local was = mod.ERB_TexturedBars(p)
                        local r, g, b, a =
                            p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA
                        local sz = p.secondary.borderSize or 1
                        local bt = p.secondary.borderTexture or "solid"
                        local cr, cm = p.secondary.cornerRadius or 0, p.secondary.cornerMask
                        p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA =
                            r, g, b, a
                        p.primary.borderSize = sz
                        p.primary.borderTexture = bt
                        p.primary.cornerRadius = cr
                        p.primary.cornerMask = cm
                        mod.ERB_CopyBorderPx(p.primary, p.secondary)
                        p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                        p.health.borderSize = sz
                        p.health.borderTexture = bt
                        p.health.cornerRadius = cr
                        p.health.cornerMask = cm
                        mod.ERB_CopyBorderPx(p.health, p.secondary)
                        SmoothRefresh()
                        CludesUI:RefreshPage(mod.ERB_TexturedBars(p) ~= was)
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local sr, sg, scrollBar, sa, ssz =
                            p.secondary.borderR,
                            p.secondary.borderG,
                            p.secondary.borderB,
                            p.secondary.borderA,
                            p.secondary.borderSize or 1
                        local sbt, scr, scm =
                            p.secondary.borderTexture or "solid",
                            p.secondary.cornerRadius or 0,
                            p.secondary.cornerMask or 15
                        local function eq(t)
                            return t.borderR == sr
                                and t.borderG == sg
                                and t.borderB == scrollBar
                                and t.borderA == sa
                                and (t.borderSize or 1) == ssz
                                and (t.borderTexture or "solid") == sbt
                                and (t.cornerRadius or 0) == scr
                                and (t.cornerMask or 15) == scm
                                and mod.ERB_SameBorderPx(t, p.secondary)
                        end
                        return eq(p.primary) and eq(p.health)
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
                local rgn = classBsRow._leftRegion
                local lastInline = rgn._lastInline or rgn._control
                local cogBtn = CludesUI.BuildInlineCog(rgn, {
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
                                local c = conf()
                                return (not (c and c.borderOnPips)) or mod.IsBarTypeSecondary()
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
                                local c = conf()
                                if not c then
                                    return
                                end
                                c.pipBgOnPips = val and true or false
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
                    local c = conf()
                    local texture = c and c.borderTexture or "solid"
                    if texture == "solid" then
                        Pix.Point(cogBtn, "RIGHT", rgn._control, "LEFT", -8, 0)
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
            classGapRow, hgt = W:DualRow(hostFrame, posY, {
                type = "slider",
                pixel = true,
                text = "Bar Spacing",
                min = 0,
                max = 20,
                step = 1,
                disabled = classOff,
                disabledTooltip = "Class Resource",
                getValue = ConfGetter("pipSpacing", 3),
                setValue = ConfSetter("pipSpacing", SmoothRefresh),
            }, {
                type = "slider",
                text = "Empty Bar Overlay",
                min = 0,
                max = 100,
                step = 5,
                disabled = classOff,
                disabledTooltip = "Class Resource",
                getValue = function()
                    local c = conf()
                    return math.floor(((c and c.bgA) or 0.1) * 100 + 0.5)
                end,
                setValue = function(val)
                    local c = conf()
                    if not c then
                        return
                    end
                    c.bgA = val / 100
                    RefreshClass()
                    CludesUI:RefreshPage()
                end,
            })
            posY = posY - hgt
            -- Bar Spacing inline enable toggle + gap-color swatch
            if not CludesUI._prebuilding then
                local rgn = classGapRow._leftRegion
                local ctrl = rgn._control
                local gapSwatch, updateGapSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    classGapRow:GetFrameLevel() + 3,
                    function()
                        local c = conf()
                        return (c and c.gapR or 0),
                            (c and c.gapG or 0),
                            (c and c.gapB or 0),
                            (c and c.gapA or 1)
                    end,
                    function(r, g, b, a)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.gapR, c.gapG, c.gapB, c.gapA = r, g, b, a
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    true,
                    20
                )
                Pix.Point(gapSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
                rgn._lastInline = gapSwatch
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
                    local c = conf()
                    if c and c.gapColorEnabled then
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
                    region = rgn,
                    getValue = ConfGetter("gapColorEnabled"),
                    setValue = function(val)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.gapColorEnabled = val and true or nil
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                })
            end
            -- Empty Bar Overlay inline color swatch (RGB only)
            if not CludesUI._prebuilding then
                local rgn = classGapRow._rightRegion
                local ctrl = rgn._control
                local ovSwatch, updateOvSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    classGapRow:GetFrameLevel() + 3,
                    function()
                        local c = conf()
                        return (c and c.bgR or 1), (c and c.bgG or 1), (c and c.bgB or 1), 1
                    end,
                    function(r, g, b)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.bgR, c.bgG, c.bgB = r, g, b
                        RefreshClass()
                        CludesUI:RefreshPage()
                    end,
                    false,
                    20
                )
                Pix.Point(ovSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    updateOvSwatch()
                end)
            end
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local classBorderRow
        classBorderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 5,
            disabled = classOff,
            disabledTooltip = "Class Resource",
            getValue = function()
                local c = conf()
                return math.floor(((c and c.barAlpha) or 1) * 100 + 0.5)
            end,
            setValue = function(val)
                local c = conf()
                if not c then
                    return
                end
                c.barAlpha = val / 100
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
            disabled = classOff,
            disabledTooltip = "Class Resource",
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
                RebuildClass()
                SmoothRefresh()
            end,
        })
        posY = posY - hgt
        -- Fill Color inline cog: Charged Combo Point color
        if not CludesUI._prebuilding then
            local rgn = classBorderRow._rightRegion
            CludesUI.BuildInlineCog(rgn, {
                disabled = classOff,
                disabledTooltip = "Class Resource",
                title = "Fill Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Darken Partially Filled Resources",
                        tooltip = "Makes partially filled Soul Shards and Essence darker than completed ones.",
                        get = function()
                            local c = conf()
                            return c and c.darkenPartialPips ~= false
                        end,
                        set = ConfSetter("darkenPartialPips", RefreshClass),
                    },
                    {
                        type = "colorpicker",
                        label = "Charged Color",
                        hasAlpha = false,
                        get = function()
                            local c = conf()
                            if not c then
                                return 0.44, 0.77, 1.00, 1
                            end
                            return c.chargedR or 0.44, c.chargedG or 0.77, c.chargedB or 1.00, c.chargedA or 1
                        end,
                        set = function(cr, cg, cb, ca)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.chargedR, c.chargedG = cr, cg
                            c.chargedB, c.chargedA = cb, ca
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
                        local c = conf()
                        if not c then
                            return 0xDB / 255, 0xCF / 255, 0x37 / 255, 1
                        end
                        return c.fillR, c.fillG, c.fillB, 1
                    end,
                    setValue = function(r, g, b)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.fillR, c.fillG, c.fillB = r, g, b
                        RebuildClass()
                        SmoothRefresh()
                    end,
                    onClick = function(self)
                        local c = conf()
                        if not c then
                            return
                        end
                        local inCustom = (not c.resourceColored) and (c.classColored == false)
                        if not inCustom then
                            -- false, never nil: a removed key harvests into
                            -- spec overrides as a key-removal marker the apply
                            -- guard can never re-apply (the soul-bar colour
                            -- revert); the runtime only tests truthiness, so
                            -- false is behaviourally identical.
                            c.resourceColored = false
                            c.classColored = false
                            RebuildClass()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local inCustom = c and not c.resourceColored and (c.classColored == false)
                        return inCustom and 1 or 0.3
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
                        return 1, 0.82, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local c = conf()
                        if not c then
                            return
                        end
                        c.resourceColored = false -- false, never nil (see Custom swatch)
                        c.classColored = true
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        local isClassMode = c and not c.resourceColored and (c.classColored ~= false)
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
                        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if cc then
                            return cc.r, cc.g, cc.b, 1
                        end
                        return 1, 0.82, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local c = conf()
                        if not c then
                            return
                        end
                        c.resourceColored = true
                        c.classColored = true
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = conf()
                        return (c and c.resourceColored) and 1 or 0.3
                    end,
                },
            }, {
                size = 20,
                disabled = function()
                    local c = conf()
                    return (not c) or not c.enabled or c.darkTheme
                end,
                disabledTooltip = function()
                    local c = conf()
                    if c and c.darkTheme then
                        return "This option requires Class Resource Bar Dark Mode to be off. Dark Mode colors can be adjusted in Global Settings -> Colors."
                    end
                    return "Class Resource"
                end,
            })
        end
        if not context.advanced and context.syncRows then
            context.syncRows.classOpacity = classBorderRow._leftRegion
            if not CludesUI._prebuilding then
                local rgn = classBorderRow._leftRegion
                CludesUI.BuildSyncIcon({
                    region = rgn,
                    tooltip = "Apply Opacity to all Bars",
                    onClick = function()
                        local p = DB()
                        if not p then
                            return
                        end
                        local val = p.secondary.barAlpha or 1
                        p.primary.barAlpha = val
                        p.health.barAlpha = val
                        SmoothRefresh()
                        CludesUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        local val = p.secondary.barAlpha or 1
                        return (p.primary.barAlpha or 1) == val and (p.health.barAlpha or 1) == val
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
            local rgn = classBorderRow._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                disabled = function()
                    local c = conf()
                    return c and not c.enabled
                end,
                disabledTooltip = "Class Resource",
                title = "Out of Combat Opacity",
                rows = {
                    {
                        type = "toggle",
                        label = "Fade Out of Combat",
                        get = function()
                            local c = conf()
                            return c and c.oocFadeEnabled == true
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
            local c = conf()
            if not c then
                return nil
            end
            return { secondary = c }
        end

        -- Row 5: Resource Text | Threshold & Hash Lines
        classColorRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Resource Text",
            disabled = classOff,
            disabledTooltip = "Class Resource",
            getValue = function()
                local p = DB()
                return p and p.secondary.showText
            end,
            setValue = function(val)
                local p = DB()
                if not p then
                    return
                end
                p.secondary.showText = val
                RebuildClass()
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "Threshold & Hash Lines" })
        posY = posY - hgt
        -- Resource Text inline cog: size + position
        if not CludesUI._prebuilding then
            local rgn = classColorRow._leftRegion
            local resTextRows = {
                {
                    type = "toggle",
                    label = "Show %",
                    get = function()
                        local p = DB()
                        return (not p) or p.secondary.showPercent ~= false
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.showPercent = val
                        RefreshClass()
                    end,
                },
                {
                    type = "toggle",
                    label = "Only if Power Bar Hidden",
                    tooltip = 'Show the resource text only while the power bar is hidden - disabled, filtered off for this spec, a spec with no power, or hidden by "Hide Power Bar if Resource". Off = always show the text.',
                    get = function()
                        local p = DB()
                        return p and p.secondary.showTextOnlyIfNoPower
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.showTextOnlyIfNoPower = val
                        RebuildClass()
                    end,
                },
                {
                    type = "toggle",
                    label = "Hide at Zero",
                    tooltip = "Hide the resource text while the resource is at zero.",
                    get = function()
                        local p = DB()
                        return p and p.secondary.hideTextAtZero
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        -- Rebuild: the build path installs or removes the filter.
                        p.secondary.hideTextAtZero = val
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
                        local p = DB()
                        return p and p.secondary.textSize or 11
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.textSize = val
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
                        local p = DB()
                        return p and p.secondary.textAnchor or "CENTER"
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.textAnchor = val
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
                        local p = DB()
                        return p and p.secondary.textXOffset or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.textXOffset = val
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
                        local p = DB()
                        return p and p.secondary.textYOffset or 0
                    end,
                    set = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.textYOffset = val
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
                            local p = DB()
                            return (not p) or p.secondary.showMaxStacks ~= false
                        end,
                        set = function(val)
                            local p = DB()
                            if not p then
                                return
                            end
                            p.secondary.showMaxStacks = val
                            RefreshClass()
                        end,
                    })
                end
            end
            CludesUI.BuildInlineCog(rgn, {
                disabled = function()
                    local p = DB()
                    return not p or not p.secondary.enabled or not p.secondary.showText
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
            local rgn = classColorRow._leftRegion
            local ctrl = rgn._control
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                rgn,
                classColorRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    if not p then
                        return 1, 1, 1, 1
                    end
                    return p.secondary.textR or 1, p.secondary.textG or 1, p.secondary.textB or 1, 1
                end,
                function(r, g, b)
                    local p = DB()
                    if not p then
                        return
                    end
                    p.secondary.textR, p.secondary.textG, p.secondary.textB = r, g, b
                    RefreshClass()
                end,
                false,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = colorSwatch
            local swatchDis = CludesUI.NewSwatchBlocker(colorSwatch)
            swatchDis:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip("Resource Text"))
            end)
            swatchDis:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateSwatchDis()
                updateSwatch()
                local p = DB()
                local off = not p or not p.secondary.enabled or not p.secondary.showText
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
            AddFormTextBtn(rgn, colorSwatch, function()
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
                getBarData = conf,
                -- The page appends an "Anchor to Cursor" row after this section, so the editor covers one row more
                pageParent = hostFrame,
                pageTopY = _advTop,
                pageBotY = function()
                    return posY
                end,
                pageBotExtra = 50,
                refreshFn = RefreshClass,
                rebuildFn = RebuildClass,
                swatchRefreshFn = SmoothRefresh,
                disabledFn = classOff,
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
                newEntry = function(ids, c)
                    local isBar = mod.IsSpecBarType(ids[1])
                    local enhAdd = false
                    if c.enhanceFiveBar then
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
                        thresholdCount = enhAdd and 7 or (isBar and 30 or 3),
                        thresholdPartialOnly = false,
                        thresholdR = c.thresholdR or 0x0c / 255,
                        thresholdG = c.thresholdG or 0xd2 / 255,
                        thresholdB = c.thresholdB or 0x9d / 255,
                        thresholdA = c.thresholdA or 1,
                    }
                    -- Default for "Threshold color below value": the only bar-type spender class resource is Hunter
                    -- Focus, so it starts ON (warn when low); builders (Maelstrom/Insanity/Astral) start OFF.
                    -- Only when the entry covers the current spec (resource readable).
                    if isBar then
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
                        local function isBar()
                            local e = current()
                            return (e and mod.IsEntryBarType(e)) and true or false
                        end
                        local function isStagger()
                            return HasSpec(current(), 268)
                        end
                        local function isEnhance()
                            local c = conf()
                            return (c and c.enhanceFiveBar == true and HasSpec(current(), 263)) and true
                                or false
                        end
                        local function enabled()
                            local e = current()
                            if not e then
                                return false
                            end
                            local val = e.thresholdEnabled
                            if val == nil then
                                val = true
                            end
                            return val
                        end
                        local function multiOn()
                            local e = current()
                            return (e and e.multiBandEnabled and not isEnhance()) and true or false
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
                            local e = current()
                            return (e and e.thresholdReverse) and true or false
                        end
                        local function isWarrCharge()
                            -- Arms/Fury class-bar thresholds render on the engine-fed
                            -- Whirlwind/Sweeping Strikes charge bar, whose only
                            -- threshold display is range coloring at/above the count
                            -- (no Lua count exists to flip the whole fill).
                            if (select(2, UnitClass("player"))) ~= "WARRIOR" then
                                return false
                            end
                            local e = current()
                            local ids = e and e.specIDs
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
                                    return (not usable()) or (not isBar()) or isStagger()
                                end,
                                disabledTooltip = function()
                                    if not usable() then
                                        return offTip()
                                    end
                                    if not isBar() then
                                        return "This option applies to bar-type resources only (pips use stack counts)."
                                    end
                                    return STAGGER_PCT_TIP
                                end,
                                get = function()
                                    local e = current()
                                    return (e and e.thresholdMode) or "percent"
                                end,
                                set = function(val)
                                    local e = current()
                                    if not e then
                                        return
                                    end
                                    e.thresholdMode = val
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
                                    local e = current()
                                    return (e and e.thresholdReverse) and "upto" or "from"
                                end,
                                set = function(val)
                                    local e = current()
                                    if not e then
                                        return
                                    end
                                    e.thresholdReverse = (val == "upto")
                                    changed()
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Only color at/above threshold",
                                rawTooltip = true,
                                disabled = function()
                                    return (not usable()) or isBar() or isUpTo() or isWarrCharge()
                                end,
                                disabledTooltip = function()
                                    if isWarrCharge() and usable() then
                                        return "Always on for Whirlwind and Sweeping Strikes charges: range coloring at/above the threshold is the only way these bars can display thresholds."
                                    end
                                    if not usable() then
                                        return offTip()
                                    end
                                    if isBar() then
                                        return "This option applies to pip-type resources only."
                                    end
                                    return "Only available with the 'From' direction -- it highlights the pips at/above the threshold."
                                end,
                                get = function()
                                    if isWarrCharge() then
                                        return true
                                    end
                                    local e = current()
                                    return (e and e.thresholdPartialOnly) and true or false
                                end,
                                set = function(val)
                                    local e = current()
                                    if not e then
                                        return
                                    end
                                    e.thresholdPartialOnly = val
                                    changed()
                                end,
                            },
                        }
                    end,
                },

                -- Per-entry rules, keyed off the SELECTED entry's specs rather than the live spec, so
                -- editing another spec's entry while playing that spec stays unlocked
                entryRules = function(ent, r, c)
                    local isBar = mod.IsEntryBarType(ent)
                    local isGuardian, isIgnorePain, isVengeance, isStagger, isEnhance
                    if ent.specIDs then
                        for _, s in ipairs(ent.specIDs) do
                            -- WoW Forever: the Druid class resource there is combo points, which
                            -- draw the card's hash lines, so the Ironfur bar exception is retail only.
                            -- Retail keeps the row while the card holds hash lines, so lines saved
                            -- on WoW Forever can be cleared.
                            if
                                s == 104
                                and not CludesUI.IS_FOREVER
                                and (ent.hashValues == nil or ent.hashValues == "")
                            then
                                isGuardian = true
                            end
                            if s == 73 then
                                isIgnorePain = true
                            end
                            if s == 581 then
                                isVengeance = true
                            end
                            if s == 268 then
                                isStagger = true
                            end
                            if s == 263 and c.enhanceFiveBar == true then
                                isEnhance = true
                            end
                        end
                    end
                    -- Brewmaster stagger reads its threshold as a percent only
                    if isStagger and ent.thresholdMode == "value" then
                        ent.thresholdMode = "percent"
                    end
                    -- Bar-type reads the threshold as % (max 100) or an absolute value (higher cap); pips count stacks
                    local isValue = isBar and not isStagger and ent.thresholdMode == "value"
                    r.pips = not isBar
                    -- The Guardian Ironfur and Prot Ignore Pain bars draw their own hash lines
                    r.hideHash = (isGuardian or isIgnorePain) and true or false
                    r.thrMin = isEnhance and 7 or 1
                    r.thrMax = isStagger and 500 or (isBar and (isValue and 1000 or 100) or 20)
                    r.thrDef = isEnhance and 7 or (isBar and 30 or 3)
                    r.thrLabel = CludesUI.L("Threshold") .. ((isBar and not isValue) and " %" or "")
                    if isEnhance then
                        r.thrTip = CludesUI.L(
                            "Enhance 5 Bar minimum is %d (if you want less just change 5 bar color)"
                        )
                            :format(7)
                        r.multiBlock = CludesUI.L("Unavailable with Enhancement 5-bar style.")
                    end
                    r.bandPctCap = isStagger and 500 or nil
                    -- "Recolor text instead" no-ops for secret resources (Vengeance soul fragments, Prot Ignore Pain bar)
                    if isVengeance or (isIgnorePain and c.protIgnorePainBar) then
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
                simpleRuneRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Custom Recharge Color",
                    tooltip = "Choose the color of recharging runes instead of a dimmed version of the rune color.",
                    disabled = classOff,
                    disabledTooltip = "Class Resource",
                    getValue = ConfGetter("runesCustomRecharge"),
                    setValue = ConfSetter("runesCustomRecharge", RebuildClass, true),
                }, {
                    type = "toggle",
                    text = "Simple Runes",
                    tooltip = "Show rune count in center and remove recharge text/animation",
                    disabled = classOff,
                    disabledTooltip = "Class Resource",
                    getValue = ConfGetter("runesSimple"),
                    setValue = ConfSetter("runesSimple", RebuildClass),
                })
                posY = posY - hgt
                -- Custom recharge color inline swatch
                if not CludesUI._prebuilding then
                    local rgn = simpleRuneRow._leftRegion
                    local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                        rgn,
                        simpleRuneRow:GetFrameLevel() + 3,
                        function()
                            local c = conf()
                            if not c then
                                return 0.5, 0.5, 0.5, 1
                            end
                            return c.runesRechargeR or 0.5,
                                c.runesRechargeG or 0.5,
                                c.runesRechargeB or 0.5,
                                c.runesRechargeA or 1
                        end,
                        function(r, g, b, a)
                            local c = conf()
                            if not c then
                                return
                            end
                            c.runesRechargeR = r
                            c.runesRechargeG = g
                            c.runesRechargeB = b
                            c.runesRechargeA = a
                            SmoothRefresh()
                        end,
                        true,
                        20
                    )
                    colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = colorSwatch
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
                        local c = conf()
                        local off = not (c and c.enabled) or not c.runesCustomRecharge
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
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Show Focus as Power Bar (BM/MM)",
                    tooltip = "When enabled, BM and MM specs show Focus as the standard power bar instead of a class resource bar.",
                    getValue = function()
                        local p = DB()
                        if not p then
                            return false
                        end
                        return p.secondary.hunterFocusAsPower or false
                    end,
                    setValue = function(val)
                        local p = DB()
                        if not p then
                            return
                        end
                        p.secondary.hunterFocusAsPower = val
                        RebuildPower()
                        RebuildClass()
                        CludesUI:RefreshPage()
                    end,
                }, { type = "label", text = "" })
                posY = posY - hgt
            end
            -- Retail only: WoW Forever has no Enhancement spec.
            if playerClass == "SHAMAN" and not CludesUI.IS_FOREVER then
                -- Enhance 5-bar applies to Enhancement (specID 263) only, gated on the active spec
                local function _enhSpecOK()
                    return C_SpecializationInfo.GetSpecialization() == 2
                end
                local enhRow
                enhRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Enhance 5 Bar Style",
                    disabled = function()
                        local c = conf()
                        return not (c and c.enabled) or not _enhSpecOK()
                    end,
                    disabledTooltip = "Requires Enhancement Shaman with Class Resource enabled.",
                    rawTooltip = true,
                    getValue = ConfGetter("enhanceFiveBar"),
                    setValue = ConfSetter("enhanceFiveBar", RebuildClass, true),
                }, { type = "label", text = "" })
                posY = posY - hgt
                -- Overflow color inline swatch
                if not CludesUI._prebuilding then
                    local rgn = enhRow._leftRegion
                    local colorSwatch = CludesUI.BuildColorSwatch(rgn, enhRow:GetFrameLevel() + 3, function()
                        local c = conf()
                        if not c then
                            return 1, 0.6, 0.2, 1
                        end
                        return c.enhanceOverflowR or 1,
                            c.enhanceOverflowG or 0.6,
                            c.enhanceOverflowB or 0.2,
                            1
                    end, function(r, g, b)
                        local c = conf()
                        if not c then
                            return
                        end
                        c.enhanceOverflowR = r
                        c.enhanceOverflowG = g
                        c.enhanceOverflowB = b
                        SmoothRefresh()
                    end, false, 20)
                    colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = colorSwatch
                    local function UpdateEnhSwatchVis()
                        local c = conf()
                        local off = not (c and c.enabled) or not c.enhanceFiveBar or not _enhSpecOK()
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
        mod.ERB_SimpleOverrideOverlay(hostFrame, _advTop, posY, "secondary")
    end

    -- Blizzard Class Resource Art stands in for this bar: block the styling rows above.
    mod.ERB_BlizzArtBlockRegions(artRegions)

    -- Header + row frames go back so the Simple page can wire its preview click-mappings (classSection/classEnableRow, and the Resource Text row for the count-text overlay).
    return posY, heading, classEnableRow, classColorRow, unlockJump
end
--- [class resource end]
