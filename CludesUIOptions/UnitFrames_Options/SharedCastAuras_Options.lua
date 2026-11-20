if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\SharedCastAuras_Options.lua
--  Unit Frames options: Cast Bar and Buffs and Debuffs sections of the
--  shared (player/target/focus) settings. Definitions only; shared helpers
--  come from ns._UFO_OptEnv, the page accessors from ctx (both filled by
--  CUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIUnitFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept page go through the
-- options frame pool (CludesUI_FramePool.lua), which hands the next build
-- the previous build's frames reset to new; on any other parent it is the
-- plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- A cast text's sync icon: its size (default when unset), its colour when the
-- selected frame has one of its own, and fitKey's toggle when given. Frames
-- agree when sizes and toggles match and both colours match or both are unset.
local function CastTextSync(region, label, sizeKey, sizeDefault, colorKey, fitKey)
    mod.UFO_UnitSync(region, label, {
        self = true,
        copy = function(tbl, from)
            tbl[sizeKey] = from[sizeKey] or sizeDefault
            if fitKey then
                tbl[fitKey] = from[fitKey] == true or nil
            end
            local color = from[colorKey]
            if color then
                tbl[colorKey] = { r = color.r, g = color.g, b = color.b }
            end
        end,
        same = function(tbl, from)
            local a, b = tbl[colorKey], from[colorKey]
            if a and b then
                if a.r ~= b.r or a.g ~= b.g or a.b ~= b.b then
                    return false
                end
            elseif a ~= b then
                return false
            end
            return (tbl[sizeKey] or sizeDefault) == (from[sizeKey] or sizeDefault)
                and (not fitKey or (tbl[fitKey] == true) == (from[fitKey] == true))
        end,
    })
end

function mod.UFO_BuildCastBarSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local GROUP_UNIT_ORDER, Pix, RegisterWidgetRefresh, ReloadAndUpdate =
        environ.GROUP_UNIT_ORDER, environ.PP, environ.RegisterWidgetRefresh, environ.ReloadAndUpdate
    local SHORT_LABELS, UF_ImpCastGlowDesc, UNIT_DB_MAP, UpdatePreview =
        environ.SHORT_LABELS, environ.UF_ImpCastGlowDesc, environ.UNIT_DB_MAP, environ.UpdatePreview
    local saved, optionState = environ.db, environ.optState
    local W, SGetSupported, SSetSupported, SVal =
        context.W, context.SGetSupported, context.SSetSupported, context.SVal
    -- Row setters over SSetSupported: the key written with the row's value, then ReloadAndUpdate() and UpdatePreview() for the Then form.
    local function SSetSupportedRowThen(key)
        return function(value)
            SSetSupported(key, value)
            ReloadAndUpdate()
            UpdatePreview()
        end
    end
    local SValSupported = context.SValSupported
    -- A row getter over SValSupported: the key's value, or the default given.
    local function SValSupportedRow(key, default)
        return function()
            return SValSupported(key, default)
        end
    end
    local height

    -------------------------------------------------------------------
    --  CAST BAR
    -------------------------------------------------------------------
    local sharedCastHeader
    sharedCastHeader, height = W:SectionHeader(hostFrame, "CAST BAR", cursorY)
    cursorY = cursorY - height

    -- Helper: get/set castbar visibility per unit
    local function GetCastbarEnabled(unitKey)
        if unitKey == "player" then
            return UNIT_DB_MAP.player().showPlayerCastbar or false
        else
            return UNIT_DB_MAP[unitKey]().showCastbar ~= false
        end
    end
    local function SetCastbarEnabled(unitKey, val)
        if unitKey == "player" then
            UNIT_DB_MAP.player().showPlayerCastbar = val
        else
            UNIT_DB_MAP[unitKey]().showCastbar = val
        end
    end

    -- Height getter/setter: player -> playerCastbarHeight, target/focus -> castbarHeight
    local function GetCastbarHeight()
        local u = optionState.selectedUnit
        if u == "player" then
            local value = UNIT_DB_MAP.player().playerCastbarHeight or 0
            return (value <= 0) and 14 or value
        else
            return UNIT_DB_MAP[u]().castbarHeight or 14
        end
    end
    local function SetCastbarHeight(value)
        if optionState.selectedUnit == "player" then
            UNIT_DB_MAP.player().playerCastbarHeight = value
        else
            UNIT_DB_MAP[optionState.selectedUnit]().castbarHeight = value
        end
    end

    -- The Move in Unlock Mode button on the cast bar's section: the selected
    -- unit's own cast bar mover, whose Show Cast Bar toggle opens the section.
    CludesUI.BuildSectionUnlockJump(sharedCastHeader, {
        key = function()
            return optionState.selectedUnit .. "Castbar"
        end,
        disabled = function()
            return not GetCastbarEnabled(optionState.selectedUnit)
        end,
        disabledTooltip = "Show Cast Bar",
    })

    -- Player-only hint: this is the compact mini cast bar under the player frame;
    -- the full-size one belongs to Resource & Cast Bars, deep-linked here. The page
    -- fully rebuilds on unit change, so gating on selectedUnit re-evaluates per unit.
    if optionState.selectedUnit == "player" then
        local accR, accG, accB = CludesUI.GetAccentColor()
        accR, accG, accB = accR or 76 / 255, accG or 201 / 255, accB or 240 / 255
        local accentHex = CludesUI.HexColor(accR, accG, accB)
        local hintText = CludesUI.Lf(
            "For player frame, this provides a simple, mini castbar below player frame. To edit the main player cast bar, %sclick here|r",
            accentHex
        )
        -- Full-width label (nil right slot expands the left region) renders text
        -- through the panel's own widget path; a transparent button over the row
        -- click-throughs to Resource & Cast Bars > Cast Bar (accent "click here").
        local hintRow
        hintRow, height = W:DualRow(hostFrame, cursorY, { type = "label", text = hintText }, nil) -- cui-style: allow dualrow-nil
        if not CludesUI._prebuilding then
            -- Labels are single-line by default; wrap this hint inside the full-width
            -- row so "click here" stays on screen.
            local labelFS = hintRow._leftRegion and hintRow._leftRegion._label
            if labelFS then
                labelFS:SetJustifyH("LEFT")
                labelFS:SetWordWrap(true)
                local rw = hintRow._leftRegion:GetWidth()
                if not rw or rw < 80 then
                    rw = 300
                end
                labelFS:SetWidth(rw - 40)
            end
            local clickRgn = hintRow._leftRegion or hintRow
            local linkBtn = CreateFrame("Button", nil, clickRgn)
            linkBtn:SetAllPoints(clickRgn)
            linkBtn:SetFrameLevel(clickRgn:GetFrameLevel() + 5)
            linkBtn:SetScript("OnClick", function()
                CludesUI:NavigateToElementSettings("CludesUIResourceBars", "Cast Bar")
            end)
            linkBtn:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, "Open Resource & Cast Bars > Cast Bar")
            end)
            linkBtn:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        cursorY = cursorY - height
    end

    -- Row 1: Show Cast Bar (toggle + fill swatch) | Height (slider). This row and
    -- the player hint stay visible while the cast bar is off; the rows below hide
    -- entirely. Height composes the castbar-off disable into the size-match guard.
    local sharedCastRow1
    local cbKey = optionState.selectedUnit .. "Castbar"
    local cbhDis, cbhTip, cbhRaw = CludesUI.MatchGuard(cbKey, "Height", function()
        return not GetCastbarEnabled(optionState.selectedUnit)
    end, "Show Cast Bar")
    sharedCastRow1, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Cast Bar",
        getValue = function()
            return GetCastbarEnabled(optionState.selectedUnit)
        end,
        -- DependentSetValue: rows below Row 1 hide while the cast bar is off,
        -- so the toggle flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return GetCastbarEnabled(optionState.selectedUnit)
        end, function(value)
            SetCastbarEnabled(optionState.selectedUnit, value)
            ReloadAndUpdate()
            UpdatePreview()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "slider",
        text = "Height",
        min = 1,
        max = 40,
        step = 1,
        disabled = cbhDis,
        disabledTooltip = cbhTip,
        rawTooltip = cbhRaw,
        getValue = GetCastbarHeight,
        setValue = function(value)
            SetCastbarHeight(value)
            ReloadAndUpdate()
            UpdatePreview()
        end,
    })
    cursorY = cursorY - height
    -- Sync icon: Show Cast Bar + Fill Color (left region)
    if not CludesUI._prebuilding then
        local region = sharedCastRow1._leftRegion
        local isKickUnit = optionState.selectedUnit == "target" or optionState.selectedUnit == "focus"
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = isKickUnit and "Apply Show Cast Bar and Cast Color to Target and Focus"
                or "Apply Show Cast Bar and Fill Color to all Frames",
            onClick = function()
                local value = GetCastbarEnabled(optionState.selectedUnit)
                local color = UNIT_DB_MAP[optionState.selectedUnit]().castbarFillColor
                local readyC = isKickUnit
                    and UNIT_DB_MAP[optionState.selectedUnit]().castbarInterruptReadyColor
                local unintC = isKickUnit
                    and UNIT_DB_MAP[optionState.selectedUnit]().castbarUninterruptibleColor
                local keyList = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                for _, key in ipairs(keyList) do
                    SetCastbarEnabled(key, value)
                    if color then
                        UNIT_DB_MAP[key]().castbarFillColor = { r = color.r, g = color.g, b = color.b }
                    end
                    if readyC then
                        UNIT_DB_MAP[key]().castbarInterruptReadyColor =
                            { r = readyC.r, g = readyC.g, b = readyC.b }
                    end
                    if unintC then
                        UNIT_DB_MAP[key]().castbarUninterruptibleColor =
                            { r = unintC.r, g = unintC.g, b = unintC.b }
                    end
                end
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local value = GetCastbarEnabled(optionState.selectedUnit)
                local color = UNIT_DB_MAP[optionState.selectedUnit]().castbarFillColor
                local readyC = isKickUnit
                    and UNIT_DB_MAP[optionState.selectedUnit]().castbarInterruptReadyColor
                local unintC = isKickUnit
                    and UNIT_DB_MAP[optionState.selectedUnit]().castbarUninterruptibleColor
                local keyList = isKickUnit and { "target", "focus" } or GROUP_UNIT_ORDER
                for _, key in ipairs(keyList) do
                    if GetCastbarEnabled(key) ~= value then
                        return false
                    end
                    local kc = UNIT_DB_MAP[key]().castbarFillColor
                    if color and kc then
                        if kc.r ~= color.r or kc.g ~= color.g or kc.b ~= color.b then
                            return false
                        end
                    elseif color ~= kc then
                        return false
                    end
                    if isKickUnit then
                        local kr = UNIT_DB_MAP[key]().castbarInterruptReadyColor
                        if readyC and kr then
                            if kr.r ~= readyC.r or kr.g ~= readyC.g or kr.b ~= readyC.b then
                                return false
                            end
                        elseif readyC ~= kr then
                            return false
                        end
                        local ku = UNIT_DB_MAP[key]().castbarUninterruptibleColor
                        if unintC and ku then
                            if ku.r ~= unintC.r or ku.g ~= unintC.g or ku.b ~= unintC.b then
                                return false
                            end
                        elseif unintC ~= ku then
                            return false
                        end
                    end
                end
                return true
            end,
            flashTargets = function()
                return { region }
            end,
            multiApply = {
                elementKeys = GROUP_UNIT_ORDER,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function()
                    return optionState.selectedUnit
                end,
                onApply = function(checkedKeys)
                    local value = GetCastbarEnabled(optionState.selectedUnit)
                    local color = UNIT_DB_MAP[optionState.selectedUnit]().castbarFillColor
                    local readyC = isKickUnit
                        and UNIT_DB_MAP[optionState.selectedUnit]().castbarInterruptReadyColor
                    local unintC = isKickUnit
                        and UNIT_DB_MAP[optionState.selectedUnit]().castbarUninterruptibleColor
                    for _, key in ipairs(checkedKeys) do
                        SetCastbarEnabled(key, value)
                        if color then
                            UNIT_DB_MAP[key]().castbarFillColor = { r = color.r, g = color.g, b = color.b }
                        end
                        if readyC and (key == "target" or key == "focus") then
                            UNIT_DB_MAP[key]().castbarInterruptReadyColor =
                                { r = readyC.r, g = readyC.g, b = readyC.b }
                        end
                        if unintC and (key == "target" or key == "focus") then
                            UNIT_DB_MAP[key]().castbarUninterruptibleColor =
                                { r = unintC.r, g = unintC.g, b = unintC.b }
                        end
                    end
                    ReloadAndUpdate()
                    CludesUI:RefreshPage()
                end,
            },
        })
    end
    -- Inline cog on Show Cast Bar: Hide When Idle (all units) + kick-ready tick
    -- (target/focus only). Deliberately outside the Show Cast Bar sync icon:
    -- these are per-unit detail settings.
    if not CludesUI._prebuilding then
        local region = sharedCastRow1._leftRegion
        local cogRows = {
            {
                type = "toggle",
                label = "Hide When Idle",
                tooltip = "Only show the cast bar while a cast is in progress; hide it the rest of the time.",
                get = function()
                    local value = UNIT_DB_MAP[optionState.selectedUnit]().castbarHideWhenInactive
                    if value == nil then
                        return true
                    end
                    return value
                end,
                set = function(value)
                    UNIT_DB_MAP[optionState.selectedUnit]().castbarHideWhenInactive = value
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
            },
            {
                type = "slider",
                label = "Fill Opacity",
                min = 0,
                max = 100,
                step = 1,
                tooltip = "Opacity of the cast bar fill; below 100 the world shows through the fill instead of the background.",
                get = function()
                    return UNIT_DB_MAP[optionState.selectedUnit]().castFillOpacity or 100
                end,
                set = function(value)
                    UNIT_DB_MAP[optionState.selectedUnit]().castFillOpacity = value
                    ReloadAndUpdate()
                    UpdatePreview()
                end,
            },
            -- Global (not per-frame, not synced): ONE db.profile key lifts every
            -- unit's cast bar to HIGH strata; off leaves them at the frame's
            -- strata. Default on.
            {
                type = "toggle",
                label = "Raise Cast Bar Strata (All)",
                tooltip = "Lifts player, target, focus, and boss cast bars above other frames so they are never hidden behind them.",
                get = function()
                    return saved.profile.raiseCastbarStrata ~= false
                end,
                set = function(value)
                    saved.profile.raiseCastbarStrata = value
                    ReloadAndUpdate()
                end,
            },
        }
        if optionState.selectedUnit == "target" or optionState.selectedUnit == "focus" then
            cogRows[#cogRows + 1] = {
                type = "toggle",
                label = "Show Kick Ready Mid-Cast Tick",
                tooltip = "Shows a small white tick mark on the cast bar at the point where the cast will be when your interrupt comes off cooldown.",
                get = function()
                    local value = SGetSupported("castbarKickTickEnabled")
                    if value == nil then
                        return true
                    end
                    return value
                end,
                set = SSetSupportedRowThen("castbarKickTickEnabled"),
            }
            cogRows[#cogRows + 1] = {
                type = "toggle",
                label = "Show Kick Ready Mid-Cast Bar",
                tooltip = "When your interrupt is on cooldown now but will be ready before the enemy cast finishes, color the part of the cast bar during which your interrupt will be available. The color clears the instant your interrupt comes off cooldown.",
                get = function()
                    local value = SGetSupported("castbarInterruptMidCastEnabled")
                    if value == nil then
                        return false
                    end
                    return value
                end,
                set = function(value)
                    SSetSupported("castbarInterruptMidCastEnabled", value)
                    ReloadAndUpdate()
                    UpdatePreview()
                    -- Refresh so the inline Mid-Cast swatch greys/ungreys at once;
                    -- the cog popup stays open.
                    CludesUI:RefreshPage()
                end,
            }
        end
        -- Opt-in for the Border Style | Border Size rows (built below only
        -- while on; the rebuild shows or drops them).
        cogRows[#cogRows + 1] = {
            type = "toggle",
            label = "Custom Border Style",
            tooltip = "Show the border style and size controls for the cast bar.",
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                return CludesUI.BlizzStyle.Label("unitframes")
            end,
            requireState = "disabled",
            get = function()
                return UNIT_DB_MAP[optionState.selectedUnit]().castBorderCustom == true
            end,
            set = function(value)
                UNIT_DB_MAP[optionState.selectedUnit]().castBorderCustom = value
                ReloadAndUpdate()
                CludesUI.ReapplyMatchPads(optionState.selectedUnit .. "Castbar")
                CludesUI:RefreshPage(true)
            end,
        }
        CludesUI.BuildInlineCog(region, {
            title = "Cast Bar",
            rows = cogRows,
        })
    end
    -- Inline cast color swatch(es) on Show Cast Bar
    if not CludesUI._prebuilding then
        local leftRegion = sharedCastRow1._leftRegion
        local function AddCastColorSwatch(tooltip, colorKey, fallback, disabledFn)
            local sw, updateSw = CludesUI.BuildColorSwatch(leftRegion, leftRegion:GetFrameLevel() + 5, function()
                local color = SGetSupported(colorKey)
                color = color or fallback
                return color.r, color.g, color.b, 1
            end, function(red, green, blue)
                SSetSupported(colorKey, { r = red, g = green, b = blue })
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            Pix.Point(sw, "RIGHT", leftRegion._lastInline or leftRegion._control, "LEFT", -8, 0)
            sw:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, tooltip)
            end)
            sw:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            leftRegion._lastInline = sw
            -- Optional disabled gate: grey (0.3) + non-interactive when disabledFn
            -- is true; used by the default-off Interrupt Ready Mid-Cast swatch so
            -- it tracks its enable toggle in the cog.
            if disabledFn then
                local function applySwState()
                    local off = disabledFn()
                    sw:SetAlpha(off and 0.3 or 1)
                    sw:EnableMouse(not off)
                    if updateSw then
                        updateSw()
                    end
                end
                applySwState()
                CludesUI.RegisterWidgetRefresh(applySwState)
            end
        end
        if optionState.selectedUnit == "target" or optionState.selectedUnit == "focus" then
            -- Inline swatches anchor right-to-left: Mid-Cast added first (rightmost),
            -- then CD, then Interruptible, matching Nameplates' left-to-right order.
            -- Mid-Cast greys unless its enable toggle in the cog is on.
            AddCastColorSwatch(
                "Interrupt Ready Mid-Cast",
                "castbarInterruptMidCastColor",
                { r = 0.318, g = 0.820, b = 0.357 },
                function()
                    return not SValSupported("castbarInterruptMidCastEnabled", false)
                end
            )
            AddCastColorSwatch(
                "Interrupt on CD",
                "castbarInterruptReadyColor",
                { r = 0.92, g = 0.35, b = 0.20 }
            )
            AddCastColorSwatch(
                "Uninterruptible Cast",
                "castbarUninterruptibleColor",
                { r = 0.5, g = 0.5, b = 0.5 }
            )
            AddCastColorSwatch("Interruptible Cast", "castbarFillColor", { r = 0.863, g = 0.820, b = 0.639 })
        else
            AddCastColorSwatch("Fill Color", "castbarFillColor", { r = 1, g = 0.7, b = 0 })
        end
    end
    -- Sync icon: Cast Bar Height (right region)
    if not CludesUI._prebuilding then
        local region = sharedCastRow1._rightRegion
        mod.UFO_UnitSync(region, "Cast Bar Height", {
            self = true,
            copy = function(tbl, _, unit)
                tbl[unit == "player" and "playerCastbarHeight" or "castbarHeight"] = GetCastbarHeight()
            end,
            same = function(tbl, _, unit)
                return (tbl[unit == "player" and "playerCastbarHeight" or "castbarHeight"] or 20)
                    == GetCastbarHeight()
            end,
        })
    end

    -- Rows 2-4 are HIDDEN while Show Cast Bar is off (DependentSetValue rebuilds
    -- on flips). Row locals are hoisted above the gate: the element-nav map
    -- references them, and an in-gate declaration would leave it reading nil globals.
    local castRow2, castTextRow, castTargetRow
    if GetCastbarEnabled(optionState.selectedUnit) then
        -- Row 2: Show Icon | Bar Background (opacity slider + inline color swatch)
        local function GetShowIcon()
            if optionState.selectedUnit == "player" then
                local value = UNIT_DB_MAP.player().showPlayerCastIcon
                if value == nil then
                    return true
                end
                return value
            else
                local value = UNIT_DB_MAP[optionState.selectedUnit]().showCastIcon
                if value == nil then
                    return true
                end
                return value
            end
        end
        local function SetShowIcon(val)
            if optionState.selectedUnit == "player" then
                UNIT_DB_MAP.player().showPlayerCastIcon = val
            else
                UNIT_DB_MAP[optionState.selectedUnit]().showCastIcon = val
            end
        end
        castRow2, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Icon",
            getValue = GetShowIcon,
            setValue = function(value)
                SetShowIcon(value)
                ReloadAndUpdate()
                UpdatePreview()
            end,
        }, {
            type = "slider",
            text = "Bar Background",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                return math.floor(SValSupported("castBgAlpha", 0.5) * 100 + 0.5)
            end,
            setValue = function(value)
                UNIT_DB_MAP[optionState.selectedUnit]().castBgAlpha = value / 100
                ReloadAndUpdate()
                UpdatePreview()
            end,
        })
        cursorY = cursorY - height
        -- Sync icon: Show Icon (left)
        if not CludesUI._prebuilding then
            local region = castRow2._leftRegion
            mod.UFO_UnitSync(region, "Show Icon", {
                self = true,
                copy = function(tbl, _, unit)
                    tbl[unit == "player" and "showPlayerCastIcon" or "showCastIcon"] = GetShowIcon()
                end,
                same = function(tbl, _, unit)
                    local value = tbl[unit == "player" and "showPlayerCastIcon" or "showCastIcon"]
                    if value == nil then
                        value = true
                    end
                    return value == GetShowIcon()
                end,
            })
        end
        -- Inline cog on Show Icon: "Icon Border", "Make Icon Part of the Bar",
        -- "Border Wraps Icon", "Vertical Separator", "Show Icon on Right",
        -- "Show Icon on Portrait", additive Offset X/Y nudges. Operates on the
        -- selected unit. An icon on the portrait greys the bar-side placement rows.
        if not CludesUI._prebuilding then
            local region = castRow2._leftRegion
            local function IconOnPortrait()
                return mod.UF_CastIconOnPortrait(
                    optionState.selectedUnit,
                    UNIT_DB_MAP[optionState.selectedUnit]()
                )
            end
            CludesUI.BuildInlineCog(region, {
                title = "Cast Icon",
                rows = {
                    {
                        type = "toggle",
                        label = "Icon Border",
                        tooltip = "Use the cast bar's border style, size and color around the icon.",
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes")
                                or not GetShowIcon()
                                or IconOnPortrait()
                        end,
                        disabledTooltip = "This option requires Show Icon beside the cast bar and the CludesUI style.",
                        get = function()
                            return UNIT_DB_MAP[optionState.selectedUnit]().castIconBorder == true
                        end,
                        set = function(value)
                            UNIT_DB_MAP[optionState.selectedUnit]().castIconBorder = value
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Make Icon Part of the Bar",
                        tooltip = "This makes it so the width of the cast bar includes the icon, rather than placing it to the left of the cast bars width.",
                        -- The stock styles count a shown icon as part of the bar
                        -- (their frame art wraps both), so the toggle reads on and locks.
                        disabled = function()
                            return CludesUI.BlizzStyle.Get("unitframes") or IconOnPortrait()
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("unitframes") then
                                return CludesUI.BlizzStyle.Label("unitframes")
                            end
                            return "Show Icon on Portrait"
                        end,
                        requireState = "disabled",
                        get = function()
                            if CludesUI.BlizzStyle.Get("unitframes") then
                                return true
                            end
                            if optionState.selectedUnit == "player" then
                                return UNIT_DB_MAP.player().playerCastbarIconInWidth ~= false
                            end
                            return UNIT_DB_MAP[optionState.selectedUnit]().castbarIconInWidth ~= false
                        end,
                        set = function(value)
                            if optionState.selectedUnit == "player" then
                                UNIT_DB_MAP.player().playerCastbarIconInWidth = value
                            else
                                UNIT_DB_MAP[optionState.selectedUnit]().castbarIconInWidth = value
                            end
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    -- Off: the custom border wraps the bar alone. The wrap
                    -- also drops while the icon has an offset.
                    {
                        type = "toggle",
                        label = "Border Wraps Icon",
                        tooltip = "Draw the custom cast bar border around the icon and the bar together. An icon with an offset keeps its own border.",
                        disabled = function()
                            local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                            return CludesUI.BlizzStyle.Get("unitframes")
                                or cfg.castBorderCustom ~= true
                                or not mod.UF_CastIconInWidth(optionState.selectedUnit, cfg)
                        end,
                        disabledTooltip = "This option requires Custom Border Style, Show Icon and Make Icon Part of the Bar, with the CludesUI style.",
                        get = function()
                            return UNIT_DB_MAP[optionState.selectedUnit]().castBorderWrapIcon == true
                        end,
                        set = function(value)
                            UNIT_DB_MAP[optionState.selectedUnit]().castBorderWrapIcon = value
                            ReloadAndUpdate()
                            UpdatePreview()
                            CludesUI.ReapplyMatchPads(optionState.selectedUnit .. "Castbar")
                        end,
                    },
                    -- Solid draws a flat line; a textured style needs its own
                    -- divider art (ns.UF_CastIconSeamOK, the runtime's gate).
                    {
                        type = "toggle",
                        label = "Vertical Separator",
                        tooltip = "Draw a divider between the integrated icon and the bar, using the cast bar's border appearance.",
                        disabled = function()
                            local s = UNIT_DB_MAP[optionState.selectedUnit]()
                            return CludesUI.BlizzStyle.Get("unitframes")
                                or not mod.UF_CastIconInWidth(optionState.selectedUnit, s)
                                or not mod.UF_CastIconSeamOK(s)
                        end,
                        disabledTooltip = function()
                            local s = UNIT_DB_MAP[optionState.selectedUnit]()
                            if
                                CludesUI.BlizzStyle.Get("unitframes")
                                or not mod.UF_CastIconInWidth(optionState.selectedUnit, s)
                            then
                                return "This option requires Show Icon and Make Icon Part of the Bar, with the CludesUI style."
                            end
                            return "This option requires Solid or a border style with divider art, and a Border Size above 0."
                        end,
                        get = function()
                            return UNIT_DB_MAP[optionState.selectedUnit]().castIconSeparator == true
                        end,
                        set = function(value)
                            UNIT_DB_MAP[optionState.selectedUnit]().castIconSeparator = value
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Icon on Right",
                        tooltip = "Place the cast icon on the right side of the bar instead of the left.",
                        disabled = IconOnPortrait,
                        disabledTooltip = "Show Icon on Portrait",
                        requireState = "disabled",
                        get = function()
                            if optionState.selectedUnit == "player" then
                                return UNIT_DB_MAP.player().playerCastbarIconRight == true
                            end
                            return UNIT_DB_MAP[optionState.selectedUnit]().castbarIconRight == true
                        end,
                        set = function(value)
                            if optionState.selectedUnit == "player" then
                                UNIT_DB_MAP.player().playerCastbarIconRight = value
                            else
                                UNIT_DB_MAP[optionState.selectedUnit]().castbarIconRight = value
                            end
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    -- Needs a visible portrait and the icon shown; the stock
                    -- styles own the icon.
                    {
                        type = "toggle",
                        label = "Show Icon on Portrait",
                        tooltip = "Shows the spell icon over the portrait while casting and lets the bar use the full width.",
                        disabled = function()
                            if CludesUI.BlizzStyle.Get("unitframes") or not GetShowIcon() then
                                return true
                            end
                            local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                            return (cfg.portraitStyle or saved.profile.portraitStyle or "attached") == "none"
                                or cfg.showPortrait == false
                                or (cfg.portraitMode or saved.profile.portraitMode or "2d") == "none"
                        end,
                        disabledTooltip = function()
                            if CludesUI.BlizzStyle.Get("unitframes") then
                                return CludesUI.BlizzStyle.Label("unitframes")
                            end
                            return "This option requires a visible Portrait and Show Icon."
                        end,
                        rawTooltip = function()
                            return not CludesUI.BlizzStyle.Get("unitframes")
                        end,
                        requireState = "disabled",
                        get = function()
                            if optionState.selectedUnit == "player" then
                                return UNIT_DB_MAP.player().playerCastbarIconOnPortrait == true
                            end
                            return UNIT_DB_MAP[optionState.selectedUnit]().castbarIconOnPortrait == true
                        end,
                        set = function(value)
                            if optionState.selectedUnit == "player" then
                                UNIT_DB_MAP.player().playerCastbarIconOnPortrait = value
                            else
                                UNIT_DB_MAP[optionState.selectedUnit]().castbarIconOnPortrait = value
                            end
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        disabled = IconOnPortrait,
                        disabledTooltip = "Show Icon on Portrait",
                        requireState = "disabled",
                        get = function()
                            if optionState.selectedUnit == "player" then
                                return UNIT_DB_MAP.player().playerCastIconOffsetX or 0
                            end
                            return UNIT_DB_MAP[optionState.selectedUnit]().castIconOffsetX or 0
                        end,
                        set = function(value)
                            if optionState.selectedUnit == "player" then
                                UNIT_DB_MAP.player().playerCastIconOffsetX = value
                            else
                                UNIT_DB_MAP[optionState.selectedUnit]().castIconOffsetX = value
                            end
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        disabled = IconOnPortrait,
                        disabledTooltip = "Show Icon on Portrait",
                        requireState = "disabled",
                        get = function()
                            if optionState.selectedUnit == "player" then
                                return UNIT_DB_MAP.player().playerCastIconOffsetY or 0
                            end
                            return UNIT_DB_MAP[optionState.selectedUnit]().castIconOffsetY or 0
                        end,
                        set = function(value)
                            if optionState.selectedUnit == "player" then
                                UNIT_DB_MAP.player().playerCastIconOffsetY = value
                            else
                                UNIT_DB_MAP[optionState.selectedUnit]().castIconOffsetY = value
                            end
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    },
                },
            })
        end
        -- Inline swatch on Bar Background; defaults to the cast bar's hardcoded black.
        if not CludesUI._prebuilding then
            local region = castRow2._rightRegion
            local bgSwGet = function()
                local color = UNIT_DB_MAP[optionState.selectedUnit]().castBgColor
                if color then
                    return color.r, color.g, color.b
                end
                return 0, 0, 0
            end
            local bgSwSet = function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().castBgColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end
            local bgSw, bgSwUpdate =
                CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 5, bgSwGet, bgSwSet, false, 20)
            Pix.Point(bgSw, "RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = bgSw
            RegisterWidgetRefresh(function()
                bgSwUpdate()
            end)
        end
        -- Sync icon: Bar Background (right) -- background color + opacity
        if not CludesUI._prebuilding then
            local region = castRow2._rightRegion
            local function ApplyCastBgTo(keyList)
                local source = UNIT_DB_MAP[optionState.selectedUnit]()
                local bc = source.castBgColor or { r = 0, g = 0, b = 0 }
                local bgA = source.castBgAlpha
                for _, key in ipairs(keyList) do
                    if key ~= optionState.selectedUnit then
                        local unitCfg = UNIT_DB_MAP[key]()
                        unitCfg.castBgColor = { r = bc.r, g = bc.g, b = bc.b }
                        unitCfg.castBgAlpha = bgA
                    end
                end
                ReloadAndUpdate()
                CludesUI:RefreshPage()
            end
            mod.UFO_UnitSync(region, "Bar Background", {
                applyTo = ApplyCastBgTo,
                isSynced = function()
                    local source = UNIT_DB_MAP[optionState.selectedUnit]()
                    local function colEq(a, b)
                        -- A nil color means "use the hardcoded default (black)", so a
                        -- nil color and an explicit black must compare equal. Without
                        -- this the icon never reads as synced after Apply to All (the
                        -- source stays nil while the targets get an explicit black).
                        local ar, ag, ab = a and a.r or 0, a and a.g or 0, a and a.b or 0
                        local cr, cg, cb = b and b.r or 0, b and b.g or 0, b and b.b or 0
                        return ar == cr and ag == cg and ab == cb
                    end
                    for _, key in ipairs(GROUP_UNIT_ORDER) do
                        local unitCfg = UNIT_DB_MAP[key]()
                        if not colEq(unitCfg.castBgColor, source.castBgColor) then
                            return false
                        end
                        if (unitCfg.castBgAlpha or 0.5) ~= (source.castBgAlpha or 0.5) then
                            return false
                        end
                    end
                    return true
                end,
            })
        end

        -- Row 3: Spell Name (position dropdown + cog + swatch) | Duration (same). Cast
        -- text dropdowns mirror nameplates: Name/Target are None/Left/Right/Center and
        -- may not share a side (setting one bumps the other to None). Duration is
        -- None/Right/Left; "None" sets showCastDuration=false but still reserves a slot,
        -- pushing same-side text. Size/X/Y live in each row's cog. Defaults: Name Left, Target Right, Duration Right.
        local castTextPosValues = { none = "None", left = "Left", right = "Right", center = "Center" }
        local castTextPosOrder = { "none", "left", "right", "center" }
        castTextRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Spell Name",
            values = castTextPosValues,
            order = castTextPosOrder,
            getValue = SValSupportedRow("castSpellNameSide", "left"),
            setValue = function(value)
                local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                cfg.castSpellNameSide = value
                if
                    value ~= "none"
                    and (cfg.showCastTarget ~= false)
                    and (cfg.castSpellTargetSide or "right") == value
                then
                    cfg.showCastTarget = false
                end
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "segmented",
            text = "Duration",
            values = { none = "None", right = "Right", left = "Left" },
            order = { "none", "right", "left" },
            getValue = function()
                if SValSupported("showCastDuration", true) == false then
                    return "none"
                end
                return SValSupported("castDurationSide", "right")
            end,
            setValue = function(value)
                local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                if value == "none" then
                    cfg.showCastDuration = false
                else
                    cfg.showCastDuration = true
                    cfg.castDurationSide = value
                end
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on Spell Name Size: X/Y offsets (+ target/focus combine)
        if not CludesUI._prebuilding then
            local snCogRgn = castTextRow._leftRegion
            local snCogRows = {
                {
                    type = "slider",
                    label = "Size",
                    min = 6,
                    max = 20,
                    step = 1,
                    get = SValSupportedRow("castSpellNameSize", 11),
                    set = SSetSupportedRowThen("castSpellNameSize"),
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValSupportedRow("castSpellNameX", 0),
                    set = SSetSupportedRowThen("castSpellNameX"),
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValSupportedRow("castSpellNameY", 0),
                    set = SSetSupportedRowThen("castSpellNameY"),
                },
                {
                    type = "toggle",
                    label = "Show Full Spell Name",
                    tooltip = "Long spell names shrink to fit beside the duration instead of being cut off.",
                    get = SValSupportedRow("castFitSpellName", false),
                    set = function(value)
                        SSetSupported("castFitSpellName", value)
                        ReloadAndUpdate()
                    end,
                },
            }
            if optionState.selectedUnit == "target" or optionState.selectedUnit == "focus" then
                snCogRows[#snCogRows + 1] = {
                    type = "toggle",
                    label = "Combine Spell Name and Target",
                    tooltip = "Appends the cast target to the spell name (Spell Name - Target), class colored, and disables the separate Spell Target display.",
                    get = SValSupportedRow("castCombineNameTarget", false),
                    set = function(value)
                        SSetSupported("castCombineNameTarget", value)
                        ReloadAndUpdate()
                        UpdatePreview()
                        -- Grey/ungrey the Spell Name dropdown immediately.
                        CludesUI:RefreshPage()
                    end,
                }
            end
            CludesUI.BuildInlineCog(snCogRgn, {
                title = "Spell Name",
                rows = snCogRows,
            })
        end
        -- Inline color swatch on Spell Name Size
        if not CludesUI._prebuilding then
            local snRgn = castTextRow._leftRegion
            local snSw = CludesUI.BuildColorSwatch(snRgn, snRgn:GetFrameLevel() + 5, function()
                local color = SGetSupported("castSpellNameColor")
                color = color or { r = 1, g = 1, b = 1 }
                return color.r, color.g, color.b, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().castSpellNameColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            snSw:SetPoint("RIGHT", snRgn._lastInline or snRgn._control, "LEFT", -8, 0)
            snRgn._lastInline = snSw
        end
        -- Inline cog on Duration Size: toggle + X/Y offsets
        if not CludesUI._prebuilding then
            local dtCogRgn = castTextRow._rightRegion
            local dtCogRows = {
                {
                    type = "slider",
                    label = "Size",
                    min = 6,
                    max = 20,
                    step = 1,
                    get = SValSupportedRow("castDurationSize", 10),
                    set = SSetSupportedRowThen("castDurationSize"),
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValSupportedRow("castDurationX", 0),
                    set = SSetSupportedRowThen("castDurationX"),
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = SValSupportedRow("castDurationY", 0),
                    set = SSetSupportedRowThen("castDurationY"),
                },
            }
            if optionState.selectedUnit == "player" then
                dtCogRows[#dtCogRows + 1] = {
                    type = "toggle",
                    label = "Full Craft Time",
                    tooltip = "While crafting several items at once, the duration shows the time left for the whole batch and the spell name shows the craft count.",
                    get = SValSupportedRow("castFullCraftTime", false),
                    set = function(value)
                        SSetSupported("castFullCraftTime", value)
                        ReloadAndUpdate()
                    end,
                }
            end
            CludesUI.BuildInlineCog(dtCogRgn, {
                title = "Duration",
                rows = dtCogRows,
            })
        end
        -- Inline color swatch on Duration Size
        if not CludesUI._prebuilding then
            local dtRgn = castTextRow._rightRegion
            local dtSw = CludesUI.BuildColorSwatch(dtRgn, dtRgn:GetFrameLevel() + 5, function()
                local color = SGetSupported("castDurationColor")
                color = color or { r = 1, g = 1, b = 1 }
                return color.r, color.g, color.b, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().castDurationColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            dtSw:SetPoint("RIGHT", dtRgn._lastInline or dtRgn._control, "LEFT", -8, 0)
            dtRgn._lastInline = dtSw
        end

        -- Sync icons: Spell Name Size + Color (left) and Duration Size + Color (right)
        if not CludesUI._prebuilding then
            local region = castTextRow._leftRegion
            CastTextSync(
                region,
                "Spell Name Size, Color and Show Full Spell Name",
                "castSpellNameSize",
                11,
                "castSpellNameColor",
                "castFitSpellName"
            )
        end
        if not CludesUI._prebuilding then
            local region = castTextRow._rightRegion
            CastTextSync(region, "Duration Size and Color", "castDurationSize", 10, "castDurationColor")
        end

        -- Row 4: Spell Target (position dropdown + cog + swatch) | Reverse Fill
        castTargetRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Spell Target",
            values = castTextPosValues,
            order = castTextPosOrder,
            -- Combine Spell Name and Target appends the target to the spell
            -- name string; the separate target display greys out and no-ops
            -- while it is on.
            disabled = function()
                if optionState.selectedUnit ~= "target" and optionState.selectedUnit ~= "focus" then
                    return false
                end
                local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                return (cfg and cfg.castCombineNameTarget == true) and true or false
            end,
            disabledTooltip = "This option requires Combine Spell Name and Target to be disabled.",
            getValue = function()
                if SValSupported("showCastTarget", true) == false then
                    return "none"
                end
                return SValSupported("castSpellTargetSide", "right")
            end,
            setValue = function(value)
                local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
                if value == "none" then
                    cfg.showCastTarget = false
                else
                    cfg.showCastTarget = true
                    cfg.castSpellTargetSide = value
                    if (cfg.castSpellNameSide or "left") == value then
                        cfg.castSpellNameSide = "none"
                    end
                end
                ReloadAndUpdate()
                UpdatePreview()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Reverse Fill",
            getValue = SValSupportedRow("castReverseFill", false),
            setValue = SSetSupportedRowThen("castReverseFill"),
        })
        cursorY = cursorY - height
        -- Inline cog on Spell Target Size: toggle + X/Y offsets
        if not CludesUI._prebuilding then
            local tgCogRgn = castTargetRow._leftRegion
            CludesUI.BuildInlineCog(tgCogRgn, {
                title = "Spell Target",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = SValSupportedRow("castSpellTargetSize", 10),
                        set = SSetSupportedRowThen("castSpellTargetSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValSupportedRow("castSpellTargetX", 0),
                        set = SSetSupportedRowThen("castSpellTargetX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = SValSupportedRow("castSpellTargetY", 0),
                        set = SSetSupportedRowThen("castSpellTargetY"),
                    },
                },
            })
        end
        -- Inline color swatch on Spell Target Size
        if not CludesUI._prebuilding then
            local trgRgn = castTargetRow._leftRegion
            local trgSw = CludesUI.BuildColorSwatch(trgRgn, trgRgn:GetFrameLevel() + 5, function()
                local color = SGetSupported("castSpellTargetColor")
                color = color or { r = 1, g = 1, b = 1 }
                return color.r, color.g, color.b, 1
            end, function(red, green, blue)
                UNIT_DB_MAP[optionState.selectedUnit]().castSpellTargetColor = { r = red, g = green, b = blue }
                ReloadAndUpdate()
                UpdatePreview()
            end, false, 20)
            trgSw:SetPoint("RIGHT", trgRgn._lastInline or trgRgn._control, "LEFT", -8, 0)
            trgRgn._lastInline = trgSw
        end

        -- Sync icons: Spell Target Size + Color (left)
        if not CludesUI._prebuilding then
            local region = castTargetRow._leftRegion
            CastTextSync(
                region,
                "Spell Target Size and Color",
                "castSpellTargetSize",
                11,
                "castSpellTargetColor"
            )
        end
        -- Custom Border Style rows (the Cast Bar cog's opt-in), inside the Show
        -- Cast Bar gate and ahead of the Classic-only Border Size row.
        if SVal("castBorderCustom", false) == true then
            cursorY = cursorY
                - mod.UF_CastBorderRows(
                    W,
                    hostFrame,
                    cursorY,
                    function()
                        return UNIT_DB_MAP[optionState.selectedUnit]()
                    end,
                    ReloadAndUpdate,
                    optionState.selectedUnit .. "Castbar",
                    {
                        units = GROUP_UNIT_ORDER,
                        labels = SHORT_LABELS,
                        current = function()
                            return optionState.selectedUnit
                        end,
                        db = function(unit)
                            local f = UNIT_DB_MAP[unit]
                            return f and f()
                        end,
                    }
                )
        end
        -- Important Cast Glow (target/focus); in Classic WoW UI it fills the Border Size row's free slot.
        local impGlowCfg, impGlowDesc
        if optionState.selectedUnit == "target" or optionState.selectedUnit == "focus" then
            impGlowDesc = UF_ImpCastGlowDesc(function()
                return UNIT_DB_MAP[optionState.selectedUnit]()
            end, function()
                ReloadAndUpdate()
                UpdatePreview()
            end)
            impGlowCfg = CludesUI.GlowOptions.DropdownSpec(
                impGlowDesc,
                "Important Cast Glow",
                "Show a glow on the cast bar when the unit is casting a spell Blizzard marks as important."
            )
        end
        -- Classic WoW UI: Border Size closes the section (odd last slot).
        local classicH, classicRow = mod.UF_ClassicCastBorderRow(
            W,
            hostFrame,
            cursorY,
            function()
                return UNIT_DB_MAP[optionState.selectedUnit]()
            end,
            mod.UF_CastClassicKey(optionState.selectedUnit),
            function()
                ReloadAndUpdate()
                UpdatePreview()
            end,
            {
                units = GROUP_UNIT_ORDER,
                labels = SHORT_LABELS,
                current = function()
                    return optionState.selectedUnit
                end,
                db = function(unit)
                    local f = UNIT_DB_MAP[unit]
                    return f and f()
                end,
                reload = ReloadAndUpdate,
            },
            optionState.selectedUnit .. "Castbar",
            impGlowCfg
        )
        cursorY = cursorY - classicH
        if impGlowCfg then
            local impGlowRow, impGlowSide = classicRow, "_rightRegion"
            if not impGlowRow then
                impGlowRow, height =
                    W:DualRow(hostFrame, cursorY, impGlowCfg, { type = "label", text = "Glow Color" })
                cursorY = cursorY - height
                impGlowSide = "_leftRegion"
            end
            if not CludesUI._prebuilding then
                local region = impGlowRow[impGlowSide]
                -- Color swatches (in the free right half when there is one), the
                -- Pixel Glow cog and a small preview.
                local GO = CludesUI.GlowOptions
                GO.AttachInline(
                    region,
                    impGlowDesc,
                    impGlowSide == "_leftRegion" and impGlowRow._rightRegion or nil
                )
                local preview = GO.BuildPreview(
                    region,
                    impGlowDesc,
                    { width = 40, height = 14, anchor = region._lastInline or region._control, x = -12 }
                )
                if preview then
                    preview:SetFrameLevel(region:GetFrameLevel() + 5)
                    region._lastInline = preview
                end

                -- Sync icon: apply glow settings to the other kick unit (target <-> focus)
                local GLOW_KEYS = {
                    "castbarImportantGlow",
                    "castbarImportantGlowStyle",
                    "castbarImportantGlowColorMode",
                    "castbarImportantGlowLines",
                    "castbarImportantGlowThickness",
                    "castbarImportantGlowSpeed",
                    "castbarImportantGlowBackground",
                }
                local GLOW_COLOR_KEYS = { "castbarImportantGlowColor", "castbarImportantGlowBackgroundColor" }
                local function colEq(a, b)
                    if a and b then
                        return a.r == b.r and a.g == b.g and a.b == b.b
                    end
                    return a == b
                end
                mod.UFO_UnitSync(region, "Important Cast Glow", {
                    units = { "target", "focus" },
                    noMenu = true,
                    copy = function(tbl, from)
                        for _, keyName in ipairs(GLOW_KEYS) do
                            tbl[keyName] = from[keyName]
                        end
                        for _, keyName in ipairs(GLOW_COLOR_KEYS) do
                            local color = from[keyName]
                            tbl[keyName] = color and { r = color.r, g = color.g, b = color.b } or nil
                        end
                    end,
                    same = function(tbl, from)
                        for _, keyName in ipairs(GLOW_KEYS) do
                            if tbl[keyName] ~= from[keyName] then
                                return false
                            end
                        end
                        for _, keyName in ipairs(GLOW_COLOR_KEYS) do
                            if not colEq(tbl[keyName], from[keyName]) then
                                return false
                            end
                        end
                        return true
                    end,
                })
            end
        end
    end -- close Cast Bar hidden-while-disabled gate

    return cursorY, sharedCastHeader, sharedCastRow1, castRow2, castTextRow, castTargetRow
end

-- Aura cog rows a frame's buff and debuff rows share (target, focus, player
-- and the pet). kind = "buff" or "debuff"; get(key, default) reads the frame's
-- own value (default while unset), set(key, v) writes it and applies.
-- Settings (the Location cog): Growth Direction, Max Count, afterMax (an
-- optional row placed right after Max Count), Max Per Row (unset follows Max
-- Count) and Cropped Icons.
-- Max Count caps each aura group on its own (the engine has no shared cap),
-- so several filters, or one drawn as two groups (Important), can show more.
-- maxTip = this tooltip wherever that can happen: not the player's buffs
-- (their filters merge into one group) nor the pet (one group per element).
-- The boss rows in MiniFrames_Options.lua use it too.
mod.UFO_MAX_COUNT_TOOLTIP = "More than this can show with some filters."
function mod.UFO_AuraSettingsRows(kind, get, set, maxMax, maxDefault, afterMax, maxTip)
    local environ = mod._UFO_OptEnv
    local growthKey, perRowKey, cropKey = kind .. "Growth", kind .. "MaxPerRow", kind .. "CropIcons"
    local maxKey = (kind == "buff") and "maxBuffs" or "maxDebuffs"
    local rowList = {
        {
            type = "dropdown",
            label = "Growth Direction",
            values = environ.buffGrowthValues,
            order = environ.buffGrowthOrder,
            get = function()
                return get(growthKey, "auto")
            end,
            set = function(value)
                set(growthKey, value)
            end,
        },
        {
            type = "slider",
            label = "Max Count",
            min = 1,
            max = maxMax,
            step = 1,
            tooltip = maxTip,
            get = function()
                return get(maxKey, maxDefault)
            end,
            set = function(value)
                set(maxKey, value)
            end,
        },
    }
    if afterMax then
        rowList[#rowList + 1] = afterMax
    end
    rowList[#rowList + 1] = {
        type = "slider",
        label = "Max Per Row",
        min = 1,
        max = maxMax,
        step = 1,
        get = function()
            return get(perRowKey, nil) or get(maxKey, maxDefault)
        end,
        set = function(value)
            set(perRowKey, value)
        end,
    }
    rowList[#rowList + 1] = {
        type = "toggle",
        label = "Cropped Icons",
        get = function()
            return get(cropKey, false)
        end,
        set = function(value)
            set(cropKey, value)
        end,
    }
    return rowList
end

-- Max Important (target, focus and boss debuffs): Important or Own caps your
-- debuffs with Max Count and the important ones from others with this, each
-- group on its own (the engine has no shared cap, and auras are secret in
-- combat). Unset follows Max Count. getS returns the frame's settings, apply
-- applies.
function mod.UFO_MaxImportantRow(getS, apply, maxMax, maxDefault)
    return {
        type = "slider",
        label = "Max Important",
        min = 1,
        max = maxMax,
        step = 1,
        tooltip = "Limits important debuffs not cast by you.",
        disabled = function()
            return mod.UF_DebuffFilterMode(getS()) ~= "importantOrOwn"
        end,
        disabledTooltip = "Debuff Filter: Important or Own",
        get = function()
            local cfg = getS()
            return cfg.maxImportantDebuffs or cfg.maxDebuffs or maxDefault
        end,
        set = function(value)
            getS().maxImportantDebuffs = value
            apply()
        end,
    }
end

-- Position (the Size cog): Offset X / Y and the physical-pixel-perfect gaps
-- between icons (Spacing X = columns, Spacing Y = rows).
function mod.UFO_AuraPositionRows(kind, get, set)
    local offXKey, offYKey = kind .. "OffsetX", kind .. "OffsetY"
    local spXKey, spYKey = kind .. "SpacingX", kind .. "SpacingY"
    return {
        {
            type = "slider",
            label = "Offset X",
            min = -1500,
            max = 1500,
            step = 1,
            get = function()
                return get(offXKey, 0)
            end,
            set = function(value)
                set(offXKey, value)
            end,
        },
        {
            type = "slider",
            label = "Offset Y",
            min = -1500,
            max = 1500,
            step = 1,
            get = function()
                return get(offYKey, 0)
            end,
            set = function(value)
                set(offYKey, value)
            end,
        },
        {
            type = "slider",
            pixel = true,
            label = "Spacing X",
            min = -1,
            max = 10,
            step = 1,
            get = function()
                return get(spXKey, 1)
            end,
            set = function(value)
                set(spXKey, value)
            end,
        },
        {
            type = "slider",
            pixel = true,
            label = "Spacing Y",
            min = -1,
            max = 10,
            step = 1,
            get = function()
                return get(spYKey, 1)
            end,
            set = function(value)
                set(spYKey, value)
            end,
        },
    }
end

function mod.UFO_BuildBuffsDebuffsSection(hostFrame, cursorY, context)
    local environ = mod._UFO_OptEnv
    local AttachDebuffModeWarn, DebuffModeDropdownCfg, Pix =
        environ.AttachDebuffModeWarn, environ.DebuffModeDropdownCfg, environ.PP
    local RegisterWidgetRefresh, ReloadAndUpdate, SwapAuraSlot =
        environ.RegisterWidgetRefresh, environ.ReloadAndUpdate, environ.SwapAuraSlot
    local UF_PurgeGlowDesc, UNIT_DB_MAP, UNIT_LABELS_SUP, UpdatePreview =
        environ.UF_PurgeGlowDesc, environ.UNIT_DB_MAP, environ.UNIT_LABELS_SUP, environ.UpdatePreview
    local HideExhaustionRow = environ.HideExhaustionRow
    local buffAnchorOrder, buffAnchorValues = environ.buffAnchorOrder, environ.buffAnchorValues
    local saved, frameList, optionState = environ.db, environ.frames, environ.optState
    local W, SApplySupport, SDB, SGet = context.W, context.SApplySupport, context.SDB, context.SGet
    local SSetSupported, SVal, SValSupported = context.SSetSupported, context.SVal, context.SValSupported
    -- Row setters over SSetSupported: the key written with the row's value.
    local function SSetSupportedRow(key)
        return function(value)
            SSetSupported(key, value)
        end
    end
    -- A row getter over SValSupported: the key's value, or the default given.
    local function SValSupportedRow(key, default)
        return function()
            return SValSupported(key, default)
        end
    end
    -- Row setters over SSetSupported: the key written with the row's value.
    local function SSetSupportedRow(key)
        return function(value)
            SSetSupported(key, value)
        end
    end
    local _, height

    local sharedBuffDebuffHeader
    -------------------------------------------------------------------
    --  BUFFS AND DEBUFFS
    -------------------------------------------------------------------
    sharedBuffDebuffHeader, height = W:SectionHeader(hostFrame, "BUFFS AND DEBUFFS", cursorY)
    cursorY = cursorY - height

    -- When Buff/Debuff Display is "none", everything in that column is disabled.
    local function BuffsOff()
        local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
        if not cfg then
            return false
        end
        -- Anchor Buffs with Debuffs renders buffs inside the debuff stack, so
        -- buff appearance settings stay live while Buff Display reads None (visibility belongs to the merge toggle).
        if cfg.debuffAnchorBuffs and SValSupported("debuffAnchor", "bottomleft") ~= "none" then
            return false
        end
        return cfg.showBuffs == false
    end
    local function DebuffsOff()
        return SValSupported("debuffAnchor", "bottomleft") == "none"
    end

    -- Buff Display gains "Anchor to Debuffs" -- a pure VIEW over the same stored
    -- keys the merge always used (debuffAnchorBuffs=true + showBuffs=false), so old
    -- cog-toggle profiles read back identically. Shared anchor tables serve three other dropdowns, hence the per-site copy.
    local buffDispValues = { ["anchor_debuffs"] = "Anchor to Debuffs" }
    for keyName, value in pairs(buffAnchorValues) do
        buffDispValues[keyName] = value
    end
    local buffDispOrder = {}
    for idx = 1, #buffAnchorOrder do
        buffDispOrder[idx] = buffAnchorOrder[idx]
    end
    buffDispOrder[#buffDispOrder + 1] = "anchor_debuffs"
    buffDispValues._menuOpts = {
        onItemHover = function(key, entry)
            if key == "anchor_debuffs" and entry then
                CludesUI.ShowWidgetTooltip(
                    entry,
                    "Buffs join the debuff stack as its first rows; debuffs continue on the next row and move as buff rows change."
                )
            end
        end,
        onItemLeave = function(key)
            if key == "anchor_debuffs" then
                CludesUI.HideWidgetTooltip()
            end
        end,
    }

    -- Buffs: Location | Icon Size + inline directions cog (X/Y)
    local sharedAddRow2
    sharedAddRow2, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Buff Display",
        values = buffDispValues,
        order = buffDispOrder,
        itemDisabled = function(value)
            return value == "anchor_debuffs" and DebuffsOff()
        end,
        itemDisabledTooltip = function(value)
            if value == "anchor_debuffs" then
                return "Requires a Debuff Display"
            end
        end,
        getValue = function()
            local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
            -- Active merge presents as its own display choice; an inert merge
            -- (Debuff Display None) falls through to the truthful None readout.
            if cfg.debuffAnchorBuffs and SValSupported("debuffAnchor", "bottomleft") ~= "none" then
                return "anchor_debuffs"
            end
            if cfg.showBuffs == false then
                return "none"
            end
            return SValSupported("buffAnchor", "topleft")
        end,
        -- DependentSetValue: the Buff Duration/Stack row (and, together
        -- with Debuff Display, the filter row) hides while None; only
        -- the None <-> shown flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return not BuffsOff()
        end, function(value)
            local cfg = UNIT_DB_MAP[optionState.selectedUnit]()
            if value == "anchor_debuffs" then
                -- Same stored shape the old cog toggle wrote: the
                -- merge owns visibility, Buff Display stores None.
                cfg.debuffAnchorBuffs = true
                cfg.showBuffs = false
            elseif value == "none" then
                cfg.showBuffs = false
                cfg.debuffAnchorBuffs = nil
            else
                cfg.showBuffs = true
                SwapAuraSlot(cfg, "buffAnchor", value)
                -- Choosing a standalone Buff Display exits the
                -- merged mode (which forces this dropdown to None).
                cfg.debuffAnchorBuffs = nil
            end
            ReloadAndUpdate()
            UpdatePreview()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "slider",
        text = "Buff Size",
        min = 10,
        max = 70,
        step = 1,
        disabled = BuffsOff,
        disabledTooltip = "Buff Display",
        getValue = SValSupportedRow("buffSize", 22),
        setValue = SSetSupportedRow("buffSize"),
    })
    cursorY = cursorY - height
    SApplySupport(sharedAddRow2._leftRegion, "showBuffs")
    -- Sync icon: Buffs Location (left)
    if not CludesUI._prebuilding then
        -- Shown (on when unset) travels with the place it shows at; hidden buffs
        -- keep each frame's own place.
        local function Shown(tbl)
            if tbl.showBuffs == nil then
                return true
            end
            return tbl.showBuffs
        end
        mod.UFO_UnitSync(sharedAddRow2._leftRegion, "Buffs Location", {
            self = true,
            copy = function(tbl, from)
                local show = Shown(from)
                tbl.showBuffs = show
                if show then
                    tbl.buffAnchor = from.buffAnchor or "topleft"
                end
            end,
            same = function(tbl, from)
                local show = Shown(from)
                return Shown(tbl) == show
                    and not (show and (tbl.buffAnchor or "topleft") ~= (from.buffAnchor or "topleft"))
            end,
        })
    end
    -- Cog on Buffs Location: the shared settings rows, then Icon Zoom and
    -- Dispel Type Borders
    if not CludesUI._prebuilding then
        local leftRegion = sharedAddRow2._leftRegion
        local buffCogRows = mod.UFO_AuraSettingsRows(
            "buff",
            SValSupported,
            SSetSupported,
            40,
            4,
            nil,
            optionState.selectedUnit ~= "player" and mod.UFO_MAX_COUNT_TOOLTIP or nil
        )
        buffCogRows[#buffCogRows + 1] = {
            type = "slider",
            label = "Icon Zoom",
            min = 0,
            max = 0.20,
            step = 0.01,
            -- The stock styles draw the whole icon (zoom 0); the active
            -- style's name is the requirement noun the widget wraps.
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                return CludesUI.BlizzStyle.Label("unitframes")
            end,
            requireState = "disabled",
            get = SValSupportedRow("buffIconZoom", 0.07),
            set = SSetSupportedRow("buffIconZoom"),
        }
        buffCogRows[#buffCogRows + 1] = {
            type = "toggle",
            label = "Dispel Type Borders",
            disabled = function()
                return optionState.selectedUnit == "player" or CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                if optionState.selectedUnit == "player" then
                    return "This option is not available on the player frame"
                end
                return "This option requires Blizzard Style to be disabled"
            end,
            get = function()
                return optionState.selectedUnit ~= "player"
                    and SValSupported("buffDispelBorder", false) == true
            end,
            set = SSetSupportedRow("buffDispelBorder"),
        }
        CludesUI.BuildInlineCog(leftRegion, {
            disabled = BuffsOff,
            disabledTooltip = "Buff Display",
            title = "Buff Settings",
            rows = buffCogRows,
        })
    end
    -- Directions cog on Buff Icon Size (X/Y offsets, spacing)
    if not CludesUI._prebuilding then
        local rightRegion = sharedAddRow2._rightRegion
        CludesUI.BuildInlineCog(rightRegion, {
            disabled = BuffsOff,
            disabledTooltip = "Buff Display",
            title = "Buff Position",
            rows = mod.UFO_AuraPositionRows("buff", SValSupported, SSetSupported),
        })
    end

    -- Buffs row 2: Duration Text Size | Stack Size. HIDDEN while Buff Display is
    -- None (DependentSetValue rebuilds). Duration Size is gated by an inline
    -- "Show Cooldown Text" toggle; off disables the slider/cog/label.
    if not BuffsOff() then
        local buffDurOff = function()
            return BuffsOff() or not SValSupported("buffShowCooldownText", false)
        end
        local buffDurTip = function()
            return BuffsOff() and "Buff Display" or "Show Cooldown Text"
        end
        local sharedBuffRow2
        sharedBuffRow2, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Buff Duration Size",
            min = 6,
            max = 100,
            step = 1,
            trackWidth = 120,
            disabled = buffDurOff,
            disabledTooltip = buffDurTip,
            getValue = SValSupportedRow("buffCooldownTextSize", 10),
            setValue = SSetSupportedRow("buffCooldownTextSize"),
        }, {
            type = "slider",
            text = "Buff Stack Size",
            min = 6,
            max = 100,
            step = 1,
            disabled = BuffsOff,
            disabledTooltip = "Buff Display",
            getValue = SValSupportedRow("buffStackTextSize", 14),
            setValue = SSetSupportedRow("buffStackTextSize"),
        })
        cursorY = cursorY - height
        -- Directions cog on Buff Duration Size (X/Y offsets) -- disabled with the row
        if not CludesUI._prebuilding then
            local leftRegion = sharedBuffRow2._leftRegion
            CludesUI.BuildInlineCog(leftRegion, {
                disabled = buffDurOff,
                disabledTooltip = buffDurTip,
                title = "Duration Text",
                rows = {
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("buffCooldownTextOffsetX", 0),
                        set = SSetSupportedRow("buffCooldownTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("buffCooldownTextOffsetY", 0),
                        set = SSetSupportedRow("buffCooldownTextOffsetY"),
                    },
                    {
                        type = "slider",
                        label = "Precise Below (minutes, 0 = off)",
                        min = 0,
                        max = 90,
                        step = 1,
                        get = function()
                            local value = SValSupported("buffCooldownTextPrecision", nil)
                            return value and value / 60 or 0
                        end,
                        set = function(value)
                            SSetSupported("buffCooldownTextPrecision", value > 0 and value * 60 or nil)
                        end,
                    },
                },
            })
        end
        -- Inline "Show Cooldown Text" toggle on Buff Duration Size (always enabled)
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineToggle({
                region = sharedBuffRow2._leftRegion,
                getValue = SValSupportedRow("buffShowCooldownText", false),
                setValue = SSetSupportedRow("buffShowCooldownText"),
                onToggle = function()
                    CludesUI:RefreshPage()
                end,
            })
        end
        -- Directions cog on Buff Stack Size (X/Y offsets)
        if not CludesUI._prebuilding then
            local rightRegion = sharedBuffRow2._rightRegion
            CludesUI.BuildInlineCog(rightRegion, {
                disabled = BuffsOff,
                disabledTooltip = "Buff Display",
                title = "Stack Position",
                rows = {
                    {
                        type = "dropdown",
                        label = "Position",
                        values = {
                            bottomright = "Bottom Right",
                            bottomleft = "Bottom Left",
                            topright = "Top Right",
                            topleft = "Top Left",
                            center = "Center",
                        },
                        order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                        get = SValSupportedRow("buffStackTextPosition", "bottomright"),
                        set = SSetSupportedRow("buffStackTextPosition"),
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("buffStackTextOffsetX", 0),
                        set = SSetSupportedRow("buffStackTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("buffStackTextOffsetY", 0),
                        set = SSetSupportedRow("buffStackTextOffsetY"),
                    },
                },
            })
        end
    end -- close Buff row 2 hidden-while-None gate

    -- Debuffs: Location | Icon Size + inline directions cog (X/Y)
    local sharedAddRow3
    sharedAddRow3, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Debuff Display",
        values = buffAnchorValues,
        order = buffAnchorOrder,
        getValue = SValSupportedRow("debuffAnchor", "bottomleft"),
        -- DependentSetValue: the Debuff Duration/Stack row (and, together
        -- with Buff Display, the filter row) hides while None; only the
        -- None <-> shown flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return not DebuffsOff()
        end, function(value)
            SwapAuraSlot(UNIT_DB_MAP[optionState.selectedUnit](), "debuffAnchor", value)
            ReloadAndUpdate()
            UpdatePreview()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "slider",
        text = "Debuff Size",
        min = 10,
        max = 70,
        step = 1,
        disabled = DebuffsOff,
        disabledTooltip = "Debuff Display",
        getValue = SValSupportedRow("debuffSize", 22),
        setValue = SSetSupportedRow("debuffSize"),
    })
    cursorY = cursorY - height
    -- Cog on Debuffs Location: the shared settings rows, then Icon Zoom,
    -- Dispel Type Borders and (player) Use Dispel Colors
    if not CludesUI._prebuilding then
        local leftRegion = sharedAddRow3._leftRegion
        local maxImpRow
        if optionState.selectedUnit ~= "player" then
            maxImpRow = mod.UFO_MaxImportantRow(SDB, function()
                ReloadAndUpdate()
                UpdatePreview()
            end, 20, 20)
        end
        local debuffCogRows = mod.UFO_AuraSettingsRows(
            "debuff",
            SValSupported,
            SSetSupported,
            20,
            20,
            maxImpRow,
            mod.UFO_MAX_COUNT_TOOLTIP
        )
        debuffCogRows[#debuffCogRows + 1] = {
            type = "slider",
            label = "Icon Zoom",
            min = 0,
            max = 0.20,
            step = 0.01,
            -- The stock styles draw the whole icon (zoom 0); the active
            -- style's name is the requirement noun the widget wraps.
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                return CludesUI.BlizzStyle.Label("unitframes")
            end,
            requireState = "disabled",
            get = SValSupportedRow("debuffIconZoom", 0.07),
            set = SSetSupportedRow("debuffIconZoom"),
        }
        debuffCogRows[#debuffCogRows + 1] = {
            type = "toggle",
            label = "Dispel Type Borders",
            -- The stock styles always paint the stock per-type border.
            disabled = function()
                return CludesUI.BlizzStyle.Get("unitframes")
            end,
            disabledTooltip = function()
                return CludesUI.BlizzStyle.Label("unitframes")
            end,
            requireState = "disabled",
            get = SValSupportedRow("debuffDispelBorder", false),
            set = SSetSupportedRow("debuffDispelBorder"),
        }
        -- Player only: the Dispel Colors palette (the Dispel Overlay row's
        -- swatches) tints the player's dispel type borders.
        if optionState.selectedUnit == "player" then
            debuffCogRows[#debuffCogRows + 1] = {
                type = "toggle",
                label = "Use Dispel Colors",
                tooltip = "Colors the dispel type borders with your Dispel Colors instead of Blizzard's.",
                disabled = function()
                    return CludesUI.BlizzStyle.Get("unitframes")
                        or SValSupported("debuffDispelBorder", false) ~= true
                end,
                disabledTooltip = function()
                    if CludesUI.BlizzStyle.Get("unitframes") then
                        return CludesUI.BlizzStyle.Label("unitframes")
                    end
                    return "This option requires Dispel Type Borders to be enabled."
                end,
                requireState = "disabled",
                get = function()
                    return SValSupported("debuffDispelUsePalette", false) == true
                end,
                -- RefreshPage (fast path) so the Dispel Colors swatches track it.
                set = function(value)
                    SSetSupported("debuffDispelUsePalette", value)
                    CludesUI:RefreshPage()
                end,
            }
        end
        CludesUI.BuildInlineCog(leftRegion, {
            disabled = DebuffsOff,
            disabledTooltip = "Debuff Display",
            title = "Debuff Settings",
            rows = debuffCogRows,
        })
    end
    -- Directions cog on Debuff Icon Size (X/Y offsets, spacing)
    if not CludesUI._prebuilding then
        local rightRegion = sharedAddRow3._rightRegion
        CludesUI.BuildInlineCog(rightRegion, {
            disabled = DebuffsOff,
            disabledTooltip = "Debuff Display",
            title = "Debuff Position",
            rows = mod.UFO_AuraPositionRows("debuff", SValSupported, SSetSupported),
        })
    end

    -- Debuffs row 2: Duration Text Size | Stack Size. HIDDEN while Debuff Display
    -- is None (DependentSetValue rebuilds). Duration Size is gated by an inline
    -- "Show Cooldown Text" toggle; off disables the slider/cog/label.
    if not DebuffsOff() then
        local debuffDurOff = function()
            return DebuffsOff() or not SValSupported("debuffShowCooldownText", false)
        end
        local debuffDurTip = function()
            return DebuffsOff() and "Debuff Display" or "Show Cooldown Text"
        end
        local sharedDebuffRow2
        sharedDebuffRow2, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Debuff Duration Size",
            min = 6,
            max = 100,
            step = 1,
            trackWidth = 120,
            disabled = debuffDurOff,
            disabledTooltip = debuffDurTip,
            getValue = SValSupportedRow("debuffCooldownTextSize", 10),
            setValue = SSetSupportedRow("debuffCooldownTextSize"),
        }, {
            type = "slider",
            text = "Debuff Stack Size",
            min = 6,
            max = 100,
            step = 1,
            disabled = DebuffsOff,
            disabledTooltip = "Debuff Display",
            getValue = SValSupportedRow("debuffStackTextSize", 14),
            setValue = SSetSupportedRow("debuffStackTextSize"),
        })
        cursorY = cursorY - height
        -- Directions cog on Debuff Duration Size (X/Y offsets) -- disabled with the row
        if not CludesUI._prebuilding then
            local leftRegion = sharedDebuffRow2._leftRegion
            CludesUI.BuildInlineCog(leftRegion, {
                disabled = debuffDurOff,
                disabledTooltip = debuffDurTip,
                title = "Duration Text",
                rows = {
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("debuffCooldownTextOffsetX", 0),
                        set = SSetSupportedRow("debuffCooldownTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("debuffCooldownTextOffsetY", 0),
                        set = SSetSupportedRow("debuffCooldownTextOffsetY"),
                    },
                    {
                        type = "slider",
                        label = "Precise Below (minutes, 0 = off)",
                        min = 0,
                        max = 90,
                        step = 1,
                        get = function()
                            local value = SValSupported("debuffCooldownTextPrecision", nil)
                            return value and value / 60 or 0
                        end,
                        set = function(value)
                            SSetSupported("debuffCooldownTextPrecision", value > 0 and value * 60 or nil)
                        end,
                    },
                },
            })
        end
        -- Inline "Show Cooldown Text" toggle on Debuff Duration Size (always enabled)
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineToggle({
                region = sharedDebuffRow2._leftRegion,
                getValue = SValSupportedRow("debuffShowCooldownText", false),
                setValue = SSetSupportedRow("debuffShowCooldownText"),
                onToggle = function()
                    CludesUI:RefreshPage()
                end,
            })
        end
        -- Directions cog on Debuff Stack Size (X/Y offsets)
        if not CludesUI._prebuilding then
            local rightRegion = sharedDebuffRow2._rightRegion
            CludesUI.BuildInlineCog(rightRegion, {
                disabled = DebuffsOff,
                disabledTooltip = "Debuff Display",
                title = "Stack Position",
                rows = {
                    {
                        type = "dropdown",
                        label = "Position",
                        values = {
                            bottomright = "Bottom Right",
                            bottomleft = "Bottom Left",
                            topright = "Top Right",
                            topleft = "Top Left",
                            center = "Center",
                        },
                        order = { "bottomright", "bottomleft", "topright", "topleft", "center" },
                        get = SValSupportedRow("debuffStackTextPosition", "bottomright"),
                        set = SSetSupportedRow("debuffStackTextPosition"),
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("debuffStackTextOffsetX", 0),
                        set = SSetSupportedRow("debuffStackTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = SValSupportedRow("debuffStackTextOffsetY", 0),
                        set = SSetSupportedRow("debuffStackTextOffsetY"),
                    },
                },
            })
        end
    end -- close Debuff row 2 hidden-while-None gate

    -- Built here with the aura section's helpers, but appended only after
    -- all other buff/debuff controls so the border row stays last.
    local function AddAuraBorderSettings()
        if
            optionState.selectedUnit == "player"
            or optionState.selectedUnit == "target"
            or optionState.selectedUnit == "focus"
        then
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local auraBorderRow
            auraBorderRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("unitframes", {
                    type = "dropdown",
                    text = "Border Style",
                    values = texValues,
                    order = texOrder,
                    getValue = function()
                        return SVal("auraBorderTexture", "solid")
                    end,
                    setValue = function(value)
                        local color, behind, behindUnitFrame = CludesUI.GetBorderStyleSelectDefaults(value)
                        local cfg = SDB()
                        cfg.auraBorderTexture = value
                        cfg.auraBorderTextureOffset = nil
                        cfg.auraBorderTextureOffsetY = nil
                        cfg.auraBorderTextureShiftX = nil
                        cfg.auraBorderTextureShiftY = nil
                        cfg.auraBorderBehind = behind
                        cfg.auraBorderBehindUnitFrame = behindUnitFrame
                        cfg.auraBorderR = color.r
                        cfg.auraBorderG = color.g
                        cfg.auraBorderB = color.b
                        cfg.auraBorderA = 1
                        local defSz = CludesUI.GetBorderDefaultSize("unitframes", value)
                        if defSz then
                            cfg.auraBorderSize = defSz
                        end
                        -- A style pick returns the icons to their legacy step; clear a
                        -- set exact size (false travels through mirror sync, nil would not).
                        if cfg.auraBorderSizePx then
                            cfg.auraBorderSizePx = false
                        end
                        ReloadAndUpdate()
                        UpdatePreview()
                        -- The Width / Height Offset row exists only under a textured style.
                        CludesUI:RefreshPage(true)
                    end,
                }),
                CludesUI.BlizzStyle.Gate(
                    "unitframes",
                    CludesUI.BorderPxSliderCfg({
                        text = "Border Size",
                        trackWidth = 120,
                        getStep = function()
                            return SVal("auraBorderSize", 1)
                        end,
                        setStep = function(step)
                            SDB().auraBorderSize = step
                        end,
                        getTex = function()
                            return SVal("auraBorderTexture", "solid")
                        end,
                        getPx = function()
                            return SGet("auraBorderSizePx")
                        end,
                        setPx = function(value)
                            SDB().auraBorderSizePx = value
                        end,
                        apply = function()
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    })
                )
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: a textured aura border's outward offsets
            -- (a Solid border has none).
            do
                local abTex = SVal("auraBorderTexture", "solid")
                if abTex ~= "solid" and abTex ~= "" then
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "unitframes",
                        getTex = function()
                            return SVal("auraBorderTexture", "solid")
                        end,
                        getStep = function()
                            return SVal("auraBorderSize", 1)
                        end,
                        getSizeKey = function()
                            return SVal("auraBorderSize", 1)
                        end,
                        getPx = function()
                            return SGet("auraBorderSizePx")
                        end,
                        getX = function()
                            return SGet("auraBorderTextureOffset")
                        end,
                        setX = function(value)
                            SDB().auraBorderTextureOffset = value
                        end,
                        getY = function()
                            return SGet("auraBorderTextureOffsetY")
                        end,
                        setY = function(value)
                            SDB().auraBorderTextureOffsetY = value
                        end,
                        apply = function()
                            ReloadAndUpdate()
                            UpdatePreview()
                        end,
                    })
                    _, height = W:DualRow(
                        hostFrame,
                        cursorY,
                        CludesUI.BlizzStyle.Gate("unitframes", ocfgL),
                        CludesUI.BlizzStyle.Gate("unitframes", ocfgR)
                    )
                    cursorY = cursorY - height
                end
            end

            if not CludesUI._prebuilding then
                local region = auraBorderRow._leftRegion
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
                                local value = SGet("auraBorderTextureShiftX")
                                if value ~= nil then
                                    return value
                                end
                                local _, _, sx = CludesUI.GetBorderDefaults(
                                    "unitframes",
                                    SVal("auraBorderTexture", "solid"),
                                    SVal("auraBorderSize", 1)
                                )
                                return sx
                            end,
                            set = function(value)
                                SSetSupported("auraBorderTextureShiftX", value == 0 and nil or value)
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local value = SGet("auraBorderTextureShiftY")
                                if value ~= nil then
                                    return value
                                end
                                local _, _, _, sy = CludesUI.GetBorderDefaults(
                                    "unitframes",
                                    SVal("auraBorderTexture", "solid"),
                                    SVal("auraBorderSize", 1)
                                )
                                return sy
                            end,
                            set = function(value)
                                SSetSupported("auraBorderTextureShiftY", value == 0 and nil or value)
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = function()
                                return SVal("auraBorderBehind", false)
                            end,
                            set = SSetSupportedRow("auraBorderBehind"),
                        },
                        {
                            type = "toggle",
                            label = "Behind Unit Frame",
                            get = function()
                                return SVal("auraBorderBehindUnitFrame", false)
                            end,
                            set = SSetSupportedRow("auraBorderBehindUnitFrame"),
                        },
                        {
                            type = "toggle",
                            label = "Textured Dispel Ring",
                            tooltip = "Draws the dispel-colored ring in this border style's shape instead of flat lines.",
                            -- Needs a dispel ring to draw: the debuff Dispel Type Borders,
                            -- or on Target/Focus the Buff Settings cog's own.
                            disabled = function()
                                return SVal("debuffDispelBorder", false) ~= true
                                    and not (
                                        optionState.selectedUnit ~= "player"
                                        and SVal("buffDispelBorder", false) == true
                                    )
                            end,
                            disabledTooltip = "Dispel Type Borders",
                            get = function()
                                return SVal("auraBorderDispelTextured", false) == true
                            end,
                            set = SSetSupportedRow("auraBorderDispelTextured"),
                        },
                    },
                })
                local function UpdateCogVis()
                    if SVal("auraBorderTexture", "solid") == "solid" then
                        cogBtn:Hide()
                    else
                        cogBtn:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end

            if not CludesUI._prebuilding then
                local region = auraBorderRow._rightRegion
                local colorSwatch, refreshSwatch = CludesUI.BuildColorSwatch(
                    region,
                    auraBorderRow:GetFrameLevel() + 3,
                    function()
                        return SVal("auraBorderR", 0),
                            SVal("auraBorderG", 0),
                            SVal("auraBorderB", 0),
                            SVal("auraBorderA", 1)
                    end,
                    function(red, green, blue, a)
                        local cfg = SDB()
                        cfg.auraBorderR = red
                        cfg.auraBorderG = green
                        cfg.auraBorderB = blue
                        cfg.auraBorderA = a
                        ReloadAndUpdate()
                        UpdatePreview()
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", region._control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(refreshSwatch)
            end
        end
    end

    -- Per-unit aura filters (NOT synced). Labels track the selected section.
    -- Buff Filter (and the player frame's Debuff Filter) are multi-select
    -- checkbox dropdowns swapped into the DualRow slots below; the
    -- target/focus Debuff Filter is a native single-select mode dropdown
    -- (DebuffModeDropdownCfg). HIDDEN only when BOTH displays are None
    -- (either dropdown's DependentSetValue rebuilds on its None flip); with
    -- one side shown, the off side just grays out.
    if not (BuffsOff() and DebuffsOff()) then
        do
            local buffFilterItems, BUFF_FILTER_KEYS, BUFF_NEG_SKEYS
            -- Two-lane rows: Show narrows the frame to checked classes (legacy
            -- behavior, nothing checked = show everything); Hide removes a class
            -- from whatever shows (s.buffNegClasses, engine ClassNegated).
            -- Non-player buff vocabulary is just these three (the engine gates
            -- every other class off for these units; stale keys from retired
            -- checkboxes stay inert).
            buffFilterItems = {
                -- AND-modifier (engine: ChainFor), not a class: never locks a lane.
                {
                    key = "__hasDuration",
                    label = "Has Duration",
                    tooltip = "Only show buffs that have a duration, excluding permanent ones. Combines with the filters below.",
                },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
                {
                    key = "stealable",
                    label = "Stealable",
                    dual = true,
                    tooltip = "Buffs you can spellsteal or purge",
                },
                {
                    key = "bigDefensive",
                    label = "Big Defensive",
                    dual = true,
                    tooltip = "Major defensive cooldowns",
                },
                {
                    key = "dispellable",
                    label = "Dispellable",
                    dual = true,
                    tooltip = "Auras with a dispel type you can dispel",
                },
            }
            BUFF_FILTER_KEYS = {
                ownOnly = "onlyPlayerBuffs",
                raidFrames = "buffRaid",
                raidInCombat = "buffRaidInCombat",
                dispellable = "buffDispellable",
                crowdControl = "buffCrowdControl",
                bigDefensive = "buffBigDefensive",
                externalDefensive = "buffExternalDefensive",
                cancelable = "buffCancelable",
                stealable = "buffStealable",
            }
            -- Hide-lane storage skeys (per-class entries in s.buffNegClasses);
            -- only dual rows appear here.
            BUFF_NEG_SKEYS =
                { stealable = "Stealable", bigDefensive = "BigDefensive", dispellable = "Dispellable" }
            local unitLabel = UNIT_LABELS_SUP[optionState.selectedUnit] or "Player"
            -- Right slot: the player frame swaps its checkbox dropdown in below;
            -- target/focus get the mode dropdown here (disabled, with the
            -- requirement tooltip, while Debuff Display is None).
            local debuffSlot
            if optionState.selectedUnit == "player" then
                debuffSlot = {
                    type = "dropdown",
                    text = unitLabel .. " Debuff Filter",
                    values = { __placeholder = "..." },
                    order = { "__placeholder" },
                    getValue = function()
                        return "__placeholder"
                    end,
                    setValue = function() end,
                }
            else
                debuffSlot = DebuffModeDropdownCfg(
                    unitLabel .. " Debuff Filter",
                    optionState.selectedUnit,
                    SDB,
                    ReloadAndUpdate,
                    { disabled = DebuffsOff, disabledTooltip = "Debuffs", requireState = "displayed" }
                )
            end
            local filterRow
            filterRow, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = unitLabel .. " Buff Filter",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }, debuffSlot)
            cursorY = cursorY - height
            -- Gray out + block a CB-dropdown when its column's Display is "none".
            local function ApplyFilterDisabled(checkDrop, labelText, isOff)
                local function refresh()
                    local off = isOff()
                    checkDrop:SetAlpha(off and 0.3 or 1)
                    checkDrop:EnableMouse(not off)
                    if labelText then
                        labelText:SetAlpha(off and 0.3 or 1)
                    end
                end
                refresh()
                RegisterWidgetRefresh(refresh)
            end
            -- Left slot: Buff Filter. Player frame runs the Player Aura Bars Filters
            -- model verbatim (keep in sync with BuildAssignedBuffsFields in
            -- CUI_PlayerAuraBars_ManagerPages.lua): pinned All Buffs/Has Duration above
            -- a divider, then shared PAB_Filters entries. Checked filters SUBTRACT
            -- while All Buffs is on, ADD with it off; toggling clears selection. Other units keep the class-checkbox model.
            if not CludesUI._prebuilding then
                local region = filterRow._leftRegion
                if region._control then
                    region._control:Hide()
                end
                local checkDrop, cbRefresh
                if optionState.selectedUnit == "player" then
                    -- The registry list needs the curated presets present
                    -- (idempotent; PAB may be disabled).
                    if mod.PAB_ImportBM2Filters then
                        mod.PAB_ImportBM2Filters()
                    end
                    local ps = UNIT_DB_MAP[optionState.selectedUnit]()
                    local ALL_KEY, DUR_KEY = "__allBuffs", "__hasDuration"
                    -- Hovering a dimmed Show box explains the dim (the lane is inert
                    -- while a broad mode already shows everything), same wording as
                    -- the Debuff Filter.
                    local lockedTip = CludesUI.L(
                        "All Buffs or Has Duration is selected, so every buff already shows. Use the red Hide box to exclude these instead."
                    )
                    -- Any Show-lane filter, or a direct Extra Spell, counts as a
                    -- content source once neither broad mode is on.
                    local function OtherContent()
                        if ps.buffFilters and next(ps.buffFilters) then
                            -- WoW Forever: visible filters only (a hidden retail
                            -- preset shows nothing on this client).
                            if not CludesUI.IS_FOREVER then
                                return true
                            end
                            for fid in pairs(ps.buffFilters) do
                                if not mod.PAB_HiddenPresetFilter(fid) then
                                    return true
                                end
                            end
                        end
                        if ps.buffSpells and #ps.buffSpells > 0 then
                            return true
                        end
                        return false
                    end
                    local function FilterItems()
                        local itemList = {
                            {
                                isTopAction = true,
                                label = "Edit Filters",
                                onClick = function()
                                    if mod.PABMP_ShowFilterEditor then
                                        mod.PABMP_ShowFilterEditor()
                                        -- Filter edits change the resolved spell
                                        -- sets; refresh the frame when the modal
                                        -- closes (the editor is our own frame).
                                        local ed = mod._pabFilterEditor
                                        if ed and not ed._ufReloadHook then
                                            ed._ufReloadHook = true
                                            ed:HookScript("OnHide", function()
                                                ReloadAndUpdate()
                                            end)
                                        end
                                    end
                                end,
                            },
                            -- Blacklist editing only matters while broad
                            -- content is on (All Buffs / Has Duration).
                            {
                                isTopAction = true,
                                label = "Edit Blacklist",
                                lockedFn = function()
                                    return ps.buffShowAll == false and ps.buffHasDuration ~= true
                                end,
                                lockedTooltip = function()
                                    return CludesUI.DisabledTooltip("All Buffs or Has Duration", "enabled")
                                end,
                                onClick = function()
                                    CludesUI.ShowSpellBlacklistPopup({
                                        title = "Buff Blacklist",
                                        get = function()
                                            return ps.buffBlacklist
                                        end,
                                        add = function(ident)
                                            ps.buffBlacklist = ps.buffBlacklist or {}
                                            ps.buffBlacklist[ident] = true
                                        end,
                                        remove = function(ident)
                                            if ps.buffBlacklist then
                                                ps.buffBlacklist[ident] = nil
                                                if not next(ps.buffBlacklist) then
                                                    ps.buffBlacklist = nil
                                                end
                                            end
                                        end,
                                        onChanged = function()
                                            ReloadAndUpdate()
                                        end,
                                    })
                                end,
                            },
                            {
                                key = ALL_KEY,
                                label = "All Buffs",
                                tooltip = "Show every buff. Use the Hide lane below to remove specific filters.",
                            },
                            {
                                key = DUR_KEY,
                                label = "Has Duration",
                                tooltip = "Show every buff that has a duration (hides permanent buffs). Use the Hide lane below to remove specific filters.",
                            },
                            { isHeader = true, label = "Show", rightLabel = "Hide" },
                        }
                        local BroadOn = function()
                            return ps.buffShowAll ~= false or ps.buffHasDuration == true
                        end
                        local entries = mod.PAB_Filters and mod.PAB_Filters() or {}
                        -- Buff Manager parity ordering (matches the PAB pages'
                        -- SortFiltersCanonical): presets in curated catalogue
                        -- order (Defensives leads), then user filters in
                        -- creation order.
                        local rank = {}
                        local BP = CludesUI.BUFF_PRESETS
                        if BP and BP.filters then
                            for idx = 1, #BP.filters do
                                rank[BP.filters[idx].name] = idx
                            end
                        end
                        local sorted, place = {}, {}
                        for idx = 1, #entries do
                            sorted[#sorted + 1] = entries[idx]
                            place[entries[idx]] = idx
                        end
                        table.sort(sorted, function(lhs, rhs)
                            return (rank[lhs.name] or (1000 + place[lhs])) < (rank[rhs.name] or (1000 + place[rhs]))
                        end)
                        for idx = 1, #sorted do
                            itemList[#itemList + 1] = {
                                key = sorted[idx].id,
                                label = sorted[idx].name,
                                dual = true,
                                showLockedFn = BroadOn,
                                showLockedTooltip = lockedTip,
                            }
                        end
                        return itemList
                    end
                    if mod.UF_EnsurePlayerAuraLanes then
                        mod.UF_EnsurePlayerAuraLanes(ps)
                    end
                    local warnClosed
                    checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                        region,
                        210,
                        region:GetFrameLevel() + 2,
                        FilterItems,
                        function(keyName, neg)
                            if keyName == ALL_KEY then
                                return ps.buffShowAll ~= false
                            end
                            if keyName == DUR_KEY then
                                return ps.buffHasDuration == true
                            end
                            if neg then
                                local nf = ps.buffNegFilters
                                return nf and nf[keyName] == true
                            end
                            return ps.buffFilters and ps.buffFilters[keyName] == true
                        end,
                        function(keyName, value, neg)
                            if keyName == ALL_KEY then
                                -- Written unconditionally (Player Aura Bars parity): the
                                -- Show lane is locked while a broad mode is on, so a
                                -- no-empty guard here would make the toggle impossible to
                                -- turn off. AttachEmptyFilterWarn below owns the feedback
                                -- for the resulting empty selection instead.
                                ps.buffShowAll = value
                                -- Mutually exclusive with Has Duration (both are broad-content
                                -- modes). Lanes persist across mode flips (the hide lane
                                -- subtracts in both modes).
                                ps.buffHasDuration = nil
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            if keyName == DUR_KEY then
                                ps.buffHasDuration = value or nil
                                -- Mutually exclusive with All Buffs (its own broad-content
                                -- mode); lanes persist.
                                if value then
                                    ps.buffShowAll = false
                                end
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            -- Two-lane filter write: checking one lane clears the other;
                            -- emptied lane tables drop to nil (saved-variable hygiene).
                            if neg then
                                ps.buffNegFilters = ps.buffNegFilters or {}
                                ps.buffNegFilters[keyName] = value or nil
                                if not next(ps.buffNegFilters) then
                                    ps.buffNegFilters = nil
                                end
                                if value and ps.buffFilters then
                                    ps.buffFilters[keyName] = nil
                                end
                            else
                                ps.buffFilters = ps.buffFilters or {}
                                ps.buffFilters[keyName] = value or nil
                                if value and ps.buffNegFilters then
                                    ps.buffNegFilters[keyName] = nil
                                    if not next(ps.buffNegFilters) then
                                        ps.buffNegFilters = nil
                                    end
                                end
                            end
                            if ps.buffFilters and not next(ps.buffFilters) then
                                ps.buffFilters = nil
                            end
                            ReloadAndUpdate()
                            -- Non-force: runs only the registered lightweight refresh
                            -- callbacks (the empty-selection warning below) in place,
                            -- without closing this open dropdown.
                            CludesUI:RefreshPage()
                        end,
                        nil,
                        12,
                        nil,
                        nil,
                        function()
                            if warnClosed then
                                warnClosed()
                            end
                        end
                    )
                    -- Empty-selection warning (Player Aura Bars parity): replaces the
                    -- old silent block. A Buff Display of None already dims the whole
                    -- control, so it is not warned about a second time.
                    warnClosed = CludesUI.AttachEmptyFilterWarn(
                        region,
                        checkDrop,
                        CludesUI.L("You are displaying NO buffs at all."),
                        function()
                            return BuffsOff()
                                or ps.buffShowAll ~= false
                                or ps.buffHasDuration == true
                                or OtherContent()
                        end
                    )
                else
                    checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                        region,
                        210,
                        region:GetFrameLevel() + 2,
                        buffFilterItems,
                        function(keyName, neg)
                            if keyName == "__hasDuration" then
                                return SDB().buffDurOnly == true
                            end
                            if neg then
                                local m = SDB().buffNegClasses
                                local sk = BUFF_NEG_SKEYS[keyName]
                                return m ~= nil and sk ~= nil and m[sk] == true
                            end
                            return SValSupported(BUFF_FILTER_KEYS[keyName], false)
                        end,
                        function(keyName, value, neg)
                            local saved = SDB()
                            if keyName == "__hasDuration" then
                                -- Not buffHasDuration: that is the player's broad
                                -- mode, which copies can have left on this unit.
                                saved.buffDurOnly = value or nil
                                ReloadAndUpdate()
                                UpdatePreview()
                                return
                            end
                            local sk = BUFF_NEG_SKEYS[keyName]
                            if neg then
                                if not sk then
                                    return
                                end
                                saved.buffNegClasses = saved.buffNegClasses or {}
                                saved.buffNegClasses[sk] = value and true or nil
                                if not next(saved.buffNegClasses) then
                                    saved.buffNegClasses = nil
                                end
                                if value then
                                    saved[BUFF_FILTER_KEYS[keyName]] = nil
                                end
                                ReloadAndUpdate()
                                UpdatePreview()
                                return
                            end
                            if value and sk and saved.buffNegClasses then
                                saved.buffNegClasses[sk] = nil
                                if not next(saved.buffNegClasses) then
                                    saved.buffNegClasses = nil
                                end
                            end
                            SSetSupported(BUFF_FILTER_KEYS[keyName], value)
                        end
                    )
                end
                Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
                region._control = checkDrop
                region._lastInline = nil
                RegisterWidgetRefresh(cbRefresh)
                ApplyFilterDisabled(checkDrop, region._label, BuffsOff)

                -- Purgeable Buff Glow (target/focus): inline cog beside the Buff
                -- Filter. The glow styles whichever purgeable buffs the filter
                -- shows; the engine gates it on the character's offensive dispel.
                if optionState.selectedUnit == "target" or optionState.selectedUnit == "focus" then
                    -- Shared glow controls over the unit's own keys. Engine aura
                    -- buttons: C-side styles only. Unset color = the suite default (gold).
                    local GO = CludesUI.GlowOptions
                    local pgDesc = UF_PurgeGlowDesc(SDB)
                    local pgRows = GO.PopupRows(pgDesc, "Glow Style")
                    pgRows[1].tooltip =
                        "Glows the buffs you can purge or spellsteal. Glowing buffs lead the row and have their own Max Buffs count."
                    CludesUI.BuildInlineCog(region, {
                        title = "Purgeable Buffs",
                        tip = "Glow the buffs you can purge or spellsteal",
                        -- Greys out with the Buff Display (None = no buffs to glow).
                        disabled = BuffsOff,
                        disabledTooltip = "Buffs",
                        rows = pgRows,
                    })
                end
            end
            -- Right slot (player frame): the Player Aura Bars debuff Filters model
            -- verbatim (sync with BuildAssignedDebuffsFields): pinned All Debuffs
            -- above a divider, then shared class vocabulary (ns.PAB_ClassItems).
            -- Checked classes SUBTRACT while All Debuffs is on, ADD with it off; class
            -- rows view the SAME legacy per-class keys (s.debuff<SKey>) the old dropdown
            -- wrote. Target/focus built their mode dropdown in the DualRow above.
            if optionState.selectedUnit == "player" and not CludesUI._prebuilding then
                local region = filterRow._rightRegion
                if region._control then
                    region._control:Hide()
                end
                local checkDrop, cbRefresh
                do
                    local ps = UNIT_DB_MAP[optionState.selectedUnit]()
                    local ALL_KEY, DUR_KEY = "__allDebuffs", "__debuffHasDuration"
                    local HIDE_EXH_KEY = "__hideExhaustion"
                    local function AllOn()
                        return ps.debuffShowAll ~= false
                    end
                    -- Hovering a dimmed Show box explains the dim (the lane is inert
                    -- while All Debuffs already shows everything), same wording as
                    -- Player Aura Bars.
                    local lockedTip = CludesUI.L(
                        "All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead."
                    )
                    -- Any Show-lane class counts as a content source -- scanned over the
                    -- FULL vocabulary (stale keys from retired checkboxes still render in
                    -- add mode, so they legitimately hold content).
                    local function AnyShowClass()
                        local function Scan(entries)
                            if not entries then
                                return false
                            end
                            for idx = 1, #entries do
                                local class = entries[idx]
                                if not class.buffOnly and ps["debuff" .. class.skey] == true then
                                    return true
                                end
                            end
                            return false
                        end
                        return Scan(mod.UF_TokenClasses) or Scan(mod.UF_CandidateClasses)
                    end
                    local function FilterItems()
                        -- Match Mode (ps.debuffFilterMatch: nil = Match Any, the
                        -- union; "all" = one group matching every Show pick). A
                        -- radio pair over one scalar, locked while All Debuffs
                        -- makes the Show lane inert (the setting is kept).
                        local matchLockTip =
                            CludesUI.L("Uncheck All Debuffs to choose how the Show filters combine.")
                        local itemList = {
                            {
                                key = ALL_KEY,
                                label = "All Debuffs",
                                tooltip = "Show every debuff. Use the Hide lane below to remove specific filters.",
                            },
                            {
                                key = DUR_KEY,
                                label = "Has Duration",
                                tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff.",
                            },
                            -- Hide Exhaustion (ps.debuffHideExhaustion, nil = on), as in
                            -- the Player Aura Bars and Raid Frames Filters; kept out of
                            -- the summary.
                            {
                                key = HIDE_EXH_KEY,
                                label = "Hide Exhaustion",
                                tooltip = "Hides Sated, Exhaustion, Temporal Displacement and the other Bloodlust lockout debuffs.",
                                excludeFromSummaryFn = function()
                                    return true
                                end,
                            },
                            { isHeader = true, label = "Match Mode" },
                            {
                                key = "__matchAny",
                                label = CludesUI.L("Match Any Filter"),
                                isModifier = true,
                                lockedFn = AllOn,
                                lockedTooltip = matchLockTip,
                                tooltip = CludesUI.L(
                                    "Shows debuffs that match any checked Show filter (the default)."
                                ),
                            },
                            {
                                key = "__matchAll",
                                label = CludesUI.L("Match All Filters"),
                                isModifier = true,
                                lockedFn = AllOn,
                                lockedTooltip = matchLockTip,
                                tooltip = CludesUI.L(
                                    "Shows only debuffs that match every checked Show filter (dispel types count as one); opposites like Non-Player Auras with Cast By You show nothing."
                                ),
                            },
                            { isHeader = true, label = "Show", rightLabel = "Hide" },
                        }
                        local classItems = mod.PAB_ClassItems and mod.PAB_ClassItems(false) or {}
                        for idx = 1, #classItems do
                            local ci = classItems[idx]
                            if ci.isHeader then
                                itemList[#itemList + 1] = { isHeader = true, label = ci.label }
                            else
                                itemList[#itemList + 1] = {
                                    key = ci.key,
                                    label = ci.label,
                                    tooltip = ci.tooltip,
                                    dual = true,
                                    showLockedFn = AllOn,
                                    showLockedTooltip = lockedTip,
                                }
                            end
                        end
                        return itemList
                    end
                    -- Non-Player / From Any Player share one engine field: a check
                    -- in either lane clears the sibling from both lanes.
                    local function ClearExclusive(keyName)
                        local other = mod.PAB_ExclusiveSkey and mod.PAB_ExclusiveSkey[keyName]
                        if not other then
                            return
                        end
                        ps["debuff" .. other] = nil
                        if ps.debuffNegClasses then
                            ps.debuffNegClasses[other] = nil
                            if not next(ps.debuffNegClasses) then
                                ps.debuffNegClasses = nil
                            end
                        end
                    end
                    if mod.UF_EnsurePlayerAuraLanes then
                        mod.UF_EnsurePlayerAuraLanes(ps)
                    end
                    local warnClosed
                    checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                        region,
                        210,
                        region:GetFrameLevel() + 2,
                        FilterItems,
                        function(keyName, neg)
                            if keyName == ALL_KEY then
                                return AllOn()
                            end
                            if keyName == DUR_KEY then
                                return ps.debuffHasDuration == true
                            end
                            if keyName == HIDE_EXH_KEY then
                                return ps.debuffHideExhaustion ~= false
                            end
                            if keyName == "__matchAny" or keyName == "__matchAll" then
                                return (keyName == "__matchAll") == (ps.debuffFilterMatch == "all")
                            end
                            if neg then
                                local m = ps.debuffNegClasses
                                return m ~= nil and m[keyName] == true
                            end
                            return ps["debuff" .. keyName] == true
                        end,
                        function(keyName, value, neg)
                            if keyName == HIDE_EXH_KEY then
                                if value then
                                    ps.debuffHideExhaustion = nil
                                else
                                    ps.debuffHideExhaustion = false
                                end
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            if keyName == "__matchAny" or keyName == "__matchAll" then
                                -- Radio: the clicked row wins whatever its checked
                                -- state was (re-clicking the active row keeps it).
                                local wanted
                                if keyName == "__matchAll" then
                                    wanted = "all"
                                end
                                if ps.debuffFilterMatch == wanted then
                                    return
                                end
                                ps.debuffFilterMatch = wanted
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            if keyName == ALL_KEY then
                                -- Written unconditionally (Player Aura Bars parity): the
                                -- Show lane is locked while All Debuffs is on, so a
                                -- no-empty guard here would make the toggle impossible to
                                -- turn off. AttachEmptyFilterWarn below owns the feedback
                                -- for the resulting empty selection instead.
                                -- Lanes persist across mode flips (the hide lane
                                -- subtracts in both modes; the show lane goes dormant
                                -- while All Debuffs is on).
                                ps.debuffShowAll = value
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            if keyName == DUR_KEY then
                                -- AND-modifier (never locks the Show lane): combines
                                -- with All Debuffs or the Show picks; alone it is the
                                -- timed catch-all.
                                ps.debuffHasDuration = value or nil
                                ReloadAndUpdate()
                                CludesUI:RefreshPage()
                                return
                            end
                            -- Two-lane class write: checking one lane clears the other.
                            if value then
                                ClearExclusive(keyName)
                            end
                            if neg then
                                ps.debuffNegClasses = ps.debuffNegClasses or {}
                                ps.debuffNegClasses[keyName] = value or nil
                                if not next(ps.debuffNegClasses) then
                                    ps.debuffNegClasses = nil
                                end
                                if value then
                                    ps["debuff" .. keyName] = nil
                                end
                            else
                                ps["debuff" .. keyName] = value or nil
                                if value and ps.debuffNegClasses then
                                    ps.debuffNegClasses[keyName] = nil
                                    if not next(ps.debuffNegClasses) then
                                        ps.debuffNegClasses = nil
                                    end
                                end
                            end
                            ReloadAndUpdate()
                            -- Non-force: runs only the registered lightweight refresh
                            -- callbacks (the empty-selection warning below) in place,
                            -- without closing this open dropdown.
                            CludesUI:RefreshPage()
                        end,
                        nil,
                        12,
                        nil,
                        nil,
                        function()
                            if warnClosed then
                                warnClosed()
                            end
                        end,
                        -- Summary joins picks with " & " while Match All combines them.
                        {
                            separatorFn = function()
                                if ps.debuffFilterMatch == "all" and not AllOn() then
                                    return " & "
                                end
                                return ", "
                            end,
                        }
                    )
                    -- Empty-selection warning (Player Aura Bars parity): replaces the
                    -- old silent block. A Debuff Display of None already dims the whole
                    -- control, so it is not warned about a second time. Match All picks
                    -- that can never match together count as empty (the engine test).
                    warnClosed = CludesUI.AttachEmptyFilterWarn(
                        region,
                        checkDrop,
                        CludesUI.L("You are displaying NO debuffs at all."),
                        function()
                            return DebuffsOff()
                                or AllOn()
                                or (ps.debuffHasDuration == true and not AnyShowClass())
                                or (
                                    AnyShowClass()
                                    and not (mod.UF_DebuffMatchEmpty and mod.UF_DebuffMatchEmpty(ps))
                                )
                        end
                    )
                end
                Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
                region._control = checkDrop
                region._lastInline = nil
                RegisterWidgetRefresh(cbRefresh)
                ApplyFilterDisabled(checkDrop, region._label, DebuffsOff)
            end
            -- Target/focus: Only Tracked Auras with an empty list renders
            -- nothing, so the mode dropdown carries the standard empty warning.
            if optionState.selectedUnit ~= "player" and not CludesUI._prebuilding then
                AttachDebuffModeWarn(filterRow._rightRegion, SDB, DebuffsOff)
                -- Has Duration: an AND-modifier on the picked mode (engine:
                -- ChainFor), in the row's cog since the mode dropdown is
                -- single-select.
                CludesUI.BuildInlineCog(filterRow._rightRegion, {
                    title = "Debuff Filter",
                    tip = "Debuff Filter Options",
                    disabled = DebuffsOff,
                    disabledTooltip = "Debuffs",
                    requireState = "displayed",
                    rows = {
                        {
                            type = "toggle",
                            label = "Has Duration",
                            tooltip = "Only show debuffs that have a duration, excluding permanent ones. Tracked Auras always show.",
                            get = function()
                                return SDB().debuffHasDuration == true
                            end,
                            set = function(value)
                                SDB().debuffHasDuration = value or nil
                                ReloadAndUpdate()
                            end,
                        },
                        HideExhaustionRow(SDB, ReloadAndUpdate),
                    },
                })
            end
        end
    end -- close filter row hidden-while-both-None gate

    -- Dispel Overlay + Dispel Colors (player frame only; settings keys
    -- mirror the Raid Frames dispel system 1:1)
    if optionState.selectedUnit == "player" then
        local dispelOverlayValues = {
            none = "None",
            fill = "Fill Overlay",
            full = "Full Overlay",
            gradient = "Gradient Overlay",
            gradient_sharp = "Gradient Sharp",
            gradient_reverse = "Gradient Sharp Reverse",
        }
        local dispelOverlayOrder =
            { "none", "fill", "full", "gradient", "gradient_sharp", "gradient_reverse" }
        local function ApplyDispelOverlay()
            if mod.UpdatePlayerDispelOverlay then
                mod.UpdatePlayerDispelOverlay()
            end
            UpdatePreview()
        end
        -- Palette edits: the overlay and border copies (DispelRefresh), and
        -- with Use Dispel Colors on also the player debuff rings and the
        -- pet's (while it copies the player frame's aura look), whose
        -- restyle is fingerprint-gated on the palette.
        local function PaletteRefresh()
            ApplyDispelOverlay()
            if saved.profile.player.debuffDispelUsePalette == true then
                if frameList.player then
                    mod.UF_ReloadAuraContainers(frameList.player, "player")
                end
                if frameList.pet and mod.UF_MiniAuraSourceKey("pet") == "player" then
                    mod.UF_ReloadAuraContainers(frameList.pet, "pet")
                end
            end
        end
        -- Color Custom Borders copies the player frame's own border, so it
        -- needs one to copy: the CludesUI style, a Border Style other than
        -- Solid and a Border Size above 0 (runtime twin: ns.UF_CustomBorderOn).
        local function CustomBorderOff()
            return not mod.UF_CustomBorderOn(saved.profile.player)
        end
        local function CustomBorderOffTip()
            if CludesUI.BlizzStyle.Get("unitframes") then
                return CludesUI.BlizzStyle.Label("unitframes")
            end
            local texture = saved.profile.player.borderTexture
            if texture == nil or texture == "" or texture == "solid" then
                return "This option requires a Border Style other than Solid."
            end
            return "This option requires a Border Size above 0."
        end
        local dispelRow
        dispelRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Dispel Overlay",
            values = dispelOverlayValues,
            order = dispelOverlayOrder,
            getValue = function()
                return saved.profile.dispelOverlay or "none"
            end,
            -- RefreshPage (fast path) so the Dispel Colors disabled
            -- state tracks the overlay selection live.
            setValue = function(value)
                saved.profile.dispelOverlay = value
                ApplyDispelOverlay()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "multiSwatch",
            text = "Dispel Colors",
            -- The palette also colours the Color Custom Borders copies and,
            -- with Use Dispel Colors, the player debuff rings.
            disabled = function()
                local profile = saved.profile
                return (profile.dispelOverlay or "none") == "none"
                    and not (profile.dispelCustomBorder == true and mod.UF_CustomBorderOn(profile.player))
                    and profile.player.debuffDispelUsePalette ~= true
            end,
            disabledTooltip = "This option requires a Dispel Overlay, Color Custom Borders or Use Dispel Colors.",
            rawTooltip = true,
            swatches = {
                {
                    tooltip = "Magic",
                    hasAlpha = false,
                    getValue = function()
                        local color = saved.profile.dispelColorMagic
                        if color then
                            return color.r, color.g, color.b
                        end
                        return 0.349, 0.475, 1.0
                    end,
                    setValue = function(red, green, blue)
                        saved.profile.dispelColorMagic = { r = red, g = green, b = blue }
                        PaletteRefresh()
                    end,
                },
                {
                    tooltip = "Curse",
                    hasAlpha = false,
                    getValue = function()
                        local color = saved.profile.dispelColorCurse
                        if color then
                            return color.r, color.g, color.b
                        end
                        return 0.636, 0.0, 0.64
                    end,
                    setValue = function(red, green, blue)
                        saved.profile.dispelColorCurse = { r = red, g = green, b = blue }
                        PaletteRefresh()
                    end,
                },
                {
                    tooltip = "Disease",
                    hasAlpha = false,
                    getValue = function()
                        local color = saved.profile.dispelColorDisease
                        if color then
                            return color.r, color.g, color.b
                        end
                        return 0.671, 0.384, 0.098
                    end,
                    setValue = function(red, green, blue)
                        saved.profile.dispelColorDisease = { r = red, g = green, b = blue }
                        PaletteRefresh()
                    end,
                },
                {
                    tooltip = "Poison",
                    hasAlpha = false,
                    getValue = function()
                        local color = saved.profile.dispelColorPoison
                        if color then
                            return color.r, color.g, color.b
                        end
                        return 0.0, 0.706, 0.286
                    end,
                    setValue = function(red, green, blue)
                        saved.profile.dispelColorPoison = { r = red, g = green, b = blue }
                        PaletteRefresh()
                    end,
                },
                {
                    tooltip = "Bleed",
                    hasAlpha = false,
                    getValue = function()
                        local color = saved.profile.dispelColorBleed
                        if color then
                            return color.r, color.g, color.b
                        end
                        return 0.75, 0.15, 0.15
                    end,
                    setValue = function(red, green, blue)
                        saved.profile.dispelColorBleed = { r = red, g = green, b = blue }
                        PaletteRefresh()
                    end,
                },
            },
        })
        cursorY = cursorY - height
        -- Inline eyeball: preview a magic dispel overlay on the top player preview.
        if not CludesUI._prebuilding then
            local region = dispelRow._leftRegion
            CludesUI.AddPreviewEye(
                region,
                optionState,
                "showDispelOverlayPreview",
                "dispel overlay",
                UpdatePreview
            )
        end
        -- Inline cog on Dispel Overlay: Overlay Opacity
        if not CludesUI._prebuilding then
            local region = dispelRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Dispel Overlay",
                rows = {
                    {
                        type = "slider",
                        label = "Overlay Opacity",
                        min = 5,
                        max = 100,
                        step = 1,
                        get = function()
                            return saved.profile.dispelOverlayOpacity or 100
                        end,
                        set = function(value)
                            saved.profile.dispelOverlayOpacity = value
                            ApplyDispelOverlay()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Color Custom Borders",
                        tooltip = "Recolors the frame border, portrait outer ring and enabled power and portrait separators in the dispel type color while a debuff of that type is shown.",
                        -- Copies the frame's own border: only over a custom border (CustomBorderOff).
                        disabled = CustomBorderOff,
                        disabledTooltip = CustomBorderOffTip,
                        requireState = "disabled",
                        get = function()
                            return saved.profile.dispelCustomBorder == true
                        end,
                        -- RefreshPage (fast path) so the Dispel Colors disabled state tracks it.
                        set = function(value)
                            saved.profile.dispelCustomBorder = value and true or false
                            ApplyDispelOverlay()
                            CludesUI:RefreshPage()
                        end,
                    },
                },
            })
        end

        -- Type Icon Position (Raid Frames parity: the dispel type's icon on a
        -- corner of the health bar, its size and offsets in the cog) | Only
        -- Dispellable by You, out of the overlay cog since it narrows the
        -- overlay, the icon and the border copies alike.
        local iconPosOrder = { "none" }
        for idx, keyName in ipairs(CludesUI.POSITION_GRID_ORDER) do
            iconPosOrder[idx + 1] = keyName
        end
        local iconRow
        iconRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Type Icon Position",
            values = CludesUI.POSITION_GRID_VALUES_NONE,
            order = iconPosOrder,
            getValue = function()
                local profile = saved.profile
                if profile.showDispelIcons ~= true then
                    return "none"
                end
                return profile.dispelIconPosition or "right"
            end,
            setValue = function(value)
                local profile = saved.profile
                if value == "none" then
                    profile.showDispelIcons = false
                else
                    profile.showDispelIcons = true
                    profile.dispelIconPosition = value
                end
                -- RefreshPage (fast path) so the cog's disabled state follows.
                ApplyDispelOverlay()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Only Dispellable by You",
            tooltip = "Shows the overlay, type icon and border colors only for debuffs you can currently dispel.",
            getValue = function()
                return saved.profile.dispelOverlayByMe == true
            end,
            setValue = function(value)
                saved.profile.dispelOverlayByMe = value and true or false
                ApplyDispelOverlay()
            end,
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(iconRow._leftRegion, {
                disabled = function()
                    return saved.profile.showDispelIcons ~= true
                end,
                disabledTooltip = "This option requires a Type Icon Position other than None",
                title = "Dispel Icon",
                rows = {
                    {
                        type = "slider",
                        label = "Icon Size",
                        min = 8,
                        max = 48,
                        step = 1,
                        get = function()
                            return saved.profile.dispelIconSize or 16
                        end,
                        set = function(value)
                            saved.profile.dispelIconSize = value
                            ApplyDispelOverlay()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Growth Direction",
                        values = { none = "None", up = "Up", down = "Down", left = "Left", right = "Right" },
                        order = { "none", "up", "down", "left", "right" },
                        get = function()
                            return saved.profile.dispelIconGrowth or "none"
                        end,
                        set = function(value)
                            saved.profile.dispelIconGrowth = value
                            ApplyDispelOverlay()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset X",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return saved.profile.dispelIconOffsetX or 0
                        end,
                        set = function(value)
                            saved.profile.dispelIconOffsetX = value
                            ApplyDispelOverlay()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Offset Y",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return saved.profile.dispelIconOffsetY or 0
                        end,
                        set = function(value)
                            saved.profile.dispelIconOffsetY = value
                            ApplyDispelOverlay()
                        end,
                    },
                },
            })
        end
    end

    AddAuraBorderSettings()

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return cursorY, sharedBuffDebuffHeader, sharedAddRow2, sharedAddRow3
end
