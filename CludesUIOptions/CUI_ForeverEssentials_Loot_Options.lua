if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end -- Forever Essentials loads on WoW Forever only
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Loot_Options.lua
--  Builds the "Loot" page inside the Forever Essentials module: a live
--  preview of the feed in the content header, then its settings.
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end -- module disabled: no options page

-- The preview surface in the content header. Exported so the module's
-- getHeaderBuilder can hand it back when the page cache outlives its header.
local function HeaderBuilder(header, width)
    local building = true
    local view = CUI._LootFeed.CreateSettingsPreview(header, width, function(height)
        if not building and header:IsVisible() and math.abs(header:GetHeight() - height) > 1 then
            CUI:SetContentHeaderHeightSilent(height)
        end
    end)
    building = false
    return view.previewHeight
end
_G._CUI_LootHeaderBuilder = HeaderBuilder

local STYLES = { BOX = "Box", BAR = "Accent Bar", TRAY = "Icon Tray", TOAST = "Loot Toast" }
local STYLE_ORDER = { "BOX", "BAR", "TRAY", "TOAST" }

_G._CUI_BuildLootFeedPage = function(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local LF = CUI._LootFeed
    local BLANK = CUI.BlankRowCfg
    local cursorY = yOffset
    local _, height, heading
    hostFrame._showRowDivider = true

    CUI:SetContentHeader(HeaderBuilder)

    local function off() return not LF.Get("enabled") end
    local function itemsOff() return off() or not LF.Get("items") end
    -- Auction prices count only while the tracker or an item price shows, and
    -- only with the price addon's API at hand.
    local function auctionSource() return CUI._ModuleNS["CludesUIForeverEssentials"].AuctionAPI() ~= nil end
    local function pricesUnused() return not (LF.Get("tracker") or (LF.Get("items") and LF.Get("showPrice"))) end
    local function auctionOff() return off() or not auctionSource() or pricesUnused() end
    local function auctionTip()
        if off() then return "Loot Feed" end
        if not auctionSource() then return "This option requires Auctionator to be loaded." end
        return "This option requires Gold per Hour Tracker or Show Item Price to be enabled."
    end
    local function style() return LF.Get("style") end
    -- Loot Toast keeps its gold frame.
    local function borderOff() return off() or style() == "TOAST" end
    local function noBorderColor() return borderOff() or LF.Get("borderSize") == 0 end
    -- Switching a source re-registers the feed's events.
    local function ApplyLootFeed()
        LF.Apply()
        LF.RefreshPreview()
        CUI:RefreshPage()
    end
    -- Binds cfg to setting key; apply runs after a change (none: the next row
    -- shown picks it up). Greyed out while the feed is off unless disabled is
    -- given.
    local function Bind(rowConf, key, apply, disabled, disabledTooltip)
        rowConf.disabled, rowConf.disabledTooltip = disabled or off, disabledTooltip or "Loot Feed"
        rowConf.getValue = rowConf.getValue or function() return LF.Get(key) end
        rowConf.setValue = rowConf.setValue
            or function(val)
                LF.Cfg()[key] = val
                if apply then apply() end
            end
        return rowConf
    end
    local function Toggle(key, textValue, tooltip, apply, disabled, disabledTooltip)
        return Bind(
            { type = "toggle", text = textValue, tooltip = tooltip },
            key,
            apply,
            disabled,
            disabledTooltip
        )
    end
    local function Slider(key, textValue, min, max, tooltip, apply)
        return Bind(
            { type = "slider", text = textValue, tooltip = tooltip, min = min, max = max, step = 1 },
            key,
            apply or LF.ApplyStyle
        )
    end
    -- An inline swatch for the prefix .. "R" / "G" / "B" colour.
    local function Swatch(regionFrame, prefixText, tooltip, disabled, disabledTooltip)
        CUI.BuildInlineSwatches(regionFrame, {
            {
                tooltip = tooltip,
                disabled = disabled,
                disabledTooltip = disabledTooltip,
                getValue = function()
                    return LF.Get(prefixText .. "R"), LF.Get(prefixText .. "G"), LF.Get(prefixText .. "B"), 1
                end,
                setValue = function(red, green, blue)
                    local c = LF.Cfg()
                    c[prefixText .. "R"], c[prefixText .. "G"], c[prefixText .. "B"] = red, green, blue
                    if prefixText == "border" and style() == "BAR" then
                        c.borderTexture = LF.Get("borderTexture") or "solid"
                    end
                    LF.ApplyStyle()
                end,
            },
        }, { disabled = off, disabledTooltip = "Loot Feed" })
    end

    ---------------------------------------------------------------------------
    --  GENERAL
    ---------------------------------------------------------------------------
    heading, height = W:SectionHeader(hostFrame, "LOOT FEED", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_LootFeed", disabled = off, disabledTooltip = "Loot Feed" }
    )

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Enable Loot Feed",
        tooltip = "Shows what you loot and gain as short-lived rows that fade out.",
        getValue = function() return not off() end,
        setValue = function(val)
            LF.Cfg().enabled = val
            ApplyLootFeed()
        end,
    }, {
        type = "labeledButton",
        text = "Preview",
        buttonText = "Show Samples",
        tooltip = "Shows a sample row for every enabled source.",
        disabled = off,
        disabledTooltip = "Loot Feed",
        onClick = function() LF.Preview() end,
    })
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Bind({ type = "dropdown", text = "Style", values = STYLES, order = STYLE_ORDER }, "style", function()
            LF.ApplyStyle()
            if CUI._unlockActive and CUI.RepositionBarToMover then
                CUI.RepositionBarToMover("CUI_LootFeed")
            end
            CUI:RefreshPage()
        end),
        Bind(
            {
                type = "slider",
                text = "Accent Bar Width",
                min = 0,
                max = 6,
                step = 1,
                tooltip = "0 hides the accent bar.",
            },
            "barWidth",
            LF.ApplyStyle,
            function() return off() or style() == "BOX" or style() == "TOAST" end,
            function() return off() and "Loot Feed" or "Style" end
        )
    )
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  SOURCES
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "SOURCES", cursorY)
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle("items", "Items", "Items you loot or receive.", ApplyLootFeed),
        Toggle("money", "Money", "Money you loot.", ApplyLootFeed)
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle(
            "reputation",
            "Reputation",
            "Reputation gains and losses, with your progress in the current standing.",
            ApplyLootFeed
        ),
        Toggle(
            "currency",
            "Currencies",
            "Honor, badges and other currencies, with your total.",
            ApplyLootFeed
        )
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle("skills", "Skill Ups", "Weapon and profession skill increases.", ApplyLootFeed),
        Toggle(
            "rolls",
            "Loot Rolls",
            "Who won each group loot roll and with what roll. Your own wins add the roll to the item's row.",
            ApplyLootFeed
        )
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle("tracker", "Gold per Hour Tracker", "Pins a row with your gold per hour.", function()
            LF.Apply()
            LF.ApplyStyle()
            if CUI._unlockActive and CUI.RepositionBarToMover then
                CUI.RepositionBarToMover("CUI_LootFeed")
            end
            CUI:RefreshPage()
        end)
    )
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  ITEMS
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "ITEMS", cursorY)
    cursorY = cursorY - height

    local qualityValues, qualityOrder = _G._CUI_ItemQualityValues(Enum.ItemQuality.Legendary)

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Bind({
            type = "dropdown",
            text = "Minimum Quality",
            values = qualityValues,
            order = qualityOrder,
            tooltip = "Items below this quality are not shown.",
            getValue = function() return tostring(LF.Get("minQuality")) end,
            setValue = function(val)
                LF.Cfg().minQuality = tonumber(val)
                LF.RefreshPreview()
            end,
        }, nil, nil, itemsOff, "Items"),
        Toggle(
            "showIlvl",
            "Show Item Level",
            "Shows the item level of weapons and armor.",
            LF.RefreshPreview,
            itemsOff,
            "Items"
        )
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle("showPrice", "Show Item Price", "Shows what the looted stack is worth.", function()
            LF.RefreshPreview()
            CUI:RefreshPage() -- Use Auctionator Prices greys with it
        end, itemsOff, "Items"),
        Toggle(
            "auctionPrices",
            "Use Auctionator Prices",
            "Prices items from Auctionator scans.",
            LF.RefreshPreview,
            auctionOff,
            auctionTip
        )
    )
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
        Slider("width", "Width", 150, 600),
        Slider("rowHeight", "Row Height", 20, 60, "Tile size in the Icon Tray style.")
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Slider("maxRows", "Max Rows", 1, 12),
        Slider("duration", "Display Time", 1, 30, "Seconds a row stays before it fades out.")
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Bind({
            type = "segmented",
            text = "Grow Direction",
            values = { UP = "Up", DOWN = "Down" },
            order = { "UP", "DOWN" },
        }, "grow", LF.ApplyStyle),
        Slider("textSize", "Text Size", 8, 24)
    )
    cursorY = cursorY - height

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Slider(
            "spacing",
            "Spacing",
            0,
            30,
            "Space between loot rows or Icon Tray tiles. Loot Toast adds room for its decorative frame."
        ),
        BLANK()
    )
    cursorY = cursorY - height

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    ---------------------------------------------------------------------------
    --  DISPLAY
    ---------------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
    cursorY = cursorY - height

    local _, textureValues, textureOrder = CUI.BuildBarTextureTables()
    local displayRow
    displayRow, height = W:DualRow(
        hostFrame,
        cursorY,
        Bind(
            { type = "dropdown", text = "Background Texture", values = textureValues, order = textureOrder },
            "bgTexture",
            LF.ApplyStyle
        ),
        Bind({
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 1,
            tooltip = "Opacity of the row background.",
            getValue = function() return math.floor(LF.Get("bgA") * 100 + 0.5) end,
            setValue = function(val)
                LF.Cfg().bgA = val / 100
                LF.ApplyStyle()
            end,
        })
    )
    cursorY = cursorY - height
    if not CUI._prebuilding then Swatch(displayRow._rightRegion, "bg", "Background Color") end

    local borderValues, borderOrder = CUI.GetBorderTextureDropdown()
    local borderRow
    borderRow, height = W:DualRow(
        hostFrame,
        cursorY,
        Bind({
            type = "dropdown",
            text = "Border Style",
            values = borderValues,
            order = borderOrder,
            tooltip = "Accent Bar applies the border to the icon.",
            getValue = function() return LF.Get("borderTexture") or "solid" end,
            setValue = function(val)
                local c = LF.Cfg()
                c.borderTexture = val
                c.borderTextureOffset, c.borderTextureOffsetY = nil, nil
                c.borderTextureShiftX, c.borderTextureShiftY = nil, nil
                local color, behind = CUI.GetBorderStyleSelectDefaults(val)
                c.borderR, c.borderG, c.borderB, c.borderBehind = color.r, color.g, color.b, behind
                local size = CUI.GetBorderDefaultSize(nil, val)
                if size then c.borderSize = size end
                if c.borderSizePx then c.borderSizePx = false end
                LF.ApplyStyle()
                CUI:RefreshPage(true)
            end,
        }, nil, nil, borderOff, function() return off() and "Loot Feed" or "Style" end),
        CUI.BorderPxSliderCfg({
            trackWidth = 120,
            tooltip = "0 hides the border.",
            disabled = borderOff,
            disabledTooltip = function() return off() and "Loot Feed" or "Style" end,
            getStep = function() return LF.Get("borderSize") end,
            setStep = function(val)
                local c = LF.Cfg()
                c.borderTexture, c.borderSize = LF.Get("borderTexture") or "solid", val
            end,
            getTex = function() return LF.Get("borderTexture") or "solid" end,
            getPx = function() return LF.Get("borderSizePx") end,
            setPx = function(val) LF.Cfg().borderSizePx = val end,
            apply = function()
                LF.ApplyStyle()
                CUI:RefreshPage()
            end,
        })
    )
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local offsetX, offsetY = CUI.BorderOffsetCogRows({
            getTex = function() return LF.Get("borderTexture") end,
            getStep = function() return LF.Get("borderSize") end,
            getPx = function() return LF.Get("borderSizePx") end,
            getX = function() return LF.Get("borderTextureOffset") end,
            setX = function(val) LF.Cfg().borderTextureOffset = val end,
            getY = function() return LF.Get("borderTextureOffsetY") end,
            setY = function(val) LF.Cfg().borderTextureOffsetY = val end,
            apply = LF.ApplyStyle,
        })
        local function Shift(key, labelText)
            return {
                type = "slider",
                label = labelText,
                min = -10,
                max = 10,
                step = 1,
                get = function() return LF.Get(key) or 0 end,
                set = function(val)
                    LF.Cfg()[key] = val
                    LF.ApplyStyle()
                end,
            }
        end
        CUI.BuildInlineCog(borderRow._leftRegion, {
            title = "Border Options",
            disabled = function()
                local texture = LF.Get("borderTexture")
                return borderOff() or not texture or texture == "solid" or texture == ""
            end,
            disabledTooltip = "This option requires a textured border.",
            rows = {
                Shift("borderTextureShiftX", "Shift X"),
                Shift("borderTextureShiftY", "Shift Y"),
                offsetX,
                offsetY,
                {
                    type = "toggle",
                    label = "Show Behind",
                    get = function() return LF.Get("borderBehind") end,
                    set = function(val)
                        LF.Cfg().borderBehind = val
                        LF.ApplyStyle()
                    end,
                },
                {
                    type = "toggle",
                    label = "Separator",
                    tooltip = "Adds a matching divider beside the icon (Box) or the accent bar (Icon Tray).",
                    hidden = function() return style() ~= "BOX" and style() ~= "TRAY" end,
                    disabled = function()
                        return LF.Get("borderSize") == 0
                            or (style() == "TRAY" and LF.Get("barWidth") == 0)
                            or not CUI.GetBorderCompanion(LF.Get("borderTexture"), "sepV")
                    end,
                    disabledTooltip = function()
                        if style() == "TRAY" and LF.Get("barWidth") == 0 then return "Accent Bar Width" end
                        return "This option requires a Pixels or Pixels Textured border above size 0."
                    end,
                    get = function() return LF.Get("separator") end,
                    set = function(val)
                        LF.Cfg().separator = val
                        LF.ApplyStyle()
                    end,
                },
            },
        })
        Swatch(borderRow._rightRegion, "border", "Border Color", noBorderColor, function()
            if off() then return "Loot Feed" end
            if style() == "TOAST" then return "Style" end
            return "Border Size"
        end)
    end

    _, height = W:DualRow(
        hostFrame,
        cursorY,
        Toggle(
            "qualityBorder",
            "Quality Borders",
            "Colors item rows by item quality.",
            LF.ApplyStyle,
            function()
                if off() or not LF.Get("items") then return true end
                return style() ~= "BAR" and style() ~= "TOAST" and LF.Get("borderSize") == 0
            end,
            function() return off() and "Loot Feed" or not LF.Get("items") and "Items" or "Border Size" end
        ),
        BLANK()
    )
    cursorY = cursorY - height

    return math.abs(cursorY)
end
