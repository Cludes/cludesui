if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Options.lua
--  Registers the Raid Frames module with CludesUI options panel.
--  Two tabs: Raid Frames (layout, health, power, text, border, absorbs,
--  indicators, debuffs, dispels, range/tooltip) and Buff Manager.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIRaidFrames"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host (a kept page wrapper or popup and every frame it hands out) are reset
-- and dressed again by the next build instead of made anew; elsewhere this is
-- CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
-- Deferred work on a pooled frame stops once the frame was dressed again.
local PoolGen = CludesUI._Pool.Gen

-- WoW Forever: the preview's numbers follow the live frames (CludesUI_NumberFormat.lua).
local AbbreviateNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local PAGE_MAIN = "Frames"
local PAGE_PARTY = "Party"
local PAGE_BUFFS = "Buff Manager"
local PAGE_DM = "Debuff Manager"
local PAGE_CLICKCAST = "Frame Bindings" -- was "HoverCast"

-- Display-only tab labels. Page IDENTITY strings above are baked into nav
-- targets/unlock/overrides/saved state; tab bar renders these instead (see CreateTabButton in CludesUI.lua).
CludesUI.TAB_LABEL_OVERRIDES = CludesUI.TAB_LABEL_OVERRIDES or {}
CludesUI.TAB_LABEL_OVERRIDES[PAGE_BUFFS] = "Buffs"
CludesUI.TAB_LABEL_OVERRIDES[PAGE_DM] = "Debuffs"

-- Party page under "Frame Style: Party Frames" (the latched stock portrait
-- party frame): the rows its layout replaces are hidden on the Party page
-- only. The page being BUILT decides (BuildVisualSections builds the Frames
-- page too, and the search prebuild can leave the party context stale). ns
-- fields, so no page builder gains an upvalue.
function mod.RF_OptPartyKit()
    return CludesUI._buildingPage == PAGE_PARTY and mod.RF_PartyKit ~= nil and mod.RF_PartyKit() and true
        or false
end
function mod.RF_PartyKitGate(conf)
    if not conf or not mod.RF_OptPartyKit() then
        return conf
    end
    conf.disabled = function()
        return true
    end
    conf.disabledTooltip = "Frame Style: Party Frames"
    conf.requireState = "disabled"
    conf.rawTooltip = nil
    conf._blizzGated = true
    return conf
end

-- Move Frames button of a Free Move group (Friendly Boss, Extra Frames, Pet Frames): toggles its
-- drag overlay, right-aligned in the DualRow half rgn. opts: isShown() and setShown(show), the
-- overlay; allowed(), whether it can open (Free Move chosen, out of combat); optional enabled()
-- with enabledTip, the group's own switch, which also dims rgn's plain label while off. Nothing is
-- built during the search prebuild; returns the button.
function mod.RF_OptMoveFramesButton(row, region, options)
    if CludesUI._prebuilding then
        return
    end
    local button = CreateFrame("Button", nil, row)
    button:SetSize(140, 26)
    button:SetPoint("RIGHT", region, "RIGHT", -20, 0)
    button:SetFrameLevel(row:GetFrameLevel() + 5)
    local bbg = button:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
    CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.25, bbg)
    local labelFS = button:CreateFontString(nil, "OVERLAY")
    CludesUI.ApplyModuleFont(labelFS, nil, 13, "raidFrames")
    labelFS:SetPoint("CENTER", button, "CENTER", 0, 0)
    local enabled = options.enabled
    local function Update()
        labelFS:SetText(options.isShown() and CludesUI.L("Stop Moving") or CludesUI.L("Move Frames"))
        button:SetAlpha(options.allowed() and 1 or 0.35)
        -- Plain-label slots have no native disabled handling.
        if enabled and region._label then
            region._label:SetAlpha(enabled() and 1 or 0.3)
        end
    end
    button:SetScript("OnEnter", function(self)
        if enabled and not enabled() then
            CludesUI.ShowWidgetTooltip(self, options.enabledTip)
        elseif not options.allowed() then
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.DisabledTooltip("This option requires Position to be set to Free Move")
            )
        else
            CludesUI.ShowWidgetTooltip(
                self,
                "Drag the overlay to position the frames, then click again to lock"
            )
        end
    end)
    button:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
    button:SetScript("OnClick", function()
        if not options.allowed() then
            return
        end
        options.setShown(not options.isShown())
        Update()
    end)
    CludesUI.RegisterWidgetRefresh(Update)
    Update()
    return button
end

-- Party page PORTRAIT section (every style; CUI_RaidFrames_Portrait.lua):
-- Portrait Mode | Art Style, then Size | Position and (Detached) Shape |
-- Shape Border. Under "Frame Style: Party Frames" the stock socket takes
-- the Art Style alone (2D or class art). `PSSet` is the Party page's setter
-- (the full party pass, for the box-width changes); every other setting
-- takes the light path. Returns the new y.
function mod.RF_BuildPartyPortrait(hostFrame, posY, W, PSSet)
    local db = mod.db
    local kit = mod.RF_OptPartyKit() -- build time only (the page rebuilds)
    local _, hgt
    local function PV(k, d)
        local v = db.profile[k]
        if v == nil then
            return d
        end
        return v
    end
    -- A row getter over PV: the key's value, or the default given.
    local function PVRow(key, default)
        return function()
            return PV(key, default)
        end
    end
    local function Refresh()
        if mod._RefreshProxyModes then
            mod._RefreshProxyModes()
        end
        if mod.RF_PtRefreshAll then
            mod.RF_PtRefreshAll()
        end
        if mod.partyPvActive and mod.partyPvActive() and mod.ShowPartyPreview then
            mod.ShowPartyPreview()
        end
    end
    local function PtSet(k, v)
        db.profile[k] = v
        Refresh()
    end
    local function RunWidgetRefresh()
        C_Timer.After(0, function()
            local rl = CludesUI._widgetRefreshList
            if rl then
                for idx = 1, #rl do
                    rl[idx]()
                end
            end
        end)
    end
    local function IsInside(side)
        return side == "insideleft" or side == "insideright" or side == "insidecenter"
    end

    _, hgt = W:SectionHeader(hostFrame, "PORTRAIT", posY)
    posY = posY - hgt

    -- An Art Style pick, with the side effects of leaving and entering 3D
    -- (Inside positions and the None shape are 3D only).
    local function SetArt(v)
        local p = db.profile
        p.partyPortraitMode = v
        if v == "3d" and p.partyPortraitStyle == "detached" then
            p.partyPortraitShape = "none"
        end
        if v ~= "3d" then
            if p.partyPortraitShape == "none" then
                p.partyPortraitShape = "portrait"
            end
            if IsInside(p.partyPortraitSide) then
                p.partyPortraitSide = "left"
            end
        end
        Refresh()
    end

    -- Art Style: 2D, 3D, or class art in one of seven sets (the flyout).
    local classVals = {
        modern = "Modern",
        arcade = "Arcade",
        glyph = "Glyph",
        legend = "Legend",
        midnight = "Midnight",
        pixel = "Pixel",
        pixelsComic = "Comic",
        runic = "Runic",
    }
    local classOrder = { "modern", "arcade", "glyph", "legend", "midnight", "pixel", "pixelsComic", "runic" }
    local artValues = {
        ["3d"] = "3D Portrait",
        ["2d"] = "2D Portrait",
        class = {
            text = "Class",
            subnav = {
                order = classOrder,
                values = classVals,
                itemHeight = 32,
                onSelect = function(key)
                    db.profile.partyPortraitClassStyle = key
                    SetArt("class")
                    RunWidgetRefresh()
                end,
                icon = function(key)
                    local _, ct = UnitClass("player")
                    local c = ct
                        and CludesUI.CLASS_ICON_SPRITE_COORDS
                        and CludesUI.CLASS_ICON_SPRITE_COORDS[ct]
                    if not c then
                        return nil
                    end
                    return "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\" .. key .. ".tga",
                        c[1],
                        c[2],
                        c[3],
                        c[4]
                end,
            },
        },
    }

    -- Row 1: Portrait Mode | Art Style. A mode change can widen the frame
    -- (the full party pass) and shows or hides the rows below (a rebuild).
    local modeRow
    modeRow, hgt = W:DualRow(
        hostFrame,
        posY,
        mod.RF_PartyKitGate({
            type = "dropdown",
            text = "Portrait Mode",
            tooltip = "Attached widens each frame by the portrait.",
            values = { none = "None", attached = "Attached", detached = "Detached" },
            order = { "none", "attached", "detached" },
            getValue = function()
                if kit then
                    return "attached"
                end
                return PV("partyPortraitStyle", "none")
            end,
            setValue = function(v)
                local p = db.profile
                local prev = p.partyPortraitStyle or "none"
                if v == prev then
                    return
                end
                if v == "detached" and (p.partyPortraitMode or "2d") == "3d" then
                    p.partyPortraitShape = "none"
                end
                if v ~= "detached" then
                    p.partyPortraitSize = 0
                    local sd = p.partyPortraitSide
                    if sd == "top" or IsInside(sd) then
                        p.partyPortraitSide = "left"
                    end
                end
                PSSet("partyPortraitStyle", v)
                CludesUI:RefreshPage(true)
            end,
        }),
        {
            type = "dropdown",
            text = "Art Style",
            values = artValues,
            order = { "3d", "2d", "class" },
            disabled = function()
                return not kit and PV("partyPortraitStyle", "none") == "none"
            end,
            disabledTooltip = "Portrait Mode is set to None",
            rawTooltip = true,
            -- A model cannot take the stock socket's round mask.
            itemDisabled = function(v)
                return kit and v == "3d"
            end,
            itemDisabledTooltip = function(v)
                if v == "3d" then
                    return "Frame Style: Party Frames"
                end
            end,
            itemRequireState = "disabled",
            getValue = function()
                local m = PV("partyPortraitMode", "2d")
                if m == "class" then
                    return PV("partyPortraitClassStyle", "modern")
                end
                if kit and m == "3d" then
                    return "2d"
                end
                return m
            end,
            setValue = function(v)
                if
                    v == "3d"
                    and PV("partyPortraitMode", "2d") ~= "3d"
                    and not (CludesUIDB and CludesUIDB.dismissed3DWarning)
                then
                    CludesUI:ShowConfirmPopup({
                        title = "3D Portraits",
                        message = "3D portraits may cause a slight loss in performance efficiency. Do you want to enable them?",
                        confirmText = "Enable",
                        cancelText = "Cancel",
                        onConfirm = function()
                            if not CludesUIDB then
                                CludesUIDB = {}
                            end
                            CludesUIDB.dismissed3DWarning = true
                            SetArt("3d")
                            CludesUI:RefreshPage(true)
                        end,
                        onCancel = function()
                            CludesUI:RefreshPage()
                        end,
                    })
                    return
                end
                SetArt(v)
                RunWidgetRefresh()
            end,
        }
    )
    posY = posY - hgt
    -- Portrait Settings (Detached only): Clickable Portrait, Background Color.
    CludesUI.BuildInlineCog(modeRow._leftRegion, {
        title = "Portrait Settings",
        disabled = function()
            return kit or PV("partyPortraitStyle", "none") ~= "detached"
        end,
        disabledTooltip = function()
            if kit then
                return "Frame Style: Party Frames"
            end
            return "This option requires Portrait Mode to be set to Detached."
        end,
        rawTooltip = function()
            return not kit
        end,
        requireState = "disabled",
        rows = {
            {
                type = "toggle",
                label = "Clickable Portrait",
                tooltip = "Clicking or hovering the detached portrait acts like clicking or hovering the frame's bars.",
                get = PVRow("partyPortraitClickable", false),
                set = function(v)
                    PtSet("partyPortraitClickable", v or nil)
                end,
            },
            {
                type = "colorpicker",
                label = "Background Color",
                hasAlpha = true,
                tooltip = "Fill color behind the detached portrait.",
                disabled = function()
                    return PV("partyPortraitShape", "portrait") == "none"
                end,
                disabledTooltip = "This option requires a Shape other than None.",
                rawTooltip = true,
                get = function()
                    local c = db.profile.partyPortraitBgColor
                    if c then
                        return c.r, c.g, c.b, c.a or 1
                    end
                    return 0.1, 0.1, 0.1, 1
                end,
                set = function(r, g, b, a)
                    PtSet("partyPortraitBgColor", { r = r, g = g, b = b, a = a or 1 })
                end,
            },
        },
    })

    if kit or PV("partyPortraitStyle", "none") == "none" then
        return posY
    end

    -- Row 2: Size | Position.
    local sizePosRow
    sizePosRow, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Size",
        min = -50,
        max = 100,
        step = 1,
        disabled = function()
            return PV("partyPortraitStyle", "none") ~= "detached"
                and not IsInside(PV("partyPortraitSide", "left"))
        end,
        disabledTooltip = "Only available in Detached or Inside modes",
        rawTooltip = true,
        getValue = PVRow("partyPortraitSize", 0),
        setValue = function(v)
            PtSet("partyPortraitSize", v)
        end,
    }, {
        type = "dropdown",
        text = "Position",
        values = {
            left = "Left",
            right = "Right",
            top = "Top",
            insideleft = "Inside Left",
            insideright = "Inside Right",
            insidecenter = "Inside Center",
        },
        order = { "left", "right", "top", "insideleft", "insideright", "insidecenter" },
        itemDisabled = function(v)
            local st = PV("partyPortraitStyle", "none")
            if v == "top" and st == "attached" then
                return true
            end
            if IsInside(v) then
                if PV("partyPortraitMode", "2d") ~= "3d" then
                    return true
                end
                if st ~= "detached" then
                    return true
                end
            end
            return false
        end,
        itemDisabledTooltip = function(v)
            if v == "top" then
                return "Top position is only available in Detached mode"
            end
            if IsInside(v) then
                if PV("partyPortraitMode", "2d") ~= "3d" then
                    return "Inside positions require 3D Art Style"
                end
                return "Inside positions require Detached mode"
            end
        end,
        getValue = PVRow("partyPortraitSide", "left"),
        setValue = function(v)
            PtSet("partyPortraitSide", v)
            CludesUI:RefreshPage()
        end,
    })
    posY = posY - hgt
    CludesUI.BuildInlineCog(sizePosRow._leftRegion, {
        title = "Portrait Zoom",
        rows = {
            {
                type = "slider",
                label = "2D Zoom",
                min = 50,
                max = 100,
                step = 1,
                get = PVRow("partyPortraitArtScale", 100),
                set = function(v)
                    PtSet("partyPortraitArtScale", v)
                end,
            },
            {
                type = "slider",
                label = "3D Zoom",
                min = 100,
                max = mod.RF_PT_ZOOM3D_MAX,
                step = 1,
                tooltip = "Above 300 the camera pulls back to show the whole character.",
                get = PVRow("partyPortrait3dZoom", 100),
                set = function(v)
                    PtSet("partyPortrait3dZoom", v)
                end,
            },
            {
                type = "slider",
                label = "Character Size",
                min = 50,
                max = 200,
                step = 1,
                tooltip = "Scales the 3D character from the portrait's bottom edge, for use with the full-body 3D Zoom range above 300.",
                disabled = function()
                    return PV("partyPortraitStyle", "none") ~= "detached"
                        or not IsInside(PV("partyPortraitSide", "left"))
                end,
                disabledTooltip = "This option requires an Inside position",
                get = PVRow("partyPortraitCharScale", 100),
                set = function(v)
                    PtSet("partyPortraitCharScale", v)
                end,
            },
        },
    })
    CludesUI.BuildInlineCog(sizePosRow._rightRegion, {
        title = "Portrait Position Offsets",
        rows = {
            {
                type = "slider",
                label = "X Offset",
                min = -100,
                max = 100,
                step = 1,
                get = PVRow("partyPortraitX", 0),
                set = function(v)
                    PtSet("partyPortraitX", v)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -100,
                max = 100,
                step = 1,
                get = PVRow("partyPortraitY", 0),
                set = function(v)
                    PtSet("partyPortraitY", v)
                end,
            },
        },
        disabled = function()
            return PV("partyPortraitStyle", "none") ~= "detached"
        end,
        disabledTooltip = "This option requires Portrait Mode to be set to Detached.",
    })

    if PV("partyPortraitStyle", "none") ~= "detached" then
        return posY
    end

    -- Row 3 (Detached): Shape | Shape Border (custom colour or class coloured).
    local shapeRow
    shapeRow, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Shape",
        values = {
            none = "None",
            portrait = "Portrait",
            circle = "Circle",
            square = "Square",
            csquare = "Rounded Square",
            diamond = "Diamond",
            hexagon = "Hexagon",
            shield = "Shield",
        },
        order = { "none", "portrait", "circle", "square", "csquare", "diamond", "hexagon", "shield" },
        itemDisabled = function(v)
            return v == "none" and PV("partyPortraitMode", "2d") ~= "3d"
        end,
        itemDisabledTooltip = function(v)
            if v == "none" then
                return "None shape requires 3D Art Style"
            end
        end,
        getValue = PVRow("partyPortraitShape", "portrait"),
        setValue = function(v)
            PtSet("partyPortraitShape", v)
        end,
    }, {
        type = "multiSwatch",
        text = "Shape Border",
        swatches = {
            {
                tooltip = "Custom Color",
                hasAlpha = false,
                getValue = function()
                    local c = db.profile.partyPortraitBorderColor or { r = 0, g = 0, b = 0 }
                    return c.r, c.g, c.b
                end,
                setValue = function(r, g, b)
                    PtSet("partyPortraitBorderColor", { r = r, g = g, b = b })
                end,
                onClick = function(self)
                    if PV("partyPortraitBorderClassColor", true) then
                        PtSet("partyPortraitBorderClassColor", false)
                        CludesUI:RefreshPage()
                        return
                    end
                    if self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
                refreshAlpha = function()
                    return PV("partyPortraitBorderClassColor", true) and 0.3 or 1
                end,
            },
            {
                tooltip = "Class Colored",
                hasAlpha = false,
                getValue = function()
                    local _, ct = UnitClass("player")
                    local c = ct and RAID_CLASS_COLORS[ct]
                    if c then
                        return c.r, c.g, c.b
                    end
                    return 1, 1, 1
                end,
                setValue = function() end,
                onClick = function()
                    PtSet("partyPortraitBorderClassColor", true)
                    CludesUI:RefreshPage()
                end,
                refreshAlpha = function()
                    return PV("partyPortraitBorderClassColor", true) and 1 or 0.3
                end,
            },
        },
    })
    posY = posY - hgt
    CludesUI.BuildInlineCog(shapeRow._rightRegion, {
        title = "Shape Border Settings",
        rows = {
            {
                type = "slider",
                label = "Size",
                min = 1,
                max = 7,
                step = 1,
                get = PVRow("partyPortraitBorderSize", 7),
                set = function(v)
                    PtSet("partyPortraitBorderSize", v)
                end,
            },
            {
                type = "slider",
                label = "Opacity",
                min = 0,
                max = 100,
                step = 1,
                get = PVRow("partyPortraitBorderOpacity", 100),
                set = function(v)
                    PtSet("partyPortraitBorderOpacity", v)
                end,
            },
        },
    })
    return posY
