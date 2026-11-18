if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_MythicTimer_KickTracker_Options.lua
--  Builds the "Kick Tracker" page inside the Mythic+ Tools module: the
--  group's interrupts, as an icon with a cooldown on each kicked enemy's
--  nameplate.
--  Definitions only: CUI_MythicTimer_Options.lua registers the module and
--  dispatches the page to ns._KT_BuildPage.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIMythicTimer"]
if not mod then
    return
end -- module disabled: no options page

local REQ = "Kick Tracker"

-- Settings: db.profile.kickTracker of the Mythic+ Tools Lite DB.
local function KT()
    local saved = _G._CUMT_AceDB
    local p = saved and saved.profile
    return p and p.kickTracker
end

local function Get(key, fallback)
    local c = KT()
    local val = c and c[key]
    if val == nil then
        return fallback
    end
    return val
end

-- The header preview's state and builder (ns._MT_Preview), made on the
-- page's first build.
local ktPv, ktBuilder

-- Every write hands the new settings to the runtime, which restyles the live
-- icons and bars first; the header sample paints second.
local function Refresh()
    if mod.KT_Refresh then
        mod.KT_Refresh()
    end
    if ktPv then
        mod._MT_Preview.Repaint(ktPv)
    end
end

local function Set(key, val)
    local c = KT()
    if not c then
        return
    end
    c[key] = val
    Refresh()
end
-- Row setters over Set: the key written with the row's value.
local function SetRow(key)
    return function(v)
        Set(key, v)
    end
end

local function On()
    return Get("enabled", false) == true
end
local function Off()
    return not On()
end
local function PlatesOn()
    return On() and Get("showPlates", true) ~= false
end
local function PlatesOff()
    return not PlatesOn()
end
local REQ_PLATES = "Show on Nameplates"
local function BarsOn()
    return On() and Get("showBars", true) ~= false
end
local function BarsOff()
    return not BarsOn()
end
local REQ_BARS = "Show Bars"

-- The header preview: the bars on the left, the nameplate icon on the right
-- (a mock plate carrying two kickers' icons, which render at UIParent's
-- scale themselves, so that column is never shrunk), each painted by the
-- runtime (ns.KTB_PaintSample, ns.KT_PaintSampleIcon; a missing export hides
-- its column) and dimmed while the feature or its own switch is off.
-- Each painter returns two values; an `and` chain would keep only the width.
local KT_COLS = {
    {
        title = "Bars",
        on = BarsOn,
        paint = function(host)
            if mod.KTB_PaintSample then
                return mod.KTB_PaintSample(host, 3)
            end
        end,
    },
    {
        title = "Nameplate Icon",
        on = PlatesOn,
        noFit = true,
        paint = function(host)
            if mod.KT_PaintSampleIcon then
                return mod.KT_PaintSampleIcon(host)
            end
        end,
    },
}
mod._KT_HeaderBuilder = function(heading, hdrW)
    if not ktBuilder then
        ktPv = mod._MT_Preview.NewState()
        ktBuilder = mod._MT_Preview.Builder(ktPv, KT_COLS)
    end
    return ktBuilder(heading, hdrW)
end
-- A kept page shown again (onPageCacheRestore): the preview paints again.
mod._KT_RestorePreview = function()
    if ktPv then
        mod._MT_Preview.Update(ktPv, false)
    end
end

-- Where to Show: every content key of ns.MTWhere, in its order, with the
-- labels the module's other Where to Show lists use. Built on first use.
local whereItems
local function WhereItems()
    if whereItems then
        return whereItems
    end
    local keyList = mod.KickEngine and mod.KickEngine.WHERE_LIST
    if not keyList then
        return {}
    end
    local labels = mod._MT_WHERE_LABELS
    whereItems = {}
    for idx = 1, #keyList do
        local k = keyList[idx]
        whereItems[idx] = { key = k, label = labels[k] or k }
    end
    return whereItems
end

-- Some entries default to true, so an unchecked entry is stored as false:
-- a missing one would be filled back in with its default at the next login.
local function WhereGet(k)
    local c = KT()
    local t = c and c.whereToShow
    return type(t) == "table" and t[k] == true
