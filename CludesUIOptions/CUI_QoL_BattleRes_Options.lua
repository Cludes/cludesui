if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL_BattleRes_Options.lua
--  Options page for the BattleRes icon (registered under CludesUIQoL).
-------------------------------------------------------------------------------

if not CludesUI._ModuleNS["CludesUIQoL"] then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

local function DB()
    local func = _G._CUI_BattleRes_DB
    return func and func() or nil
end

local function P()
    local d = DB()
    return d and d.profile and d.profile.battleRes
end

local function Cfg(key, fallback)
    local p = P()
    if not p then
        return fallback
    end
    if p[key] == nil then
        return fallback
    end
    return p[key]
end

local function Set(key, val)
    local p = P()
    if p then
        p[key] = val
    end
end

local function Refresh()
    if _G._CUI_BattleRes_Apply then
        _G._CUI_BattleRes_Apply()
    end
end
-- Row setters over Set: the key written with the row's value, then Refresh() for the Then form.
local function SetRowThen(key)
    return function(value)
        Set(key, value)
        Refresh()
    end
end

local SHAPE_VALUES = {
    none = "None",
    cropped = "Cropped",
    square = "Square",
    circle = "Circle",
    csquare = "Curved Square",
    diamond = "Diamond",
    hexagon = "Hexagon",
    portrait = "Portrait",
    shield = "Shield",
}
local SHAPE_ORDER =
    { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }

-- Border Size as a 0-4 pixel slider over the stored word (none..strong): the
-- border is solid only, so the step is the pixel count. It writes the same
-- word the dropdown wrote and only on a real change, so a Bloodlust value that
-- inherits Battle Res (nil) keeps inheriting while the slider merely shows it.
-- get/set/refresh are the page's accessors (Cfg/Set/Refresh or the BL_ trio).
local function BorderSizeSliderCfg(get, set, refresh, disabled, disabledTooltip)
    return {
        type = "slider",
        text = "Border Size",
        min = 0,
        max = 4,
        step = 1,
        disabled = disabled,
        disabledTooltip = disabledTooltip,
        getValue = function()
            return CludesUI.BORDER_STEP_OF_LABEL[get("borderSize") or "thin"] or 1
        end,
        setValue = function(val)
            local word = CludesUI.BORDER_LABEL_OF_STEP[math.floor(val + 0.5)] or "thin"
            if word == (get("borderSize") or "thin") then
                return
            end
            set("borderSize", word)
            refresh()
        end,
    }
end

local VIS_VALUES = {
    MPLUS_AND_RAID = "M+ and Raid",
    MPLUS = "M+",
    RAID = "Raid",
    NEVER = "Never",
}
local VIS_ORDER = { "MPLUS_AND_RAID", "MPLUS", "RAID", "NEVER" }

local function MakeBorderColorSwatches()
    return {
        {
            tooltip = "Custom Color",
            hasAlpha = false,
            getValue = function()
                local color = Cfg("borderColor")
                if color then
                    return color.r or 0, color.g or 0, color.b or 0
                end
                return 0, 0, 0
            end,
            setValue = function(red, green, blue)
                Set("borderColor", { r = red, g = green, b = blue, a = 1 })
                Refresh()
            end,
            onClick = function(self)
                if Cfg("borderUseClass") then
                    Set("borderUseClass", false)
                    Refresh()
                    CludesUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then
                    self._eabOrigClick(self)
                end
            end,
            refreshAlpha = function()
                if Cfg("enabled") == false or Cfg("visibility") == "NEVER" then
                    return 0.15
                end
                return Cfg("borderUseClass") and 0.3 or 1
            end,
        },
        {
            tooltip = "Class Colored",
            hasAlpha = false,
            getValue = function()
                local _, ct = UnitClass("player")
                local classColor = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                if classColor then
                    return classColor.r, classColor.g, classColor.b
                end
                return 1, 1, 1
            end,
            setValue = function() end,
            onClick = function()
                Set("borderUseClass", true)
                Refresh()
                CludesUI:RefreshPage()
            end,
            refreshAlpha = function()
                if Cfg("enabled") == false or Cfg("visibility") == "NEVER" then
                    return 0.15
                end
                return Cfg("borderUseClass") and 1 or 0.3
            end,
        },
    }
end

-- Text display mode ("2 | 4:14"): shared predicates + swatches for the
-- Display Style controls.
local function TextModeOn()
    return (Cfg("displayMode") or "icon") == "text"
