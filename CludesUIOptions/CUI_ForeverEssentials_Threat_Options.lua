if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Threat_Options.lua
--  Builds the "Threat" page inside the Forever Essentials module: a live
--  preview of the meter in the content header, then its settings. Reads go
--  through the meter's Get (saved value, else the default); writes create only
--  the key they change.
-------------------------------------------------------------------------------
local module = CludesUI._ModuleNS["CludesUIForeverEssentials"]
local mod = module and module.ThreatMeter
if not mod then
    return
end -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = mod.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            CludesUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._CUI_ThreatHeaderBuilder = HeaderBuilder

local ICON_STYLES = {
    none = "None",
    blizzard = "Blizzard",
    modern = "Modern",
    pixel = "Pixel",
    pixelsComic = "Comic",
    glyph = "Glyph",
    arcade = "Arcade",
    legend = "Legend",
    midnight = "Midnight",
    runic = "Runic",
}
local ICON_STYLE_ORDER = {
    "none",
    "---",
    "blizzard",
    "modern",
    "pixel",
    "pixelsComic",
    "glyph",
    "arcade",
    "legend",
    "midnight",
    "runic",
}
local BAR_COLORS = { class = "Class Color", accent = "Accent Color", custom = "Custom Color" }
local BAR_COLOR_ORDER = { "class", "accent", "custom" }
local OUTLINES =
    { __global = "CUI Global Default", none = "Drop Shadow", outline = "Outline", thick = "Thick Outline" }
local OUTLINE_ORDER = { "__global", "none", "outline", "thick" }
local PCT_POSITIONS = { RIGHT = "Inside Right", LEFT = "Inside Left", CENTER = "Inside Center" }
local PCT_POSITION_ORDER = { "RIGHT", "LEFT", "CENTER" }
local PCT_MODES = { percent = "Threat %", gap = "Threat Gap" }
local PCT_MODE_ORDER = { "percent", "gap" }