end

local function WhereSet(k, val)
    local c = KT()
    if not c then
        return
    end
    local t = c.whereToShow
    if type(t) ~= "table" then
        t = {}
        c.whereToShow = t
    end
    t[k] = val and true or false
    Refresh()
end

local POSITION_VALUES = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
local POSITION_ORDER = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

-- Each side's natural X offset on CludesUI nameplates: a small gap outside
-- the bar on Left and Right, centered on Top and Bottom.
local SIDE_X = { LEFT = -4, RIGHT = 4, TOP = 0, BOTTOM = 0 }

-- A new side takes its own natural X offset while the old side's offsets are
-- still untouched; custom offsets stay as they are.
local function SetPosition(val)
    local c = KT()
    if not c then
        return
    end
    local old = Get("anchor", "LEFT")
    if SIDE_X[val] and Get("offsetX", -4) == SIDE_X[old] and Get("offsetY", 0) == 0 then
        c.offsetX = SIDE_X[val]
    end
    Set("anchor", val)
end

-- Which plates the icons sit on: the CludesUI plates while that module is
-- on (its plate registry exists, the runtime's own test), else Blizzard's or
-- another addon's. The Position Offsets cog shows the pair that applies.
local function NoCUIPlates()
    local m = CludesUI._ModuleNS.CludesUINameplates
    return not (m and m.plates)
end
local function CUIPlatesOn()
    return not NoCUIPlates()
end

-- The shared position labels, in this row's own order (the menu lists only
-- the keys the order names).
local TIMER_POS_VALUES = CludesUI.POSITION_GRID_VALUES
local TIMER_POS_ORDER = { "center", "topleft", "topright", "bottomleft", "bottomright" }

-- Icon Effects: one checkbox dropdown over three settings keys.
local ICON_EFFECTS = {
    {
        key = "swipe",
        label = "Cooldown Swipe",
        tooltip = "The dark sweep over the icon that clears as the interrupt comes back.",
    },
    {
        key = "classBorder",
        label = "Class Color Border",
        tooltip = "The icon's border in the kicker's class color; black when the game hides the kicker's class.",
    },
    {
        key = "desaturate",
        label = "Desaturate on Cooldown",
        tooltip = "Grey the icon while the kicker's interrupt is on cooldown.",
    },
}

-- Display Elements: the bars' checkbox dropdown over four settings keys.
local BAR_ELEMENTS = {
    { key = "barShowIcon", label = "Icon", tooltip = "The interrupt's icon at the end of the row." },
    { key = "barShowName", label = "Name", tooltip = "The member's name on the row." },
    {
        key = "barShowTimer",
        label = "Timer",
        tooltip = "The seconds left on the interrupt, on the right of its row.",
    },
    {
        key = "barShowMarker",
        label = "Marker",
        tooltip = "The raid marker of the enemy the member interrupted, beside their row while that interrupt is on cooldown.",
    },
}

local ICON_STYLE_VALUES = { spec = "Spec Icon", kick = "Kick Icon", class = "Class Icon" }
local ICON_STYLE_ORDER = { "kick", "spec", "class" }

-- Focus Announce: None, then the raid markers 1-8 with their icons and the
-- game's own names (the Forever Essentials macro editor's marker list).
local MARKER_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local MARKER_ORDER = { "0", "1", "2", "3", "4", "5", "6", "7", "8" }
local markerValues
local function MarkerValues()
    if not markerValues then
        markerValues = { _noLoc = true, ["0"] = CludesUI.L("None") }
        for idx = 1, 8 do
            markerValues[tostring(idx)] = _G["RAID_TARGET_" .. idx]
        end
        markerValues._menuOpts = {
            icon = function(key)
                local idx = tonumber(key)
                if not idx or idx < 1 then
                    return nil
                end
                local l, t = ((idx - 1) % 4) * 0.25, math.floor((idx - 1) / 4) * 0.25
                return MARKER_ICONS, l, l + 0.25, t, t + 0.25
            end,
        }
    end
    return markerValues
end