end

local ICON_ROWS_TIP = "This option requires Display Style to be set to Icon"
local TEXT_ROWS_TIP = "This option requires Display Style to be set to Text"

-- Settings cog holding one toggle, placed left of the row region's inline
-- controls (same shape as the Skip Cinematics cog). offFn greys and blocks
-- it; offReq is the DisabledTooltip requirement shown while blocked.
local function AttachToggleCog(region, title, labelText, get, set, offFn, offReq)
    CludesUI.BuildInlineCog(region, {
        title = title,
        gap = 9,
        rows = { { type = "toggle", label = labelText, get = get, set = set } },
        disabled = offFn,
        disabledTooltip = offReq,
    })
end

local function BuildBattleResPage(page, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PP
    local cursorY = yOffset
    local _, height, row

    if CludesUI.ClearContentHeader then
        CludesUI:ClearContentHeader()
    end
    hostFrame._showRowDivider = true

    -- -- BATTLE RES ----------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "BATTLE RES", cursorY)
    cursorY = cursorY - height

    -- Enable + Icon Size
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Enable BattleRes Icon",
        values = VIS_VALUES,
        order = VIS_ORDER,
        getValue = function()
            return Cfg("visibility") or "MPLUS_AND_RAID"
        end,
        setValue = function(val)
            Set("visibility", val)
            Refresh()
            CludesUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Icon Size",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
        min = 16,
        max = 120,
        step = 1,
        isPercent = false,
        getValue = function()
            return Cfg("iconSize") or 40
        end,
        setValue = SetRowThen("iconSize"),
    })
    cursorY = cursorY - height

    -- Shape | Border Color
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Icon Shape",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
        values = SHAPE_VALUES,
        order = SHAPE_ORDER,
        getValue = function()
            return Cfg("shape") or "none"
        end,
        setValue = SetRowThen("shape"),
    }, {
        type = "multiSwatch",
        text = "Border Color",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
        swatches = MakeBorderColorSwatches(),
    })
    cursorY = cursorY - height

    -- Border Size | Icon Zoom
    row, height = W:DualRow(
        hostFrame,
        cursorY,
        BorderSizeSliderCfg(Cfg, Set, Refresh, function()
            return Cfg("visibility") == "NEVER"
        end, "BattleRes Icon"),
        {
            type = "slider",
            text = "Icon Zoom",
            disabled = function()
                if Cfg("visibility") == "NEVER" then
                    return true
                end
                local s = Cfg("shape") or "none"
                return s ~= "none" and s ~= "cropped"
            end,
            disabledTooltip = function()
                if Cfg("visibility") == "NEVER" then
                    return "BattleRes Icon"
                end
                return "This option requires Icon Shape to be set to None or Cropped"
            end,
            min = 0,
            max = 20,
            step = 0.5,
            isPercent = false,
            getValue = function()
                return Cfg("iconZoom") or 11
            end,
            setValue = SetRowThen("iconZoom"),
        }
    )
    cursorY = cursorY - height

    -- Duration Size | Count Size, each with inline cog (X/Y offsets)
    row, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Duration Size",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
        min = 8,
        max = 30,
        step = 1,
        isPercent = false,
        getValue = function()
            return Cfg("durationSize") or 12
        end,
        setValue = SetRowThen("durationSize"),
    }, {
        type = "slider",
        text = "Count Size",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
        min = 8,
        max = 20,
        step = 1,
        isPercent = false,
        getValue = function()
            return Cfg("countSize") or 11
        end,
        setValue = SetRowThen("countSize"),
    })
    cursorY = cursorY - height

    -- Inline RESIZE cogs on Duration Size (left) and Count Size (right): X/Y offsets
    do
        local function _attachOffsetCog(region, popupTitle, xKey, yKey)
            CludesUI.BuildInlineCog(region, {
                title = popupTitle,
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return Cfg(xKey) or 0
                        end,
                        set = function(val)
                            Set(xKey, val)
                            Refresh()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -50,
                        max = 50,
                        step = 1,
                        get = function()
                            return Cfg(yKey) or 0
                        end,
                        set = function(val)
                            Set(yKey, val)
                            Refresh()
                        end,
                    },
                },
                gap = 6,
                chain = false,
                disabled = function()
                    return Cfg("visibility") == "NEVER"
                end,
            })
        end
        _attachOffsetCog(row._leftRegion, "Duration Position", "durationOffsetX", "durationOffsetY")
        _attachOffsetCog(row._rightRegion, "Count Position", "countOffsetX", "countOffsetY")
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    hostFrame:SetHeight(math.abs(cursorY - yOffset))
end

