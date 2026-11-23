if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ResourceBars_Options\SwingTimerPage_Options.lua
--  Resource Bars options: Swing Timer page. Definitions only; the shared
--  helpers come from ns._CURB_OptEnv (filled by CUI_ResourceBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIResourceBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- The Talent Conditions picker's texts, in the swing timer's words (made on
-- the first open).
local swingTalentTexts
local function SwingTalentTexts()
    if not swingTalentTexts then
        swingTalentTexts = {
            hint = CUI.L(
                "Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the swing timer to show."
            ),
            none = CUI.L("No conditions: the swing timer always shows."),
            met = function(num)
                return CUI.Lf(
                    "%1$d condition(s), met by your current talents: the swing timer shows.",
                    num
                )
            end,
            notMet = function(num)
                return CUI.Lf(
                    "%1$d condition(s), not met by your current talents: the swing timer is hidden.",
                    num
                )
            end,
        }
    end
    return swingTalentTexts
end

-- Swing Timer page (WoW Forever only: the page exists only where the client
-- has C_SwingTimer; see CUI_ResourceBars_SwingTimer.lua). Same widget set as
-- the GCD Bar page, plus the row/text/range rows the swing timer adds.
function mod.ERB_BuildSwingTimerPage(page, hostFrame, yOffset)
    local environ = mod._CURB_OptEnv
    local DB, Pix = environ.DB, environ.PP
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    CUI.AppendSharedMediaTextures(
        _G._CURB_BarTextureNames or {},
        _G._CURB_BarTextureOrder or {},
        nil,
        _G._CURB_BarTextures
    )
    local texValues, texOrder = {}, {}
    do
        local texNames = _G._CURB_BarTextureNames or {}
        local texOrder2 = _G._CURB_BarTextureOrder or {}
        local texLookup = _G._CURB_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then texValues[key] = texNames[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return texLookup[key] end,
        }
    end

    local SWING_TIP = "Swing Timer"
    local stOff = function()
        local profile = DB()
        return profile and not profile.swingTimer.enabled
    end

    local function ApplySwingTimer()
        if _G._CURB_Apply then _G._CURB_Apply() end
        if CUI.NotifyElementResized then CUI.NotifyElementResized("ERB_SwingTimer") end
    end
    -- A setting row's getter for one swing timer key: its value, or default when
    -- it is unset (no default: the value as stored, nil without a profile).
    local function Getter(key, default)
        return function()
            local profile = DB()
            if default == nil then return profile and profile.swingTimer[key] end
            return profile and profile.swingTimer[key] or default
        end
    end
    -- A setting row's setter for one swing timer key: written (when the profile
    -- exists), the swing timer redrawn, and with alsoPage the page rebuilt too.
    local function Setter(key, alsoPage)
        return function(val)
            local profile = DB()
            if not profile then return end
            profile.swingTimer[key] = val
            ApplySwingTimer()
            if alsoPage then CUI:RefreshPage() end
        end
    end

    local _sec
    _sec, height = W:SectionHeader(hostFrame, "LAYOUT", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(
        _sec,
        { key = "ERB_SwingTimer", disabled = stOff, disabledTooltip = SWING_TIP }
    )

    local sStrataValues = CUI.FRAME_STRATA_LABELS
    local sStrataOrder = CUI.FRAME_STRATA_ORDER_BASE

    -- Row: Enable Swing Timer (+ position cog) | Frame Strata
    local enableRow
    enableRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Swing Timer",
        tooltip = "One bar per weapon that can swing, each filling over the time to the next auto attack.",
        getValue = Getter("enabled"),
        setValue = Setter("enabled", true),
    }, {
        type = "dropdown",
        text = "Frame Strata",
        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        values = sStrataValues,
        order = sStrataOrder,
        getValue = Getter("frameStrata", "MEDIUM"),
        setValue = Setter("frameStrata"),
    })
    cursorY = cursorY - height
    -- Inline position cog (X/Y + unlock) on Enable, as on the GCD Bar page
    if not CUI._prebuilding then
        local region = enableRow._leftRegion
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and not profile.swingTimer.enabled
            end,
            disabledTooltip = SWING_TIP,
            title = "Swing Timer Position",
            rows = {
                {
                    type = "slider",
                    label = "X Offset",
                    min = -600,
                    max = 600,
                    step = 1,
                    get = function()
                        local profile = DB()
                        if not profile then return 0 end
                        local swingCfg = profile.swingTimer
                        if swingCfg.unlockPos and swingCfg.unlockPos.point then
                            return swingCfg.unlockPos.x or 0
                        end
                        return swingCfg.anchorX or 0
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        local swingCfg = profile.swingTimer
                        if swingCfg.unlockPos and swingCfg.unlockPos.point then
                            swingCfg.unlockPos.x = val
                        else
                            swingCfg.anchorX = val
                        end
                        ApplySwingTimer()
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
                        if not profile then return 0 end
                        local swingCfg = profile.swingTimer
                        if swingCfg.unlockPos and swingCfg.unlockPos.point then
                            return swingCfg.unlockPos.y or 0
                        end
                        return swingCfg.anchorY or -130
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        local swingCfg = profile.swingTimer
                        if swingCfg.unlockPos and swingCfg.unlockPos.point then
                            swingCfg.unlockPos.y = val
                        else
                            swingCfg.anchorY = val
                        end
                        ApplySwingTimer()
                    end,
                },
            },
            footer = { unlockKey = "ERB_SwingTimer" },
        })
    end

    -- Row: Row Height | Width. Height is per row; the mover reports the whole stack.
    local shDis, shTip, shRaw = CUI.MatchGuard("ERB_SwingTimer", "Height", stOff, SWING_TIP)
    local swDis, swTip, swRaw = CUI.MatchGuard("ERB_SwingTimer", "Width", stOff, SWING_TIP)
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Row Height",
        min = 1,
        max = 60,
        step = 1,
        tooltip = "Height of each weapon row.",
        disabled = shDis,
        disabledTooltip = shTip,
        rawTooltip = shRaw,
        getValue = Getter("height", 12),
        setValue = Setter("height"),
    }, {
        type = "slider",
        text = "Width",
        min = 50,
        max = 800,
        step = 1,
        disabled = swDis,
        disabledTooltip = swTip,
        rawTooltip = swRaw,
        getValue = Getter("width", 220),
        setValue = Setter("width"),
    })
    cursorY = cursorY - height

    -- Row: Row Spacing | Text Size (+ text offsets cog)
    local stTextRow
    stTextRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        pixel = true,
        text = "Row Spacing",
        min = 0,
        max = 20,
        step = 1,
        tooltip = "Gap between the weapon rows.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = Getter("rowSpacing", 2),
        setValue = Setter("rowSpacing"),
    }, {
        type = "slider",
        text = "Text Size",
        min = 6,
        max = 24,
        step = 1,
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = Getter("textSize", 11),
        setValue = Setter("textSize"),
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local function OffsetSlider(labelText, key)
            return {
                type = "slider",
                label = labelText,
                min = -100,
                max = 100,
                step = 1,
                get = function()
                    local profile = DB()
                    return profile and profile.swingTimer[key] or 0
                end,
                set = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.swingTimer[key] = val
                    ApplySwingTimer()
                end,
            }
        end
        CUI.BuildInlineCog(stTextRow._rightRegion, {
            disabled = stOff,
            disabledTooltip = SWING_TIP,
            title = "Text Position",
            rows = {
                OffsetSlider("Time X Offset", "timeX"),
                OffsetSlider("Time Y Offset", "timeY"),
                OffsetSlider("Label X Offset", "labelX"),
                OffsetSlider("Label Y Offset", "labelY"),
            },
        })
    end

    -- Row: Visibility (shared checklist) | Hide When Idle (+ idle fill cog)
    local stShowRow
    stShowRow, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, {
        getStore = function()
            local profile = DB()
            return profile and profile.swingTimer
        end,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true },
        disabledFn = stOff,
        disabledTooltip = SWING_TIP,
        onChanged = function() ApplySwingTimer() end,
        onOptionChanged = function() ApplySwingTimer() end,
    }, {
        type = "toggle",
        text = "Hide When Idle",
        tooltip = "Hide the bar while no swing is running.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = Getter("hideWhenIdle"),
        setValue = Setter("hideWhenIdle"),
    })
    cursorY = cursorY - height
    -- Inline cog on Visibility: Forms and Talents. A druid picks the forms the
    -- timer shows in (the per-form map the other bars' cogs write); any class can
    -- require talents, saved per class so one profile serves every class. While
    -- they rule it out, the timer stands down like switched off. A class with no
    -- forms gets the talent picker straight from the cog.
    if not CUI._prebuilding then
        local function STCfg()
            local profile = DB()
            return profile and profile.swingTimer
        end
        local condShow
        local function OpenTalentPicker()
            local popFrame = condShow and condShow._popupFrame
            if popFrame and popFrame:IsShown() then popFrame:Hide() end
            local g = STCfg()
            if not g then return end
            local _, class = UnitClass("player")
            local byClass = g.classTalentConditions
            CUI.ShowTalentConditionsPopup({
                title = CUI.Lf("Talent Conditions: %1$s", CUI.L("Swing Timer")),
                conds = byClass and byClass[class],
                texts = SwingTalentTexts(),
                fontKey = "resourceBars",
                onConfirm = function(entries)
                    local q = STCfg()
                    if not q then return end
                    local tbl = q.classTalentConditions
                    if entries then
                        if not tbl then
                            tbl = {}
                            q.classTalentConditions = tbl
                        end
                        tbl[class] = entries
                    elseif tbl then
                        tbl[class] = nil
                        if not next(tbl) then q.classTalentConditions = nil end
                    end
                    ApplySwingTimer()
                end,
            })
        end
        local formRows = environ.FormToggleRows(STCfg, ApplySwingTimer, "barDisabledForms")
        if formRows then
            formRows[#formRows + 1] = { type = "button", label = "Talent Conditions", action = OpenTalentPicker }
            _, condShow = CUI.BuildInlineCog(stShowRow._leftRegion, {
                disabled = stOff,
                disabledTooltip = SWING_TIP,
                title = "Forms and Talents",
                rows = formRows,
            })
        else
            CUI.BuildInlineCog(stShowRow._leftRegion, {
                disabled = stOff,
                disabledTooltip = SWING_TIP,
                tip = "Talent Conditions",
                show = OpenTalentPicker,
            })
        end
    end

    if not CUI._prebuilding then
        CUI.BuildInlineCog(stShowRow._rightRegion, {
            title = "Idle Rows",
            rows = {
                {
                    type = "toggle",
                    label = "Show Fill Color When Idle",
                    tooltip = "Show an idle row full of its fill color instead of the background color.",
                    get = function()
                        local profile = DB()
                        return (profile and profile.swingTimer.idleShowFill) == true
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        if val then
                            profile.swingTimer.idleShowFill = true
                        else
                            profile.swingTimer.idleShowFill = nil
                        end
                        ApplySwingTimer()
                    end,
                },
            },
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 16)
    cursorY = cursorY - height

    _sec, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height

    -- Global Settings > Style: the rows wear the Resource Bars row's stock
    -- frame (ns.ST_Style), which gates the CUI border rows as on the other
    -- bars.
    local stStock = mod.ST_Style() ~= "cui"
    local stClassic = stStock and mod.ERB_BarsClassic()
    local function Gate(rowConf)
        if stStock then return CUI.BlizzStyle.Gate("resourcebars", rowConf) end
        return rowConf
    end
    if stStock then cursorY = CUI.BlizzStyle.Note(hostFrame, cursorY, "resourcebars") end

    -- Row: Border Style | Border Size (+ inline color swatch + offset cog).
    -- Classic WoW UI: the Border Size slot sizes the vanilla frame instead.
    do
        local btValues, btOrder = CUI.GetBorderTextureDropdown()
        local bsRow
        bsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            Gate({
                type = "dropdown",
                text = "Border Style",
                disabled = stOff,
                disabledTooltip = SWING_TIP,
                values = btValues,
                order = btOrder,
                getValue = Getter("borderTexture", "solid"),
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    local swingCfg = profile.swingTimer
                    swingCfg.borderTexture = val
                    swingCfg.borderTextureOffset = nil
                    swingCfg.borderTextureOffsetY = nil
                    swingCfg.borderTextureShiftX = nil
                    swingCfg.borderTextureShiftY = nil
                    local _bcol, _bbehind = CUI.GetBorderStyleSelectDefaults(val)
                    swingCfg.borderR = _bcol.r
                    swingCfg.borderG = _bcol.g
                    swingCfg.borderB = _bcol.b
                    swingCfg.borderA = 1
                    swingCfg.borderBehind = _bbehind
                    local defSz = CUI.GetBorderDefaultSize("resourcebars", val)
                    if defSz then swingCfg.borderSize = defSz end
                    if swingCfg.borderSizePx then swingCfg.borderSizePx = false end
                    ApplySwingTimer()
                    CUI:RefreshPage(true)
                end,
            }),
            stClassic
                    and CUI.BlizzStyle.ClassicBorderSizeCfg(function()
                        local profile = DB()
                        return profile and profile.swingTimer.stockBorderScale
                    end, function(val)
                        local profile = DB()
                        if not profile then return end
                        profile.swingTimer.stockBorderScale = val
                        ApplySwingTimer()
                        CUI.ReapplyMatchPads("ERB_SwingTimer")
                        CUI:RefreshPage()
                    end, { disabled = stOff, disabledTooltip = SWING_TIP })
                or Gate(CUI.BorderPxSliderCfg({
                    text = "Border Size",
                    disabled = stOff,
                    disabledTooltip = SWING_TIP,
                    getStep = function()
                        local profile = DB()
                        return profile and (profile.swingTimer.borderSize or 0) or 0
                    end,
                    setStep = function(val)
                        local profile = DB()
                        if profile then profile.swingTimer.borderSize = val end
                    end,
                    getTex = function()
                        local profile = DB()
                        return profile and (profile.swingTimer.borderTexture or "solid") or "solid"
                    end,
                    getPx = function()
                        local profile = DB()
                        return profile and profile.swingTimer.borderSizePx
                    end,
                    setPx = function(val)
                        local profile = DB()
                        if profile then profile.swingTimer.borderSizePx = val end
                    end,
                    apply = function()
                        ApplySwingTimer()
                        CUI:RefreshPage()
                    end,
                }))
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: own row while a textured style is selected.
        do
            local profile = DB()
            local texture = profile and profile.swingTimer.borderTexture or "solid"
            if texture ~= "solid" and texture ~= "" then
                local function step()
                    local profile = DB()
                    return profile and (profile.swingTimer.borderSize or 0) or 0
                end
                local ocfgL, ocfgR = CUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    disabled = stOff,
                    disabledTooltip = SWING_TIP,
                    getTex = function()
                        local profile = DB()
                        return profile and (profile.swingTimer.borderTexture or "solid") or "solid"
                    end,
                    getStep = step,
                    getSizeKey = step,
                    getPx = function()
                        local profile = DB()
                        return profile and profile.swingTimer.borderSizePx
                    end,
                    getX = function()
                        local profile = DB()
                        return profile and profile.swingTimer.borderTextureOffset
                    end,
                    setX = function(val)
                        local profile = DB()
                        if profile then profile.swingTimer.borderTextureOffset = val end
                    end,
                    getY = function()
                        local profile = DB()
                        return profile and profile.swingTimer.borderTextureOffsetY
                    end,
                    setY = function(val)
                        local profile = DB()
                        if profile then profile.swingTimer.borderTextureOffsetY = val end
                    end,
                    apply = function()
                        ApplySwingTimer()
                        CUI:RefreshPage()
                    end,
                })
                _, height = W:DualRow(hostFrame, cursorY, Gate(ocfgL), Gate(ocfgR))
                cursorY = cursorY - height
            end
        end
        -- Corner Radius cog on the size slider (right region), the Border color
        -- swatch left of it; neither in the search pre-build (they index
        -- nothing, and the row is a stand-in there) nor on Classic WoW UI's
        -- frame size slider
        if not CUI._prebuilding and not stClassic then
            -- Corner Radius (CludesUI_RoundedCorners.lua): an inline cog on the
            -- border size control. The stock styles keep the rows square.
            CUI.BuildInlineCog(bsRow._rightRegion, {
                title = "Corner Radius",
                tip = "Corner Radius",
                disabled = function()
                    if stOff() or stStock then return true end
                    local profile = DB()
                    return not CUI.RoundedStyleOK(profile and profile.swingTimer.borderTexture)
                end,
                disabledTooltip = function()
                    if stStock then return CUI.BlizzStyle.Label("resourcebars") end
                    if stOff() then return SWING_TIP end
                    return "This option requires the Solid, Glow or Shadow border style."
                end,
                requireState = function() return stStock and "disabled" or "enabled" end,
                rows = CUI.RoundedCornerRows({
                    {
                        type = "slider",
                        label = "Corner Radius",
                        min = 0,
                        max = CUI.ROUNDED_MAX_RADIUS,
                        step = 1,
                        get = Getter("cornerRadius", 0),
                        set = Setter("cornerRadius"),
                    },
                }, function()
                    local profile = DB()
                    return profile and profile.swingTimer.cornerMask
                end, function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.swingTimer.cornerMask = val
                    ApplySwingTimer()
                end),
            })
            CUI.BuildInlineSwatches(bsRow._rightRegion, {
                {
                    tooltip = "Border Color",
                    hasAlpha = true,
                    disabled = function()
                        local profile = DB()
                        return not (
                            profile
                            and profile.swingTimer.enabled
                            and (profile.swingTimer.borderSize or 0) > 0
                        )
                    end,
                    disabledTooltip = function()
                        if stOff() then return SWING_TIP end
                        return "This option requires a Border Size above 0."
                    end,
                    getValue = function()
                        local profile = DB()
                        return (profile and profile.swingTimer.borderR or 0),
                            (profile and profile.swingTimer.borderG or 0),
                            (profile and profile.swingTimer.borderB or 0),
                            (profile and profile.swingTimer.borderA or 1)
                    end,
                    setValue = function(red, green, blue, a)
                        local profile = DB()
                        if not profile then return end
                        profile.swingTimer.borderR, profile.swingTimer.borderG, profile.swingTimer.borderB, profile.swingTimer.borderA =
                            red, green, blue, a
                        ApplySwingTimer()
                        CUI:RefreshPage()
                    end,
                },
            }, { size = 20 })
        end
        if not CUI._prebuilding then
            local region = bsRow._leftRegion
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
                            local val = profile.swingTimer.borderTextureShiftX
                            if val then return val end
                            local _, _, dsx = CUI.GetBorderDefaults(
                                "resourcebars",
                                profile.swingTimer.borderTexture or "solid",
                                profile.swingTimer.borderSize or 0
                            )
                            return dsx
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            profile.swingTimer.borderTextureShiftX = val == 0 and nil or val
                            ApplySwingTimer()
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
                            local val = profile.swingTimer.borderTextureShiftY
                            if val then return val end
                            local _, _, _, dsy = CUI.GetBorderDefaults(
                                "resourcebars",
                                profile.swingTimer.borderTexture or "solid",
                                profile.swingTimer.borderSize or 0
                            )
                            return dsy
                        end,
                        set = function(val)
                            local profile = DB()
                            if not profile then return end
                            profile.swingTimer.borderTextureShiftY = val == 0 and nil or val
                            ApplySwingTimer()
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
                            profile.swingTimer.borderBehind = val == false and nil or val
                            ApplySwingTimer()
                            CUI:RefreshPage()
                        end,
                    },
                },
            })
            local function UpdateCogVis()
                local profile = DB()
                local texture = profile and profile.swingTimer.borderTexture or "solid"
                if texture == "solid" or stClassic then
                    cogBtn:Hide()
                else
                    cogBtn:Show()
                end
            end
            CUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
    end

    -- Row: Color (gradient end / Main Hand / Off Hand / Ranged / class + gradient cog) | Background (+ bg swatch)
    local function RowSwatch(prefixText, tipText)
        return {
            tooltip = tipText,
            hasAlpha = true,
            getValue = function()
                local profile = DB()
                if not profile then return 1, 1, 1, 1 end
                local swingCfg = profile.swingTimer
                return swingCfg[prefixText .. "R"],
                    swingCfg[prefixText .. "G"],
                    swingCfg[prefixText .. "B"],
                    swingCfg[prefixText .. "A"]
            end,
            setValue = function(r, gg, b, a)
                local profile = DB()
                if not profile then return end
                local swingCfg = profile.swingTimer
                swingCfg[prefixText .. "R"], swingCfg[prefixText .. "G"], swingCfg[prefixText .. "B"], swingCfg[prefixText .. "A"] =
                    r, gg, b, a
                if swingCfg.classColored then swingCfg.classColored = false end
                ApplySwingTimer()
                CUI:RefreshPage()
            end,
            onClick = function(self)
                local profile = DB()
                if not profile then return end
                if profile.swingTimer.classColored then
                    profile.swingTimer.classColored = false
                    ApplySwingTimer()
                    CUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then self._eabOrigClick(self) end
            end,
            refreshAlpha = function()
                local profile = DB()
                return (profile and not profile.swingTimer.classColored) and 1 or 0.3
            end,
        }
    end
    local colorRow
    colorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "multiSwatch",
        text = "Color",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        swatches = {
            {
                tooltip = "Gradient End Color",
                hasAlpha = true,
                disabled = function()
                    local profile = DB()
                    return not (profile and profile.swingTimer.gradientEnabled)
                end,
                disabledTooltip = function()
                    if stOff() then return SWING_TIP end
                    return "Gradient"
                end,
                getValue = function()
                    local profile = DB()
                    if not profile then return 0.20, 0.20, 0.80, 1 end
                    return profile.swingTimer.gradientR,
                        profile.swingTimer.gradientG,
                        profile.swingTimer.gradientB,
                        profile.swingTimer.gradientA
                end,
                setValue = function(red, green, blue, a)
                    local profile = DB()
                    if not profile then return end
                    profile.swingTimer.gradientR, profile.swingTimer.gradientG, profile.swingTimer.gradientB, profile.swingTimer.gradientA =
                        red, green, blue, a
                    ApplySwingTimer()
                end,
            },
            RowSwatch("mh", "Main Hand Color"),
            RowSwatch("oh", "Off Hand Color"),
            RowSwatch("r", "Ranged Color"),
            {
                tooltip = "Class Colored",
                getValue = function()
                    local _, classFile = UnitClass("player")
                    local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                    if classColor then return classColor.r, classColor.g, classColor.b, 1 end
                    return 1, 0.70, 0, 1
                end,
                setValue = function() end,
                onClick = function()
                    local profile = DB()
                    if not profile then return end
                    profile.swingTimer.classColored = true
                    ApplySwingTimer()
                    CUI:RefreshPage()
                end,
                refreshAlpha = function()
                    local profile = DB()
                    return (not profile or profile.swingTimer.classColored == true) and 1 or 0.3
                end,
            },
        },
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return math.floor(((profile and profile.swingTimer.bgA or 0.7) * 100) + 0.5)
        end,
        setValue = function(val)
            local profile = DB()
            if not profile then return end
            profile.swingTimer.bgA = val / 100
            ApplySwingTimer()
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local region = colorRow._leftRegion
        CUI.BuildInlineCog(region, {
            disabled = function()
                local profile = DB()
                return profile and not profile.swingTimer.enabled
            end,
            disabledTooltip = SWING_TIP,
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
    if not CUI._prebuilding then
        CUI.BuildInlineSwatches(colorRow._rightRegion, {
            {
                tooltip = "Background Color",
                getValue = function()
                    local profile = DB()
                    return (profile and profile.swingTimer.bgR or 0),
                        (profile and profile.swingTimer.bgG or 0),
                        (profile and profile.swingTimer.bgB or 0)
                end,
                setValue = function(red, green, blue)
                    local profile = DB()
                    if not profile then return end
                    profile.swingTimer.bgR, profile.swingTimer.bgG, profile.swingTimer.bgB = red, green, blue
                    ApplySwingTimer()
                end,
            },
        }, { size = 20, disabled = stOff, disabledTooltip = SWING_TIP })
    end

    -- Row: Bar Texture | Deplete Fill
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        values = texValues,
        order = texOrder,
        getValue = Getter("texture", "none"),
        setValue = Setter("texture"),
    }, {
        type = "toggle",
        text = "Deplete Fill",
        tooltip = "Start each row full and drain it as the swing timer elapses, instead of filling it up.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = Getter("depleteFill"),
        setValue = Setter("depleteFill"),
    })
    cursorY = cursorY - height

    -- Row: Show Spark | Tracked Weapons (checkbox dropdown, built below)
    local sparkRow
    sparkRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Spark",
        tooltip = "Show a small glowing spark that moves along the leading edge of the fill while a swing is running.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = Getter("showSpark"),
        setValue = Setter("showSpark"),
    }, {
        type = "dropdown",
        text = "Tracked Weapons",
        tooltip = "Choose which weapons get a swing row. A row also needs a weapon in that slot.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function() return "__placeholder" end,
        setValue = function() end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        -- Not tied to Show Spark: a combined off hand's spark shows either way.
        -- Colours: store keys <key>SparkR/G/B/A, unset by default; each swatch
        -- shows the colour the bar paints (ST_SparkColor). A pick of the unset
        -- colour (white, or a combined off hand's fill) stores nothing, so the
        -- picker's Cancel leaves an unset spark following its default.
        local function IsNear(posX, cursorY) return math.abs(posX - cursorY) < 0.002 end
        local function SparkColorRow(name, key)
            local prefixText = key .. "Spark"
            return {
                tooltip = name,
                hasAlpha = true,
                getValue = function()
                    if mod.ST_SparkColor then return mod.ST_SparkColor(key) end
                    return 1, 1, 1, 1
                end,
                setValue = function(r, gg, b, a)
                    local profile = DB()
                    if not profile then return end
                    a = a or 1
                    if mod.ST_SparkColor then
                        local ur, ug, ub, ua = mod.ST_SparkColor(key, true)
                        if IsNear(r, ur) and IsNear(gg, ug) and IsNear(b, ub) and IsNear(a, ua) then
                            r, gg, b, a = nil, nil, nil, nil
                        end
                    end
                    local swingCfg = profile.swingTimer
                    swingCfg[prefixText .. "R"], swingCfg[prefixText .. "G"], swingCfg[prefixText .. "B"], swingCfg[prefixText .. "A"] =
                        r, gg, b, a
                    ApplySwingTimer()
                end,
            }
        end
        CUI.BuildInlineCog(sparkRow._leftRegion, {
            disabled = stOff,
            disabledTooltip = SWING_TIP,
            title = "Spark",
            rows = {
                {
                    type = "slider",
                    label = "Width",
                    min = 1,
                    max = 32,
                    step = 1,
                    get = Getter("sparkWidth", 8),
                    set = Setter("sparkWidth"),
                },
                {
                    type = "slider",
                    pixel = true,
                    label = "Overhang",
                    min = 0,
                    max = 20,
                    step = 1,
                    tooltip = "How far the spark reaches past the top and bottom of the bar.",
                    get = Getter("sparkOverhang", 0),
                    set = Setter("sparkOverhang"),
                },
                {
                    type = "multiswatch",
                    label = "Spark Colors",
                    swatches = {
                        SparkColorRow("Main Hand", "mh"),
                        SparkColorRow("Off Hand", "oh"),
                        SparkColorRow("Ranged", "r"),
                    },
                },
            },
        })
    end
    if not CUI._prebuilding then
        local region = sparkRow._rightRegion
        if region._control then region._control:Hide() end
        -- Checked = the row shows. The keys are the per-row toggles this
        -- list replaces (nil = on), so every profile carries over as is.
        local WEAPON_ITEMS = {
            { key = "showMH", label = "Main Hand" },
            { key = "showOH", label = "Off Hand" },
            { key = "showR", label = "Ranged" },
        }
        local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            210,
            region:GetFrameLevel() + 2,
            WEAPON_ITEMS,
            function(keyName)
                local profile = DB()
                return not profile or profile.swingTimer[keyName] ~= false
            end,
            function(keyName, val)
                local profile = DB()
                if not profile then return end
                profile.swingTimer[keyName] = val
                -- The cog's Combine Hands greys out while a hand is off.
                ApplySwingTimer()
                CUI:RefreshPage()
            end
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        local function UpdateWeaponsDD()
            local off = stOff()
            checkDrop:SetAlpha(off and 0.3 or 1)
            checkDrop:EnableMouse(not off)
            cbDDRefresh()
        end
        UpdateWeaponsDD()
        CUI.RegisterWidgetRefresh(UpdateWeaponsDD)
        -- Combine Hands needs both hands tracked, so it rides this row's cog.
        CUI.BuildInlineCog(region, {
            disabled = stOff,
            disabledTooltip = SWING_TIP,
            title = "Tracked Weapons",
            rows = {
                {
                    type = "toggle",
                    label = "Always Show Rows",
                    tooltip = "Show every row ticked in the list even when no weapon is equipped in that slot, so the bar keeps the same layout on every class.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.alwaysShowRows == true
                    end,
                    set = Setter("alwaysShowRows"),
                },
                {
                    type = "toggle",
                    label = "Hide Label Without Weapon",
                    tooltip = "A row shown only because of Always Show Rows drops its MH / OH / R label while no weapon is equipped in that slot. A shield keeps its Shield label.",
                    disabled = function()
                        local profile = DB()
                        return not (profile and profile.swingTimer.alwaysShowRows)
                    end,
                    disabledTooltip = "Always Show Rows",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.hideLabelNoWeapon == true
                    end,
                    set = Setter("hideLabelNoWeapon"),
                },
                {
                    type = "toggle",
                    label = "Show Shield As Off Hand",
                    tooltip = "Show the Off Hand row, labelled Shield, while a shield is equipped. Always Show Rows also labels it.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.shieldRow == true
                    end,
                    set = Setter("shieldRow"),
                },
                {
                    type = "toggle",
                    label = "Combine Hands",
                    tooltip = "Show the off hand as a spark on the Main Hand bar instead of its own row.",
                    disabled = function()
                        local profile = DB()
                        return profile
                            and (profile.swingTimer.showMH == false or profile.swingTimer.showOH == false)
                    end,
                    disabledTooltip = function()
                        local profile = DB()
                        return (profile and profile.swingTimer.showMH == false) and "Main Hand" or "Off Hand"
                    end,
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.combineHands == true
                    end,
                    set = Setter("combineHands"),
                },
            },
        })
    end

    -- Row: Show Time | Show Weapon Label
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Time",
        tooltip = "Show the seconds left to the next swing on each row.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.showTime ~= false
        end,
        setValue = Setter("showTime"),
    }, {
        type = "toggle",
        text = "Show Weapon Label",
        tooltip = "Tag each row with its weapon slot: MH (Main Hand), OH (Off Hand), R (Ranged).",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.showLabel ~= false
        end,
        setValue = Setter("showLabel"),
    })
    cursorY = cursorY - height

    -- A cog's colour row: store keys prefix .. R/G/B/A, `def` the fallback
    -- {r, g, b, a}; `off` (optional) greys it out with `offTip`.
    -- `shared` (optional): a prefix whose colour shows while this one is unset.
    local function ColorRow(labelText, prefixText, def, tipText, off, offTip, shared)
        return {
            type = "colorpicker",
            label = labelText,
            tooltip = tipText,
            hasAlpha = true,
            disabled = off,
            disabledTooltip = offTip,
            get = function()
                local profile = DB()
                local g = profile and profile.swingTimer
                if not g then return def[1], def[2], def[3], def[4] end
                local keyName = prefixText
                if shared and g[prefixText .. "R"] == nil then keyName = shared end
                return g[keyName .. "R"] or def[1],
                    g[keyName .. "G"] or def[2],
                    g[keyName .. "B"] or def[3],
                    g[keyName .. "A"] or def[4]
            end,
            set = function(r, gg, b, a)
                local profile = DB()
                if not profile then return end
                local swingCfg = profile.swingTimer
                swingCfg[prefixText .. "R"], swingCfg[prefixText .. "G"], swingCfg[prefixText .. "B"], swingCfg[prefixText .. "A"] =
                    r, gg, b, a
                ApplySwingTimer()
            end,
        }
    end
    local stateNotFull = function()
        local profile = DB()
        return not profile or profile.swingTimer.attackState ~= "full"
    end
    local stateOff = function()
        local profile = DB()
        return not profile or profile.swingTimer.attackState == "off"
    end
    local guideOff = function()
        local profile = DB()
        return not profile or (profile.swingTimer.moveGuide or "off") == "off"
    end

    -- Row: Range Check (+ out-of-range alpha cog) | Attack State (+ colors cog)
    local stateRow
    stateRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Range Check",
        tooltip = "Dim a row and paint its text red while the current target is out of that weapon's auto attack range.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.rangeCheck ~= false
        end,
        setValue = Setter("rangeCheck"),
    }, {
        type = "segmented",
        text = "Attack State",
        tooltip = "Queued Only colors and names a queued attack; Full also colors rows while the attack is on or waiting.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        values = { off = "Off", queued = "Queued Only", full = "Full" },
        order = { "off", "queued", "full" },
        getValue = Getter("attackState", "queued"),
        setValue = Setter("attackState", true),
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(stateRow._rightRegion, {
            disabled = stOff,
            disabledTooltip = SWING_TIP,
            title = "Attack State Colors",
            rows = {
                ColorRow(
                    "On",
                    "active",
                    { 0.298, 0.788, 0.941, 1 },
                    "While the attack is on and a swing is running.",
                    stateNotFull,
                    "This option requires Attack State Full."
                ),
                ColorRow(
                    "Waiting",
                    "pending",
                    { 0.659, 0.502, 0.949, 1 },
                    "While the attack is on but nothing is swinging.",
                    stateNotFull,
                    "This option requires Attack State Full."
                ),
                ColorRow(
                    "Heroic Strike",
                    "queueHS",
                    { 1, 0.70, 0.20, 1 },
                    "Heroic Strike queued.",
                    stateOff,
                    "This option requires an Attack State other than Off.",
                    "queue"
                ),
                ColorRow(
                    "Raptor Strike",
                    "queueRaptor",
                    { 1, 0.70, 0.20, 1 },
                    "Raptor Strike queued.",
                    stateOff,
                    "This option requires an Attack State other than Off.",
                    "queue"
                ),
                ColorRow(
                    "Maul",
                    "queueMaul",
                    { 1, 0.70, 0.20, 1 },
                    "Maul queued.",
                    stateOff,
                    "This option requires an Attack State other than Off.",
                    "queue"
                ),
                ColorRow(
                    "Cleave",
                    "queueCleave",
                    { 0.95, 0.35, 0.25, 1 },
                    "Cleave queued.",
                    stateOff,
                    "This option requires an Attack State other than Off."
                ),
                {
                    type = "toggle",
                    label = "Queued On Main Hand Only",
                    tooltip = "Show a queued attack on the Main Hand row only, not on the Off Hand row.",
                    disabled = stateOff,
                    disabledTooltip = "This option requires an Attack State other than Off.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.queueMainHandOnly == true
                    end,
                    set = Setter("queueMainHandOnly"),
                },
            },
        })
    end
    if not CUI._prebuilding then
        CUI.BuildInlineCog(stateRow._leftRegion, {
            title = "Range Check",
            rows = {
                {
                    type = "slider",
                    label = "Out of Range Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    tooltip = "Opacity of a row whose target is out of range.",
                    get = function()
                        local profile = DB()
                        return math.floor(
                            ((profile and profile.swingTimer.outOfRangeAlpha or 0.4) * 100) + 0.5
                        )
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        profile.swingTimer.outOfRangeAlpha = val / 100
                        ApplySwingTimer()
                    end,
                },
            },
        })
    end
    -- Row: Movement Guide (+ GO / STILL colors and Text Cue cog) | Swing Window
    -- (+ length, latency and color cog)
    local guideRow
    guideRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Movement Guide",
        tooltip = "Marks when you can move (GO) and, for wand Shoot and Auto Shot, when you must stand still (STILL).",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        values = { off = "Off", segments = "Segments", windup = "Wind-Up Bar" },
        order = { "off", "segments", "windup" },
        getValue = Getter("moveGuide", "off"),
        setValue = Setter("moveGuide", true),
    }, {
        type = "toggle",
        text = "Swing Window",
        tooltip = "Mark the last moments of each melee swing: the time left to queue an attack onto it.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.swingWindow == true
        end,
        setValue = Setter("swingWindow"),
    })
    cursorY = cursorY - height
    local windowOff = function()
        local profile = DB()
        return not profile or profile.swingTimer.swingWindow ~= true
    end
    if not CUI._prebuilding then
        CUI.BuildInlineCog(guideRow._rightRegion, {
            disabled = function() return stOff() or windowOff() end,
            disabledTooltip = function()
                if stOff() then return SWING_TIP end
                return "Swing Window"
            end,
            title = "Swing Window",
            rows = {
                {
                    type = "slider",
                    label = "Window Length",
                    min = 0.1,
                    max = 1.5,
                    step = 0.05,
                    tooltip = "Seconds at the end of each melee swing.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.swingWindowTime or 0.4
                    end,
                    set = function(val)
                        local profile = DB()
                        if not profile then return end
                        profile.swingTimer.swingWindowTime = val
                        ApplySwingTimer()
                    end,
                },
                {
                    type = "toggle",
                    label = "Add Latency",
                    tooltip = "Widen the window by your current latency.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.windowLatency == true
                    end,
                    set = Setter("windowLatency"),
                },
                ColorRow("Window", "window", { 1, 1, 1, 0.35 }, "The swing window's color."),
            },
        })
    end

    -- Row: Seal Colors (+ per-seal colors cog; paladins only) | Cast Clip
    -- (+ colors cog)
    local _, playerClass = UnitClass("player")
    local notPaladin = playerClass ~= "PALADIN"
    local PALADIN_TIP = "This option is for paladins."
    local sealOff = function()
        local profile = DB()
        return notPaladin or not profile or profile.swingTimer.sealColors == false
    end
    local clipOff = function()
        local profile = DB()
        return not profile or profile.swingTimer.castClip ~= true
    end
    local sealRow
    sealRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Seal Colors",
        tooltip = "Color the melee rows by the seal you have up.",
        disabled = function() return stOff() or notPaladin end,
        disabledTooltip = function()
            if stOff() then return SWING_TIP end
            return PALADIN_TIP
        end,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.sealColors ~= false
        end,
        setValue = Setter("sealColors"),
    }, {
        type = "toggle",
        text = "Cast Clip",
        tooltip = "Mark where your cast ends on the Main Hand row. It turns red when the cast runs past the swing and delays it.",
        disabled = stOff,
        disabledTooltip = SWING_TIP,
        getValue = function()
            local profile = DB()
            return profile and profile.swingTimer.castClip == true
        end,
        setValue = Setter("castClip"),
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(sealRow._leftRegion, {
            disabled = function() return stOff() or sealOff() end,
            disabledTooltip = function()
                if stOff() then return SWING_TIP end
                if notPaladin then return PALADIN_TIP end
                return "Seal Colors"
            end,
            title = "Seal Colors",
            rows = {
                ColorRow("Righteousness", "sealRighteous", { 0.95, 0.85, 0.40, 1 }, "Seal of Righteousness."),
                ColorRow("Crusader", "sealCrusader", { 0.95, 0.55, 0.20, 1 }, "Seal of the Crusader."),
                ColorRow("Command", "sealCommand", { 0.75, 0.35, 0.95, 1 }, "Seal of Command."),
                ColorRow("Justice", "sealJustice", { 0.60, 0.65, 0.75, 1 }, "Seal of Justice."),
                ColorRow("Light", "sealLight", { 1, 0.95, 0.70, 1 }, "Seal of Light."),
                ColorRow("Wisdom", "sealWisdom", { 0.35, 0.65, 1, 1 }, "Seal of Wisdom."),
                ColorRow("Fury", "sealFury", { 0.95, 0.25, 0.20, 1 }, "Seal of Fury."),
                ColorRow("Martyrdom", "sealMartyrdom", { 0.90, 0.40, 0.70, 1 }, "Seal of Martyrdom."),
            },
        })
        CUI.BuildInlineCog(sealRow._rightRegion, {
            disabled = function() return stOff() or clipOff() end,
            disabledTooltip = function()
                if stOff() then return SWING_TIP end
                return "Cast Clip"
            end,
            title = "Cast Clip",
            rows = {
                ColorRow("In Time", "castOk", { 1, 1, 1, 1 }, "The cast ends before the swing."),
                ColorRow("Delays Swing", "castBad", { 1, 0.15, 0.15, 1 }, "The cast runs past the swing."),
            },
        })
    end
    if not CUI._prebuilding then
        CUI.BuildInlineCog(guideRow._leftRegion, {
            disabled = function() return stOff() or guideOff() end,
            disabledTooltip = function()
                if stOff() then return SWING_TIP end
                return "Movement Guide"
            end,
            title = "Movement Guide",
            rows = {
                ColorRow(
                    "Go",
                    "latency",
                    { 0.949, 0.957, 0.969, 0.9 },
                    "The last stretch of each swing, as long as your latency."
                ),
                ColorRow(
                    "Still",
                    "aim",
                    { 1, 0.82, 0.25, 0.6 },
                    "The half second to stand still before a wand or Auto Shot fires."
                ),
                {
                    type = "toggle",
                    label = "Text Cue",
                    tooltip = "The Ranged row's time reads Move (seconds left to move), then Still, then Go. Needs Show Time.",
                    get = function()
                        local profile = DB()
                        return profile and profile.swingTimer.moveCue == true
                    end,
                    set = Setter("moveCue"),
                },
            },
        })
    end

    return math.abs(cursorY)
end