-- Edit Announce Text: the player's own Focus Announce line, edited in the
-- input popup over the saved one or the default (ns.KT_AnnounceDefault, with
-- {marker} where the raid marker goes). Saved trimmed; empty, or the default
-- typed back, clears the setting so the default line is sent again. 80
-- letters keep a line of any script, plus the marker, inside a chat
-- message's 255 bytes.
local ANNOUNCE_MAX = 80

local function AnnounceDefault()
    return mod.KT_AnnounceDefault and mod.KT_AnnounceDefault() or ""
end

local function EditAnnounceText()
    local current = Get("announceText", nil)
    if type(current) ~= "string" or current == "" then
        current = AnnounceDefault()
    end
    CludesUI:ShowInputPopup({
        title = "Edit Announce Text",
        message = "Sent in party chat at the ready check. {marker} stands for your raid marker. Empty brings the default line back.",
        placeholder = "Enter your announce line...",
        initialText = current,
        maxLetters = ANNOUNCE_MAX,
        showCount = true,
        allowEmpty = true,
        confirmText = "Save",
        onConfirm = function(textValue)
            textValue = strtrim(textValue or "")
            if textValue == "" or textValue == AnnounceDefault() then
                textValue = nil
            end
            Set("announceText", textValue)
        end,
    })
end