_G._CUI_BuildBattleResPage = BuildBattleResPage

-- Live preview hidden per tracker for this session only (a preview toggle is
-- never saved): shown again after a /reload.
local previewHidden = {}
local function PreviewHidden(key)
    return previewHidden[key] == true
end
local function SetPreviewHidden(key, hidden)
    previewHidden[key] = hidden or nil
end

-- Inline eye left of a row's control: shows/hides that tracker's live preview.
local function AttachPreviewEye(region, key, showTip, hideTip, setOwner, ownerFrame)
    local EYE_VISIBLE = CludesUI.EYE_VISIBLE_ICON
    local EYE_INVISIBLE = CludesUI.EYE_INVISIBLE_ICON
    local eyeButton, eyeTex = CludesUI.NewInlineEye(region)
    local function RefreshEye()
        eyeTex:SetTexture(PreviewHidden(key) and EYE_VISIBLE or EYE_INVISIBLE)
    end
    RefreshEye()
    eyeButton:SetScript("OnClick", function(self)
        SetPreviewHidden(key, not PreviewHidden(key))
        RefreshEye()
        local func = _G[setOwner]
        if func then
            func((not PreviewHidden(key)) and ownerFrame or nil)
        end
        if self:IsMouseOver() then
            self:GetScript("OnEnter")(self)
        end
    end)
    eyeButton:SetScript("OnEnter", function(self)
        CludesUI.SetGlyphAlpha(self, 0.7)
        CludesUI.ShowWidgetTooltip(self, PreviewHidden(key) and showTip or hideTip)
    end)
    eyeButton:SetScript("OnLeave", function(self)
        CludesUI.SetGlyphAlpha(self, 0.4)
        CludesUI.HideWidgetTooltip()
    end)
end