_G._CUI_BuildThreatMeterPage = function(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local BLANK = CludesUI.BlankRowCfg
    local BS = CludesUI.BlizzStyle
    local Get, GetStyle = mod.Get, mod.GetStyleValue
    local cursorY = yOffset
    local _, height, heading
    hostFrame._showRowDivider = true

    -- Style page gates: Gate() for settings neither stock look uses,
    -- BlizzOnly() for those only Blizzard Style ignores.
    local function ThreatGate(rowConf)
        return BS.Gate("threatmeter", rowConf)
    end
    local function BlizzOnly(rowConf)
        if BS.Active("threatmeter") == "blizzard" then
            return ThreatGate(rowConf)
        end
        return rowConf
    end

    mod.BarTextures()
    CludesUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not Get("enabled")
    end
    -- A row that needs the meter on and one more condition: greyed by either,
    -- with the requirement that is actually blocking it. raw marks a whole
    -- sentence (shown as is instead of wrapped).
    local function Needs(cond, requirement, raw)
        return function()
            return off() or cond()
        end,
            function()
                if off() then
                    return "Threat Meter"
                end
                return requirement
            end,
            raw and function()
                return not off()
            end or nil
    end
    -- Writes only (read live by the meter), writes that restyle, and writes
    -- whose toggle gates other rows.
    local function Store(key, val)
        mod.Cfg()[key] = val
    end
    local function Set(key, val)
        mod.Cfg()[key] = val
        mod.ApplyStyle()
    end
    local function SetAndRefresh(key, val)
        Set(key, val)
        CludesUI:RefreshPage()
    end
    -- A size whose swatch greys out at zero refreshes the page only when it
    -- crosses zero, so a slider drag just restyles.
    local function IsZero(set, key)
        return (GetStyle(set, key) or 0) == 0
    end
    local function SetStyleSize(set, key, val)
        local was = IsZero(set, key)
        mod.SetStyleValue(set, key, val)
        if IsZero(set, key) ~= was then
            CludesUI:RefreshPage()
        end
    end
    -- The separator options exist only for border styles with divider art (the
    -- Pixels styles): role "sepH" (under a bar or the header) or "sepV" (beside
    -- an icon), key the window or bar border's style. Read live, so a style pick
    -- shows or hides them with the page's refresh.
    local function DividerArt(key, role)
        return CludesUI.GetBorderCompanion(GetStyle("borders", key), role) ~= nil
    end

    local function Toggle(key, textValue, tooltip, setValue)
        return {
            type = "toggle",
            text = textValue,
            tooltip = tooltip,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return Get(key)
            end,
            setValue = setValue or function(val)
                Set(key, val)
            end,
        }
    end
    -- The threat list's own settings, which a Damage Meters Threat window shows
    -- too: editable whether or not this meter is on.
    local function ListToggle(key, textValue, tooltip, setValue)
        local rowConf = Toggle(key, textValue, tooltip, setValue)
        rowConf.disabled, rowConf.disabledTooltip = nil, nil
        return rowConf
    end
    local function Slider(key, textValue, low, high, tooltip)
        return {
            type = "slider",
            text = textValue,
            min = low,
            max = high,
            step = 1,
            tooltip = tooltip,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return Get(key)
            end,
            setValue = function(val)
                Set(key, val)
            end,
        }
    end
    local function StyleToggle(set, key, textValue, gates)
        return {
            type = "toggle",
            text = textValue,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return GetStyle(set, key)
            end,
            setValue = function(val)
                mod.SetStyleValue(set, key, val)
                if gates then
                    CludesUI:RefreshPage()
                end
            end,
        }
    end
    local function StyleSlider(set, key, textValue, low, high, step)
        return {
            type = "slider",
            text = textValue,
            min = low,
            max = high,
            step = step or 1,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return GetStyle(set, key)
            end,
            setValue = function(val)
                mod.SetStyleValue(set, key, val)
            end,
        }
    end

    -- Inline swatches. A saved colour table is shared or converted, so every
    -- write stores a new one.
    local function ColorSwatch(key, tooltip, disabled, disabledTooltip)
        return {
            tooltip = tooltip,
            disabled = disabled,
            disabledTooltip = disabledTooltip,
            getValue = function()
                local color = Get(key)
                return color.r, color.g, color.b
            end,
            setValue = function(red, green, blue)
                Set(key, { r = red, g = green, b = blue })
            end,
        }
    end
    local function StyleSwatch(set, key, tooltip)
        local sc = { tooltip = tooltip, disabled = off, disabledTooltip = "Threat Meter" }
        if type(key) == "table" then
            sc.getValue = function()
                return GetStyle(set, key[1]), GetStyle(set, key[2]), GetStyle(set, key[3])
            end
            sc.setValue = function(red, green, blue)
                mod.SetStyleValues(set, { [key[1]] = red, [key[2]] = green, [key[3]] = blue })
            end
        else
            sc.getValue = function()
                local color = GetStyle(set, key)
                return color.r, color.g, color.b
            end
            sc.setValue = function(red, green, blue)
                mod.SetStyleValue(set, key, { r = red, g = green, b = blue, a = 1 })
            end
        end
        return sc
    end
    -- The custom alternative to a class or accent colour: dimmed while that one
    -- is in use, and its first click switches to the custom colour.
    local function Alternative(sc, isActive, activate)
        sc.refreshAlpha = function()
            return isActive() and 1 or 0.3
        end
        sc.onClick = function(self)
            if not isActive() then
                activate()
                CludesUI:RefreshPage()
                return
            end
            if self._eabOrigClick then
                self._eabOrigClick(self)
            end
        end
        return sc
    end
    local function AlternativeTo(sc, set, flag)
        return Alternative(sc, function()
            return not GetStyle(set, flag)
        end, function()
            mod.SetStyleValue(set, flag, false)
        end)
    end
    local function Swatch(regionFrame, sc)
        CludesUI.BuildInlineSwatches(regionFrame, { sc })
    end
    -- head (optional): a row above the offsets; the cog then takes the
    -- settings icon, as it holds more than a position.
    local function OffsetCog(regionFrame, title, keyX, keyY, disabled, disabledTooltip, rawTooltip, head)
        local rowList = {
            {
                type = "slider",
                label = "X Offset",
                min = -20,
                max = 20,
                step = 1,
                get = function()
                    return GetStyle(keyX[1], keyX[2])
                end,
                set = function(val)
                    mod.SetStyleValue(keyX[1], keyX[2], val)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -20,
                max = 20,
                step = 1,
                get = function()
                    return GetStyle(keyY[1], keyY[2])
                end,
                set = function(val)
                    mod.SetStyleValue(keyY[1], keyY[2], val)
                end,
            },
        }
        if head then
            table.insert(rowList, 1, head)
        end
        CludesUI.BuildInlineCog(regionFrame, {
            title = title,
            disabled = disabled,
            disabledTooltip = disabledTooltip,
            rawTooltip = rawTooltip,
            rows = rowList,
        })
    end

    ---------------------------------------------------------------------------
    --  THREAT METER
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "THREAT METER", cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_ThreatMeter", disabled = off, disabledTooltip = "Threat Meter" }
    )
    cursorY = BS.Note(hostFrame, cursorY, "threatmeter")

    -- Lock state belongs to the lock icon on the meter itself.
    _, height = CludesUI.BuildVisibilityRow(W, hostFrame, cursorY, {
        leftCfg = {
            type = "toggle",
            text = "Enable Threat Meter",
            tooltip = "Shows everyone's threat on your target, highest first. With a friendly target, it shows the threat on what they are fighting.",
            getValue = function()
                return not off()
            end,
            setValue = function(val)
                mod.Cfg().enabled = val
                mod.Apply()
                CludesUI:RefreshPage()
            end,
        },
        getStore = mod.Cfg,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        -- Stored as onlyWithThreat: nil (the default) hides the meter while it
        -- has no threat to list, false keeps it on screen.
        extraItems = {
            {
                key = "onlyWithThreat",
                label = "Only With Threat",
                default = true,
                tooltip = "Only show the meter while there is threat to list. Unchecked keeps the header and its buttons on screen.",
            },
        },
        disabledFn = off,
        disabledTooltip = "Threat Meter",
        onChanged = CludesUI.RequestVisibilityUpdate,
        onOptionChanged = CludesUI.RequestVisibilityUpdate,
    })
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ListToggle(
            "focusEnabled",
            "Enable Focus Tracking",
            "Adds a Target/Focus switch to the meter header.",
            function(val)
                mod.SetFocusEnabled(val)
                mod.ApplyStyle()
            end
        ),
        {
            type = "toggle",
            text = "Ignore Pets",
            tooltip = "Leaves pets out of the list.",
            getValue = function()
                return not Get("pets")
            end,
            setValue = function(val)
                Set("pets", not val)
            end,
        }
    )
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  WARNING (its settings are built while the sound is on)
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "WARNING", cursorY)
    cursorY = cursorY - height

    local warnOn = Get("warnSound")
    local warnToggle = Toggle(
        "warnSound",
        "Warning Sound",
        "Plays once when your threat climbs past the threshold, and again only after it has dropped back below.",
        CludesUI.SectionToggleSetValue(function(val)
            Store("warnSound", val)
        end)
    )
    if warnOn then
        local sndValues, sndOrder = CludesUI.BuildSoundDropdownValues(mod.Sounds())
        _, height = W:DualRow(hostFrame, cursorY, warnToggle, {
            type = "dropdown",
            text = "Sound",
            values = sndValues,
            order = sndOrder,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return Get("warnSoundKey")
            end,
            setValue = function(val)
                Store("warnSoundKey", val)
            end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "slider",
                text = "Warn At (%)",
                min = 50,
                max = 100,
                step = 1,
                tooltip = "100% is where you pull aggro.",
                disabled = off,
                disabledTooltip = "Threat Meter",
                getValue = function()
                    return Get("warnAt")
                end,
                setValue = function(val)
                    Store("warnAt", val)
                end,
            },
            Toggle("warnSkipTank", "Not While Tanking", "No warning while you are the tank.", function(val)
                Store("warnSkipTank", val)
            end)
        )
        cursorY = cursorY - height
    else
        _, height = W:DualRow(hostFrame, cursorY, warnToggle, BLANK())
        cursorY = cursorY - height
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  THREAT % TEXT (the Nameplates and Unit Frames settings; a module that
    --  is off has no row)
    ---------------------------------------------------------------------------
    local np = CludesUI._ModuleNS["CludesUINameplates"]
    local uf = CludesUI._ModuleNS["CludesUIUnitFrames"]
    local hasNP = np and np.db
    local hasUF = uf and uf.db
    if hasNP or hasUF then
        _, height = W:SectionHeader(hostFrame, "THREAT % TEXT", cursorY)
        cursorY = cursorY - height

        -- Toggle | Position, the Threat % cog on the dropdown. blocked (optional)
        -- greys the row with blockedTip; a toggle left on stays clickable so it
        -- can still be turned off. positions / positionOrder (optional) replace
        -- the three inside spots. withGap (the nameplates) moves Color by Threat
        -- out of the cog into a Text Shows | Color by Threat row below.
        local function PctRow(
            textValue,
            tooltip,
            profile,
            apply,
            blocked,
            blockedTip,
            positions,
            positionOrder,
            withGap
        )
            local function PGet(key)
                return profile()[key]
            end
            local function PSet(key, val)
                profile()[key] = val
                apply(key, val)
            end
            local function pctOff()
                return (blocked and blocked()) or not PGet("threatPctEnabled")
            end
            local function pctOffTip()
                if blocked and blocked() then
                    return blockedTip
                end
                return textValue
            end
            local function Offset(key, labelText, low, high)
                return {
                    type = "slider",
                    label = labelText,
                    min = low,
                    max = high,
                    step = 1,
                    get = function()
                        return PGet(key)
                    end,
                    set = function(val)
                        PSet(key, val)
                    end,
                }
            end
            local row
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = textValue,
                tooltip = tooltip,
                disabled = blocked and function()
                    return blocked() and not PGet("threatPctEnabled")
                end,
                disabledTooltip = blocked and blockedTip,
                getValue = function()
                    return PGet("threatPctEnabled")
                end,
                setValue = function(val)
                    PSet("threatPctEnabled", val)
                    -- The withGap row is built while the text is on.
                    CludesUI:RefreshPage(withGap)
                end,
            }, {
                type = "dropdown",
                text = "Position",
                values = positions or PCT_POSITIONS,
                order = positionOrder or PCT_POSITION_ORDER,
                disabled = pctOff,
                disabledTooltip = pctOffTip,
                getValue = function()
                    return PGet("threatPctPosition")
                end,
                setValue = function(val)
                    PSet("threatPctPosition", val)
                end,
            })
            cursorY = cursorY - height
            if not CludesUI._prebuilding then
                local rowList = {
                    Offset("threatPctSize", "Size", 6, 20),
                    Offset("threatPctXOffset", "X Offset", -300, 300),
                    Offset("threatPctYOffset", "Y Offset", -300, 300),
                }
                if not withGap then
                    table.insert(rowList, 1, {
                        type = "toggle",
                        label = "Color by Threat",
                        tooltip = "Colors the number by threat status. Off shows it in white.",
                        get = function()
                            return PGet("threatPctColorByThreat")
                        end,
                        set = function(val)
                            PSet("threatPctColorByThreat", val)
                        end,
                    })
                end
                CludesUI.BuildInlineCog(row._rightRegion, {
                    title = "Threat %",
                    disabled = pctOff,
                    disabledTooltip = pctOffTip,
                    rows = rowList,
                })
            end
            -- What the text shows and how it is coloured. The Threat Gap colours
            -- sit on Color by Threat while the gap is picked.
            if withGap and PGet("threatPctEnabled") then
                local function Gap()
                    return PGet("threatPctMode") == "gap"
                end
                local function ColorOff()
                    return not PGet("threatPctColorByThreat")
                end
                local modeRow
                modeRow, height = W:DualRow(hostFrame, cursorY, {
                    type = "dropdown",
                    text = "Text Shows",
                    values = PCT_MODES,
                    order = PCT_MODE_ORDER,
                    tooltip = "Threat Gap shows on your target's plate only.",
                    getValue = function()
                        return PGet("threatPctMode") or "percent"
                    end,
                    setValue = CludesUI.DependentSetValue(Gap, function(val)
                        PSet("threatPctMode", val)
                    end),
                }, {
                    type = "toggle",
                    text = "Color by Threat",
                    tooltip = "Colors the number. Off shows it in white.",
                    getValue = function()
                        return PGet("threatPctColorByThreat")
                    end,
                    setValue = function(val)
                        PSet("threatPctColorByThreat", val)
                        CludesUI:RefreshPage()
                    end,
                })
                cursorY = cursorY - height
                if Gap() and not CludesUI._prebuilding then
                    local function GapSwatch(key, labelText)
                        return {
                            tooltip = labelText,
                            disabled = ColorOff,
                            disabledTooltip = "Color by Threat",
                            getValue = function()
                                local color = PGet(key)
                                if color then
                                    return color.r, color.g, color.b
                                end
                                return 1, 1, 1
                            end,
                            setValue = function(red, green, blue)
                                PSet(key, { r = red, g = green, b = blue })
                            end,
                        }
                    end
                    CludesUI.BuildInlineSwatches(modeRow._rightRegion, {
                        GapSwatch("threatGapAheadColor", "Ahead Color"),
                        GapSwatch("threatGapBehindColor", "Behind Color"),
                    })
                end
            end
            return row, pctOff, pctOffTip
        end

        if hasNP then
            PctRow(
                "Show on Nameplates",
                "Shows your threat percentage on each enemy nameplate while you are in combat with it.",
                function()
                    return np.db.profile
                end,
                function()
                    np.RefreshThreatPct()
                end,
                nil,
                nil,
                nil,
                nil,
                true
            )
        end
        if hasUF then
            -- The unit frames add the outside spots (the Unit Frames page's list).
            local row, pctOff, pctOffTip = PctRow(
                "Show on Target Frame",
                "Shows your threat percentage on the target frame while you are in combat with it. The cog adds the focus frame.",
                function()
                    return uf.db.profile
                end,
                function(key, val)
                    if key == "threatPctEnabled" then
                        uf.SetThreatPctEnabled(val)
                    else
                        uf.RefreshThreatPct()
                    end
                end,
                function()
                    return not (uf.frames.target or uf.frames.focus)
                end,
                "This option requires an CludesUI Target or Focus frame.",
                uf._threatPctPositions,
                uf._threatPctPositionOrder
            )
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(row._leftRegion, {
                    title = "Threat % Units",
                    disabled = pctOff,
                    disabledTooltip = pctOffTip,
                    rows = {
                        {
                            type = "toggle",
                            label = "Show on Focus",
                            get = function()
                                return uf.db.profile.threatPctFocus
                            end,
                            set = function(val)
                                uf.db.profile.threatPctFocus = val
                                uf.RefreshThreatPct()
                            end,
                        },
                    },
                })
            end
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  BARS
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "BARS", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Slider("barHeight", "Bar Height", 8, 40),
        Slider("barSpacing", "Bar Spacing", 0, 10)
    )
    cursorY = cursorY - height

    local texValues, texOrder = {}, {}
    do
        local lookup, nameList = mod.BarTextures(), mod.BarTextureNames
        for _, key in ipairs(mod.BarTextureOrder) do
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
    local iconRow
    iconRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        values = texValues,
        order = texOrder,
        disabled = off,
        disabledTooltip = "Threat Meter",
        getValue = function()
            return GetStyle("bars", "barTexture")
        end,
        setValue = function(val)
            mod.SetStyleValue("bars", "barTexture", val)
        end,
    }, {
        type = "dropdown",
        text = "Icon Style",
        values = ICON_STYLES,
        order = ICON_STYLE_ORDER,
        disabled = off,
        disabledTooltip = "Threat Meter",
        getValue = function()
            return GetStyle("bars", "iconStyle")
        end,
        setValue = function(val)
            mod.SetStyleValue("bars", "iconStyle", val)
        end,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local zoomOff, zoomTip = Needs(function()
            return GetStyle("bars", "iconStyle") == "none"
        end, "Icon Style")
        CludesUI.BuildInlineCog(iconRow._rightRegion, {
            title = "Icon Settings",
            disabled = zoomOff,
            disabledTooltip = zoomTip,
            rows = {
                {
                    type = "slider",
                    label = "Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    get = function()
                        return GetStyle("bars", "iconZoom")
                    end,
                    set = function(val)
                        mod.SetStyleValue("bars", "iconZoom", val)
                    end,
                },
                ThreatGate({
                    type = "toggle",
                    label = "Separator",
                    tooltip = "Adds a divider between each icon and its bar.",
                    hidden = function()
                        return not DividerArt("borderTexture", "sepV")
                    end,
                    disabled = function()
                        return IsZero("borders", "borderSize")
                    end,
                    disabledTooltip = "Bar Border Size",
                    get = function()
                        return GetStyle("bars", "iconSeparator")
                    end,
                    set = function(val)
                        mod.SetStyleValue("bars", "iconSeparator", val)
                    end,
                }),
            },
        })
    end

    local pullRow
    pullRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ListToggle(
            "pullBar",
            "Pull Aggro Bar",
            "An extra bar showing how much threat takes aggro from the tank.",
            function(val)
                SetAndRefresh("pullBar", val)
            end
        ),
        Toggle("growUp", "Grow Upward", "Lists the highest threat at the bottom instead of the top.")
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        Swatch(
            pullRow._leftRegion,
            ColorSwatch("pullColor", "Pull Aggro Bar Color", function()
                return not Get("pullBar")
            end, "Pull Aggro Bar")
        )
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  HEADER (its settings are built while the header is shown)
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "HEADER", cursorY)
    cursorY = cursorY - height

    local headerToggle = Toggle(
        "showHeader",
        "Show Header",
        "A title row with the name of the mob whose threat is shown.",
        CludesUI.SectionToggleSetValue(function(val)
            Set("showHeader", val)
        end)
    )
    if Get("showHeader") then
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            headerToggle,
            StyleSlider("header", "hdrHeight", "Header Height", 14, 40)
        )
        cursorY = cursorY - height

        local textRow
        textRow, height = W:DualRow(
            hostFrame,
            cursorY,
            StyleSlider("header", "hdrFontSize", "Header Text Size", 8, 20),
            StyleToggle("header", "hdrTextUseAccent", "Accent Header Text", true)
        )
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            OffsetCog(
                textRow._leftRegion,
                "Title Position",
                { "header", "hdrTextOffX" },
                { "header", "hdrTextOffY" },
                off,
                "Threat Meter"
            )
            Swatch(
                textRow._rightRegion,
                AlternativeTo(
                    StyleSwatch("header", "hdrTextColor", "Header Text Color"),
                    "header",
                    "hdrTextUseAccent"
                )
            )
        end

        -- While the Bottom Separator shows, it stands in for the plain line.
        local function SeparatorShown()
            return GetStyle("header", "hdrBottomSeparator")
                and GetStyle("borders", "windowBorderIncludeHeader") ~= false
                and not IsZero("borders", "windowBorderSize")
                and DividerArt("windowBorderTexture", "sepH")
        end
        local function LineState()
            return not off() and SeparatorShown() and "disabled" or nil
        end
        local bgRow
        bgRow, height = W:DualRow(
            hostFrame,
            cursorY,
            StyleSlider("header", "hdrBgAlpha", "Header Opacity", 0, 1, 0.01),
            ThreatGate({
                type = "slider",
                text = "Header Bottom Border",
                min = 0,
                max = 4,
                step = 1,
                disabled = function()
                    return off() or SeparatorShown()
                end,
                disabledTooltip = function()
                    return off() and "Threat Meter" or "Bottom Separator"
                end,
                requireState = LineState,
                getValue = function()
                    return GetStyle("header", "hdrBottomBorderSize")
                end,
                setValue = function(val)
                    SetStyleSize("header", "hdrBottomBorderSize", val)
                end,
            })
        )
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            Swatch(bgRow._leftRegion, ThreatGate(StyleSwatch("header", "hdrBgColor", "Header Background")))
            local sepRgn = bgRow._rightRegion
            local sepCog = CludesUI.BuildInlineCog(
                sepRgn,
                ThreatGate({
                    title = "Header Settings",
                    disabled = off,
                    disabledTooltip = "Threat Meter",
                    rows = {
                        {
                            type = "toggle",
                            label = "Bottom Separator",
                            tooltip = "Draws a divider under the header in the window border's style.",
                            disabled = function()
                                return GetStyle("borders", "windowBorderIncludeHeader") == false
                                    or IsZero("borders", "windowBorderSize")
                            end,
                            disabledTooltip = function()
                                if GetStyle("borders", "windowBorderIncludeHeader") == false then
                                    return "Include Header in Border"
                                end
                                return "Window Border Size"
                            end,
                            get = function()
                                return GetStyle("header", "hdrBottomSeparator")
                            end,
                            set = function(val)
                                mod.SetStyleValue("header", "hdrBottomSeparator", val)
                                CludesUI:RefreshPage()
                            end,
                        },
                    },
                })
            )
            local lineSwatch = StyleSwatch("header", "hdrBottomBorderColor", "Header Border Color")
            lineSwatch.disabled = function()
                return off() or SeparatorShown() or IsZero("header", "hdrBottomBorderSize")
            end
            lineSwatch.disabledTooltip = function()
                if off() then
                    return "Threat Meter"
                end
                return SeparatorShown() and "Bottom Separator" or "Header Bottom Border"
            end
            lineSwatch.requireState = LineState
            Swatch(sepRgn, ThreatGate(lineSwatch))
            -- The swatch sits left of the cog while the cog shows, else beside
            -- the slider; re-anchored only when the cog's shown state flips.
            local lineSw, sepShown = sepRgn._lastInline, nil
            local function SyncSepCog()
                local isShown = DividerArt("windowBorderTexture", "sepH")
                sepCog:SetShown(isShown)
                if isShown ~= sepShown then
                    sepShown = isShown
                    lineSw:ClearAllPoints()
                    CludesUI.PanelPP.Point(
                        lineSw,
                        "RIGHT",
                        isShown and sepCog or sepRgn._control,
                        "LEFT",
                        -8,
                        0
                    )
                end
            end
            SyncSepCog()
            CludesUI.RegisterWidgetRefresh(SyncSepCog)
        end
    else
        _, height = W:DualRow(hostFrame, cursorY, headerToggle, BLANK())
        cursorY = cursorY - height
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  COLORS
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "COLORS", cursorY)
    cursorY = cursorY - height

    local function BarColorMode()
        if GetStyle("colors", "showClassColor") ~= false then
            return "class"
        end
        if GetStyle("colors", "barColorUseAccent") ~= false then
            return "accent"
        end
        return "custom"
    end
    local function SetBarColorMode(val)
        if val == "class" then
            mod.SetStyleValue("colors", "showClassColor", true)
        else
            mod.SetStyleValues("colors", { showClassColor = false, barColorUseAccent = val == "accent" })
        end
    end
    local fillRow
    fillRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Color",
        values = BAR_COLORS,
        order = BAR_COLOR_ORDER,
        disabled = off,
        disabledTooltip = "Threat Meter",
        getValue = BarColorMode,
        setValue = function(val)
            SetBarColorMode(val)
            CludesUI:RefreshPage()
        end,
    }, StyleSlider("colors", "barFillAlpha", "Bar Opacity", 0, 1, 0.01))
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        Swatch(
            fillRow._leftRegion,
            Alternative(StyleSwatch("colors", "barColor", "Custom Color"), function()
                return BarColorMode() == "custom"
            end, function()
                SetBarColorMode("custom")
            end)
        )
    end

    local customRow
    customRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ListToggle(
            "playerColorOn",
            "Custom Player Color",
            "Your own bar in a fixed color instead of your class color.",
            function(val)
                SetAndRefresh("playerColorOn", val)
            end
        ),
        ListToggle(
            "tankColorOn",
            "Custom Tank Color",
            "The bar of whoever holds aggro in a fixed color instead of their class color.",
            function(val)
                SetAndRefresh("tankColorOn", val)
            end
        )
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineCog(customRow._leftRegion, {
            title = "Player Bar Settings",
            disabled = off,
            disabledTooltip = "Threat Meter",
            rows = {
                {
                    type = "toggle",
                    label = "Show Player Marker",
                    tooltip = "Shows a white stripe on your own bar.",
                    get = function()
                        return Get("showPlayerMarker")
                    end,
                    set = function(val)
                        Set("showPlayerMarker", val)
                    end,
                },
            },
        })
        Swatch(
            customRow._leftRegion,
            ColorSwatch("playerColor", "Player Color", function()
                return not Get("playerColorOn")
            end, "Custom Player Color")
        )
        Swatch(
            customRow._rightRegion,
            ColorSwatch("tankColor", "Tank Color", function()
                return not Get("tankColorOn")
            end, "Custom Tank Color")
        )
    end

    local barBgRow
    barBgRow, height = W:DualRow(
        hostFrame,
        cursorY,
        BlizzOnly(StyleToggle("colors", "barBgUseClassColor", "Class-Colored Background", true)),
        BlizzOnly(StyleSlider("colors", "barBgAlpha", "Bar Background Opacity", 0, 1, 0.01))
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        Swatch(
            barBgRow._leftRegion,
            BlizzOnly(
                AlternativeTo(
                    StyleSwatch("colors", { "barBgR", "barBgG", "barBgB" }, "Bar Background"),
                    "colors",
                    "barBgUseClassColor"
                )
            )
        )
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  BAR TEXT
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "BAR TEXT", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(hostFrame, cursorY, Slider("fontSize", "Text Size", 8, 24), {
        type = "dropdown",
        text = "Displayed Value",
        tooltip = "Pull % reaches 100 where a player would take aggro, Tank % where they match the tank's threat.",
        values = mod.DisplayValues,
        order = mod.DisplayOrder,
        getValue = mod.GetDisplayedValue,
        setValue = function(val)
            mod.SetDisplayedValue(val)
            mod.ApplyStyle()
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height

    do
        local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Font",
            values = fontValues,
            order = fontOrder,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return Get("font")
            end,
            setValue = function(val)
                Set("font", val)
            end,
        }, {
            type = "dropdown",
            text = "Font Outline",
            values = OUTLINES,
            order = OUTLINE_ORDER,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return Get("outlineMode")
            end,
            setValue = function(val)
                Set("outlineMode", val)
            end,
        })
        cursorY = cursorY - height
    end

    -- Value text settings do nothing while no value is displayed.
    local valueOff, valueTip, valueRaw = Needs(function()
        return mod.GetDisplayedValue() == "none"
    end, "This option requires a Displayed Value other than None.", true)
    local valuesToggle = StyleToggle("colors", "rightTextUseClassColor", "Class-Colored Values", true)
    valuesToggle.disabled, valuesToggle.disabledTooltip, valuesToggle.rawTooltip =
        valueOff, valueTip, valueRaw
    valuesToggle.setValue = function(val)
        mod.SetStyleValues("colors", { rightTextUseClassColor = val, rightTextUseThreatGradient = false })
        CludesUI:RefreshPage()
    end
    local nameRow
    nameRow, height = W:DualRow(
        hostFrame,
        cursorY,
        StyleToggle("colors", "leftTextUseClassColor", "Class-Colored Names", true),
        valuesToggle
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        -- Name Text: the Name Format (a player's first or last name; First and
        -- Last is the unset default) above the name's offsets.
        OffsetCog(
            nameRow._leftRegion,
            "Name Text",
            { "bars", "leftTextOffsetX" },
            { "bars", "leftTextOffsetY" },
            off,
            "Threat Meter",
            nil,
            CludesUI.NameFormatCogRow(function()
                return Get("nameFormat")
            end, function(val)
                Set("nameFormat", val)
            end)
        )
        Swatch(
            nameRow._leftRegion,
            AlternativeTo(
                StyleSwatch("colors", "leftTextColor", "Name Color"),
                "colors",
                "leftTextUseClassColor"
            )
        )
        OffsetCog(
            nameRow._rightRegion,
            "Value Position",
            { "bars", "rightTextOffsetX" },
            { "bars", "rightTextOffsetY" },
            valueOff,
            valueTip,
            valueRaw
        )
        local valueSwatch = Alternative(StyleSwatch("colors", "rightTextColor", "Value Color"), function()
            return not GetStyle("colors", "rightTextUseClassColor")
                and not GetStyle("colors", "rightTextUseThreatGradient")
        end, function()
            mod.SetStyleValues(
                "colors",
                { rightTextUseClassColor = false, rightTextUseThreatGradient = false }
            )
        end)
        valueSwatch.disabled, valueSwatch.disabledTooltip, valueSwatch.rawTooltip =
            valueOff, valueTip, valueRaw
        Swatch(nameRow._rightRegion, valueSwatch)
        -- Threat gradient: a swatch showing its colour scale, toggled by a click.
        Swatch(nameRow._rightRegion, {
            tooltip = "Colors each value from green to red as that player nears pulling aggro.",
            gradient = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
            disabled = valueOff,
            disabledTooltip = valueTip,
            rawTooltip = valueRaw,
            getValue = function()
                return 1, 1, 1
            end,
            setValue = function() end,
            refreshAlpha = function()
                return GetStyle("colors", "rightTextUseThreatGradient") and 1 or 0.3
            end,
            onClick = function()
                mod.SetStyleValues("colors", {
                    rightTextUseClassColor = false,
                    rightTextUseThreatGradient = not GetStyle("colors", "rightTextUseThreatGradient"),
                })
                CludesUI:RefreshPage()
            end,
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  WINDOW & BORDERS
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "WINDOW & BORDERS", cursorY)
    cursorY = cursorY - height

    local windowBorderOff, windowBorderTip = Needs(function()
        return IsZero("borders", "windowBorderSize")
    end, "Window Border Size")
    local includeHeader =
        StyleToggle("borders", "windowBorderIncludeHeader", "Include Header in Border", true)
    includeHeader.disabled, includeHeader.disabledTooltip = windowBorderOff, windowBorderTip
    local bgRow
    bgRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ThreatGate({
            type = "dropdown",
            text = "Background Texture",
            values = texValues,
            order = texOrder,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return GetStyle("colors", "bgTexture")
            end,
            setValue = function(val)
                mod.SetStyleValue("colors", "bgTexture", val)
            end,
        }),
        StyleSlider("colors", "bgAlpha", "Background", 0, 1, 0.01)
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        Swatch(
            bgRow._rightRegion,
            BlizzOnly(StyleSwatch("colors", { "bgR", "bgG", "bgB" }, "Background Color"))
        )
    end

    local borderValues, borderOrder = CludesUI.GetBorderTextureDropdown()
    -- Shadow is drawn behind its surface, and the bars have no layer behind
    -- them, so their list leaves it out (as the Damage Meters bars do).
    local barValues, barOrder = CludesUI.GetBorderTextureDropdown()
    barValues.shadow = nil
    for idx = #barOrder, 1, -1 do
        if barOrder[idx] == "shadow" then
            table.remove(barOrder, idx)
        end
    end
    local function BorderStyle(window, textValue)
        local key = window and "windowBorderTexture" or "borderTexture"
        return {
            type = "dropdown",
            text = textValue,
            values = window and borderValues or barValues,
            order = window and borderOrder or barOrder,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getValue = function()
                return GetStyle("borders", key)
            end,
            setValue = function(val)
                local color = CludesUI.GetBorderStyleSelectDefaults(val)
                local size = CludesUI.GetBorderDefaultSize(mod.BORDER_KEY, val) or 1
                local patch = { [key] = val }
                if window then
                    patch.windowBorderSize, patch.windowBorderSizePx = size, false
                    patch.windowBorderColor = { r = color.r, g = color.g, b = color.b, a = 1 }
                else
                    patch.borderSize, patch.borderSizePx = size, false
                    patch.borderR, patch.borderG, patch.borderB = color.r, color.g, color.b
                    patch.borderTextureOffset, patch.borderTextureOffsetY = false, false
                    patch.borderTextureShiftX, patch.borderTextureShiftY = 0, 0
                end
                mod.SetStyleValues("borders", patch)
                CludesUI:RefreshPage()
            end,
        }
    end
    -- One slider write can change both the size step and its exact pixels; they
    -- land together in one restyle.
    local pending = {}
    local function BorderSize(window, textValue)
        local stepKey = window and "windowBorderSize" or "borderSize"
        local pxKey = window and "windowBorderSizePx" or "borderSizePx"
        local texKey = window and "windowBorderTexture" or "borderTexture"
        return CludesUI.BorderPxSliderCfg({
            text = textValue,
            disabled = off,
            disabledTooltip = "Threat Meter",
            getStep = function()
                return GetStyle("borders", stepKey)
            end,
            setStep = function(val)
                pending[stepKey] = val
            end,
            getTex = function()
                return GetStyle("borders", texKey)
            end,
            getPx = function()
                return GetStyle("borders", pxKey)
            end,
            setPx = function(val)
                pending[pxKey] = val
            end,
            apply = function()
                local was = IsZero("borders", stepKey)
                mod.SetStyleValues("borders", pending)
                wipe(pending)
                if IsZero("borders", stepKey) ~= was then
                    CludesUI:RefreshPage()
                end
            end,
        })
    end

    local windowRow
    windowRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ThreatGate(BorderStyle(true, "Window Border Style")),
        ThreatGate(BorderSize(true, "Window Border Size"))
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local sc = StyleSwatch("borders", "windowBorderColor", "Window Border Color")
        sc.disabled, sc.disabledTooltip = windowBorderOff, windowBorderTip
        Swatch(windowRow._rightRegion, ThreatGate(sc))
    end

    local barBorderRow
    barBorderRow, height = W:DualRow(
        hostFrame,
        cursorY,
        ThreatGate(BorderStyle(false, "Bar Border Style")),
        ThreatGate(BorderSize(false, "Bar Border Size"))
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local sepCog = CludesUI.BuildInlineCog(
            barBorderRow._leftRegion,
            ThreatGate({
                title = "Bar Border Settings",
                disabled = off,
                disabledTooltip = "Threat Meter",
                rows = {
                    {
                        type = "toggle",
                        label = "Separators",
                        tooltip = "Replaces each bar's border with a divider under it.",
                        disabled = function()
                            return IsZero("borders", "borderSize")
                        end,
                        disabledTooltip = "Bar Border Size",
                        get = function()
                            return GetStyle("borders", "barSeparators")
                        end,
                        set = function(val)
                            mod.SetStyleValue("borders", "barSeparators", val)
                        end,
                    },
                },
            })
        )
        local function SyncSepCog()
            sepCog:SetShown(DividerArt("borderTexture", "sepH"))
        end
        SyncSepCog()
        CludesUI.RegisterWidgetRefresh(SyncSepCog)
        local sc = StyleSwatch("borders", { "borderR", "borderG", "borderB" }, "Bar Border Color")
        sc.disabled, sc.disabledTooltip = Needs(function()
            return IsZero("borders", "borderSize")
        end, "Bar Border Size")
        Swatch(barBorderRow._rightRegion, ThreatGate(sc))
    end

    _, height = W:DualRow(hostFrame, cursorY, ThreatGate(includeHeader), BLANK())
    cursorY = cursorY - height

    return math.abs(cursorY)
end