mod._KT_BuildPage = function(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local posY = yOffset
    local _, row, hgt

    CludesUI:SetContentHeader(mod._KT_HeaderBuilder)
    hostFrame._showRowDivider = true

    -- The experimental notice between the header preview and the settings, in
    -- the empty-selection warning's red. The page wrapper is a pool host, so a
    -- rebuild hands this font string back instead of making a new one.
    if not CludesUI._prebuilding then
        local pad = CludesUI.CONTENT_PAD
        local warn = CludesUI.MakeFont(hostFrame, 15, nil, 1, 0.4, 0.4)
        warn:SetJustifyH("CENTER")
        warn:SetWordWrap(true)
        warn:SetSpacing(4)
        warn:SetWidth(hostFrame:GetWidth() - pad * 2)
        warn:SetText(
            CludesUI.L(
                "Like all current kick trackers, this feature is experimental and may stop working if\nBlizzard decides to hotfix the workaround that makes this possible."
            )
        )
        CludesUI.PP.Point(warn, "TOPLEFT", hostFrame, "TOPLEFT", pad, posY - 10)
        posY = posY - 10 - math.ceil(warn:GetStringHeight()) - 2
    end

    _, hgt = W:SectionHeader(hostFrame, "KICK TRACKER", posY)
    posY = posY - hgt

    row, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Kick Tracker",
        tooltip = "Who in the group kicked each enemy and when their interrupt comes back, read from Blizzard's own damage meter (which must be on). Others' cooldowns follow their class, spec and talents, read before a key starts; yours follow your own talents.",
        getValue = On,
        setValue = CludesUI.SectionToggleSetValue(function(val)
            -- The runtime alone: the section rebuild that follows builds
            -- the header again and paints its samples then.
            local c = KT()
            if not c then
                return
            end
            c.enabled = val and true or false
            if mod.KT_Refresh then
                mod.KT_Refresh()
            end
        end),
    }, {
        type = "dropdown",
        text = "Where to Show",
        disabled = Off,
        disabledTooltip = REQ,
        tooltip = "The tracker runs in Mythic and Mythic+ dungeons and arenas only; untick one to turn it off there.",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    posY = posY - hgt
    if not CludesUI._prebuilding then
        local region = row._rightRegion
        if region._control then
            region._control:Hide()
        end
        local whereDD, whereRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            220,
            region:GetFrameLevel() + 2,
            WhereItems(),
            WhereGet,
            WhereSet,
            nil,
            nil,
            nil,
            nil,
            nil,
            { disabled = Off, disabledTooltip = REQ, emptyLabel = "All" }
        )
        CludesUI.PanelPP.Point(whereDD, "RIGHT", region, "RIGHT", -20, 0)
        region._control = whereDD
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(whereRefresh)
    end

    row, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Focus Announce",
        tooltip = "Tells the party your focus marker at ready checks.",
        disabled = Off,
        disabledTooltip = REQ,
        values = MarkerValues(),
        order = MARKER_ORDER,
        getValue = function()
            return tostring(Get("focusMarker", 0))
        end,
        setValue = function(val)
            Set("focusMarker", tonumber(val) or 0)
        end,
    }, {
        type = "labeledButton",
        text = "Edit Announce Text",
        buttonText = "Edit",
        width = 90,
        tooltip = "Change the line Focus Announce sends: your own words, with {marker} where your raid marker goes.",
        disabled = Off,
        disabledTooltip = REQ,
        onClick = EditAnnounceText,
    })
    posY = posY - hgt
    -- The red warning on the dropdown while the nameplate icons are on with
    -- no marker set (the standard empty-selection warning), with a dismiss
    -- button beside it that waves it off for good, account-wide.
    if not CludesUI._prebuilding then
        local region = row._leftRegion
        if region and region._control then
            CludesUI.AttachEmptyFilterWarn(
                region,
                region._control,
                CludesUI.L("Nameplate Kick Icons use this to auto-assign kicks when a mob is first marked."),
                function()
                    return not PlatesOn()
                        or (tonumber(Get("focusMarker", 0)) or 0) ~= 0
                        or (CludesUIDB and CludesUIDB.dismissedKickMarkerWarning) == true
                end,
                {
                    onDismiss = function()
                        if not CludesUIDB then
                            CludesUIDB = {}
                        end
                        CludesUIDB.dismissedKickMarkerWarning = true
                    end,
                }
            )
        end
    end

    -- The rest of the page exists only while the feature is on.
    if On() then
        _, hgt = W:SectionHeader(hostFrame, "NAMEPLATE ICON", posY)
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show on Nameplates",
            tooltip = "Kick icons with their cooldown on the kicked enemies' nameplates.",
            getValue = PlatesOn,
            setValue = function(val)
                Set("showPlates", val and true or false)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Icon",
            tooltip = "The kicker's interrupt icon, their spec icon or their class icon. A kick the tracker cannot place on a member shows no icon.",
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            values = ICON_STYLE_VALUES,
            order = ICON_STYLE_ORDER,
            getValue = function()
                return Get("iconStyle", "kick")
            end,
            setValue = SetRow("iconStyle"),
        })
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 48,
            step = 1,
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            getValue = function()
                return Get("size", 28)
            end,
            setValue = SetRow("size"),
        }, {
            type = "dropdown",
            text = "Position",
            tooltip = "The side of the nameplate the icon sits on.",
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            values = POSITION_VALUES,
            order = POSITION_ORDER,
            getValue = function()
                return Get("anchor", "LEFT")
            end,
            setValue = SetPosition,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._rightRegion, {
                tip = "Position Offsets",
                title = "Position Offsets",
                disabled = PlatesOff,
                disabledTooltip = REQ_PLATES,
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        tooltip = "On CludesUI nameplates.",
                        hidden = NoCUIPlates,
                        get = function()
                            return Get("offsetX", -4)
                        end,
                        set = SetRow("offsetX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        tooltip = "On CludesUI nameplates.",
                        hidden = NoCUIPlates,
                        get = function()
                            return Get("offsetY", 0)
                        end,
                        set = SetRow("offsetY"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        tooltip = "On Blizzard's or another addon's nameplates.",
                        hidden = CUIPlatesOn,
                        get = function()
                            return Get("otherOffsetX", 0)
                        end,
                        set = SetRow("otherOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        tooltip = "On Blizzard's or another addon's nameplates.",
                        hidden = CUIPlatesOn,
                        get = function()
                            return Get("otherOffsetY", 0)
                        end,
                        set = SetRow("otherOffsetY"),
                    },
                },
            })
        end

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Cooldown Timer",
            tooltip = "The seconds left on the kicker's interrupt.",
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            getValue = function()
                return Get("showTimer", true) == true
            end,
            setValue = function(val)
                Set("showTimer", val and true or false)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Icon Effects",
            tooltip = "The cooldown swipe, a border in the kicker's class color, and greying the icon while the interrupt is on cooldown.",
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            -- Icon Effects: the checkbox dropdown over its three keys, in
            -- place of the row's placeholder dropdown.
            local fxRgn = row._rightRegion
            if fxRgn._control then
                fxRgn._control:Hide()
            end
            local fxDD, fxRefresh = CludesUI.BuildVisOptsCBDropdown(
                fxRgn,
                220,
                fxRgn:GetFrameLevel() + 2,
                ICON_EFFECTS,
                function(key)
                    return Get(key, key ~= "desaturate") == true
                end,
                function(key, val)
                    Set(key, val and true or false)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = PlatesOff, disabledTooltip = REQ_PLATES, emptyLabel = "None" }
            )
            CludesUI.PanelPP.Point(fxDD, "RIGHT", fxRgn, "RIGHT", -20, 0)
            fxRgn._control = fxDD
            fxRgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(fxRefresh)
            CludesUI.BuildInlineCog(row._leftRegion, {
                tip = "Timer Settings",
                title = "Cooldown Timer",
                disabled = function()
                    return PlatesOff() or Get("showTimer", true) ~= true
                end,
                disabledTooltip = "Show Cooldown Timer",
                rows = {
                    {
                        type = "dropdown",
                        label = "Timer Position",
                        values = TIMER_POS_VALUES,
                        order = TIMER_POS_ORDER,
                        get = function()
                            return Get("timerPos", "center")
                        end,
                        set = SetRow("timerPos"),
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        get = function()
                            return Get("timerSize", 11)
                        end,
                        set = SetRow("timerSize"),
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return Get("timerX", 0)
                        end,
                        set = SetRow("timerX"),
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = function()
                            return Get("timerY", 0)
                        end,
                        set = SetRow("timerY"),
                    },
                },
            })
        end

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Above Overlapping Nameplates",
            tooltip = "The icons draw over every other nameplate, so an overlapping plate never hides one. When off, an icon stays inside its own nameplate, behind any plate that covers it.",
            disabled = PlatesOff,
            disabledTooltip = REQ_PLATES,
            getValue = function()
                return Get("aboveOverlap", true) ~= false
            end,
            setValue = function(val)
                Set("aboveOverlap", val and true or false)
            end,
        }, CludesUI.BlankRowCfg())
        posY = posY - hgt

        -- The Move in Unlock Mode button on the bars' first section, built
        -- whatever Show Bars says: its disabled state explains itself.
        local heading
        heading, hgt = W:SectionHeader(hostFrame, "BARS", posY)
        posY = posY - hgt
        CludesUI.BuildSectionUnlockJump(
            heading,
            { key = "EMT_KickBars", disabled = BarsOff, disabledTooltip = REQ_BARS }
        )

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Bars",
            tooltip = "A row per group member with an interrupt: the interrupt's icon, their name on a bar in their class color, and the seconds left while it is on cooldown.",
            getValue = BarsOn,
            setValue = function(val)
                Set("showBars", val and true or false)
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Bar Width",
            min = 80,
            max = 600,
            step = 1,
            pixel = true,
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            getValue = function()
                return Get("barWidth", 200)
            end,
            setValue = SetRow("barWidth"),
        })
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Height",
            min = 6,
            max = 60,
            step = 1,
            pixel = true,
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            getValue = function()
                return Get("barHeight", 22)
            end,
            setValue = SetRow("barHeight"),
        }, {
            type = "slider",
            text = "Bar Spacing",
            min = 0,
            max = 20,
            step = 1,
            pixel = true,
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            getValue = function()
                return Get("barSpacing", 2)
            end,
            setValue = SetRow("barSpacing"),
        })
        posY = posY - hgt

        local texValues, texOrder = {}, {}
        if mod._MT_BuildBarTexDropdown then
            texValues, texOrder = mod._MT_BuildBarTexDropdown()
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "segmented",
            text = "Grow Direction",
            tooltip = "Which way the rows stack.",
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            values = { DOWN = "Down", UP = "Up" },
            order = { "DOWN", "UP" },
            getValue = function()
                return Get("barGrowUp", false) == true and "UP" or "DOWN"
            end,
            setValue = function(val)
                Set("barGrowUp", val == "UP")
            end,
        }, {
            type = "dropdown",
            text = "Bar Texture",
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            values = texValues,
            order = texOrder,
            getValue = function()
                return Get("texture", "none")
            end,
            setValue = SetRow("texture"),
        })
        posY = posY - hgt

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "multiSwatch",
            text = "Background Color",
            tooltip = "Behind each row: a darkened version of the member's class color, or one custom color.",
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            swatches = {
                -- Suite-wide convention: a mode swatch selects its mode; the
                -- custom swatch selects custom on the first click and opens
                -- the picker once custom is already active.
                {
                    tooltip = "Dark Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local _, cls = UnitClass("player")
                        local c = cls and C_ClassColor.GetClassColor(cls)
                        if not c then
                            return 0.2, 0.2, 0.2
                        end
                        local r, g, b = c:GetRGB()
                        return r * 0.3, g * 0.3, b * 0.3
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("barBgMode", "class")
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return Get("barBgMode", "class") ~= "custom" and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = true,
                    getValue = function()
                        local col = Get("barBgColor", nil)
                        return (col and col.r) or 0,
                            (col and col.g) or 0,
                            (col and col.b) or 0,
                            (col and col.a) or 0.45
                    end,
                    setValue = function(r, g, b, a)
                        local c = KT()
                        if not c then
                            return
                        end
                        c.barBgColor = { r = r, g = g, b = b, a = a }
                        Set("barBgMode", "custom")
                    end,
                    onClick = function(self)
                        if Get("barBgMode", "class") ~= "custom" then
                            Set("barBgMode", "custom")
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        return Get("barBgMode", "class") == "custom" and 1 or 0.3
                    end,
                },
            },
        }, {
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 5,
            step = 1,
            pixel = true,
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            getValue = function()
                return Get("barBorderSize", 0)
            end,
            setValue = SetRow("barBorderSize"),
        })
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Display Elements",
            tooltip = "The interrupt's icon, the member's name, the seconds left on the interrupt and the raid marker of the enemy they interrupted.",
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, {
            type = "toggle",
            text = "Include Yourself",
            tooltip = "Adds your own row, with its cooldown read from your talents.",
            disabled = BarsOff,
            disabledTooltip = REQ_BARS,
            getValue = function()
                return Get("barIncludeSelf", true) == true
            end,
            setValue = function(val)
                Set("barIncludeSelf", val and true or false)
            end,
        })
        posY = posY - hgt
        if not CludesUI._prebuilding then
            -- Display Elements: the checkbox dropdown over its four keys, in
            -- place of the row's placeholder dropdown, and its cog beside it:
            -- the icon's side and one text size for the name and the timer
            -- (the Fonts page sets the two apart).
            local elRgn = row._leftRegion
            if elRgn._control then
                elRgn._control:Hide()
            end
            local elDD, elRefresh = CludesUI.BuildVisOptsCBDropdown(
                elRgn,
                220,
                elRgn:GetFrameLevel() + 2,
                BAR_ELEMENTS,
                function(key)
                    return Get(key, true) == true
                end,
                function(key, val)
                    Set(key, val and true or false)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = BarsOff, disabledTooltip = REQ_BARS, emptyLabel = "None" }
            )
            CludesUI.PanelPP.Point(elDD, "RIGHT", elRgn, "RIGHT", -20, 0)
            elRgn._control = elDD
            elRgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(elRefresh)
            CludesUI.BuildInlineCog(elRgn, {
                tip = "Element Settings",
                title = "Display Elements",
                disabled = BarsOff,
                disabledTooltip = REQ_BARS,
                rows = {
                    {
                        type = "toggle",
                        label = "Icon on Right",
                        get = function()
                            return Get("barIconOnRight", false) == true
                        end,
                        set = function(val)
                            Set("barIconOnRight", val and true or false)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        get = function()
                            return Get("barNameSize", 11)
                        end,
                        set = function(val)
                            Set("barNameSize", val)
                            Set("barTimerSize", val)
                        end,
                    },
                },
            })
        end
    end

    _, hgt = W:Spacer(hostFrame, posY, 20)
    posY = posY - hgt
    hostFrame:SetHeight(math.abs(posY - yOffset))
end