-- Section-only builder for embedding in the Keys, Logs & Brez tab.
-- Returns total height consumed.
_G._CUI_BuildBattleResSection = function(hostFrame, yOffset, W, Pix)
    local cursorY = yOffset
    local _, height, row, heading

    heading, height = W:SectionHeader(hostFrame, "BATTLE RES", cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_BattleRes",
        disabled = function()
            return Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "BattleRes Icon",
    })

    -- Live preview: forces the icon on screen for as long as this page is (mirrors
    -- the Bloodlust Tracker section below). PollCharges falls back to stand-in
    -- charge data wherever the brez pool reports none, so it previews from anywhere.
    -- The OnSHOW hook is what makes revisits work: the options panel caches built
    -- pages and re-shows the wrapper without re-running this builder, so without it
    -- the preview would arm on the first visit only.
    if not CludesUI._prebuilding and _G._CUI_BattleRes_SetPreviewOwner then
        _G._CUI_BattleRes_SetPreviewOwner((not PreviewHidden("brez")) and hostFrame or nil)
        if not hostFrame._brPreviewHooked then
            hostFrame._brPreviewHooked = true
            hostFrame:HookScript("OnShow", function()
                if _G._CUI_BattleRes_SetPreviewOwner then
                    _G._CUI_BattleRes_SetPreviewOwner((not PreviewHidden("brez")) and hostFrame or nil)
                end
            end)
            hostFrame:HookScript("OnHide", function()
                if _G._CUI_BattleRes_UpdateVisibility then
                    _G._CUI_BattleRes_UpdateVisibility()
                end
            end)
        end
    end

    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Enable BattleRes Icon",
        values = VIS_VALUES,
        order = VIS_ORDER,
        getValue = function()
            return Cfg("visibility") or "MPLUS_AND_RAID"
        end,
        -- DependentSetValue: the rows below Row 1 are hidden while Never;
        -- only the Never <-> shown flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return Cfg("visibility") ~= "NEVER"
        end, function(val)
            Set("visibility", val)
            Refresh()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "slider",
        text = "Icon Size",
        disabled = function()
            return Cfg("visibility") == "NEVER" or TextModeOn()
        end,
        disabledTooltip = function()
            if Cfg("visibility") == "NEVER" then
                return "BattleRes Icon"
            end
            return ICON_ROWS_TIP
        end,
        min = 16,
        max = 120,
        step = 1,
        isPercent = false,
        getValue = function()
            return Cfg("iconSize") or 40
        end,
        setValue = SetRowThen("iconSize"),
    })
    cursorY = cursorY - height

    -- Rows below are HIDDEN entirely while the icon is set to Never (the
    -- dropdown's DependentSetValue forces the rebuild on flips).
    if Cfg("visibility") ~= "NEVER" then
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Icon Shape",
            disabled = TextModeOn,
            disabledTooltip = ICON_ROWS_TIP,
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            getValue = function()
                return Cfg("shape") or "none"
            end,
            setValue = SetRowThen("shape"),
        }, {
            type = "multiSwatch",
            text = "Border Color",
            disabled = TextModeOn,
            disabledTooltip = ICON_ROWS_TIP,
            swatches = MakeBorderColorSwatches(),
        })
        if not CludesUI._prebuilding then
            AttachPreviewEye(
                row._leftRegion,
                "brez",
                "Show Battle Res preview",
                "Hide Battle Res preview",
                "_CUI_BattleRes_SetPreviewOwner",
                hostFrame
            )
        end
        cursorY = cursorY - height

        row, height =
            W:DualRow(hostFrame, cursorY, BorderSizeSliderCfg(Cfg, Set, Refresh, TextModeOn, ICON_ROWS_TIP), {
                type = "slider",
                text = "Icon Zoom",
                disabled = function()
                    if TextModeOn() then
                        return true
                    end
                    local s = Cfg("shape") or "none"
                    return s ~= "none" and s ~= "cropped"
                end,
                disabledTooltip = function()
                    if TextModeOn() then
                        return ICON_ROWS_TIP
                    end
                    return "This option requires Icon Shape to be set to None or Cropped"
                end,
                min = 0,
                max = 20,
                step = 0.5,
                isPercent = false,
                getValue = function()
                    return Cfg("iconZoom") or 11
                end,
                setValue = SetRowThen("iconZoom"),
            })
        cursorY = cursorY - height

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Duration Size",
            disabled = TextModeOn,
            disabledTooltip = ICON_ROWS_TIP,
            min = 8,
            max = 30,
            step = 1,
            isPercent = false,
            getValue = function()
                return Cfg("durationSize") or 12
            end,
            setValue = SetRowThen("durationSize"),
        }, {
            type = "slider",
            text = "Count Size",
            disabled = TextModeOn,
            disabledTooltip = ICON_ROWS_TIP,
            min = 8,
            max = 20,
            step = 1,
            isPercent = false,
            getValue = function()
                return Cfg("countSize") or 11
            end,
            setValue = SetRowThen("countSize"),
        })
        cursorY = cursorY - height

        do
            local function _attachOffsetCog(region, popupTitle, xKey, yKey)
                CludesUI.BuildInlineCog(region, {
                    title = popupTitle,
                    rows = {
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return Cfg(xKey) or 0
                            end,
                            set = function(val)
                                Set(xKey, val)
                                Refresh()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return Cfg(yKey) or 0
                            end,
                            set = function(val)
                                Set(yKey, val)
                                Refresh()
                            end,
                        },
                    },
                    gap = 6,
                    chain = false,
                    disabled = TextModeOn,
                })
            end
            _attachOffsetCog(row._leftRegion, "Duration Position", "durationOffsetX", "durationOffsetY")
            _attachOffsetCog(row._rightRegion, "Count Position", "countOffsetX", "countOffsetY")
        end

        -- Display Style (icon vs text) + text-mode appearance. The count / timer
        -- color swatches sit inline on the dropdown, disabled outside text mode.
        local dispRow
        dispRow, height = W:DualRow(hostFrame, cursorY, {
            type = "segmented",
            text = "Display Style",
            tooltip = "Show the tracker as the Rebirth icon or as a compact text line with charges and time until the next one.",
            values = { icon = "Icon", text = "Text" },
            order = { "icon", "text" },
            getValue = function()
                return Cfg("displayMode") or "icon"
            end,
            setValue = function(val)
                Set("displayMode", val)
                Refresh()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Text Size",
            disabled = function()
                return not TextModeOn()
            end,
            disabledTooltip = TEXT_ROWS_TIP,
            min = 8,
            max = 40,
            step = 1,
            isPercent = false,
            getValue = function()
                return Cfg("textSize") or 14
            end,
            setValue = SetRowThen("textSize"),
        })
        cursorY = cursorY - height

        if not CludesUI._prebuilding then
            local region = dispRow._leftRegion
            -- Builds one inline color swatch with the blocking-overlay disabled
            -- state (interactive only while Display Style is Text). Anchored
            -- right-to-left so the visual order matches the "2 | 4:14" line.
            local function MakeInlineTextSwatch(colorKey, tipText, anchorTo)
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local color = Cfg(colorKey)
                        if color then
                            return color.r or 1, color.g or 1, color.b or 1
                        end
                        return 1, 1, 1
                    end,
                    function(red, green, blue)
                        Set(colorKey, { r = red, g = green, b = blue })
                        Refresh()
                    end,
                    nil,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", anchorTo, "LEFT", -8, 0)
                colorSwatch:HookScript("OnEnter", function()
                    if TextModeOn() then
                        CludesUI.ShowWidgetTooltip(colorSwatch, tipText)
                    end
                end)
                colorSwatch:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local block = CludesUI.NewSwatchBlocker(colorSwatch)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(colorSwatch, TEXT_ROWS_TIP)
                end)
                block:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateState()
                    updateSwatch()
                    if TextModeOn() then
                        colorSwatch:SetAlpha(1)
                        block:Hide()
                    else
                        colorSwatch:SetAlpha(0.3)
                        block:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateState)
                UpdateState()
                return colorSwatch
            end
            AttachToggleCog(region, "Icon Settings", "Desaturate when No Charges", function()
                return Cfg("desaturateNoCharges") ~= false
            end, function(val)
                Set("desaturateNoCharges", val)
                Refresh()
            end, TextModeOn, ICON_ROWS_TIP)

            local timerSwatch =
                MakeInlineTextSwatch("textTimerColor", "Timer Color", region._lastInline or region._control)
            local countSwatch = MakeInlineTextSwatch("textCountColor", "Count Color", timerSwatch)
            region._lastInline = countSwatch
        end

        -- Font | Font Outline: text-display-only controls (the icon's duration /
        -- count texts keep the fixed module style), so both disable while
        -- Display Style is Icon. Mirrors the Chat module's font controls, but
        -- applies live -- no reload needed for these font strings.
        do
            local fontValues, fontOrder = CludesUI.BuildFontDropdownData()
            local outlineValues = {
                ["__global"] = { text = "CUI Global Default" },
                ["none"] = { text = "Drop Shadow" },
                ["outline"] = { text = "Outline" },
                ["thick"] = { text = "Thick Outline" },
            }
            local outlineOrder = { "__global", "none", "outline", "thick" }
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Font",
                disabled = function()
                    return not TextModeOn()
                end,
                disabledTooltip = TEXT_ROWS_TIP,
                values = fontValues,
                order = fontOrder,
                getValue = function()
                    return Cfg("font") or "__global"
                end,
                setValue = SetRowThen("font"),
            }, {
                type = "dropdown",
                text = "Font Outline",
                disabled = function()
                    return not TextModeOn()
                end,
                disabledTooltip = TEXT_ROWS_TIP,
                values = outlineValues,
                order = outlineOrder,
                getValue = function()
                    return Cfg("outlineMode") or "__global"
                end,
                setValue = SetRowThen("outlineMode"),
            })
            cursorY = cursorY - height
        end
    end -- close BattleRes hidden-while-Never gate

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return math.abs(cursorY - yOffset)
end

