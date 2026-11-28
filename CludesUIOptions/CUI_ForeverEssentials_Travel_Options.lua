if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Travel_Options.lua
--  Builds the "Travel" page inside the Forever Essentials module: a live
--  preview of the flight timer in the content header, then its settings.
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = CUI._FlightTimer.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            CUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._CUI_TravelHeaderBuilder = HeaderBuilder

_G._CUI_BuildFlightTimerPage = function(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local FT = CUI._FlightTimer
    local cursorY = yOffset
    local _, height, heading
    hostFrame._showRowDivider = true

    CUI:SetContentHeader(HeaderBuilder)

    local function off() return not FT.Get("enabled") end
    local function Set(key, val)
        FT.Cfg()[key] = val
        FT.ApplyStyle()
    end
    -- Row setters over Set: the key written with the row's value.
    local function SetRow(key)
        return function(value) Set(key, value) end
    end

    local function TextCogRows(prefixText)
        return {
            {
                type = "slider",
                label = "Text Size",
                min = 8,
                max = 24,
                step = 1,
                get = function() return FT.Get(prefixText .. "Size") end,
                set = function(val) Set(prefixText .. "Size", val) end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -100,
                max = 100,
                step = 1,
                get = function() return FT.Get(prefixText .. "X") end,
                set = function(val) Set(prefixText .. "X", val) end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -100,
                max = 100,
                step = 1,
                get = function() return FT.Get(prefixText .. "Y") end,
                set = function(val) Set(prefixText .. "Y", val) end,
            },
        }
    end

    local function BorderOffsets(prefixText, disabled)
        return CUI.BorderOffsetCogRows({
            getTex = function() return FT.Get("borderTexture") end,
            getStep = function() return FT.Get("borderSize") end,
            getPx = function() return FT.Get("borderSizePx") end,
            getX = function() return FT.Get(prefixText .. "Offset") end,
            setX = function(val) FT.Cfg()[prefixText .. "Offset"] = val end,
            getY = function() return FT.Get(prefixText .. "OffsetY") end,
            setY = function(val) FT.Cfg()[prefixText .. "OffsetY"] = val end,
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
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_FlightTimer", disabled = off, disabledTooltip = "Flight Timer" }
    )

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Flight Timer",
        tooltip = "Shows a bar with the time left while you ride a flight path.",
        getValue = function() return not off() end,
        setValue = function(val)
            FT.Cfg().enabled = val
            FT.Apply()
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Fade In/Out",
        tooltip = "Fades the timer in at takeoff and out on landing.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function() return FT.Get("fade") end,
        setValue = function(val) FT.Cfg().fade = val end,
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
            getValue = function() return FT.Get("width") end,
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
            getValue = function() return FT.Get("trackHeight") end,
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
        local tbl = FT.textures
        CUI.AppendSharedMediaTextures(tbl.names, tbl.order, nil, tbl.lookup)
        for _, key in ipairs(tbl.order) do
            if key ~= "---" then texValues[key] = tbl.names[key] or key end
            texOrder[#texOrder + 1] = key
        end
    end

    local borderValues, borderOrder = CUI.GetBorderTextureDropdown()
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
            getValue = function() return FT.Get("borderTexture") end,
            setValue = function(val)
                local cfg = FT.Cfg()
                cfg.borderTexture = val
                cfg.borderTextureOffset, cfg.borderTextureOffsetY = nil, nil
                cfg.borderTextureShiftX, cfg.borderTextureShiftY = nil, nil
                cfg.exitBorderOffset, cfg.exitBorderOffsetY = nil, nil
                local color, behind = CUI.GetBorderStyleSelectDefaults(val)
                cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderBehind = color.r, color.g, color.b, behind
                local size = CUI.GetBorderDefaultSize(nil, val)
                if size then cfg.borderSize = size end
                if cfg.borderSizePx then cfg.borderSizePx = false end
                FT.ApplyStyle()
                CUI:RefreshPage(true)
            end,
        },
        CUI.BorderPxSliderCfg({
            trackWidth = 120,
            disabled = off,
            disabledTooltip = "Flight Timer",
            getStep = function() return FT.Get("borderSize") end,
            setStep = function(val)
                local cfg = FT.Cfg()
                cfg.borderTexture, cfg.borderSize = FT.Get("borderTexture"), val
            end,
            getTex = function() return FT.Get("borderTexture") end,
            getPx = function() return FT.Get("borderSizePx") end,
            setPx = function(val) FT.Cfg().borderSizePx = val end,
            apply = function()
                FT.ApplyStyle()
                CUI:RefreshPage()
            end,
        })
    )
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local offsetX, offsetY = BorderOffsets("borderTexture")
        CUI.BuildInlineCog(borderRow._leftRegion, {
            title = "Border Options",
            disabled = function() return off() or SolidBorder() end,
            disabledTooltip = "This option requires a textured border.",
            rows = {
                {
                    type = "slider",
                    label = "Shift X",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function() return FT.Get("borderTextureShiftX") or 0 end,
                    set = SetRow("borderTextureShiftX"),
                },
                {
                    type = "slider",
                    label = "Shift Y",
                    min = -10,
                    max = 10,
                    step = 1,
                    get = function() return FT.Get("borderTextureShiftY") or 0 end,
                    set = SetRow("borderTextureShiftY"),
                },
                offsetX,
                offsetY,
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function() return FT.Get("borderBehind") end,
                    set = SetRow("borderBehind"),
                },
            },
        })
        CUI.BuildInlineSwatches(borderRow._rightRegion, {
            {
                tooltip = "Border Color",
                disabled = function() return off() or FT.Get("borderSize") == 0 end,
                disabledTooltip = function() return off() and "Flight Timer" or "Border Size" end,
                getValue = function() return FT.Get("borderR"), FT.Get("borderG"), FT.Get("borderB"), 1 end,
                setValue = function(red, green, blue)
                    local cfg = FT.Cfg()
                    cfg.borderR, cfg.borderG, cfg.borderB = red, green, blue
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
        getValue = function() return FT.Get("texture") end,
        setValue = SetRow("texture"),
    }, {
        type = "dropdown",
        text = "Background Texture",
        tooltip = "The texture behind the window.",
        values = texValues,
        order = texOrder,
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function() return FT.Get("bgTexture") end,
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
        getValue = function() return FT.Get("fillOpacity") end,
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
        getValue = function() return math.floor(FT.Get("bgA") * 100 + 0.5) end,
        setValue = function(val) Set("bgA", val / 100) end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineSwatches(colorRow._leftRegion, {
            {
                tooltip = "Custom Colored",
                getValue = function()
                    local fr = FT.Get("fillR")
                    if fr then return fr, FT.Get("fillG"), FT.Get("fillB"), 1 end
                    local ACC = CUI.CLUDES_GREEN
                    return ACC.r, ACC.g, ACC.b, 1
                end,
                setValue = function(red, green, blue)
                    local cfg = FT.Cfg()
                    cfg.fillR, cfg.fillG, cfg.fillB = red, green, blue
                    cfg.classColored = false
                    FT.ApplyStyle()
                    CUI:RefreshPage()
                end,
                onClick = function(self)
                    if FT.Get("classColored") then
                        Set("classColored", false)
                        CUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then self._eabOrigClick(self) end
                end,
                refreshAlpha = function() return FT.Get("classColored") and 0.3 or 1 end,
            },
            {
                tooltip = "Class Colored",
                getValue = function()
                    local _, class = UnitClass("player")
                    local classColor = class and CUI.GetClassColor(class)
                    if classColor then return classColor.r, classColor.g, classColor.b, 1 end
                    return 1, 1, 1, 1
                end,
                setValue = function() end,
                onClick = function()
                    Set("classColored", true)
                    CUI:RefreshPage()
                end,
                refreshAlpha = function() return FT.Get("classColored") and 1 or 0.3 end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
        CUI.BuildInlineSwatches(colorRow._rightRegion, {
            {
                tooltip = "Background Color",
                getValue = function() return FT.Get("bgR"), FT.Get("bgG"), FT.Get("bgB"), 1 end,
                setValue = function(red, green, blue)
                    local cfg = FT.Cfg()
                    cfg.bgR, cfg.bgG, cfg.bgB = red, green, blue
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
        getValue = function() return FT.Get("timeText") ~= "none" end,
        setValue = function(val)
            Set("timeText", not val and "none" or nil)
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Show Total Time",
        tooltip = "Shows the full flight time next to the time left, for example 1:23 / 4:19.",
        disabled = function() return off() or FT.Get("timeText") == "none" end,
        disabledTooltip = "Show Time",
        getValue = function() return FT.Get("showTotal") end,
        setValue = function(val) FT.Cfg().showTotal = val end,
    })
    cursorY = cursorY - height
    CUI.BuildInlineCog(textRow._leftRegion, {
        title = "Time Text Settings",
        rows = TextCogRows("time"),
        gap = 9,
        disabledTooltip = "Show Time",
        disabled = function() return off() or FT.Get("timeText") == "none" end,
    })

    local exitRow
    exitRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Show Names",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function() return FT.Get("destText") ~= "none" end,
        setValue = function(val)
            Set("destText", not val and "none" or nil)
            CUI:RefreshPage()
        end,
    }, {
        type = "toggle",
        text = "Early Exit Button",
        tooltip = "Shows a button next to the bar that lands you at the next flight point.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function() return FT.Get("earlyExit") end,
        setValue = function(val)
            Set("earlyExit", val)
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    CUI.BuildInlineCog(exitRow._leftRegion, {
        title = "Name Text Settings",
        rows = TextCogRows("dest"),
        gap = 9,
        disabledTooltip = "Show Names",
        disabled = function() return off() or FT.Get("destText") == "none" end,
    })
    local offsetX, offsetY = BorderOffsets(
        "exitBorder",
        function()
            return not FT.Get("exitBorder")
                or not FT.Get("exitBorderCustom")
                or FT.Get("borderSize") == 0
                or SolidBorder()
        end
    )
    CUI.BuildInlineCog(exitRow._rightRegion, {
        title = "Early Exit Border Options",
        disabled = function() return off() or not FT.Get("earlyExit") end,
        disabledTooltip = "Early Exit Button",
        rows = {
            {
                type = "toggle",
                label = "Enable Border",
                get = function() return FT.Get("exitBorder") end,
                set = SetRow("exitBorder"),
            },
            {
                type = "toggle",
                label = "Use Bar Border",
                tooltip = "Inherits the travel bar's border style, size and color instead of the plain button border.",
                disabled = function() return not FT.Get("exitBorder") end,
                disabledTooltip = "Enable Border",
                get = function() return FT.Get("exitBorderCustom") end,
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
        getValue = function() return FT.Get("showEndCaps") end,
        setValue = SetRow("showEndCaps"),
    }, {
        type = "toggle",
        text = "Show Separator",
        tooltip = "The white line at the middle of the track on flights with multiple stops.",
        disabled = off,
        disabledTooltip = "Flight Timer",
        getValue = function() return FT.Get("showSeparator") end,
        setValue = function(val)
            Set("showSeparator", val)
            CUI:RefreshPage()
        end,
    })
    cursorY = cursorY - height
    CUI.BuildInlineCog(separatorRow._rightRegion, {
        title = "Separator Settings",
        disabled = function() return off() or not FT.Get("showSeparator") end,
        disabledTooltip = "Show Separator",
        rows = {
            {
                type = "slider",
                label = "Height",
                min = 1,
                max = 60,
                step = 1,
                get = function() return FT.Get("separatorHeight") end,
                set = SetRow("separatorHeight"),
            },
            {
                type = "toggle",
                label = "Custom Separator",
                tooltip = "Uses the separator artwork from the Pixels or Pixels Textured border.",
                disabled = function()
                    return FT.Get("borderSize") == 0
                        or not CUI.GetBorderCompanion(FT.Get("borderTexture"), "sepV")
                end,
                disabledTooltip = "This option requires a Pixels or Pixels Textured border above size 0.",
                get = function() return FT.Get("customSeparator") end,
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
        getValue = function() return FT.Get("showSpark") end,
        setValue = function(val)
            Set("showSpark", val)
            CUI:RefreshPage()
        end,
    }, CUI.BlankRowCfg())
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineSwatches(sparkRow._leftRegion, {
            {
                tooltip = "Spark Color",
                disabled = function() return off() or not FT.Get("showSpark") end,
                disabledTooltip = "Show Spark",
                getValue = function() return FT.Get("sparkR"), FT.Get("sparkG"), FT.Get("sparkB"), 1 end,
                setValue = function(red, green, blue)
                    local cfg = FT.Cfg()
                    cfg.sparkR, cfg.sparkG, cfg.sparkB = red, green, blue
                    FT.ApplyStyle()
                end,
            },
        }, { disabled = off, disabledTooltip = "Flight Timer" })
    end

    -- Flight Point Reminder (CludesUIForeverEssentials_FlightPoints.lua).
    local FP = CUI._FlightPoints
    if FP then
        local function fpOff() return not FP.Get("enabled") end
        local function FPSet(key, val)
            FP.Cfg()[key] = val
            FP.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        local fpHeading
        fpHeading, height = W:SectionHeader(hostFrame, "FLIGHT POINT REMINDER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            fpHeading,
            { key = "CUI_FlightPoints", disabled = fpOff, disabledTooltip = "Flight Point Reminder" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Flight Point Reminder",
            tooltip = "Reminds you to learn a flight point when you reach a town whose flight master you have not spoken to, and for a few seconds as you enter a zone that has one. Open a flight master's map once per continent so it knows the points you have.",
            getValue = function() return not fpOff() end,
            setValue = function(val)
                FPSet("enabled", val and true or false)
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 10,
            max = 24,
            step = 1,
            isPercent = false,
            disabled = fpOff,
            getValue = function() return FP.Get("textSize") end,
            setValue = function(val) FPSet("textSize", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  JOURNEYS
    ---------------------------------------------------------------------------
    local JY = CUI._Journeys
    if JY then
        local function Set(key, val)
            JY.Cfg()[key] = val
            JY.Apply()
        end
        local function jOff() return not JY.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "JOURNEYS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Journeys",
            tooltip = "Place a map pin and a small card shows the fastest way there, over walking, the flights you know, boats, zeppelins, the tram, your Hearthstone and class teleports, with an arrow pointing to the next step. Open a flight master's map once so it knows your flights. Move the card in Edit Layout.",
            getValue = function() return not jOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Use Hearthstone",
            disabled = jOff,
            tooltip = "Includes your Hearthstone when it is ready. It learns where it takes you the first time you use it.",
            getValue = function() return JY.Get("hearth") end,
            setValue = function(val) Set("hearth", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Use Class Teleports",
            disabled = jOff,
            tooltip = "Includes mage teleports and Moonglade when you know them and they are ready.",
            getValue = function() return JY.Get("teleports") end,
            setValue = function(val) Set("teleports", val and true or false) end,
        }, {
            type = "toggle",
            text = "Route on Minimap",
            disabled = jOff,
            tooltip = "Dots on the minimap along the walk to the next step.",
            getValue = function() return JY.Get("minimapRoute") end,
            setValue = function(val) Set("minimapRoute", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  BOAT AND ZEPPELIN TIMERS
    ---------------------------------------------------------------------------
    local TR2 = CUI._Transport
    if TR2 then
        local function tOff() return not TR2.Get("enabled") end
        local function Set(key, val)
            TR2.Cfg()[key] = val
            TR2.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "BOAT AND ZEPPELIN TIMERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_ShipTimer", disabled = tOff, disabledTooltip = "Boat and Zeppelin Timer" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Boat and Zeppelin Timers",
            tooltip = "When each ship leaves and arrives, on minimap pins at its docks. A ship is timed when you ride it, when you click its pin as it arrives (left) or leaves (right), or from players who share timings.",
            getValue = function() return not tOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Zone Timer",
            disabled = tOff,
            tooltip = "A list of the boats and zeppelins in your zone with their times. Move it in Edit Layout.",
            getValue = function() return TR2.Get("zone") end,
            setValue = function(val) Set("zone", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Share Timings",
            disabled = tOff,
            tooltip = "Sends the ships you time to your group and guild, and takes theirs, and the timings of ForeverTransport and NauticusClassic users.",
            getValue = function() return TR2.Get("share") end,
            setValue = function(val) Set("share", val and true or false) end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 10,
            max = 24,
            step = 1,
            isPercent = false,
            disabled = tOff,
            getValue = function() return TR2.Get("size") end,
            setValue = function(val) Set("size", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  TOWN MAP
    ---------------------------------------------------------------------------
    local TWN = CUI._TownMap
    if TWN then
        local function nOff() return not TWN.Get("enabled") end
        local function Tog(key, textValue, tipText, dis)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = dis or nOff,
                getValue = function() return TWN.Get(key) end,
                setValue = function(val)
                    TWN.Cfg()[key] = val and true or false
                    TWN.Apply()
                end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "TOWN MAP", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "enabled",
                "Town Map",
                "Service NPCs for your faction, mailboxes and spirit healers on the world map. Hover a pin for its name.",
                function() return false end
            ),
            Tog(
                "capitalsOnly",
                "Vendors and Trainers Only in Cities",
                "Keeps vendors, trainers and the bank off questing maps. Flight masters, innkeepers and stable masters still show everywhere."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("minimapMail", "Mailboxes on Minimap", "Pins the mailboxes near you on the minimap."),
            Tog(
                "minimapSpirit",
                "Spirit Healers on Minimap",
                "Pins the spirit healers near you on the minimap."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("mail", "Mailboxes", "Every mailbox, in towns and out in the world."),
            Tog("spirit", "Spirit Healers", "Every graveyard's spirit healer, in towns and out in the world.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("class", "Class Trainers", "Your own class's trainers only."),
            Tog("profession", "Profession Trainers")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("flight", "Flight Masters", "Left to Map Markers when its Flight Points pins are on."),
            Tog("inn", "Innkeepers")
        )
        cursorY = cursorY - height
        _, height =
            W:DualRow(hostFrame, cursorY, Tog("bank", "Bank and Auction House"), Tog("repair", "Repairs"))
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("supplies", "Reagents, Ammo and Food"),
            Tog("stable", "Stable Masters", "Hunters only.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("vendors", "Other Vendors", "Trade goods and every other merchant."),
            {
                type = "slider",
                text = "Pin Size",
                min = 10,
                max = 32,
                step = 1,
                isPercent = false,
                disabled = nOff,
                getValue = function() return TWN.Get("size") end,
                setValue = function(val)
                    TWN.Cfg().size = math.floor(val + 0.5)
                    TWN.Apply()
                end,
            }
        )
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  LAYERS
    ---------------------------------------------------------------------------
    local LY = CUI._Layers
    if LY then
        local lt, ls = LY.tracker, LY.swap
        local function lOff() return not lt.Get("enabled") end
        local function Set(key, val)
            lt.Cfg()[key] = val
            lt.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "LAYERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_LayerTracker", disabled = lOff, disabledTooltip = "Layer Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Layer Tracker",
            tooltip = "Which layer of the zone you are on, read from the NPCs around you. Hover it for the layers seen in this zone.",
            getValue = function() return not lOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Auto-Accept Layer Swap",
            tooltip = "Confirms the game's layer swap prompt when you join a group.",
            getValue = function() return ls.Get("enabled") end,
            setValue = function(val) ls.Cfg().enabled = val and true or false end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Countdown to a Layer Change",
            disabled = lOff,
            getValue = function() return lt.Get("countdown") end,
            setValue = function(val) Set("countdown", val and true or false) end,
        }, {
            type = "toggle",
            text = "Say When You Move",
            disabled = lOff,
            getValue = function() return lt.Get("chat") end,
            setValue = function(val) Set("chat", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
