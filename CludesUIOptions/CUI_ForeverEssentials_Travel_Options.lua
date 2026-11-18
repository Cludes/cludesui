if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Travel_Options.lua
--  Builds the "Travel" page inside the Forever Essentials module: a live
--  preview of the flight timer in the content header, then its settings.
-------------------------------------------------------------------------------
if not CludesUI._ModuleNS["CludesUIForeverEssentials"] then
    return
end -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = CludesUI._FlightTimer.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            CludesUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._CUI_TravelHeaderBuilder = HeaderBuilder

_G._CUI_BuildFlightTimerPage = function(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local FT = CludesUI._FlightTimer
    local cursorY = yOffset
    local _, height, heading
    hostFrame._showRowDivider = true

    CludesUI:SetContentHeader(HeaderBuilder)

    local function off()
        return not FT.Get("enabled")
    end
    local function Set(key, val)
        FT.Cfg()[key] = val
        FT.ApplyStyle()
    end
    -- Row setters over Set: the key written with the row's value.
    local function SetRow(key)
        return function(value)
            Set(key, value)
        end
    end

    local function TextCogRows(prefixText)
        return {
            {
                type = "slider",
                label = "Text Size",
                min = 8,
                max = 24,
                step = 1,
                get = function()
                    return FT.Get(prefixText .. "Size")
                end,
                set = function(val)
                    Set(prefixText .. "Size", val)
                end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -100,
                max = 100,
                step = 1,
                get = function()
                    return FT.Get(prefixText .. "X")
                end,
                set = function(val)
                    Set(prefixText .. "X", val)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -100,
                max = 100,
                step = 1,
                get = function()
                    return FT.Get(prefixText .. "Y")
                end,
                set = function(val)
                    Set(prefixText .. "Y", val)
                end,
            },
        }
    end

    local function BorderOffsets(prefixText, disabled)
        return CludesUI.BorderOffsetCogRows({
            getTex = function()
                return FT.Get("borderTexture")
            end,
            getStep = function()
                return FT.Get("borderSize")
            end,
            getPx = function()
                return FT.Get("borderSizePx")
            end,
            getX = function()
                return FT.Get(prefixText .. "Offset")
            end,
            setX = function(val)
                FT.Cfg()[prefixText .. "Offset"] = val
            end,
            getY = function()
                return FT.Get(prefixText .. "OffsetY")
            end,
            setY = function(val)
                FT.Cfg()[prefixText .. "OffsetY"] = val
            end,
            apply = FT.ApplyStyle,
            disabled = disabled,
            disabledTooltip = disabled and "This option requires an enabled textured border." or nil,
        })
    end

    local function SolidBorder()
        local texture = FT.Get("borderTexture")
        return texture == "solid" or texture == ""
    end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "FLIGHT TIMER", cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_FlightTimer", disabled = off, disabledTooltip = "Flight Timer" }
    )

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Flight Timer",
        tooltip = "Shows a bar with the time left while you ride a flight path.",
        getValue = function()
            return not off()
        end,
        setValue = function(val)
            FT.Cfg().enabled = val
            FT.Apply()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Fade In/Out",
        tooltip = "Fades the timer in at takeoff and out on landing.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("fade")
        end,
        setValue = function(val)
            FT.Cfg().fade = val
        end,
    })
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  LAYOUT
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "LAYOUT", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        {
            type = "slider",
            text = "Width",
            min = 50,
            max = 800,
            step = 1,
            disabled = off,
            disabledTooltip = "Flight Timer",
            getValue = function()
                return FT.Get("width")
            end,
            setValue = SetRow("width"),
        },
        -- The track's own key (trackHeight), not the retired bar's height.
        {
            type = "slider",
            text = "Height",
            min = 1,
            max = 30,
            step = 1,
            disabled = off,
            disabledTooltip = "Flight Timer",
            getValue = function()
                return FT.Get("trackHeight")
            end,
            setValue = SetRow("trackHeight"),
        }
    )
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height

    local texValues, texOrder = {}, {}
    do
        local t = FT.textures
        CludesUI.AppendSharedMediaTextures(t.names, t.order, nil, t.lookup)
        for _, key in ipairs(t.order) do
            if key ~= "---" then
                texValues[key] = t.names[key] or key
            end
            texOrder[#texOrder + 1] = key
        end
    end

    local borderValues, borderOrder = CludesUI.GetBorderTextureDropdown()
    local borderRow
    borderRow, height = W:DualRow(
        hostFrame,
        cursorY,
        {
            type = "dropdown",
            text = "Border Style",
            values = borderValues,
            order = borderOrder,
            disabled = off,
            disabledTooltip = "Flight Timer",
            getValue = function()
                return FT.Get("borderTexture")
            end,
            setValue = function(val)
                local c = FT.Cfg()
                c.borderTexture = val
                c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                c.borderTextureShiftX, c.borderTextureShiftY = nil, nil
                c.exitBorderOffset, c.exitBorderOffsetY = nil, nil
                local color, behind = CludesUI.GetBorderStyleSelectDefaults(val)
                c.borderR, c.borderG, c.borderB, c.borderBehind = color.r, color.g, color.b, behind
                local size = CludesUI.GetBorderDefaultSize(nil, val)
                if size then
                    c.borderSize = size
                end
                if c.borderSizePx then
                    c.borderSizePx = false
                end
                FT.ApplyStyle()
                CludesUI:RefreshPage(true)
            end,
        },
        CludesUI.BorderPxSliderCfg({
            trackWidth = 120,
            disabled = off,
            disabledTooltip = "Flight Timer",
            getStep = function()
                return FT.Get("borderSize")
            end,
            setStep = function(val)
                local c = FT.Cfg()
                c.borderTexture, c.borderSize = FT.Get("borderTexture"), val
            end,
            getTex = function()
                return FT.Get("borderTexture")
            end,
            getPx = function()
                return FT.Get("borderSizePx")
            end,
            setPx = function(val)
                FT.Cfg().borderSizePx = val
            end,
            apply = function()
                FT.ApplyStyle()
                CludesUI:RefreshPage()
            end,
        })
    )
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local offsetX, offsetY = BorderOffsets("borderTexture")
        CludesUI.BuildInlineCog(borderRow._leftRegion, {
            title = "Border Options",
            disabled = function()
                return off() or SolidBorder()
            end,
            disabledTooltip = "This option requires a textured border.",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return FT.Get("borderTextureShiftX") or 0
                    end,
                    set = SetRow("borderTextureShiftX"),
                },
                {
                    type = "slider",
                    label = "Shift Y",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function()
                        return FT.Get("borderTextureShiftY") or 0
                    end,
                    set = SetRow("borderTextureShiftY"),
                },
                offsetX,
                offsetY,
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function()
                        return FT.Get("borderBehind")
                    end,
                    set = SetRow("borderBehind"),
                },
            },
        })
        CludesUI.BuildInlineSwatches(borderRow._rightRegion, {
            {
                tooltip = "Border Color",
                disabled = function()
                    return off() or FT.Get("borderSize") == 0
                end,
                disabledTooltip = function()
                    return off() and "Flight Timer" or "Border Size"
                end,
                getValue = function()
                    return FT.Get("borderR"), FT.Get("borderG"), FT.Get("borderB"), 1
                end,
                setValue = function(r, g, b)
                    local c = FT.Cfg()
                    c.borderR, c.borderG, c.borderB = r, g, b
                    FT.ApplyStyle()
                end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Bar Texture",
        values = texValues,
        order = texOrder,
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("texture")
        end,
        setValue = SetRow("texture"),
    }, {
        type = "dropdown",
        text = "Background Texture",
        values = texValues,
        order = texOrder,
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("bgTexture")
        end,
        setValue = SetRow("bgTexture"),
    })
    cursorY = cursorY - height

    local colorRow
    colorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Fill Color",
        min = 0,
        max = 100,
        step = 1,
        trackWidth = 120,
        tooltip = "Opacity of the bar fill.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("fillOpacity")
        end,
        setValue = SetRow("fillOpacity"),
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        trackWidth = 120,
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return math.floor(FT.Get("bgA") * 100 + 0.5)
        end,
        setValue = function(val)
            Set("bgA", val / 100)
        end,
    })
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineSwatches(colorRow._leftRegion, {
            {
                tooltip = "Custom Colored",
                getValue = function()
                    local fr = FT.Get("fillR")
                    if fr then
                        return fr, FT.Get("fillG"), FT.Get("fillB"), 1
                    end
                    local ACC = CludesUI.CLUDES_GREEN
                    return ACC.r, ACC.g, ACC.b, 1
                end,
                setValue = function(r, g, b)
                    local c = FT.Cfg()
                    c.fillR, c.fillG, c.fillB = r, g, b
                    c.classColored = false
                    FT.ApplyStyle()
                    CludesUI:RefreshPage()
                end,
                onClick = function(self)
                    if FT.Get("classColored") then
                        Set("classColored", false)
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return FT.Get("classColored") and 0.3 or 1
                end,
            },
            {
                tooltip = "Class Colored",
                getValue = function()
                    local _, class = UnitClass("player")
                    local classColor = class and CludesUI.GetClassColor(class)
                    if classColor then
                        return classColor.r, classColor.g, classColor.b, 1
                    end
                    return 1, 1, 1, 1
                end,
                setValue = function() end,
                onClick = function()
                    Set("classColored", true)
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return FT.Get("classColored") and 1 or 0.3
                end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
        CludesUI.BuildInlineSwatches(colorRow._rightRegion, {
            {
                tooltip = "Background Color",
                getValue = function()
                    return FT.Get("bgR"), FT.Get("bgG"), FT.Get("bgB"), 1
                end,
                setValue = function(r, g, b)
                    local c = FT.Cfg()
                    c.bgR, c.bgG, c.bgB = r, g, b
                    FT.ApplyStyle()
                end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    local textRow
    textRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Time",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("timeText") ~= "none"
        end,
        setValue = function(val)
            Set("timeText", not val and "none" or nil)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Total Time",
        tooltip = "Shows the full flight time next to the time left, for example 1:23 / 4:19.",
        disabled = function()
            return off() or FT.Get("timeText") == "none"
        end,
        disabledTooltip = "Show Time",
        getValue = function()
            return FT.Get("showTotal")
        end,
        setValue = function(val)
            FT.Cfg().showTotal = val
        end,
    })
    cursorY = cursorY - height
    CludesUI.BuildInlineCog(textRow._leftRegion, {
        title = "Time Text Settings",
        rows = TextCogRows("time"),
        gap = 9,
        disabledTooltip = "Show Time",
        disabled = function()
            return off() or FT.Get("timeText") == "none"
        end,
    })

    local exitRow
    exitRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Names",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("destText") ~= "none"
        end,
        setValue = function(val)
            Set("destText", not val and "none" or nil)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Early Exit Button",
        tooltip = "Shows a button next to the bar that lands you at the next flight point.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("earlyExit")
        end,
        setValue = function(val)
            Set("earlyExit", val)
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    CludesUI.BuildInlineCog(exitRow._leftRegion, {
        title = "Name Text Settings",
        rows = TextCogRows("dest"),
        gap = 9,
        disabledTooltip = "Show Names",
        disabled = function()
            return off() or FT.Get("destText") == "none"
        end,
    })
    local offsetX, offsetY = BorderOffsets("exitBorder", function()
        return not FT.Get("exitBorder")
            or not FT.Get("exitBorderCustom")
            or FT.Get("borderSize") == 0
            or SolidBorder()
    end)
    CludesUI.BuildInlineCog(exitRow._rightRegion, {
        title = "Early Exit Border Options",
        disabled = function()
            return off() or not FT.Get("earlyExit")
        end,
        disabledTooltip = "Early Exit Button",
        rows = {
            {
                type = "toggle",
                label = "Enable Border",
                get = function()
                    return FT.Get("exitBorder")
                end,
                set = SetRow("exitBorder"),
            },
            {
                type = "toggle",
                label = "Use Bar Border",
                tooltip = "Inherits the travel bar's border style, size and color instead of the plain button border.",
                disabled = function()
                    return not FT.Get("exitBorder")
                end,
                disabledTooltip = "Enable Border",
                get = function()
                    return FT.Get("exitBorderCustom")
                end,
                set = SetRow("exitBorderCustom"),
            },
            offsetX,
            offsetY,
        },
    })

    local separatorRow
    separatorRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show End Caps",
        tooltip = "The dots at the two ends of the track.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("showEndCaps")
        end,
        setValue = SetRow("showEndCaps"),
    }, {
        type = "toggle",
        text = "Show Separator",
        tooltip = "The white line at the middle of the track on flights with multiple stops.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("showSeparator")
        end,
        setValue = function(val)
            Set("showSeparator", val)
            CludesUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    CludesUI.BuildInlineCog(separatorRow._rightRegion, {
        title = "Separator Settings",
        disabled = function()
            return off() or not FT.Get("showSeparator")
        end,
        disabledTooltip = "Show Separator",
        rows = {
            {
                type = "slider",
                label = "Height",
                min = 1,
                max = 60,
                step = 1,
                get = function()
                    return FT.Get("separatorHeight")
                end,
                set = SetRow("separatorHeight"),
            },
            {
                type = "toggle",
                label = "Custom Separator",
                tooltip = "Uses the separator artwork from the Pixels or Pixels Textured border.",
                disabled = function()
                    return FT.Get("borderSize") == 0
                        or not CludesUI.GetBorderCompanion(FT.Get("borderTexture"), "sepV")
                end,
                disabledTooltip = "This option requires a Pixels or Pixels Textured border above size 0.",
                get = function()
                    return FT.Get("customSeparator")
                end,
                set = SetRow("customSeparator"),
            },
        },
    })

    local sparkRow
    sparkRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Spark",
        tooltip = "Shows a Pixels glow line at the moving end of the bar fill.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function()
            return FT.Get("showSpark")
        end,
        setValue = function(val)
            Set("showSpark", val)
            CludesUI:RefreshPage()
        end,
    }, CludesUI.BlankRowCfg())
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        CludesUI.BuildInlineSwatches(sparkRow._leftRegion, {
            {
                tooltip = "Spark Color",
                disabled = function()
                    return off() or not FT.Get("showSpark")
                end,
                disabledTooltip = "Show Spark",
                getValue = function()
                    return FT.Get("sparkR"), FT.Get("sparkG"), FT.Get("sparkB"), 1
                end,
                setValue = function(r, g, b)
                    local c = FT.Cfg()
                    c.sparkR, c.sparkG, c.sparkB = r, g, b
                    FT.ApplyStyle()
                end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    return math.abs(cursorY)
end