-------------------------------------------------------------------------------
--  BLOODLUST TRACKER
--  A 1:1 duplicate of the BattleRes section. Appearance keys proxy-read through
--  to the current battleRes values until the user overrides them here, so the
--  tracker "starts identical" to Brez but can diverge (the raid/party model).
--  Only the Enable dropdown and position are stored independently per icon.
-------------------------------------------------------------------------------
local function BL_DB()
    local func = _G._CUI_Bloodlust_DB or _G._CUI_BattleRes_DB
    return func and func() or nil
end

local function BL_P()
    local d = BL_DB()
    return d and d.profile and d.profile.bloodlust
end

local function BL_BR()
    local d = BL_DB()
    return d and d.profile and d.profile.battleRes
end

-- Keys stored independently on the bloodlust profile (everything else proxies).
local BL_OWN_KEYS = {
    visibility = true,
    enabled = true,
    pos = true,
    showSated = true,
    showReady = true,
    readySize = true,
    readyColor = true,
    readyOffsetX = true,
    readyOffsetY = true,
    desaturateSated = true,
}

local function BL_Cfg(key, fallback)
    local bl = BL_P()
    if BL_OWN_KEYS[key] then
        if not bl then
            return fallback
        end
        if bl[key] == nil then
            return fallback
        end
        return bl[key]
    end
    -- Proxied appearance key: own override -> battleRes -> fallback.
    if bl and bl[key] ~= nil then
        return bl[key]
    end
    local br = BL_BR()
    if br and br[key] ~= nil then
        return br[key]
    end
    return fallback