end

-- Party page PARTY TARGETS section (every style, not kit-gated): Enable |
-- Include Own Target, then, only while enabled, Fill Color | Background,
-- Width | Height and Position (offsets cog). Party-only keys on db.profile;
-- each setter takes the runtime's own light path (restyle, layout or the
-- include edge), never a party reload. Returns the new y.
function mod.RF_BuildPartyTargets(hostFrame, posY, W)
    local db = mod.db
    local BLANK = CludesUI.BlankRowCfg
    local _, hgt, row
    local function PV(k, d)
        local v = db.profile[k]
        if v == nil then
            return d
        end
        return v
    end
    -- A row getter over PV: the key's value, or the default given.
    local function PVRow(key, default)
        return function()
            return PV(key, default)
        end
    end
    -- The party preview draws its own target frames (the real ones are dimmed under it).
    local function Preview()
        if mod.partyPvActive() then
            mod.ShowPartyPreview()
        end
    end
    -- Colour and background: the fingerprint-gated restyle and repaint.
    local function PtSet(k, v)
        db.profile[k] = v
        mod.PT_Refresh()
        Preview()
    end
    -- Size, side and offsets: the delta-gated layout (combat-deferred).
    local function LaySet(k, v)
        db.profile[k] = v
        mod._PT_Layout()
        Preview()
    end
    local DARK_TIP =
        "Not available in Dark Mode. Dark Mode colors can be adjusted in Global Settings -> Colors."

    _, hgt = W:SectionHeader(hostFrame, "PARTY TARGETS", posY)
    posY = posY - hgt

    -- Row 1: Enable | Include Own Target. The rows below are HIDDEN while
    -- off, so the flip rebuilds the page.
    local on = db.profile.partyShowTargets == true -- build time (the page rebuilds)
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "toggle",
        text = "Enable Party Targets",
        tooltip = "Show a smaller secure target button beside each party frame. Left-click a button to target that party member's current target.",
        disabled = function()
            local p = db.profile
            return not p.partyShowTargets and p.partyCompactMode and mod.PT_AlongStack(p, true)
        end,
        disabledTooltip = "Move Party Targets beside the frame stack or turn off Compact Mode.",
        rawTooltip = true,
        getValue = function()
            return db.profile.partyShowTargets or false
        end,
        setValue = CludesUI.SectionToggleSetValue(function(v)
            if v and db.profile.partyCompactMode and mod.PT_AlongStack(db.profile, true) then
                return
            end
            db.profile.partyShowTargets = v
            mod.PT_SetEnabled(v)
            Preview()
        end),
    }, on and {
        type = "toggle",
        text = "Include Own Target",
        tooltip = "Also show your own target beside your frame.",
        -- Hide Self leaves no frame of yours to attach to.
        disabled = function()
            return db.profile.partyHideSelf == true
        end,
        disabledTooltip = "Hide Self",
        requireState = "disabled",
        getValue = function()
            return db.profile.partyTargetIncludeSelf or false
        end,
        setValue = function(v)
            db.profile.partyTargetIncludeSelf = v
            mod.PT_SetIncludeSelf(v)
            Preview()
        end,
    } or BLANK())
    posY = posY - hgt

    if not on then
        return posY
    end

    -- Row 2: Fill Color | Background (the Health Bar row's controls on the
    -- target frames' own keys).
    row, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Fill Color",
        values = { class = "Class Color", dark = "Dark Mode", classic = "Classic", custom = "Custom Color" },
        order = { "class", "dark", "classic", "custom" },
        tooltip = "Class Color uses the class color for players and the reaction color for NPCs.",
        getValue = PVRow("partyTargetHealthColorMode", "class"),
        setValue = function(v)
            PtSet("partyTargetHealthColorMode", v)
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        disabled = function()
            return PV("partyTargetHealthColorMode", "class") == "dark"
        end,
        disabledTooltip = DARK_TIP,
        rawTooltip = true,
        getValue = PVRow("partyTargetBgDarkness", 50),
        setValue = function(v)
            PtSet("partyTargetBgDarkness", v)
        end,
    })
    posY = posY - hgt
    -- Custom fill swatch: live only in Custom mode, dimmed and blocked otherwise.
    if not CludesUI._prebuilding then
        local region = row._leftRegion
        local colorSwatch = CludesUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local c = db.profile.partyTargetCustomFillColor
            if c then
                return c.r, c.g, c.b, 1
            end
            return 37 / 255, 193 / 255, 29 / 255, 1
        end, function(r, g, b)
            PtSet("partyTargetCustomFillColor", { r = r, g = g, b = b })
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        -- Blocking overlay: non-clickable + tooltip unless Fill Color is Custom.
        local block = CludesUI.NewSwatchBlocker(colorSwatch)
        block:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(colorSwatch, "Only available with Custom fill color")
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateSwatchVis()
            if PV("partyTargetHealthColorMode", "class") == "custom" then
                colorSwatch:SetAlpha(1)
                block:Hide()
            else
                colorSwatch:SetAlpha(0.3)
                block:Show()
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateSwatchVis)
        UpdateSwatchVis()
    end
    -- Background Custom + Class swatch pair: clicking either toggles partyTargetBgClassColored, the inactive one dims (mirrors the fill picker).
    if not CludesUI._prebuilding then
        local region = row._rightRegion
        -- Class swatch shows the player's class color and is not editable.
        local bgClassSwatch = CludesUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local _, ct = UnitClass("player")
            local cc = ct and CludesUI.GetClassColor(ct)
            if cc then
                return cc.r, cc.g, cc.b, 1
            end
            return 1, 1, 1, 1
        end, function() end, false, 20)
        bgClassSwatch:SetScript("OnClick", function()
            PtSet("partyTargetBgClassColored", true)
            CludesUI:RefreshPage()
        end)
        bgClassSwatch:HookScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(bgClassSwatch, "Class Colored Background")
        end)
        bgClassSwatch:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        bgClassSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgClassSwatch

        local bgSwatch = CludesUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local c = db.profile.partyTargetCustomBgColor
            if c then
                return c.r, c.g, c.b, 1
            end
            return 17 / 255, 17 / 255, 17 / 255, 1
        end, function(r, g, b)
            PtSet("partyTargetCustomBgColor", { r = r, g = g, b = b })
        end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if PV("partyTargetBgClassColored", false) then
                PtSet("partyTargetBgClassColored", false)
                CludesUI:RefreshPage()
                return
            end
            if self._eabOrigClick then
                self._eabOrigClick(self)
            end
        end)
        bgSwatch:HookScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(bgSwatch, "Custom Background Color")
        end)
        bgSwatch:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgSwatch
        -- Blocking overlay spans BOTH swatches: Dark Mode has no background.
        local bgBlock = CreateFrame("Frame", nil, region)
        bgBlock:SetPoint("TOPLEFT", bgSwatch, "TOPLEFT", 0, 0)
        bgBlock:SetPoint("BOTTOMRIGHT", bgClassSwatch, "BOTTOMRIGHT", 0, 0)
        bgBlock:SetFrameLevel(bgClassSwatch:GetFrameLevel() + 10)
        bgBlock:EnableMouse(true)
        bgBlock:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(bgSwatch, DARK_TIP)
        end)
        bgBlock:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateBgSwatchVis()
            if PV("partyTargetHealthColorMode", "class") == "dark" then
                bgSwatch:SetAlpha(0.3)
                bgClassSwatch:SetAlpha(0.3)
                bgBlock:Show()
            else
                bgBlock:Hide()
                local classOn = PV("partyTargetBgClassColored", false)
                bgSwatch:SetAlpha(classOn and 0.3 or 1)
                bgClassSwatch:SetAlpha(classOn and 1 or 0.3)
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateBgSwatchVis)
        UpdateBgSwatchVis()
    end

    -- Row 3: Width | Height (absolute, not scaled with the party frames).
    _, hgt = W:DualRow(hostFrame, posY, {
        type = "slider",
        text = "Width",
        min = 20,
        max = 300,
        step = 1,
        getValue = PVRow("partyTargetWidth", 70),
        setValue = function(v)
            LaySet("partyTargetWidth", v)
        end,
    }, {
        type = "slider",
        text = "Height",
        min = 10,
        max = 150,
        step = 1,
        getValue = PVRow("partyTargetHeight", 33),
        setValue = function(v)
            LaySet("partyTargetHeight", v)
        end,
    })
    posY = posY - hgt

    -- Row 4: Position (+ offsets cog). Shows the side the frames actually
    -- take (the Horizontal Frames setter's refresh re-reads it); a pick of
    -- the side an unset Position shows (the kit's move included) is stored
    -- as unset, so it keeps following the layout and the frame style.
    -- Under the Party Frames kit the stacked frames' buff side is taken.
    row, hgt = W:DualRow(hostFrame, posY, {
        type = "dropdown",
        text = "Position",
        tooltip = "Right by default, or Bottom with Horizontal Frames. With Frame Style: Party Frames, the side holding the buffs is not available.",
        values = { top = "Top", bottom = "Bottom", left = "Left", right = "Right" },
        order = { "top", "bottom", "left", "right" },
        itemDisabled = function(v)
            local p = db.profile
            if p.partyCompactMode and mod.PT_PositionAlongStack(v, p.partyHorizontal) then
                return true
            end
            if p.partyHorizontal or not mod.RF_PartyKit() then
                return false
            end
            local m = mod.RF_KitBuffMode(p)
            return (m == "RIGHT" and v == "right") or (m == "LEFT" and v == "left")
        end,
        itemDisabledTooltip = function(v)
            if db.profile.partyCompactMode and mod.PT_PositionAlongStack(v, db.profile.partyHorizontal) then
                return "Compact Mode"
            end
            if v == "left" or v == "right" then
                return "Frame Style: Party Frames"
            end
        end,
        itemRequireState = "disabled",
        getValue = function()
            return mod.PT_ShownSide()
        end,
        setValue = function(v)
            if db.profile.partyCompactMode and mod.PT_PositionAlongStack(v, db.profile.partyHorizontal) then
                return
            end
            LaySet("partyTargetPosition", (v ~= mod.PT_ShownSide(true)) and v or nil)
        end,
    }, BLANK())
    posY = posY - hgt
    CludesUI.BuildInlineCog(row._leftRegion, {
        title = "Target Position Offsets",
        rows = {
            {
                type = "slider",
                label = "X Offset",
                min = -100,
                max = 100,
                step = 1,
                get = PVRow("partyTargetOffsetX", 0),
                set = function(v)
                    LaySet("partyTargetOffsetX", v)
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -100,
                max = 100,
                step = 1,
                get = PVRow("partyTargetOffsetY", 0),
                set = function(v)
                    LaySet("partyTargetOffsetY", v)
                end,
            },
        },
    })
    return posY
end

CludesUI.AtLogin(function()
    mod._InitCUIModule = function()
        if not CludesUI or not CludesUI.RegisterModule then
            return
        end
        if not mod.db then
            return
        end

        local Pix = CludesUI.PanelPP
        local db = mod.db
        local ReloadFrames = mod.ReloadFrames
        local floor = math.floor

        ---------------------------------------------------------------------------
        --  Shared helpers
        ---------------------------------------------------------------------------
        local GetFFD = mod.GetFFD

        local function ReloadAndUpdate()
            if ReloadFrames then
                ReloadFrames()
            end
            -- Preview refresh keeps health values, updates layout/colors.
            if mod.previewActive and mod.previewActive() and mod.ShowPreview then
                mod.ShowPreview()
            end
            if mod._sizePreviewTier and mod._ShowSizePreview then
                mod._ShowSizePreview(mod._sizePreviewTier)
            end
            if mod.RefreshPvAuraVisuals then
                mod.RefreshPvAuraVisuals()
            end
            -- Party frames share all settings except width/height.
            if mod.ReloadPartyFrames then
                mod.ReloadPartyFrames()
            end
            if mod.partyPvActive and mod.partyPvActive() and mod.ShowPartyPreview then
                mod.ShowPartyPreview()
            end
        end

        ---------------------------------------------------------------------------
        --  Context-aware settings helpers
        --  With _partyCtx true (party tab), reads/writes go to "party_<key>" with
        --  fallthrough to raid values, so ONE set of page builders serves both tabs.
        ---------------------------------------------------------------------------
        -- Mutable state shared with the page builders under RaidFrames_Options\.
        -- A table instead of locals so every file reads and writes the live value.
        -- _partyCtx: true while building/interacting on the party tab.
        local optionState = { _partyCtx = false }
        local PARTY_KEY_SECTION = mod._PARTY_KEY_SECTION or {}
        local IsPartySectionCustom = mod._IsPartySectionCustom

        local function SGet(key)
            if
                optionState._partyCtx
                and PARTY_KEY_SECTION[key]
                and IsPartySectionCustom(PARTY_KEY_SECTION[key])
            then
                local pv = db.profile["party_" .. key]
                if pv ~= nil then
                    return pv
                end
            end
            return db.profile[key]
        end
        local function SSet(key, val)
            if
                optionState._partyCtx
                and PARTY_KEY_SECTION[key]
                and IsPartySectionCustom(PARTY_KEY_SECTION[key])
            then
                db.profile["party_" .. key] = val
            else
                db.profile[key] = val
            end
            if mod._BumpAbsorbGen then
                mod._BumpAbsorbGen()
            end
            ReloadAndUpdate()
        end
        local function SVal(key, default)
            if
                optionState._partyCtx
                and PARTY_KEY_SECTION[key]
                and IsPartySectionCustom(PARTY_KEY_SECTION[key])
            then
                local pv = db.profile["party_" .. key]
                if pv ~= nil then
                    return pv
                end
            end
            local v = db.profile[key]
            if v ~= nil then
                return v
            end
            return default
        end
        -- Context-aware direct write, for color swatches that bypass SSet.
        local function SWrite(key, val)
            if
                optionState._partyCtx
                and PARTY_KEY_SECTION[key]
                and IsPartySectionCustom(PARTY_KEY_SECTION[key])
            then
                db.profile["party_" .. key] = val
            else
                db.profile[key] = val
            end
            if mod._BumpAbsorbGen then
                mod._BumpAbsorbGen()
            end
        end
        -- A border's exact-size companion (<sib>Px) is ONE setting with its legacy
        -- sibling, the party proxy's rule: on the party tab a stored party sibling
        -- carries only the party companion (nil included), never the raid one.
        local function SGetPx(key, sib)
            if
                optionState._partyCtx
                and PARTY_KEY_SECTION[key]
                and IsPartySectionCustom(PARTY_KEY_SECTION[key])
                and db.profile["party_" .. sib] ~= nil
            then
                return db.profile["party_" .. key]
            end
            return SGet(key)
        end

        -- WoW Forever: the Missing Buffs icons' glow (prefix keys missingBuffsGlow*)
        -- as a shared glow descriptor over a read/write pair -- the page's context-
        -- aware SVal/SWrite in the indicator's cog, the raid keys on Global
        -- Settings > Glows (built outside any tab, so never through the tab context).
        local MissingGlowDesc
        if CludesUI.IS_FOREVER then
            local GK = CludesUI.Glows.PrefixKeys("missingBuffsGlow")
            function MissingGlowDesc(read, write)
                return {
                    host = "icon",
                    excludes = { [4] = true },
                    caps = { mode = true, params = true, bg = true },
                    defaultColor = CludesUI.Glows.DEFAULT_COLOR,
                    onChange = ReloadAndUpdate,
                    disabled = function()
                        return read("showMissingBuffs", true) == false
                    end,
                    disabledTooltip = "Missing Buffs",
                    get = function(f)
                        if f == "style" then
                            return read(GK.type, 2)
                        elseif f == "mode" then
                            return read(GK.mode, "default")
                        elseif f == "color" then
                            return read(GK.r), read(GK.g), read(GK.b)
                        elseif f == "lines" then
                            return read(GK.lines)
                        elseif f == "thickness" then
                            return read(GK.th)
                        elseif f == "speed" then
                            return read(GK.speed)
                        elseif f == "bg" then
                            return read(GK.bg) == true
                        elseif f == "bgColor" then
                            return read(GK.bgR), read(GK.bgG), read(GK.bgB)
                        end
                    end,
                    set = function(f, a, b, c)
                        if f == "style" then
                            write(GK.type, a)
                        elseif f == "mode" then
                            write(GK.mode, a)
                        elseif f == "color" then
                            write(GK.r, a)
                            write(GK.g, b)
                            write(GK.b, c)
                        elseif f == "lines" then
                            write(GK.lines, a)
                        elseif f == "thickness" then
                            write(GK.th, a)
                        elseif f == "speed" then
                            write(GK.speed, a)
                        elseif f == "bg" then
                            write(GK.bg, a and true or nil)
                        elseif f == "bgColor" then
                            write(GK.bgR, a)
                            write(GK.bgG, b)
                            write(GK.bgB, c)
                        end
                    end,
                }
            end
            CludesUI.GlowOptions.RegisterSite({
                id = "rf_missing_buffs",
                label = "Missing Buffs Glow",
                group = "module",
                module = "CludesUIRaidFrames",
                page = PAGE_MAIN,
                section = "INDICATORS",
                highlight = "Missing Buffs",
                desc = MissingGlowDesc(function(key, default)
                    local v = db.profile[key]
                    if v == nil then
                        return default
                    end
                    return v
                end, function(key, v)
                    db.profile[key] = v
                end),
            })
        end

        ---------------------------------------------------------------------------
        --  Health bar texture dropdown
        ---------------------------------------------------------------------------
        -- Re-append post-login: the OnInitialize append runs too early to catch most
        -- SM texture providers, which register after our ADDON_LOADED.
        CludesUI.AppendSharedMediaTextures(
            mod.healthBarTextureNames or {},
            mod.healthBarTextureOrder or {},
            nil,
            mod.healthBarTextures
        )

        local hbtValues = {}
        local hbtOrder = {}
        do
            local texNames = mod.healthBarTextureNames or {}
            local texOrder2 = mod.healthBarTextureOrder or {}
            local texLookup = mod.healthBarTextures or {}
            for _, key in ipairs(texOrder2) do
                if key ~= "---" then
                    hbtValues[key] = texNames[key] or key
                end
                hbtOrder[#hbtOrder + 1] = key
            end
            hbtValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return texLookup[key]
                end,
            }
        end

        ---------------------------------------------------------------------------
        --  Value tables for dropdowns
        ---------------------------------------------------------------------------
        local healthColorValues = {
            ["class"] = "Class Color",
            ["classReactive"] = "Class Color Reactive",
            ["dark"] = "Dark Mode",
            ["classic"] = "Classic",
            ["custom"] = "Custom Color",
            ["customDynamic"] = "Custom Dynamic Colors",
        }
        local healthColorOrder = { "class", "classReactive", "dark", "classic", "custom", "customDynamic" }

        local absorbStyleValues = {
            ["none"] = "None",
            ["striped"] = "Striped",
            ["stripedReversed"] = "Striped Reversed",
            ["stripedThick"] = "Striped Thick", -- striped-thick.png
            ["stripedThickR"] = "Striped Thick Reversed", -- striped-thick-r.png
            ["clean"] = "Clean (Flat)",
            ["blizzard"] = "Classic WoW", -- DB key stays "blizzard"; label only
            ["blizzardModern"] = "Default Blizz Frames", -- compound: solid base + tiled stripes (shield only)
            ["healBlizzModern"] = "Default Blizz Frames", -- heal-absorb only: louis-absorb.png texture
            ["largeOutlinedStripes"] = "Large Outlined Stripes", -- heal-absorb only: large-habsorb-left.png
            ["largeOutlinedStripesR"] = "Large Outlined Stripes R", -- heal-absorb only: large-habsorb-right.png
            ["largeStripes"] = "Large Stripes", -- large-absorb-left.png
            ["largeStripesR"] = "Large Stripes R", -- large-absorb-right.png
            ["maxHealthStripes"] = "Max Health Stripes", -- reduced max-health overlay
            -- The native raid fill (the shared-media copy dedupes against it).
            ["blizzardRaid"] = "Blizzard Raid Bar",
            ["pixelsShield"] = "Pixels Shield", -- pixels-shield.tga
            ["pixelsShieldEdge"] = "Pixels Shield Edge", -- shield-only: pixels-shield-edge.tga
            ["pixelsShieldFill"] = "Pixels Shield Fill", -- shield-only: pixels-shield-fill.tga (tiled)
        }
        -- Shield absorb shows every style including Blizzard (Modern).
        local absorbStyleOrder = {
            "none",
            "blizzardModern",
            "striped",
            "stripedReversed",
            "stripedThick",
            "stripedThickR",
            "clean",
            "blizzard",
            "largeStripes",
            "largeStripesR",
            "blizzardRaid",
            "pixelsShield",
            "pixelsShieldEdge",
            "pixelsShieldFill",
        }
        -- Heal absorb shares the values table but EXCLUDES Blizzard (Modern).
        local healAbsorbStyleOrder = {
            "none",
            "healBlizzModern",
            "striped",
            "stripedReversed",
            "stripedThick",
            "stripedThickR",
            "clean",
            "blizzard",
            "largeOutlinedStripes",
            "largeOutlinedStripesR",
            "largeStripes",
            "largeStripesR",
            "blizzardRaid",
            "pixelsShield",
        }
        -- Max Health mirrors Heal Absorb plus "Max Health Stripes" first.
        local maxHealthStyleOrder = {
            "none",
            "maxHealthStripes",
            "striped",
            "stripedReversed",
            "stripedThick",
            "stripedThickR",
            "clean",
            "blizzard",
            "healBlizzModern",
            "largeOutlinedStripes",
            "largeOutlinedStripesR",
            "largeStripes",
            "largeStripesR",
            "blizzardRaid",
            "pixelsShield",
        }
        -- Appends SharedMedia statusbar textures after a divider (mirrors Bar Texture dropdown). "sm:" keys land in the shared health-bar tables via AppendSharedMediaTextures; resolution flows through ns.ResolveAbsorbStyleTex -> health-bar lookup.
        -- All three dropdowns share absorbStyleValues, so each gains the SM entries and preview swatch.
        do
            CludesUI.AppendSharedMediaTextures(
                mod.healthBarTextureNames or {},
                mod.healthBarTextureOrder or {},
                nil,
                mod.healthBarTextures
            )
            local smNames = mod.healthBarTextureNames or {}
            local smKeys = {}
            for _, k in ipairs(mod.healthBarTextureOrder or {}) do
                if type(k) == "string" and k:find("^sm:") then
                    smKeys[#smKeys + 1] = k
                    absorbStyleValues[k] = smNames[k] or k
                end
            end
            if #smKeys > 0 then
                for _, ord in ipairs({ absorbStyleOrder, healAbsorbStyleOrder, maxHealthStyleOrder }) do
                    ord[#ord + 1] = "---"
                    for _, k in ipairs(smKeys) do
                        ord[#ord + 1] = k
                    end
                end
            end
            -- Preview swatch behind each row via ns.ResolveAbsorbStyleTex. Default Blizz
            -- Frames draws its in-game compound: tinted tiled stripes over the solid base
            -- (ns.ApplyModernAbsorbBar / the _modernBase colour).
            local modernSwatch = { base = { 0.776, 0.784, 1.0 }, tint = { 0.569, 0.588, 1.0 }, tile = true }
            absorbStyleValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    if not key or key == "---" or key == "none" then
                        return nil
                    end
                    if key == "blizzardModern" then
                        return mod.ResolveAbsorbStyleTex("striped"), modernSwatch
                    end
                    if key == "maxHealthStripes" then
                        return CludesUI.MAX_HEALTH_STRIPES_TEX
                    end
                    return mod.ResolveAbsorbStyleTex and mod.ResolveAbsorbStyleTex(key) or nil
                end,
            }
        end

        local growthValues = {
            DOWN = "Down",
            UP = "Up",
            RIGHT = "Right",
            LEFT = "Left",
        }
        local allGrowthOrder = { "DOWN", "UP", "RIGHT", "LEFT" }

        -- Group Growth additionally offers the grid flow: ns._RF_GRID_ROWS groups
        -- stack down the first column (G1 above G2) before the next column starts to
        -- the right (G3 above G4) -- a 2x2 raid block instead of one long run. Unit
        -- Growth has no such mode: a header's children only ever run along one axis.
        local groupGrowthValues = {
            DOWN = "Down",
            UP = "Up",
            RIGHT = "Right",
            LEFT = "Left",
            DOWNRIGHT = "Down and then Right",
        }
        local groupGrowthOrder = { "DOWN", "UP", "RIGHT", "LEFT", "DOWNRIGHT" }

        -- Merge Groups renders through Blizzard's flat header, which has a single
        -- column axis and cannot wrap into a grid, so the grid flow degrades to the
        -- plain RIGHT run there (same self-heal as ns._RFEffectiveGrowth in the
        -- runtime). Report what actually renders instead of showing a value the
        -- merged grid ignores.
        local function ReadGroupGrowth(v)
            if v == "DOWNRIGHT" and SVal("mergeGroups", false) then
                return "RIGHT"
            end
            return v
        end

        -- ns._RFGrowthIsVertical is the runtime module's single source of truth for
        -- this check (CUI_RaidFrames_Reload.lua); reuse it here rather than a second copy.
        local GrowthIsVertical = mod._RFGrowthIsVertical

        -- Merge Groups renders through Blizzard's flat SecureGroupHeader, whose column
        -- axis (columnAnchorPoint) is always perpendicular to Unit Growth -- a same-axis
        -- Group Growth has no valid column direction, so the runtime silently substitutes
        -- an unrelated one instead of honoring it. Bump the OTHER axis to a perpendicular
        -- value instead of letting an unrenderable pair through, mirroring the Spell
        -- Name/Spell Target side-conflict rule used elsewhere in these options.
        local function KeepGrowthPerpendicular(newVal, getOther, setOther)
            local other = getOther()
            if GrowthIsVertical(newVal) == GrowthIsVertical(other) then
                setOther(GrowthIsVertical(newVal) and "RIGHT" or "DOWN")
            end
        end

        -- The preview mode dropdown label of each tab's latest build (raid, party);
        -- all refresh when one changes.
        local pvModeDropdowns = {}

        -- Preview Mode controls carrying override-preview chrome (gold border host
        -- + tooltip): each tab's latest build (raid, party), so a rebuild replaces
        -- its tab's entry and nothing holds an earlier build.
        local pvModeCtrls = {}

        -- An entry of either list is its build's only while the dropdown control
        -- keeps the dress generation it was stored at (the options page pool):
        -- a control dressed again since is another row's now, and is skipped.
        local function PvEntryLive(e)
            return PoolGen(e.ctrl) == e.gen
        end

        -- Gold border + tooltip on every Preview Mode control while the REAL preview renders an override's effective values (spec group or applied conditional). State comes from the runtime resolvers, NEVER the panel's view flags, so it always matches what the real preview shows.
        -- Recomputed at row build time and from ns._RebuildPvOverlay (view/spec/conditional changes).
        function mod._UpdatePvModeChrome()
            if not next(pvModeCtrls) then
                return
            end
            local textValue
            if (db.profile.previewMode or "overlay") == "real" then
                -- Editing-as session: preview shows THAT session's values (effective overlay off there by design), so name it.
                local sessName = CludesUI.SpecOverrides_EditSessionName()
                if sessName then
                    textValue = CludesUI.Lf("Previewing Override: %1$s", sessName)
                elseif CludesUI.SpecOverrides_PeekEffectiveValues then
                    local _, specSrc, condSrc =
                        CludesUI.SpecOverrides_PeekEffectiveValues("CludesUIRaidFrames")
                    if specSrc and condSrc then
                        textValue = CludesUI.Lf("Previewing Overrides: %1$s, %2$s", specSrc, condSrc)
                    elseif specSrc or condSrc then
                        textValue = CludesUI.Lf("Previewing Override: %1$s", specSrc or condSrc)
                    end
                end
            end
            for _, e in pairs(pvModeCtrls) do
                if PvEntryLive(e) then
                    e.gold:SetShown(textValue ~= nil)
                    e.ctrl._ttText = textValue
                    e.ctrl._ttOpts = nil
                end
            end
        end

        -- True when preview is disabled; eyeball toggles gray out.
        local function IsPreviewOff()
            return (db.profile.previewMode or "overlay") == "none"
        end

        -- Builds the "Preview Mode" row at the top of a page; returns the new y.
        local function BuildPreviewModeRow(hostFrame, posY)
            local ROW_H = 50
            local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
            local contentPad = CludesUI.CONTENT_PAD or 45
            -- The tab this row belongs to (the page being built sets the context first).
            local pvCtx = optionState._partyCtx and "party" or "raid"

            posY = posY - 10
            local modeRow = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(modeRow, hostFrame:GetWidth() - contentPad * 2, ROW_H)
            Pix.Point(modeRow, "TOPLEFT", hostFrame, "TOPLEFT", contentPad, posY)
            posY = posY - ROW_H

            local modeLabel = modeRow:CreateFontString(nil, "OVERLAY")
            CludesUI.ApplyModuleFont(modeLabel, fontFile, 14, "raidFrames")
            modeLabel:SetPoint("TOP", modeRow, "TOP", 0, 0)
            modeLabel:SetText(CludesUI.L("Preview Mode"))
            modeLabel:SetTextColor(1, 1, 1, 0.6)

            local previewModeValues = {
                real = "Real Preview",
                overlay = "Overlay Preview",
                none = "No Preview",
            }
            local previewModeOrder = { "real", "overlay", "none" }
            local ddCtrl, ddLbl = CludesUI.BuildDropdownControl(
                modeRow,
                180,
                modeRow:GetFrameLevel() + 2,
                previewModeValues,
                previewModeOrder,
                function()
                    return db.profile.previewMode or "overlay"
                end,
                function(v)
                    db.profile.previewMode = v
                    -- Apply to whichever preview the current tab owns.
                    local page = CludesUI:GetActivePage()
                    if page == PAGE_PARTY then
                        if v == "none" then
                            if mod.HidePartyPreview then
                                mod.HidePartyPreview()
                            end
                        else
                            if mod.HidePreview then
                                mod.HidePreview()
                            end
                            if mod.ShowPartyPreview then
                                mod.ShowPartyPreview()
                            end
                        end
                    else
                        if mod.ApplyPreviewMode then
                            mod.ApplyPreviewMode()
                        end
                        if mod.HidePartyPreview then
                            mod.HidePartyPreview()
                        end
                    end
                    for _, e in pairs(pvModeDropdowns) do
                        if PvEntryLive(e) then
                            e.lbl:SetText(previewModeValues[v] or v)
                        end
                    end
                    CludesUI:RefreshPage()
                end
            )
            ddCtrl:SetPoint("TOP", modeLabel, "BOTTOM", 0, -9)

            -- The search prebuild's row is a stand-in: it never takes a tab's place.
            if not CludesUI._prebuilding then
                local d = pvModeDropdowns[pvCtx]
                if not d then
                    d = {}
                    pvModeDropdowns[pvCtx] = d
                end
                d.lbl, d.ctrl, d.gen = ddLbl, ddCtrl, PoolGen(ddCtrl)
            end

            -- Override-preview chrome lives on a SEPARATE gold border host: the control's own border is re-asserted by its hover scripts, so never recolor it directly (same pattern as the overrides UI slot marks).
            do
                local gold = CludesUI._SPECOV_GOLD or { 199 / 255, 166 / 255, 90 / 255 }
                local host = CreateFrame("Frame", nil, ddCtrl)
                host:SetAllPoints(ddCtrl)
                host:SetFrameLevel(ddCtrl:GetFrameLevel() + 30)
                CludesUI.MakeRoundedBorder(host, gold[1], gold[2], gold[3], 0.9)
                host:Hide()
                if not CludesUI._prebuilding then
                    local e = pvModeCtrls[pvCtx]
                    if not e then
                        e = {}
                        pvModeCtrls[pvCtx] = e
                    end
                    e.ctrl, e.gold, e.gen = ddCtrl, host, PoolGen(ddCtrl)
                end
            end
            if mod._UpdatePvModeChrome then
                mod._UpdatePvModeChrome()
            end

            mod._previewMode = db.profile.previewMode or "overlay"
            return posY
        end

        ---------------------------------------------------------------------------
        --  Visual settings sections (shared by raid + party pages)
        ---------------------------------------------------------------------------
        local function BuildVisualSections(hostFrame, posY, W, onSection)
            -- Eyeball handles are per-context (raid vs party) so the two page builds don't clobber each other's eye-icon refreshers. Animation start/stop stay on ns: one shared ticker resolves the active preview at call time via ns.PvActiveFrames.
            local _eyeCtx = optionState._partyCtx and "party" or "raid"
            mod._eye = mod._eye or {}
            mod._eye[_eyeCtx] = mod._eye[_eyeCtx] or {}
            local EYE = mod._eye[_eyeCtx]
            -- The sections live in RaidFrames_Options\VisualBars_Options.lua (HEALTH BAR ..
            -- TEXT DISPLAY) and VisualIndicators_Options.lua (INDICATORS .. RANGE & TOOLTIP);
            -- Dispels reuses the Health Bar custom-border gates.
            local CustomBorderOff, CustomBorderOffTip
            posY, CustomBorderOff, CustomBorderOffTip =
                mod.RFO_BuildVisualBars(hostFrame, posY, W, onSection, EYE)
            posY = mod.RFO_BuildVisualIndicators(
                hostFrame,
                posY,
                W,
                onSection,
                EYE,
                CustomBorderOff,
                CustomBorderOffTip
            )
            return posY
        end

        ---------------------------------------------------------------------------
        --  Buff Manager page (placeholder)
        ---------------------------------------------------------------------------
        local function BuildBuffManagerPage(pageName, hostFrame, yOffset)
            -- Buff Manager v2 runs INSIDE the legacy page shell.
            -- The from-scratch replacement page was rejected in field review and is not routed to; do not wire it up.
            if mod.BM_BuildPage then
                return mod.BM_BuildPage(pageName, hostFrame, yOffset)
            end
            return math.abs(yOffset)
        end

        ---------------------------------------------------------------------------
        --  Test Mode (global preview with all toggleable elements)
        ---------------------------------------------------------------------------
        local testModeFrame = nil
        local testModeActive = false

        local function CloseTestMode()
            testModeActive = false
            mod._testMode = false
            if testModeFrame then
                testModeFrame:SetAlpha(1)
                local fadeOutAG = testModeFrame._fadeOut
                if not fadeOutAG then
                    fadeOutAG = testModeFrame:CreateAnimationGroup()
                    local fadeOutA = fadeOutAG:CreateAnimation("Alpha")
                    fadeOutA:SetFromAlpha(1)
                    fadeOutA:SetToAlpha(0)
                    fadeOutA:SetDuration(0.3)
                    fadeOutAG:SetScript("OnFinished", function()
                        testModeFrame:Hide()
                    end)
                    testModeFrame._fadeOut = fadeOutAG
                end
                testModeFrame:SetAlpha(0)
                fadeOutAG:Play()
            end
            mod._indicatorsVisible = false
            mod._dispelsVisible = false
            mod._defensivesPreviewVisible = false
            mod._debuffsPreviewVisible = false
            if mod._stopHealthAnim and mod._healthAnimActive then
                mod._stopHealthAnim()
            end
            mod._healthAnimActive = false
            mod._bmFrameEffectsVisible = false
            mod._testReducedMaxHealth = false
            mod._testAbsorbs = nil
            mod._testHealAbsorbs = nil
            mod._testHealPrediction = nil
            mod._testThreat = nil
            mod._testBuffsVisible = false
            if mod.StopPvBuffTicker then
                mod.StopPvBuffTicker()
            end
            -- Hide the container immediately; the dimmer fade masks it.
            if mod._overlayContainer then
                mod._overlayContainer:Hide()
            end
            if mod.HidePreview then
                mod.HidePreview()
            end
            local activePage = CludesUI:GetActivePage()
            if activePage == PAGE_MAIN then
                local mode = db.profile.previewMode or "overlay"
                if mode ~= "none" and mod.ShowPreview then
                    C_Timer.After(0, function()
                        if mod.ShowPreview then
                            mod.ShowPreview()
                        end
                    end)
                end
            end
        end

        -- Builds the Full Preview sidebar on the first open; every open re-dresses
        -- it through panel._redress (fonts, accent, check states, hover looks, anchor).
        local function BuildTestPanel(Pix, fontFile, accentColor, s)
            local PANEL_W = 260
            local ROW_H = 32
            local PAD = 16
            local panelFrame = CreateFrame("Frame", nil, testModeFrame)
            panelFrame:SetSize(PANEL_W, 600)
            panelFrame:SetPoint("LEFT", testModeFrame, "LEFT", 40, 0)
            panelFrame:Hide() -- shown once the overlay container is positioned
            panelFrame:SetFrameLevel(testModeFrame:GetFrameLevel() + 5)
            local panelBg = panelFrame:CreateTexture(nil, "BACKGROUND")
            panelBg:SetAllPoints()
            panelBg:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 0.9)
            CludesUI.MakeBorder(panelFrame, 1, 1, 1, 0.1, Pix)
            local panelFadeAG = panelFrame:CreateAnimationGroup()
            local panelFadeA = panelFadeAG:CreateAnimation("Alpha")
            panelFadeA:SetFromAlpha(0)
            panelFadeA:SetToAlpha(1)
            panelFadeA:SetDuration(0.3)
            panelFrame._fadeIn = panelFadeAG

            -- What every open re-dresses: each font string with its size, each
            -- checkbox with its mark, each Edit button's background and label.
            local fonts, checks, editParts = {}, {}, {}

            local function MakeFont(p, size, r, g, b, a)
                local fontStr = p:CreateFontString(nil, "OVERLAY")
                CludesUI.PrimeFontShadow(fontStr, true)
                fontStr:SetFont(fontFile, size, "")
                fontStr:SetTextColor(r or 1, g or 1, b or 1, a or 1)
                fonts[#fonts + 1] = fontStr
                fonts[#fonts + 1] = size
                return fontStr
            end

            local cy = -PAD

            local function SectionHeader(textValue)
                cy = cy - 10
                local labelFS = MakeFont(panelFrame, 11, 1, 1, 1, 0.75)
                labelFS:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", PAD, cy)
                labelFS:SetText(CludesUI.L(textValue))
                local line = panelFrame:CreateTexture(nil, "ARTWORK")
                line:SetHeight(1)
                line:SetPoint("LEFT", labelFS, "RIGHT", 8, 0)
                line:SetPoint("RIGHT", panelFrame, "RIGHT", -PAD, 0)
                line:SetColorTexture(1, 1, 1, 0.06)
                cy = cy - 15
            end

            -- Every checkbox refresher, re-run together for mutual exclusion.
            local allRefreshFns = {}
            -- Shared edit-target glow, made on first use and again whenever the
            -- accent changed (a glow takes its colour when it first plays).
            local editGlow, glowR, glowG, glowB

            local function CheckboxRow(labelText, getVal, setVal, editTarget)
                local row = CreateFrame("Frame", nil, panelFrame)
                row:SetSize(PANEL_W - PAD * 2, ROW_H)
                row:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", PAD, cy)
                row:SetFrameLevel(panelFrame:GetFrameLevel() + 1)

                local cb = CreateFrame("CheckButton", nil, row)
                cb:SetSize(18, 18)
                cb:SetPoint("LEFT", row, "LEFT", 0, 0)

                local cbBg = cb:CreateTexture(nil, "BACKGROUND")
                cbBg:SetAllPoints()
                cbBg:SetColorTexture(0.15, 0.15, 0.15, 1)
                CludesUI.MakeBorder(cb, 1, 1, 1, 0.2, Pix)

                local checkMark = cb:CreateTexture(nil, "OVERLAY")
                checkMark:SetSize(12, 12)
                checkMark:SetPoint("CENTER")
                checkMark:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 1)
                checks[#checks + 1] = cb
                checks[#checks + 1] = checkMark

                local function Refresh()
                    local v = getVal()
                    checkMark:SetShown(v)
                end
                Refresh()

                local function DoToggle()
                    setVal(not getVal())
                    for _, func in ipairs(allRefreshFns) do
                        func()
                    end
                    if mod._applyTestState then
                        mod._applyTestState()
                    end
                    if mod.ShowPreview then
                        mod.ShowPreview()
                    end
                end

                cb:SetScript("OnClick", DoToggle)

                -- Label is clickable and toggles the checkbox.
                local lblBtn = CreateFrame("Button", nil, row)
                lblBtn:SetPoint("LEFT", cb, "RIGHT", 8, 0)
                lblBtn:SetPoint("RIGHT", row, "RIGHT", -50, 0)
                lblBtn:SetHeight(ROW_H)
                lblBtn:SetScript("OnClick", DoToggle)
                local labelFS = MakeFont(lblBtn, 11, 1, 1, 1, 0.85)
                labelFS:SetPoint("LEFT")
                labelFS:SetText(CludesUI.L(labelText))

                if editTarget then
                    local editBtn = CreateFrame("Button", nil, row)
                    editBtn:SetSize(43, 22)
                    editBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    editBtn:SetFrameLevel(row:GetFrameLevel() + 1)
                    local eBg = editBtn:CreateTexture(nil, "BACKGROUND")
                    eBg:SetAllPoints()
                    eBg:SetColorTexture(1, 1, 1, 0.05)
                    local eLbl = MakeFont(editBtn, 10, 1, 1, 1, 0.4)
                    eLbl:SetPoint("CENTER")
                    eLbl:SetText(CludesUI.L("Edit"))
                    editParts[#editParts + 1] = eBg
                    editParts[#editParts + 1] = eLbl
                    editBtn:SetScript("OnEnter", function()
                        eBg:SetColorTexture(1, 1, 1, 0.1)
                        eLbl:SetAlpha(0.7)
                    end)
                    editBtn:SetScript("OnLeave", function()
                        eBg:SetColorTexture(1, 1, 1, 0.05)
                        eLbl:SetAlpha(0.4)
                    end)
                    editBtn:SetScript("OnClick", function()
                        CloseTestMode()
                        if editTarget.page then
                            CludesUI:SelectPage(editTarget.page)
                            -- Scroll to + highlight the target row once the page builds.
                            if editTarget.key then
                                C_Timer.After(0.1, function()
                                    local target = mod._editTargets and mod._editTargets[editTarget.key]
                                    if not target then
                                        return
                                    end
                                    -- A row the page rebuilt since is dressed again (maybe as
                                    -- another row): the glow below is for this dress only.
                                    local targetGen = PoolGen(target)
                                    local scrollFrame = CludesUI._scrollFrame
                                    if scrollFrame then
                                        local _, _, _, _, rowY = target:GetPoint(1)
                                        if rowY then
                                            local scrollPos = math.max(0, math.abs(rowY) - 40)
                                            if CludesUI.SmoothScrollTo then
                                                CludesUI.SmoothScrollTo(scrollPos)
                                            end
                                        end
                                    end
                                    C_Timer.After(0.15, function()
                                        if PoolGen(target) ~= targetGen or not target:IsShown() then
                                            return
                                        end
                                        local eg = CludesUI.CLUDES_GREEN
                                        if
                                            not editGlow
                                            or glowR ~= eg.r
                                            or glowG ~= eg.g
                                            or glowB ~= eg.b
                                        then
                                            glowR, glowG, glowB = eg.r, eg.g, eg.b
                                            editGlow = CludesUI.MakeSettingGlow({ color = eg })
                                        end
                                        editGlow(target)
                                    end)
                                end)
                            end
                        end
                    end)
                end

                cy = cy - ROW_H
                allRefreshFns[#allRefreshFns + 1] = Refresh
                return cb, Refresh, row
            end

            local nonIndicatorRows = {}

            -- Test mode toggle state persists across open/close within a session.
            if not mod._testState then
                local specIdx = GetSpecialization and GetSpecialization()
                local specRole = specIdx and GetSpecializationRole and GetSpecializationRole(specIdx)
                mod._testState = {
                    animateBars = false,
                    absorbs = s.absorbStyle ~= "none",
                    healAbsorbs = (s.healAbsorbStyle or "clean") ~= "none",
                    healPrediction = s.healPrediction == true,
                    threat = (s.threatBorderSize or 0) > 0
                        or (s.threatCustomBorder == true and mod.RF_CustomBorderOn(s)),
                    reducedMaxHealth = false,
                    dispels = false,
                    debuffs = s.debuffFilter ~= "none",
                    defensives = s.showDefensives or s.showExternals or false,
                    buffs = true,
                    indicators = false,
                }
            end
            local testState = mod._testState

            mod._applyTestState = function()
                local indOn = testState.indicators
                mod._indicatorsVisible = indOn
                -- Indicators suppress every other preview WITHOUT altering testState.
                mod._dispelsVisible = not indOn and testState.dispels
                mod._debuffsPreviewVisible = not indOn and testState.debuffs
                mod._defensivesPreviewVisible = not indOn and testState.defensives
                mod._testReducedMaxHealth = not indOn and testState.reducedMaxHealth
                mod._testAbsorbs = not indOn and testState.absorbs
                mod._testHealAbsorbs = not indOn and testState.healAbsorbs
                mod._testHealPrediction = not indOn and testState.healPrediction
                mod._testThreat = not indOn and testState.threat
                mod._testBuffsVisible = not indOn and testState.buffs
                local wantAnim = not indOn and testState.animateBars
                if wantAnim then
                    if mod._startHealthAnim and not mod._healthAnimActive then
                        mod._startHealthAnim()
                    end
                else
                    if mod._stopHealthAnim and mod._healthAnimActive then
                        mod._stopHealthAnim()
                    end
                end
                -- Restart so debuff/defensive icons hide/show immediately.
                if mod.RestartPvAuraTicker then
                    mod.RestartPvAuraTicker()
                end
                -- Always stop first so re-init picks up new preview frames.
                if mod.StopPvBuffTicker then
                    mod.StopPvBuffTicker()
                end
                local wantBuffs = not indOn and testState.buffs
                if wantBuffs and mod.StartPvBuffTicker then
                    mod.StartPvBuffTicker()
                end
            end

            ---------------------------------------------------------------
            --  HEALTH & POWER BARS
            ---------------------------------------------------------------
            SectionHeader("HEALTH & POWER BARS")

            do
                local _, _, r = CheckboxRow("Animate Bars", function()
                    return testState.animateBars
                end, function(v)
                    testState.animateBars = v
                end, { page = PAGE_MAIN, key = "animateBars" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Absorbs", function()
                    return testState.absorbs
                end, function(v)
                    testState.absorbs = v
                end, { page = PAGE_MAIN, key = "absorbs" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Healing Absorbs", function()
                    return testState.healAbsorbs
                end, function(v)
                    testState.healAbsorbs = v
                end, { page = PAGE_MAIN, key = "healAbsorbs" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Heal Prediction", function()
                    return testState.healPrediction
                end, function(v)
                    testState.healPrediction = v
                end, { page = PAGE_MAIN, key = "healPrediction" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Threat Indicator", function()
                    return testState.threat
                end, function(v)
                    testState.threat = v
                end, { page = PAGE_MAIN, key = "threat" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Reduced Max Health", function()
                    return testState.reducedMaxHealth
                end, function(v)
                    testState.reducedMaxHealth = v
                end, { page = PAGE_MAIN, key = "absorbs" })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            ---------------------------------------------------------------
            --  AURAS
            ---------------------------------------------------------------
            SectionHeader("AURAS")

            do
                local _, _, r = CheckboxRow("Dispels", function()
                    return testState.dispels
                end, function(v)
                    testState.dispels = v
                    mod._applyTestState()
                end, { page = PAGE_MAIN })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Debuffs", function()
                    return testState.debuffs
                end, function(v)
                    testState.debuffs = v
                    mod._applyTestState()
                end, { page = PAGE_DM })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Defensives & Externals", function()
                    return testState.defensives
                end, function(v)
                    testState.defensives = v
                    mod._applyTestState()
                end, { page = PAGE_BUFFS })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            do
                local _, _, r = CheckboxRow("Configured Buffs", function()
                    return testState.buffs
                end, function(v)
                    testState.buffs = v
                    mod._applyTestState()
                end, { page = PAGE_BUFFS })
                nonIndicatorRows[#nonIndicatorRows + 1] = r
            end

            ---------------------------------------------------------------
            --  INDICATORS
            ---------------------------------------------------------------
            SectionHeader("INDICATORS")

            local function SetNonIndicatorRowsEnabled(enabled)
                for _, row2 in ipairs(nonIndicatorRows) do
                    row2:SetAlpha(enabled and 1 or 0.35)
                    row2:EnableMouse(enabled)
                end
            end

            CheckboxRow("Show All", function()
                return testState.indicators
            end, function(v)
                testState.indicators = v
                SetNonIndicatorRowsEnabled(not v)
                mod._applyTestState()
            end, { page = PAGE_MAIN })

            -- Content height plus room for the close button.
            panelFrame:SetHeight(math.abs(cy) + 32 + PAD * 3)

            local closeBtn = CreateFrame("Button", nil, panelFrame)
            closeBtn:SetSize(PANEL_W - PAD * 2, 32)
            closeBtn:SetPoint("BOTTOM", panelFrame, "BOTTOM", 0, PAD)
            closeBtn:SetFrameLevel(panelFrame:GetFrameLevel() + 1)
            local clBg = closeBtn:CreateTexture(nil, "BACKGROUND")
            clBg:SetAllPoints()
            clBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
            local clLbl = MakeFont(closeBtn, 12, 1, 1, 1, 0.7)
            clLbl:SetPoint("CENTER")
            clLbl:SetText(CludesUI.L("Close"))
            closeBtn:SetScript("OnEnter", function()
                clBg:SetColorTexture(0.35, 0.35, 0.35, 0.8)
                clLbl:SetAlpha(1)
            end)
            closeBtn:SetScript("OnLeave", function()
                clBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
                clLbl:SetAlpha(0.7)
            end)
            closeBtn:SetScript("OnClick", CloseTestMode)

            -- Dead space closes.
            testModeFrame:SetScript("OnMouseDown", function()
                local oc = mod._overlayContainer
                if (panelFrame and panelFrame:IsMouseOver()) or (oc and oc:IsMouseOver()) then
                    return
                end
                CloseTestMode()
            end)

            testModeFrame:SetScript("OnKeyDown", function(self, key)
                if InCombatLockdown() then
                    return
                end
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    CloseTestMode()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)
            CludesUI.PopupTakeKeys(testModeFrame, testModeFrame)

            -- Every open starts the sidebar from the look a new one has.
            panelFrame._redress = function(fp, ac)
                for idx = 1, #fonts, 2 do
                    fonts[idx]:SetFont(fp, fonts[idx + 1], "")
                end
                for idx = 1, #checks, 2 do
                    checks[idx]:SetChecked(false)
                    checks[idx + 1]:SetColorTexture(ac.r, ac.g, ac.b, 1)
                end
                for idx = 1, #editParts, 2 do
                    editParts[idx]:SetColorTexture(1, 1, 1, 0.05)
                    editParts[idx + 1]:SetAlpha(1)
                end
                clBg:SetColorTexture(0.25, 0.25, 0.25, 0.6)
                clLbl:SetAlpha(1)
                for _, func in ipairs(allRefreshFns) do
                    func()
                end
                for _, row2 in ipairs(nonIndicatorRows) do
                    row2:SetAlpha(1)
                    row2:EnableMouse(false)
                end
                -- Indicators may already be on from a previous open.
                if testState.indicators then
                    SetNonIndicatorRowsEnabled(false)
                end
                panelFrame:ClearAllPoints()
                panelFrame:SetPoint("LEFT", testModeFrame, "LEFT", 40, 0)
                panelFrame:SetAlpha(1)
                panelFrame:Hide() -- shown once the overlay container is positioned
                panelFrame:SetFrameLevel(testModeFrame:GetFrameLevel() + 5)
            end
            mod._testPanel = panelFrame
        end

        local function OpenTestMode()
            if testModeActive then
                CloseTestMode()
                return
            end
            testModeActive = true
            mod._testMode = true

            local Pix = CludesUI.PanelPP or CludesUI.PP
            local fontFile = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"
            local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
            local s = db.profile

            if not testModeFrame then
                testModeFrame = CreateFrame("Frame", nil, UIParent)
                testModeFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                testModeFrame:SetAllPoints()
                testModeFrame:EnableMouse(true)
                local dimBg = testModeFrame:CreateTexture(nil, "BACKGROUND")
                dimBg:SetAllPoints()
                dimBg:SetColorTexture(0, 0, 0, 0.75)
            end
            testModeFrame:SetFrameLevel(50)
            testModeFrame:SetAlpha(0)
            testModeFrame:Show()

            -- Preview flags are set by ns._applyTestState() below.
            local fadeInAG = testModeFrame._fadeIn
            if not fadeInAG then
                fadeInAG = testModeFrame:CreateAnimationGroup()
                local fadeInA = fadeInAG:CreateAnimation("Alpha")
                fadeInA:SetFromAlpha(0)
                fadeInA:SetToAlpha(1)
                fadeInA:SetDuration(0.3)
                testModeFrame._fadeIn = fadeInAG
            end
            testModeFrame:SetAlpha(1)
            fadeInAG:Play()

            -- Force the preview up; ns._testMode forces overlay mode.
            if mod.HidePreview then
                mod.HidePreview()
            end
            C_Timer.After(0, function()
                if mod.ShowPreview and mod._testMode then
                    mod.ShowPreview()
                    -- Re-apply now that preview frames exist and previewActive is true.
                    if mod._applyTestState then
                        mod._applyTestState()
                    end
                    -- Reanchor + fade in the sidebar once the container is placed.
                    C_Timer.After(0, function()
                        if not mod._testMode then
                            return
                        end
                        local oc = mod._overlayContainer
                        if oc and oc:IsShown() and mod._testPanel then
                            mod._testPanel:ClearAllPoints()
                            mod._testPanel:SetPoint("RIGHT", oc, "LEFT", -20, 0)
                            mod._testPanel:SetAlpha(0)
                            mod._testPanel:Show()
                            mod._testPanel:SetAlpha(1)
                            mod._testPanel._fadeIn:Play()
                        end
                    end)
                end
            end)

            if not mod._testPanel then
                BuildTestPanel(Pix, fontFile, accentColor, s)
            end
            mod._testPanel._redress(fontFile, accentColor)
            mod._applyTestState()
        end

        mod.OpenTestMode = OpenTestMode
        mod.CloseTestMode = CloseTestMode

        -- Test button appears on the tab bar while the RF module is selected.
        local testTabBtn = nil
        if CludesUI.SelectModule then
            hooksecurefunc(CludesUI, "SelectModule", function(_, folderName)
                if folderName == "CludesUIRaidFrames" then
                    local tb = CludesUI._tabBar
                    if not tb or not tb._tabButtons then
                        return
                    end
                    local lastBtn = tb._tabButtons[#tb._tabButtons]
                    if not lastBtn then
                        return
                    end

                    if testTabBtn then
                        -- The tab bar rebuilds on module switch, so re-anchor.
                        testTabBtn:SetParent(tb)
                        testTabBtn:ClearAllPoints()
                        testTabBtn:SetPoint("BOTTOMLEFT", lastBtn, "BOTTOMRIGHT", 6, 0)
                        testTabBtn:Show()
                        return
                    end

                    testTabBtn = CreateFrame("Button", nil, tb)
                    testTabBtn:SetHeight(40)
                    testTabBtn:SetFrameLevel(tb:GetFrameLevel() + 1)

                    local PP2 = CludesUI.PanelPP or CludesUI.PP
                    local labelText = CludesUI.MakeFont(
                        testTabBtn,
                        16,
                        nil,
                        CludesUI.TEXT_DIM_R or 0.65,
                        CludesUI.TEXT_DIM_G or 0.65,
                        CludesUI.TEXT_DIM_B or 0.65,
                        CludesUI.TEXT_DIM_A or 0.65
                    )
                    labelText:SetPoint("CENTER", 0, 0)
                    labelText:SetText(CludesUI.L("Full Preview"))
                    testTabBtn._label = labelText

                    local textW = labelText:GetStringWidth() or 30
                    testTabBtn:SetWidth(textW + 30)
                    testTabBtn:SetPoint("BOTTOMLEFT", lastBtn, "BOTTOMRIGHT", 6, 0)

                    testTabBtn:SetScript("OnEnter", function(self)
                        self._label:SetTextColor(1, 1, 1, 0.86)
                    end)
                    testTabBtn:SetScript("OnLeave", function(self)
                        self._label:SetTextColor(
                            CludesUI.TEXT_DIM_R or 0.65,
                            CludesUI.TEXT_DIM_G or 0.65,
                            CludesUI.TEXT_DIM_B or 0.65,
                            CludesUI.TEXT_DIM_A or 0.65
                        )
                    end)
                    testTabBtn:SetScript("OnClick", function()
                        OpenTestMode()
                    end)
                else
                    if testTabBtn then
                        testTabBtn:Hide()
                    end
                end
            end)
        end

        -- Textured Background: the Health Bar Fill cog's row, shared with Global
        -- Settings > Textures. read(key, default) / write(key, value): the page's own
        -- settings access (the Textures card reads and writes the raid keys).
        local function TexBgRowCfg(read, write)
            local function Dark()
                return read("healthColorMode", "class") == "dark"
            end
            return {
                type = "toggle",
                label = "Textured Background",
                tooltip = "Draws the bar texture on the health and power backgrounds too.",
                disabled = function()
                    if read("healthBarTexture", "atrocity") == "none" then
                        return true
                    end
                    if Dark() then
                        return not mod.RF_TexBgOpaque(nil, true)
                    end
                    return read("healthBarOpacity", 100) < 100
                end,
                disabledTooltip = function()
                    if read("healthBarTexture", "atrocity") == "none" then
                        return "This option requires a Health Bar Texture other than None."
                    end
                    if Dark() then
                        return "This option requires a Dark Mode Fill of 100 (Global Settings > Colors)."
                    end
                    return "This option requires a Fill Opacity of 100."
                end,
                get = function()
                    return read("textureBg", false) == true
                end,
                set = function(v)
                    write("textureBg", v and true or false)
                end,
            }
        end

        -- Shared with the page builders under RaidFrames_Options\ (read in their
        -- prologs). Every field is final here: optState holds the mutable state.
        mod._RFO_OptEnv = {
            TexBgRowCfg = TexBgRowCfg,
            AbbreviateNumbers = AbbreviateNumbers,
            absorbStyleOrder = absorbStyleOrder,
            absorbStyleValues = absorbStyleValues,
            allGrowthOrder = allGrowthOrder,
            BuildPreviewModeRow = BuildPreviewModeRow,
            BuildVisualSections = BuildVisualSections,
            db = db,
            floor = floor,
            growthValues = growthValues,
            groupGrowthOrder = groupGrowthOrder,
            groupGrowthValues = groupGrowthValues,
            hbtOrder = hbtOrder,
            hbtValues = hbtValues,
            healAbsorbStyleOrder = healAbsorbStyleOrder,
            healthColorOrder = healthColorOrder,
            healthColorValues = healthColorValues,
            IsPreviewOff = IsPreviewOff,
            KeepGrowthPerpendicular = KeepGrowthPerpendicular,
            maxHealthStyleOrder = maxHealthStyleOrder,
            MissingGlowDesc = MissingGlowDesc,
            optState = optionState,
            PP = Pix,
            ReadGroupGrowth = ReadGroupGrowth,
            ReloadAndUpdate = ReloadAndUpdate,
            SGet = SGet,
            SGetPx = SGetPx,
            SSet = SSet,
            SVal = SVal,
            SWrite = SWrite,
        }

        ---------------------------------------------------------------------------
        --  Register module
        ---------------------------------------------------------------------------
        local rfSearchTerms = {
            "raid",
            "frames",
            "group",
            "health",
            "power",
            "absorb",
            "shield",
            "debuff",
            "dispel",
            "threat",
            "role",
            "marker",
            "ready",
            "check",
            "border",
            "range",
            "tooltip",
            "layout",
            "spacing",
            "buff",
            "manager",
            "strata",
            "layer",
            "overlap",
            "click",
            "cast",
            "binding",
            "keybind",
            "spell",
            "macro",
            "mouseover",
        }

        -- A dropped manager root waits here, hidden and off the scroll frame, so
        -- the scroll frame only ever holds the root on screen; its next render
        -- dresses it again and puts it back (the options page pool's kept frame).
        local rootPark
        local function ParkRoot(root)
            root:Hide()
            if not rootPark then
                rootPark = CreateFrame("Frame")
                rootPark:Hide()
            end
            root:SetParent(rootPark)
        end

        -- Drops the BM / DM / CC roots (built on the shared scroll frame, not a
        -- page wrapper) except keepPage's: parked, and marked for a render (nil).
        -- Each root is a kept frame of the options page pool, so its next render
        -- dresses the same frame again. popups: true = also hide the Add New,
        -- DM add and BM2 editor popups; "dm" = those DM/BM2 popups only when
        -- the DM root drops. stripAlways: hide the CC spell strip (parented to
        -- the panel, not the CC root; kept for the next build) even with no CC root.
        local function DropManagerRoots(keepPage, popups, stripAlways)
            if popups == true and mod._addNewPopup then
                mod._addNewPopup:Hide()
            end
            if keepPage ~= PAGE_BUFFS and mod._bmRoot then
                ParkRoot(mod._bmRoot)
                mod._bmRoot = nil
            end
            local dropDm = keepPage ~= PAGE_DM and mod._dmRoot
            if popups == true or (popups == "dm" and dropDm) then
                if mod._dmAddPopup then
                    mod._dmAddPopup:Hide()
                end
                if mod._bm2FilterEditor then
                    mod._bm2FilterEditor:Hide()
                    mod._bm2FilterEditor = nil
                end
            end
            if dropDm then
                ParkRoot(mod._dmRoot)
                mod._dmRoot = nil
            end
            local dropCc = keepPage ~= PAGE_CLICKCAST and mod._ccRoot
            if dropCc then
                if mod._ccGridPopup then
                    mod._ccGridPopup:Hide()
                    mod._ccGridPopup = nil
                end
                if mod._ccSpecPopup then
                    mod._ccSpecPopup:Hide()
                    mod._ccSpecPopup = nil
                end
                if mod._ccQBPopup then
                    mod._ccQBPopup:Hide()
                    mod._ccQBPopup = nil
                end
                -- (The Quickbind popup's hide renders the page again, which sets
                -- ns._ccRoot anew: read it after the popups.)
                if mod._ccRoot then
                    ParkRoot(mod._ccRoot)
                    mod._ccRoot = nil
                end
            end
            if (dropCc or stripAlways) and mod._ccSpellStrip then
                mod._ccSpellStrip:Hide()
            end
        end

        -- A manager root's deferred build runs only while its page still shows: a
        -- deep link opens this module on its last page and moves on in one click.
        local function RFPageShown(page)
            return CludesUI:GetActiveModule() == "CludesUIRaidFrames" and CludesUI:GetActivePage() == page
        end

        local function WithStack(err)
            return tostring(err) .. "\n" .. debugstack(2)
        end
        local function RestorePartyCtx(saved, success, ...)
            optionState._partyCtx = saved
            if not success then
                error((...), 0)
            end
            return ...
        end

        CludesUI:RegisterModule("CludesUIRaidFrames", {
            title = "Raid & Party Frames",
            description = "Configure raid and party frame appearance and behavior.",
            -- No Auras page: debuffs and defensives/externals live in the managers.
            pages = { PAGE_MAIN, PAGE_PARTY, PAGE_BUFFS, PAGE_DM, PAGE_CLICKCAST },
            -- Module-scoped: "Frames" is a generic page name another module could use.
            tabLabels = { [PAGE_MAIN] = "Raid" },
            -- The managers draw over the scroll frame: no inline search there.
            noSearchPages = { [PAGE_BUFFS] = true, [PAGE_DM] = true, [PAGE_CLICKCAST] = true },
            searchTerms = rfSearchTerms,
            buildPage = function(pageName, hostFrame, yOffset)
                -- The cleanup/preview logic below acts on live state (BM/CC roots, raid/party preview overlays over the player's real frames) keyed only on the pageName being built, not what the player is actually looking at. An off-screen search pre-build cycles pageName through every page in `pages`, so NONE of it may run here.
                -- PAGE_BUFFS / PAGE_CLICKCAST go further: their builders (BuildBuffManagerPage -> ns.BM_BuildPage, ns.CC_BuildPage) bypass `parent` and build directly onto the live shared CludesUI._scrollFrame, so building them here would inject visible UI over whatever is on screen. Skip them; they index normally on the player's first live visit.
                --
                -- The pre-build must not leave the live page's _partyCtx changed.
                if CludesUI._prebuilding then
                    if pageName == PAGE_MAIN or pageName == PAGE_PARTY then
                        local saved = optionState._partyCtx
                        optionState._partyCtx = (pageName == PAGE_PARTY)
                        local build = (pageName == PAGE_PARTY) and mod.RFO_BuildPartyPage
                            or mod.RFO_BuildMainPage
                        return RestorePartyCtx(saved, xpcall(build, WithStack, pageName, hostFrame, yOffset))
                    end
                    return
                end
                -- Drop the BM / DM / CC roots when switching away.
                DropManagerRoots(pageName)
                if pageName == PAGE_MAIN then
                    local mode = db.profile.previewMode or "overlay"
                    -- Skip-restore keeps real party frames hidden under the preview so they don't flash on return to the party tab; restore only for "none", where real frames are meant to be visible.
                    if mod.HidePartyPreview then
                        mod.HidePartyPreview(mode ~= "none")
                    end
                    if mode ~= "none" and mod.ShowPreview then
                        C_Timer.After(0, function()
                            if mod.ShowPreview then
                                mod.ShowPreview()
                            end
                        end)
                    elseif mode == "none" and mod.HidePreview then
                        mod.HidePreview()
                    end
                elseif pageName == PAGE_PARTY then
                    local mode = db.profile.previewMode or "overlay"
                    -- Skip-restore avoids a one-frame flash of the real frames before the deferred ShowPartyPreview.
                    if mod.HidePreview then
                        mod.HidePreview(mode ~= "none")
                    end
                    if mode ~= "none" and mod.ShowPartyPreview then
                        C_Timer.After(0, function()
                            if mod.ShowPartyPreview then
                                mod.ShowPartyPreview()
                            end
                        end)
                    elseif mode == "none" and mod.HidePartyPreview then
                        mod.HidePartyPreview()
                    end
                else
                    -- BUFFS / CLICKCAST show no preview, so FULL restore both real containers: a skip-restore here would strand the party container under the hidden preview parent with nothing to reparent it back.
                    if mod.HidePreview then
                        mod.HidePreview()
                    end
                    if mod.HidePartyPreview then
                        mod.HidePartyPreview()
                    end
                end
                -- Set party context BEFORE building any page so SGet/SSet/SVal read the correct keys during widget construction.
                optionState._partyCtx = (pageName == PAGE_PARTY)

                if pageName == PAGE_MAIN then
                    return mod.RFO_BuildMainPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_PARTY then
                    return mod.RFO_BuildPartyPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_DM then
                    if mod.DMP_BuildPage then
                        return mod.DMP_BuildPage(pageName, hostFrame, yOffset)
                    end
                    return math.abs(yOffset)
                elseif pageName == PAGE_BUFFS then
                    return BuildBuffManagerPage(pageName, hostFrame, yOffset)
                elseif pageName == PAGE_CLICKCAST then
                    if mod.CC_BuildPage then
                        return mod.CC_BuildPage(pageName, hostFrame, yOffset)
                    end
                    return math.abs(yOffset)
                end
            end,
            onPageCacheRestore = function(pageName)
                -- Mirrors buildPage's root cleanup: fires INSTEAD of buildPage when the target page is already cached.
                -- Without it, switching from Buffs/HoverCast to a cached page never hides ns._bmRoot/ns._ccRoot, which are built onto the shared live scroll frame (not a per-page wrapper) and would stay stuck over the restored page.
                DropManagerRoots(pageName)
                -- Presets, spec changes and profile switches can alter the text list
                -- while the page is cached (CUI_RaidFrames_TextDisplay_Options.lua).
                local textCheck = mod._rfTextChecks and mod._rfTextChecks[pageName]
                if textCheck and textCheck() then
                    C_Timer.After(0, function()
                        if RFPageShown(pageName) then
                            CludesUI:RefreshPage(true)
                        end
                    end)
                end
                if pageName == PAGE_MAIN then
                    local mode = db.profile.previewMode or "overlay"
                    -- Skip-restore; see buildPage.
                    if mod.HidePartyPreview then
                        mod.HidePartyPreview(mode ~= "none")
                    end
                    if mode ~= "none" and mod.ShowPreview then
                        C_Timer.After(0, function()
                            if mod.ShowPreview then
                                mod.ShowPreview()
                            end
                        end)
                    elseif mode == "none" and mod.HidePreview then
                        mod.HidePreview()
                    end
                elseif pageName == PAGE_PARTY then
                    local mode = db.profile.previewMode or "overlay"
                    -- Skip-restore avoids a one-frame flash of the real frames before the deferred ShowPartyPreview.
                    if mod.HidePreview then
                        mod.HidePreview(mode ~= "none")
                    end
                    if mode ~= "none" and mod.ShowPartyPreview then
                        C_Timer.After(0, function()
                            if mod.ShowPartyPreview then
                                mod.ShowPartyPreview()
                            end
                        end)
                    elseif mode == "none" and mod.HidePartyPreview then
                        mod.HidePartyPreview()
                    end
                elseif pageName == PAGE_BUFFS then
                    if mod.HidePreview then
                        mod.HidePreview()
                    end
                    if mod.HidePartyPreview then
                        mod.HidePartyPreview()
                    end
                    if not mod._bmRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(pageName) then
                                BuildBuffManagerPage(pageName, nil, -6)
                            end
                        end)
                    end
                elseif pageName == PAGE_DM then
                    if mod.HidePreview then
                        mod.HidePreview()
                    end
                    if mod.HidePartyPreview then
                        mod.HidePartyPreview()
                    end
                    if not mod._dmRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(PAGE_DM) and mod.DMP_BuildPage then
                                mod.DMP_BuildPage(PAGE_DM, nil, -6)
                            end
                        end)
                    end
                elseif pageName == PAGE_CLICKCAST then
                    if mod.HidePreview then
                        mod.HidePreview()
                    end
                    if not mod._ccRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(PAGE_CLICKCAST) and mod.CC_BuildPage then
                                mod.CC_BuildPage(PAGE_CLICKCAST, nil, -6)
                            end
                        end)
                    end
                end
            end,
            onReset = function()
                -- Clearing the first-install flag re-captures position on reload.
                if db.sv then
                    db.sv._capturedOnce_RF = nil
                end
                db:ResetProfile()
                -- No reload here: Reset CUI Module Settings reloads after this returns.
            end,
            -- Tears down all 6 Raid Frames preview mechanisms on cross-module
            -- switch (Real/Party/Size/HealthAnim/PowerAnim/HM previews).
            onModuleLeave = function()
                if mod.HidePreview then
                    mod.HidePreview()
                end
                if mod.HidePartyPreview then
                    mod.HidePartyPreview()
                end
                mod._sizePreviewTier = nil
                if mod._HideSizePreview then
                    mod._HideSizePreview()
                end
                if mod._healthAnimActive and mod.StopHealthAnim then
                    mod.StopHealthAnim()
                end
                if mod._powerAnimActive and mod.StopPowerAnim then
                    mod.StopPowerAnim()
                end
                if mod._hmPreview and mod.HM_SetPreview then
                    mod.HM_SetPreview(false)
                end
            end,
        })

        -- Re-open on an RF page: show preview / rebuild BM.
        CludesUI:RegisterOnShow(function()
            if CludesUI:GetActiveModule() == "CludesUIRaidFrames" then
                local page = CludesUI:GetActivePage()
                if page == PAGE_MAIN then
                    local mode = db.profile.previewMode or "overlay"
                    if mode ~= "none" and mod.ShowPreview then
                        mod.ShowPreview()
                    end
                elseif page == PAGE_PARTY then
                    local mode = db.profile.previewMode or "overlay"
                    if mode ~= "none" and mod.ShowPartyPreview then
                        mod.ShowPartyPreview()
                    end
                elseif page == PAGE_BUFFS then
                    -- Panel opening on Buffs counts as entering it (WoW Forever: All Specs).
                    mod.BM_EnterAllSpecs()
                    if not mod._bmRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(PAGE_BUFFS) then
                                BuildBuffManagerPage(PAGE_BUFFS, nil, -6)
                            end
                        end)
                    end
                elseif page == PAGE_DM then
                    if not mod._dmRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(PAGE_DM) and mod.DMP_BuildPage then
                                mod.DMP_BuildPage(PAGE_DM, nil, -6)
                            end
                        end)
                    end
                elseif page == PAGE_CLICKCAST then
                    if not mod._ccRoot then
                        C_Timer.After(0, function()
                            if RFPageShown(PAGE_CLICKCAST) and mod.CC_BuildPage then
                                mod.CC_BuildPage(PAGE_CLICKCAST, nil, -6)
                            end
                        end)
                    end
                end
            end
        end)
        -- Panel close: hide preview and clean up BM/CC.
        if CludesUI.RegisterOnHide then
            CludesUI:RegisterOnHide(function()
                if mod._rfEyeHintTip then
                    mod._rfEyeHintTip:Hide()
                end
                -- HARD INVARIANT against "frames vanish after closing options": both real containers get reparented to UIParent and their visibility recomputed even if a skip-restore tab swap or a post-close deferred ShowPreview orphaned one under the hidden preview parent.
                -- Self-defers to PLAYER_REGEN_ENABLED in combat.
                if mod.EnsureRealFramesRestored then
                    mod.EnsureRealFramesRestored()
                end
                if mod._sizePreviewTier then
                    mod._sizePreviewTier = nil
                    if mod._HideSizePreview then
                        mod._HideSizePreview()
                    end
                end
                -- BM root + Add New popup: the popup is DIALOG strata and otherwise persists after close.
                DropManagerRoots(nil, true, true)
            end)
        end

        -- HideAllChildren callback: BM/CC intentionally bypass the scroll child, so their scrollFrame-parented roots need explicit cleanup.
        -- Registered beside the other modules' scroll-root hiders (never in place of them).
        local function HideManagerRoots()
            DropManagerRoots(nil, true, true)
        end
        CludesUI._AddScrollRootHider(HideManagerRoots)

        -- Module switch: drop the BM/CC roots and hide the preview.
        if CludesUI.SelectModule then
            hooksecurefunc(CludesUI, "SelectModule", function(_, folderName)
                if folderName ~= "CludesUIRaidFrames" then
                    if mod._rfEyeHintTip then
                        mod._rfEyeHintTip:Hide()
                    end
                    -- Tear down previews and guarantee the real containers return to UIParent, including the orphaned-flag-false cases.
                    if mod.EnsureRealFramesRestored then
                        mod.EnsureRealFramesRestored()
                    end
                    DropManagerRoots(nil, true)
                end
            end)
        end

        -- Party Frames search excludes raid-synced sections (their controls live on the Raid tabs). Maps section HEADER TEXT to sync key:
        -- KEEP IN SYNC with the SectionHeader names in the builders and ns._PARTY_SECTION_ORDER.
        mod._PARTY_SEARCH_SECTION_KEY = {
            ["HEALTH BAR"] = "healthBar",
            ["ABSORBS"] = "absorbs",
            ["POWER BAR"] = "powerBar",
            ["TEXT DISPLAY"] = "textDisplay",
            ["INDICATORS"] = "indicators",
            ["DISPELS"] = "dispels",
            ["TOP NAME BAR"] = "topNameBar",
            ["EXTRAS"] = "rangeTooltip",
        }
        mod._PartySearchExclude = function(sectionName)
            local key = mod._PARTY_SEARCH_SECTION_KEY[sectionName]
            if not key then
                return false
            end
            if not db or not db.profile then
                return false
            end
            local ss = db.profile.partySyncSections
            return (not ss) or ss[key] ~= false -- synced (default = all synced)
        end

        -- Party sync overlays track the inline search: hidden while a search is active (those sections are excluded), restored to their per-section sync state when empty. Overlays carry _searchIgnore so the generic search never re-anchors them.
        mod._PartySearchOverlaySync = function(query)
            if not mod._syncOverlays then
                return
            end
            local searching = query and query ~= ""
            local ss = db and db.profile and db.profile.partySyncSections
            for key, shade in pairs(mod._syncOverlays) do
                if searching then
                    shade:Hide()
                elseif (not ss) or ss[key] ~= false then
                    shade:Show()
                else
                    shade:Hide()
                end
            end
        end

        -- The eye refreshers (ns._eye[ctx]) of the preview effects a tab change turns off.
        local TAB_RESET_EYES = {
            "refreshHealthEye",
            "refreshPowerEye",
            "refreshAbsorbEye",
            "refreshIndicatorEye",
            "refreshDispelEye",
        }

        -- Page switch cleanup within RF. PRE-hook (wrap, not hooksecurefunc): _partyCtx must be set BEFORE SelectPage refreshes widget values.
        if CludesUI.SelectPage then
            local origSelectPage = CludesUI.SelectPage
            CludesUI.SelectPage = function(self, pageName, ...)
                optionState._partyCtx = (pageName == PAGE_PARTY)
                -- Entering Buffs from another page (not a rebuild while on it): WoW Forever opens it on All Specs.
                if pageName == PAGE_BUFFS and CludesUI:GetActivePage() ~= PAGE_BUFFS then
                    mod.BM_EnterAllSpecs()
                end
                -- Party tab excludes synced sections from inline search; cleared on every other page (any module) so the hook can never leak.
                CludesUI._searchExcludeSection = (pageName == PAGE_PARTY) and mod._PartySearchExclude or nil
                CludesUI._onInlineSearch = (pageName == PAGE_PARTY) and mod._PartySearchOverlaySync or nil
                local result = origSelectPage(self, pageName, ...)
                -- Re-sync overlays on entering the party tab: a prior search may have hidden them, and the search box clears on page change.
                if pageName == PAGE_PARTY and mod._PartySearchOverlaySync then
                    mod._PartySearchOverlaySync("")
                end
                if mod._rfEyeHintTip then
                    if pageName == PAGE_MAIN then
                        mod._rfEyeHintTip:Show()
                    else
                        mod._rfEyeHintTip:Hide()
                    end
                end
                -- Every eyeball toggle resets on tab change.
                mod._indicatorsVisible = false
                mod._dispelsVisible = false
                mod._defensivesPreviewVisible = false
                mod._debuffsPreviewVisible = false
                mod._absorbsPreviewVisible = false
                -- The health/power tickers live on ns, so one cancel covers whichever preview built them.
                mod._healthAnimActive = false
                mod._powerAnimActive = false
                if mod._healthAnimTicker then
                    mod._healthAnimTicker:Cancel()
                    mod._healthAnimTicker = nil
                end
                if mod._powerAnimTicker then
                    mod._powerAnimTicker:Cancel()
                    mod._powerAnimTicker = nil
                end
                -- Each tab's latest eyes show the reset too (a page shown from the
                -- cache keeps the icons it last painted).
                local eyes = mod._eye
                if eyes then
                    for _, eye in pairs(eyes) do
                        for idx = 1, #TAB_RESET_EYES do
                            local refresh = eye[TAB_RESET_EYES[idx]]
                            if refresh then
                                refresh()
                            end
                        end
                    end
                end
                mod._bmFrameEffectsVisible = false
                if mod.RestartPvAuraTicker then
                    mod.RestartPvAuraTicker()
                end
                if mod.ResetPreviewRandomization then
                    mod.ResetPreviewRandomization()
                end

                -- Manager/HoverCast tabs show no raid frame preview.
                if pageName == PAGE_BUFFS or pageName == PAGE_DM or pageName == PAGE_CLICKCAST then
                    if mod.HidePreview then
                        mod.HidePreview()
                    end
                end
                if pageName == PAGE_MAIN then
                    local mode = db.profile.previewMode or "overlay"
                    if mode ~= "none" and mod.ShowPreview then
                        C_Timer.After(0, function()
                            if mod.ShowPreview then
                                mod.ShowPreview()
                            end
                        end)
                    end
                end
                -- Drop the BM / DM / CC roots when switching away.
                DropManagerRoots(pageName, "dm")
                return result
            end
        end

        ---------------------------------------------------------------------------
        --  Slash command
        ---------------------------------------------------------------------------
        SLASH_CLUDESRAIDFRAMES1 = "/crf"
        SlashCmdList.CLUDESRAIDFRAMES = function(msg)
            if InCombatLockdown and InCombatLockdown() then
                print("Cannot open options in combat")
                return
            end
            if msg == "reset" then
                -- The reload first (RequestReload); the reset lands before it.
                CludesUI.RequestReload()
                db:ResetProfile()
                return
            end
            CludesUI:ShowModule("CludesUIRaidFrames")
        end
    end -- ns._InitCUIModule

    -- SetupOptionsPanel may already have run before PLAYER_LOGIN.
    if mod.db then
        mod._InitCUIModule()
    end
end)