end

local function BL_Set(key, val)
    local bl = BL_P()
    if bl then
        bl[key] = val
    end
end

local function BL_Refresh()
    if _G._CUI_Bloodlust_Apply then
        _G._CUI_Bloodlust_Apply()
    end
end

local function MakeBloodlustBorderColorSwatches()
    return {
        {
            tooltip = "Custom Color",
            hasAlpha = false,
            getValue = function()
                local color = BL_Cfg("borderColor")
                if color then
                    return color.r or 0, color.g or 0, color.b or 0
                end
                return 0, 0, 0
            end,
            setValue = function(red, green, blue)
                BL_Set("borderColor", { r = red, g = green, b = blue, a = 1 })
                BL_Refresh()
            end,
            onClick = function(self)
                if BL_Cfg("borderUseClass") then
                    BL_Set("borderUseClass", false)
                    BL_Refresh()
                    CludesUI:RefreshPage()
                    return
                end
                if self._eabOrigClick then
                    self._eabOrigClick(self)
                end
            end,
            refreshAlpha = function()
                if BL_Cfg("enabled") == false or BL_Cfg("visibility") == "NEVER" then
                    return 0.15
                end
                return BL_Cfg("borderUseClass") and 0.3 or 1
            end,
        },
        {
            tooltip = "Class Colored",
            hasAlpha = false,
            getValue = function()
                local _, ct = UnitClass("player")
                local classColor = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
                if classColor then
                    return classColor.r, classColor.g, classColor.b
                end
                return 1, 1, 1
            end,
            setValue = function() end,
            onClick = function()
                BL_Set("borderUseClass", true)
                BL_Refresh()
                CludesUI:RefreshPage()
            end,
            refreshAlpha = function()
                if BL_Cfg("enabled") == false or BL_Cfg("visibility") == "NEVER" then
                    return 0.15
                end
                return BL_Cfg("borderUseClass") and 1 or 0.3
            end,
        },
    }
end

-- Section-only builder for embedding in the Keys, Logs & Brez tab, directly
-- below the Battle Res section. Returns total height consumed.
_G._CUI_BuildBloodlustSection = function(hostFrame, yOffset, W, Pix)
    local cursorY = yOffset
    local _, height, row, heading

    heading, height = W:SectionHeader(hostFrame, "BLOODLUST TRACKER", cursorY)
    cursorY = cursorY - height
    CludesUI.BuildSectionUnlockJump(heading, {
        key = "CUI_Bloodlust",
        disabled = function()
            return BL_Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "Bloodlust Icon",
    })

    -- Live preview: the icon is forced on screen for as long as this page is, so the
    -- ready label, sizes and offsets can be judged without waiting for a real lust.
    -- The runtime keys off the page's own visibility, so the OnHide hook only has to
    -- poke it; a hidden search pre-build never owns the preview.
    -- The OnSHOW hook is what makes revisits work: the options panel caches built
    -- pages and re-shows the wrapper without re-running this builder, so without it
    -- the preview would arm on the first visit only.
    if not CludesUI._prebuilding and _G._CUI_Bloodlust_SetPreviewOwner then
        _G._CUI_Bloodlust_SetPreviewOwner((not PreviewHidden("lust")) and hostFrame or nil)
        if not hostFrame._blPreviewHooked then
            hostFrame._blPreviewHooked = true
            hostFrame:HookScript("OnShow", function()
                if _G._CUI_Bloodlust_SetPreviewOwner then
                    _G._CUI_Bloodlust_SetPreviewOwner((not PreviewHidden("lust")) and hostFrame or nil)
                end
            end)
            hostFrame:HookScript("OnHide", function()
                if _G._CUI_Bloodlust_UpdateVisibility then
                    _G._CUI_Bloodlust_UpdateVisibility()
                end
            end)
        end
    end

    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Enable Bloodlust Icon",
        values = VIS_VALUES,
        order = VIS_ORDER,
        getValue = function()
            return BL_Cfg("visibility") or "NEVER"
        end,
        -- DependentSetValue: the rows below Row 1 are hidden while Never;
        -- only the Never <-> shown flip forces the full rebuild.
        setValue = CludesUI.DependentSetValue(function()
            return BL_Cfg("visibility") ~= "NEVER"
        end, function(val)
            local was = BL_Cfg("visibility") or "NEVER"
            BL_Set("visibility", val)
            if was == "NEVER" and val ~= "NEVER" and _G._CUI_Bloodlust_SeedPos then
                _G._CUI_Bloodlust_SeedPos()
            end
            BL_Refresh()
            CludesUI:RefreshPage()
        end),
    }, {
        type = "slider",
        text = "Icon Size",
        disabled = function()
            return BL_Cfg("visibility") == "NEVER"
        end,
        disabledTooltip = "Bloodlust Icon",
        min = 16,
        max = 120,
        step = 1,
        isPercent = false,
        getValue = function()
            return BL_Cfg("iconSize") or 40
        end,
        setValue = function(val)
            BL_Set("iconSize", val)
            BL_Refresh()
        end,
    })
    cursorY = cursorY - height

    -- Rows below are HIDDEN entirely while the icon is set to Never (the
    -- dropdown's DependentSetValue forces the rebuild on flips).
    if BL_Cfg("visibility") ~= "NEVER" then
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Icon Shape",
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            getValue = function()
                return BL_Cfg("shape") or "none"
            end,
            setValue = function(val)
                BL_Set("shape", val)
                BL_Refresh()
            end,
        }, {
            type = "multiSwatch",
            text = "Border Color",
            swatches = MakeBloodlustBorderColorSwatches(),
        })
        if not CludesUI._prebuilding then
            AttachPreviewEye(
                row._leftRegion,
                "lust",
                "Show Bloodlust preview",
                "Hide Bloodlust preview",
                "_CUI_Bloodlust_SetPreviewOwner",
                hostFrame
            )
        end
        cursorY = cursorY - height

        row, height = W:DualRow(hostFrame, cursorY, BorderSizeSliderCfg(BL_Cfg, BL_Set, BL_Refresh), {
            type = "slider",
            text = "Icon Zoom",
            disabled = function()
                local s = BL_Cfg("shape") or "none"
                return s ~= "none" and s ~= "cropped"
            end,
            disabledTooltip = "This option requires Icon Shape to be set to None or Cropped",
            min = 0,
            max = 20,
            step = 0.5,
            isPercent = false,
            getValue = function()
                return BL_Cfg("iconZoom") or 11
            end,
            setValue = function(val)
                BL_Set("iconZoom", val)
                BL_Refresh()
            end,
        })
        cursorY = cursorY - height

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Duration Size",
            min = 8,
            max = 30,
            step = 1,
            isPercent = false,
            getValue = function()
                return BL_Cfg("durationSize") or 12
            end,
            setValue = function(val)
                BL_Set("durationSize", val)
                BL_Refresh()
            end,
        }, {
            type = "slider",
            text = "Count Size",
            min = 8,
            max = 20,
            step = 1,
            isPercent = false,
            getValue = function()
                return BL_Cfg("countSize") or 11
            end,
            setValue = function(val)
                BL_Set("countSize", val)
                BL_Refresh()
            end,
        })
        cursorY = cursorY - height

        do
            -- disabledFn/disabledText: optional, block the popup + grey the cog while
            -- the row it belongs to is disabled (Duration/Count Position pass neither
            -- and stay always-on, unchanged). anchorTo: optional, anchor the cog to
            -- something other than the row's own control while keeping rgn as parent
            -- (parenting it to the anchor instead would multiply the cog's disabled
            -- alpha by that anchor's, greying it into invisibility).
            local function _attachOffsetCog(
                region,
                popupTitle,
                xKey,
                yKey,
                disabledFn,
                disabledText,
                anchorTo
            )
                return CludesUI.BuildInlineCog(region, {
                    title = popupTitle,
                    rows = {
                        {
                            type = "slider",
                            label = "X Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return BL_Cfg(xKey) or 0
                            end,
                            set = function(val)
                                BL_Set(xKey, val)
                                BL_Refresh()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                return BL_Cfg(yKey) or 0
                            end,
                            set = function(val)
                                BL_Set(yKey, val)
                                BL_Refresh()
                            end,
                        },
                    },
                    gap = 6,
                    chain = false,
                    anchorTo = anchorTo,
                    disabled = disabledFn,
                    disabledTooltip = disabledText,
                })
            end
            _attachOffsetCog(row._leftRegion, "Duration Position", "durationOffsetX", "durationOffsetY")
            _attachOffsetCog(row._rightRegion, "Count Position", "countOffsetX", "countOffsetY")

            -- Show Sated / Show Ready: independent toggles. Sated gates the real lockout
            -- countdown, Ready gates the label shown once that lockout is gone -- either,
            -- both or neither can be on.
            -- Toggle controls don't self-trigger a refresh pass (unlike sliders/
            -- dropdowns), so without the explicit RefreshPage() the Ready row below
            -- stays stale (not greyed/ungreyed) until something else repaints the page.
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Icon when Sated",
                tooltip = "Show the Sated/Exhaustion lockout countdown on the icon.",
                getValue = function()
                    return BL_Cfg("showSated") ~= false
                end,
                setValue = function(val)
                    BL_Set("showSated", val)
                    BL_Refresh()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Show Icon with Ready Text",
                tooltip = "Once the lockout expires, show a Ready label on the icon in place of the countdown. The visibility rule above still applies.",
                getValue = function()
                    return BL_Cfg("showReady") == true
                end,
                setValue = function(val)
                    BL_Set("showReady", val)
                    BL_Refresh()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height

            if not CludesUI._prebuilding then
                AttachToggleCog(row._leftRegion, "Sated Settings", "Desaturate when Sated", function()
                    return BL_Cfg("desaturateSated") ~= false
                end, function(val)
                    BL_Set("desaturateSated", val)
                    BL_Refresh()
                end, function()
                    return BL_Cfg("showSated") == false
                end, "Show Icon when Sated")
            end

            -- Ready appearance: colour swatch, offset cog and size slider on one row,
            -- disabled (not hidden) while Show Ready is off so the layout never
            -- reshuffles on the toggle.
            local function readyOff()
                return BL_Cfg("showReady") ~= true
            end
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Ready Size",
                disabled = readyOff,
                disabledTooltip = "Show Icon with Ready Text",
                min = 8,
                max = 30,
                step = 1,
                isPercent = false,
                getValue = function()
                    return BL_Cfg("readySize") or 12
                end,
                setValue = function(val)
                    BL_Set("readySize", val)
                    BL_Refresh()
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height
            do
                local leftRegion = row._leftRegion
                -- The offset cog sits beside the slider and the swatch left of it,
                -- both parented to the row region like the other two.
                local readyCog = _attachOffsetCog(
                    leftRegion,
                    "Ready Position",
                    "readyOffsetX",
                    "readyOffsetY",
                    readyOff,
                    "Show Icon with Ready Text"
                )
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    leftRegion,
                    leftRegion:GetFrameLevel() + 5,
                    function()
                        local color = BL_Cfg("readyColor")
                        if color then
                            return color.r or 1, color.g or 1, color.b or 1
                        end
                        return 1, 1, 1
                    end,
                    function(red, green, blue)
                        BL_Set("readyColor", { r = red, g = green, b = blue })
                        BL_Refresh()
                    end,
                    false,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", readyCog or leftRegion._control, "LEFT", -8, 0)
                -- The leftmost item: the label clamp's bound.
                leftRegion._lastInline = colorSwatch
                CludesUI.RegisterWidgetRefresh(function()
                    local off = readyOff()
                    colorSwatch:SetAlpha(off and 0.3 or 1)
                    updateSwatch()
                end)
                -- The slider's own "disabled" already blocks clicks on itself; the
                -- swatch is a manual inline extra, so it needs the same click-block
                -- overlay the ActionBars range-colour swatch uses.
                local readyColorBlock = CludesUI.NewSwatchBlocker(colorSwatch)
                readyColorBlock:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        colorSwatch,
                        CludesUI.DisabledTooltip("Show Icon with Ready Text")
                    )
                end)
                readyColorBlock:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                CludesUI.RegisterWidgetRefresh(function()
                    readyColorBlock:SetShown(readyOff())
                end)
                readyColorBlock:SetShown(readyOff())
            end
        end
    end -- close Bloodlust hidden-while-Never gate

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    return math.abs(cursorY - yOffset)
end
