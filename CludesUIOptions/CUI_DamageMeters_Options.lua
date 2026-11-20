if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_DamageMeters_Options.lua
--  Options page for CludesUI Damage Meters.
--  All settings are live (no Edit Mode, no reload required), except the WoW
--  Forever look's Border Style, latched with the look (reload popup).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIDamageMeters"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page
local EDM = mod.EDM
-- Blizzard Style paints its own window colours and bar tracks, so those
-- controls go inert under it; the Classic WoW UI box is tinted by the
-- configured colours and its rows keep the plain track, so they stay live.
local function DMBlizzArt()
    return CludesUI.BlizzStyle.Active("damagemeters") == "blizzard"
end
local function DMBlizzGate(rowConf, keepRow)
    if DMBlizzArt() then
        return CludesUI.BlizzStyle.Gate("damagemeters", rowConf, keepRow)
    end
    return rowConf
end

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolIsIdle = CludesUI._Pool.IsIdle

CludesUI.AtOptionsLogin(function()
    if not EDM then
        return
    end
    -- Do nothing if the module is disabled / coming soon
    if not _G._CUDM_DB then
        return
    end

    local function DB()
        local db = _G._CUDM_DB
        if db and db.profile and db.profile.dm then
            return db.profile.dm
        end
        return {}
    end
    local function MeterGet(keyName)
        return DB()[keyName]
    end
    -- Row getters over Cfg: a key's value (or a default), or whether it is true.
    local function CfgOr(settingKey, default)
        return function()
            return MeterGet(settingKey) or default
        end
    end
    local function CfgIs(settingKey)
        return function()
            return MeterGet(settingKey) == true
        end
    end
    local function MeterSet(keyName, val)
        DB()[keyName] = val
    end
    -- Row setters over Set: the key written with the row's value.
    local function SetRow(settingKey)
        return function(value)
            MeterSet(settingKey, value)
        end
    end

    -- All settings are picked up on the next refresh cycle (0.3s combat,
    -- 2s idle). Just Set() and go -- except the WoW Forever look's Border
    -- Style, which asks for a reload.

    -- Shared capture button for both damage meter hotkeys (reset data, show/hide
    -- windows). Returns the button so the caller can anchor its cog to it.
    local function MakeKeybindButton(region, dbKey, tooltip)
        local kbBtn, refresh = CludesUI.BuildKeybindButton(region, {
            w = 120,
            h = 26,
            pp = CludesUI.PP,
            tooltip = tooltip,
            get = function()
                return MeterGet(dbKey)
            end,
            set = function(val)
                MeterSet(dbKey, val)
                if mod.ApplyDMKeybinds then
                    mod.ApplyDMKeybinds()
                end
            end,
        })
        CludesUI.PP.Point(kbBtn, "RIGHT", region, "RIGHT", -10, 0)
        CludesUI.RegisterWidgetRefresh(refresh)
        return kbBtn
    end

    -- Bar texture dropdown values (same pattern as Resource Bars / Nameplates)
    local textureValues = {}
    local dmTexOrder = {}
    do
        CludesUI.AppendSharedMediaTextures(
            _G._CUDM_BarTextureNames or {},
            _G._CUDM_BarTextureOrder or {},
            nil,
            _G._CUDM_BarTextures
        )
        local texNames = _G._CUDM_BarTextureNames or {}
        local texOrder2 = _G._CUDM_BarTextureOrder or {}
        local texLookup = _G._CUDM_BarTextures or {}
        for _, settingKey in ipairs(texOrder2) do
            if settingKey ~= "---" then
                textureValues[settingKey] = texNames[settingKey] or settingKey
            end
            dmTexOrder[#dmTexOrder + 1] = settingKey
        end
        textureValues._menuOpts = {
            itemHeight = 28,
            background = function(settingKey)
                return texLookup[settingKey]
            end,
        }
    end

    -- Variant with "Match Damage Meters" at the top (for breakdown / spell history)
    local matchTexValues = { match = "Match Damage Meters" }
    local matchTexOrder = { "match", "---" }
    for _, settingKey in ipairs(dmTexOrder) do
        matchTexOrder[#matchTexOrder + 1] = settingKey
        if settingKey ~= "---" then
            matchTexValues[settingKey] = textureValues[settingKey]
        end
    end
    matchTexValues._menuOpts = textureValues._menuOpts

    local function BuildPage(_, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local cursorY = yOffset
        local height, heading

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        local function RefreshMeters()
            if mod.RefreshMeter then
                mod.RefreshMeter()
            end
        end
        local function ApplyHeaderBar()
            if mod.ApplyHeader then
                mod.ApplyHeader()
            end
        end
        local function ApplyBorderLook()
            if mod.ApplyBorder then
                mod.ApplyBorder()
            end
        end
        local function ApplyWindowBrd()
            if mod.ApplyWindowBorder then
                mod.ApplyWindowBorder()
            end
        end
        local function ApplyIconBorderLook()
            if mod.ApplyIconBorder then
                mod.ApplyIconBorder()
            end
        end

        -- ── DISPLAY ─────────────────────────────────────────────────────
        heading, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
        cursorY = cursorY - height
        -- Every setting here is shared by all the windows, so the one button
        -- selects window 1, which always exists (its header button is New Window).
        CludesUI.BuildSectionUnlockJump(heading, { key = "EDM_Win1" })
        cursorY = CludesUI.BlizzStyle.Note(hostFrame, cursorY, "damagemeters")

        -- Visibility (one control)
        local function VisApply()
            CludesUI.RequestVisibilityUpdate()
        end
        local visRow
        visRow, height = CludesUI.BuildVisibilityRow(
            W,
            hostFrame,
            cursorY,
            {
                getStore = DB,
                legacyKey = "visibility",
                caps = { partyIncludesRaid = false, luaDragonriding = true },
                onChanged = VisApply,
                onOptionChanged = VisApply,
            },
            -- Refresh Rate moved up into the slot the Visibility Options dropdown left
            -- behind; its "(seconds)" suffix is attached below. Range widens once the
            -- cog's Unsafe Refresh Rate toggle is on (see below); that toggle rebuilds
            -- the page so this table is re-evaluated with the new min/tooltip.
            (
                MeterGet("unsafeRefreshRate")
                    and {
                        type = "slider",
                        text = "Refresh Rate",
                        tooltip = "Faster than 0.5s makes the meters work much harder in combat and can cost you frames, especially with several windows open.",
                        min = 0.2,
                        max = 2,
                        step = 0.05,
                        getValue = CfgOr("refreshRate", 1),
                        setValue = SetRow("refreshRate"),
                        fmt = function(val)
                            return format("%.2fs", val)
                        end,
                    }
                or {
                    type = "slider",
                    text = "Refresh Rate",
                    tooltip = "Increase to improve performance, Decrease to update meters faster",
                    min = 0.5,
                    max = 2,
                    step = 0.1,
                    getValue = CfgOr("refreshRate", 1),
                    setValue = SetRow("refreshRate"),
                    fmt = function(val)
                        return format("%.2fs", val)
                    end,
                }
            )
        )
        if not CludesUI._prebuilding then
            local region = visRow._rightRegion
            -- Forward-declared so the row's set() can close the popup before the page
            -- rebuild below tears down the button it's anchored to: RefreshPage(true)
            -- recreates this whole block's frames, and a still-open popup left anchored
            -- to the old (now orphaned) cog button drifts to wherever that frame lands.
            local cogShowUnsafe
            local _, _unsafeCogShow = CludesUI.BuildInlineCog(region, {
                title = "Refresh Rate",
                rows = {
                    {
                        type = "toggle",
                        label = "Unsafe Refresh Rate",
                        tooltip = "Lets you set Refresh Rate faster than 0.5s. The meters update more often but work much harder in combat, which can cost you frames. Only turn this on if your PC has performance to spare.",
                        get = CfgIs("unsafeRefreshRate"),
                        set = function(val)
                            MeterSet("unsafeRefreshRate", val)
                            if not val then
                                local floor = mod._REFRESH_RATE_FLOOR or 0.5
                                local r = MeterGet("refreshRate")
                                if r and r < floor then
                                    MeterSet("refreshRate", floor)
                                end
                            end
                            if cogShowUnsafe and cogShowUnsafe._popupFrame then
                                cogShowUnsafe._popupFrame:Hide()
                            end
                            CludesUI:RefreshPage(true)
                        end,
                    },
                },
                anchorTo = region._control,
            })
            cogShowUnsafe = _unsafeCogShow
        end
        cursorY = cursorY - height

        -- Window Border Style (+ directions submenu) | Border Size (+ color)
        local windowTexValues, windowTexOrder = CludesUI.GetBorderTextureDropdown()
        local windowBorderRow
        windowBorderRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("damagemeters", {
                type = "dropdown",
                text = "Border Style",
                values = windowTexValues,
                order = windowTexOrder,
                getValue = CfgOr("windowBorderTexture", "solid"),
                setValue = function(val)
                    MeterSet("windowBorderTexture", val)
                    MeterSet("windowBorderOffsetX", 0)
                    MeterSet("windowBorderOffsetY", 0)
                    local color, behind = CludesUI.GetBorderStyleSelectDefaults(val)
                    MeterSet("windowBorderColor", { r = color.r, g = color.g, b = color.b, a = 1 })
                    MeterSet("windowBorderBehind", behind)
                    local defaultSize = CludesUI.GetBorderDefaultSize("damagemeters", val)
                    if defaultSize then
                        MeterSet("windowBorderSize", defaultSize)
                    end
                    -- A style pick returns the surface to its legacy step; clear a set exact size (false travels, nil would not).
                    if MeterGet("windowBorderSizePx") then
                        MeterSet("windowBorderSizePx", false)
                    end
                    -- force: the offset row below exists only for a textured style
                    ApplyWindowBrd()
                    CludesUI:RefreshPage(true)
                end,
            }),
            CludesUI.BlizzStyle.Gate(
                "damagemeters",
                CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function()
                        return tonumber(MeterGet("windowBorderSize")) or 0
                    end,
                    setStep = function(step)
                        MeterSet("windowBorderSize", step)
                    end,
                    getTex = function()
                        return MeterGet("windowBorderTexture") or "solid"
                    end,
                    getPx = function()
                        return MeterGet("windowBorderSizePx")
                    end,
                    setPx = function(val)
                        MeterSet("windowBorderSizePx", val)
                    end,
                    apply = ApplyWindowBrd,
                })
            )
        )
        if not CludesUI._prebuilding then
            local region = windowBorderRow._leftRegion
            local directionBtn = CludesUI.BuildInlineCog(region, {
                title = "Border Options",
                rows = {
                    {
                        type = "toggle",
                        label = "Include Headerbar",
                        get = function()
                            return MeterGet("windowBorderIncludeHeader") ~= false
                        end,
                        set = function(val)
                            MeterSet("windowBorderIncludeHeader", val)
                            ApplyWindowBrd()
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = CfgOr("windowBorderBehind", false),
                        set = function(val)
                            MeterSet("windowBorderBehind", val)
                            ApplyWindowBrd()
                        end,
                    },
                },
                anchorTo = region._control,
            })
            if directionBtn then
                CludesUI.BlizzStyle.BlockInline("damagemeters", directionBtn, 0.15)
            end
        end
        if not CludesUI._prebuilding then
            local region, control = windowBorderRow._rightRegion, windowBorderRow._rightRegion._control
            local colorSwatch, refreshSwatch = CludesUI.BuildColorSwatch(
                region,
                windowBorderRow:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("windowBorderColor") or {}
                    return color.r or 0, color.g or 0, color.b or 0, color.a or 1
                end,
                function(red, green, blue, a)
                    MeterSet("windowBorderColor", { r = red, g = green, b = blue, a = a or 1 })
                    ApplyWindowBrd()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
            CludesUI.RegisterWidgetRefresh(refreshSwatch)
            CludesUI.BlizzStyle.BlockInline("damagemeters", colorSwatch)
        end
        cursorY = cursorY - height
        -- Width Offset | Height Offset: only while a textured style is selected
        -- (a solid border has no outward offsets). Built during prebuild too so
        -- the y advance is identical whenever it is present. The window's offsets
        -- ADD to the texture's own default (the renderer grows the border frame
        -- by them), so nil and 0 are the same: an addonKey with no registry row
        -- makes the row's default 0 and it stores every other value as picked.
        do
            local wTex = MeterGet("windowBorderTexture") or "solid"
            if wTex ~= "" and wTex ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "damagemeters_window",
                    getTex = function()
                        return MeterGet("windowBorderTexture") or "solid"
                    end,
                    getStep = function()
                        return tonumber(MeterGet("windowBorderSize")) or 0
                    end,
                    getSizeKey = function()
                        return nil
                    end,
                    getPx = function()
                        return MeterGet("windowBorderSizePx")
                    end,
                    getX = function()
                        return MeterGet("windowBorderOffsetX")
                    end,
                    setX = function(val)
                        MeterSet("windowBorderOffsetX", val)
                    end,
                    getY = function()
                        return MeterGet("windowBorderOffsetY")
                    end,
                    setY = function(val)
                        MeterSet("windowBorderOffsetY", val)
                    end,
                    apply = ApplyWindowBrd,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CludesUI.BlizzStyle.Gate("damagemeters", ocfgL),
                    CludesUI.BlizzStyle.Gate("damagemeters", ocfgR)
                )
                cursorY = cursorY - height
            end
        end

        -- Background Texture (or the WoW Forever border style) | Background Opacity.
        -- Refresh Rate and its "(seconds)"
        -- suffix moved up to the Visibility row. The Border Style is latched with
        -- the look (the windows are built with its insets), so picking another kind
        -- than the latched one asks for a reload; Slim Textured (Blizzard's live
        -- art) is the default and reads for an unset value, each pick is saved,
        -- and a kind this client has no art for draws Slim
        -- (CludesUI.ForeverBorderKind).
        local fvBorderCfg = CludesUI.BlizzStyle.Forever("damagemeters")
            and {
                type = "dropdown",
                text = "Border Style",
                tooltip = "WoW Forever's frame round the meter windows, the breakdown, Spell History and the Forever Tools threat meter. Slim Textured uses Blizzard's current art; a style whose art this client lacks draws Slim. Applies after a UI reload.",
                values = { slim = "Slim", textured = "Slim Textured", heavy = "Heavy Bronze" },
                order = { "slim", "textured", "heavy" },
                getValue = function()
                    local val = MeterGet("foreverBorder")
                    return (val == "slim" or val == "heavy") and val or "textured"
                end,
                setValue = function(val)
                    MeterSet("foreverBorder", val)
                    if CludesUI.ForeverBorderKind(val) == mod.DMFvKind() then
                        return
                    end
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Border Style changed. A UI reload is needed to apply it.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                end,
            }
        local bgRow
        bgRow, height = W:DualRow(hostFrame, cursorY, fvBorderCfg or CludesUI.BlizzStyle.Gate("damagemeters", {
            type = "dropdown",
            text = "Background Texture",
            values = textureValues,
            order = dmTexOrder,
            getValue = CfgOr("bgTexture", "none"),
            setValue = function(val)
                MeterSet("bgTexture", val)
                mod.ApplyBackground()
            end,
        }), {
            type = "slider",
            text = "Background Opacity",
            min = 0,
            max = 1,
            step = 0.01,
            getValue = CfgOr("bgAlpha", 0.75),
            setValue = function(val)
                MeterSet("bgAlpha", val)
                if mod.ApplyBackground then
                    mod.ApplyBackground()
                end
            end,
        })
        -- Inline color swatch on Background Opacity
        do
            local region = bgRow._rightRegion
            local control = region._control
            local bgSwatch, bgSwatchRefresh = CludesUI.BuildColorSwatch(
                region,
                bgRow:GetFrameLevel() + 3,
                function()
                    return (MeterGet("bgR") or 0), (MeterGet("bgG") or 0), (MeterGet("bgB") or 0)
                end,
                function(red, green, blue)
                    MeterSet("bgR", red)
                    MeterSet("bgG", green)
                    MeterSet("bgB", blue)
                    if mod.ApplyBackground then
                        mod.ApplyBackground()
                    end
                end,
                false,
                20
            )
            Pix.Point(bgSwatch, "RIGHT", control, "LEFT", -8, 0)
            CludesUI.RegisterWidgetRefresh(function()
                bgSwatchRefresh()
            end)
            if DMBlizzArt() then
                CludesUI.BlizzStyle.BlockInline("damagemeters", bgSwatch)
            end
        end
        cursorY = cursorY - height

        -- Always Show Player | Reset Data Keybind
        local rrRow
        rrRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Always Show Player",
            tooltip = "This will pin your bar to the window when it is not within the visible area",
            getValue = function()
                return MeterGet("showPinnedSelf") ~= false
            end,
            setValue = function(val)
                MeterSet("showPinnedSelf", val)
                RefreshMeters()
            end,
        }, { type = "label", text = "Reset Data Keybind" })
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(rrRow._leftRegion, {
                title = "Player Bar Settings",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Player Marker",
                        tooltip = "Shows a white stripe on your own bar.",
                        get = CfgIs("showPlayerMarker"),
                        set = function(val)
                            MeterSet("showPlayerMarker", val)
                            RefreshMeters()
                        end,
                    },
                },
            })
        end
        -- "(seconds)" suffix for Refresh Rate, which lives in the Visibility row's right
        -- slot -- not this row.
        do
            local region = visRow._rightRegion
            local tail = region:CreateFontString(nil, "OVERLAY")
            tail:SetFont(CludesUI.EXPRESSWAY, 11, "")
            tail:SetTextColor(1, 1, 1, 0.35)
            local rrLabel
            -- An idle pooled region keeps its last build's text: skip it.
            local regions = { region:GetRegions() }
            for idx = 1, #regions do
                local reg = regions[idx]
                if
                    reg
                    and reg.GetText
                    and not PoolIsIdle(reg)
                    and CludesUI.EnKey(reg:GetText()) == "Refresh Rate"
                then
                    rrLabel = reg
                    break
                end
            end
            if rrLabel then
                tail:SetPoint("LEFT", rrLabel, "RIGHT", 5, 0)
            else
                tail:SetPoint("LEFT", region, "LEFT", 150, 0)
            end
            tail:SetText(CludesUI.L("(seconds)"))
        end

        if not CludesUI._prebuilding then
            local region = rrRow._rightRegion
            local kbBtn = MakeKeybindButton(
                region,
                "resetDataKey",
                "Left-click to set a keybind.\nRight-click to unbind."
            )

            -- Inline cog: hide reset button
            CludesUI.BuildInlineCog(region, {
                title = "Reset Button",
                rows = {
                    {
                        type = "toggle",
                        label = "Hide Reset Button",
                        get = CfgIs("hideResetButton"),
                        set = function(val)
                            MeterSet("hideResetButton", val)
                            ApplyHeaderBar()
                        end,
                    },
                },
                anchorTo = kbBtn,
            })
        end
        cursorY = cursorY - height

        -- ── HEADER ──────────────────────────────────────────────────────
        _, height = W:SectionHeader(hostFrame, "HEADER", cursorY)
        cursorY = cursorY - height

        -- Row 1: Header Height | Opacity (+ inline bg color swatch)
        local hdrRow1
        hdrRow1, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Header Height",
            min = 14,
            max = 40,
            step = 1,
            getValue = CfgOr("hdrHeight", 22),
            setValue = function(val)
                MeterSet("hdrHeight", val)
                ApplyHeaderBar()
                RefreshMeters()
            end,
        }, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 1,
            step = 0.01,
            getValue = CfgOr("hdrBgAlpha", 1),
            setValue = function(val)
                MeterSet("hdrBgAlpha", val)
                ApplyHeaderBar()
            end,
        })
        -- Inline color swatch on Opacity
        if not CludesUI._prebuilding then
            local region = hdrRow1._rightRegion
            local control = region._control
            local hdrSwatch, hdrSwatchRefresh = CludesUI.BuildColorSwatch(
                region,
                hdrRow1:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("hdrBgColor")
                    if color then
                        return color.r or 0x1B / 255, color.g or 0x1B / 255, color.b or 0x1B / 255
                    end
                    return 0x1B / 255, 0x1B / 255, 0x1B / 255
                end,
                function(red, green, blue)
                    MeterSet("hdrBgColor", { r = red, g = green, b = blue })
                    ApplyHeaderBar()
                end,
                false,
                20
            )
            Pix.Point(hdrSwatch, "RIGHT", control, "LEFT", -8, 0)
            CludesUI.RegisterWidgetRefresh(function()
                hdrSwatchRefresh()
            end)
            CludesUI.BlizzStyle.BlockInline("damagemeters", hdrSwatch)
        end
        cursorY = cursorY - height

        -- Row 2: Header Bottom Border (+ inline swatch) | Icon Size (+ inline dual swatches)
        local hdrBorderRow
        hdrBorderRow, height = W:DualRow(
            hostFrame,
            cursorY,
            -- Solid-only: a 0-4 px slider view over the same numeric key (no companion).
            CludesUI.BlizzStyle.Gate("damagemeters", {
                type = "slider",
                text = "Header Bottom Border",
                min = 0,
                max = 4,
                step = 1,
                getValue = function()
                    return tonumber(MeterGet("hdrBottomBorderSize")) or 0
                end,
                setValue = function(val)
                    MeterSet("hdrBottomBorderSize", tonumber(val) or 0)
                    ApplyHeaderBar()
                end,
            }),
            {
                type = "slider",
                text = "Icon Size",
                min = 20,
                max = 30,
                step = 1,
                getValue = CfgOr("hdrIconSize", 22),
                setValue = function(val)
                    MeterSet("hdrIconSize", val)
                    ApplyHeaderBar()
                end,
            }
        )
        if not CludesUI._prebuilding and CludesUI.GetBorderCompanion(MeterGet("windowBorderTexture"), "sepH") then
            CludesUI.BuildInlineCog(
                hdrBorderRow._leftRegion,
                CludesUI.BlizzStyle.Gate("damagemeters", {
                    title = "Header Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Bottom Separator",
                            tooltip = "Draws a divider under the header in the window border's style.",
                            disabled = function()
                                return MeterGet("windowBorderIncludeHeader") == false
                                    or (MeterGet("windowBorderSize") or 0) <= 0
                            end,
                            disabledTooltip = function()
                                if MeterGet("windowBorderIncludeHeader") == false then
                                    return "Include Headerbar"
                                end
                                return "Border Size"
                            end,
                            get = CfgIs("hdrBottomSeparator"),
                            set = function(val)
                                MeterSet("hdrBottomSeparator", val)
                                ApplyHeaderBar()
                            end,
                        },
                    },
                })
            )
        end
        if not CludesUI._prebuilding then
            local region, control = hdrBorderRow._leftRegion, hdrBorderRow._leftRegion._control
            local colorSwatch, refreshSwatch = CludesUI.BuildColorSwatch(
                region,
                hdrBorderRow:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("hdrBottomBorderColor") or {}
                    return color.r or 0, color.g or 0, color.b or 0, color.a or 1
                end,
                function(red, green, blue, a)
                    MeterSet("hdrBottomBorderColor", { r = red, g = green, b = blue, a = a or 1 })
                    ApplyHeaderBar()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            CludesUI.RegisterWidgetRefresh(refreshSwatch)
            CludesUI.BlizzStyle.BlockInline("damagemeters", colorSwatch)
            region._lastInline = colorSwatch
        end
        -- Inline dual swatches on Icon Size: right = Custom, left = Accent
        if not CludesUI._prebuilding then
            local region = hdrBorderRow._rightRegion
            local control = region._control

            -- Inline cog: icon visibility
            CludesUI.BuildInlineCog(region, {
                title = "Icon Visibility",
                rows = {
                    {
                        type = "toggle",
                        label = "Mouseover Icons",
                        get = CfgOr("hdrMouseoverIcons", false),
                        set = function(val)
                            MeterSet("hdrMouseoverIcons", val)
                            ApplyHeaderBar()
                        end,
                    },
                },
            })

            local customColorSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                hdrBorderRow:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("iconColor")
                    if color then
                        return color.r or 1, color.g or 1, color.b or 1
                    end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    MeterSet("iconColorUseAccent", false)
                    MeterSet("iconColor", { r = red, g = green, b = blue })
                    if mod.ApplyIconColor then
                        mod.ApplyIconColor()
                    end
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            local origIconClick = customColorSwatch:GetScript("OnClick")
            customColorSwatch:SetScript("OnClick", function(self, ...)
                if MeterGet("iconColorUseAccent") then
                    MeterSet("iconColorUseAccent", false)
                    if mod.ApplyIconColor then
                        mod.ApplyIconColor()
                    end
                    CludesUI:RefreshPage()
                    return
                end
                if origIconClick then
                    origIconClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            local accentColorSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                hdrBorderRow:GetFrameLevel() + 3,
                function()
                    return CludesUI.ResolveActiveAccent()
                end,
                function()
                    MeterSet("iconColorUseAccent", true)
                    if mod.ApplyIconColor then
                        mod.ApplyIconColor()
                    end
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(accentColorSwatch, "RIGHT", customColorSwatch, "LEFT", -8, 0)
            accentColorSwatch:SetScript("OnClick", function()
                MeterSet("iconColorUseAccent", true)
                if mod.ApplyIconColor then
                    mod.ApplyIconColor()
                end
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(accentColorSwatch, "Accent Color")
            region._lastInline = accentColorSwatch

            -- Classic WoW UI paints every header icon with vanilla art that
            -- carries its own colours, and WoW Forever tints the glyphs its
            -- own tan on their plates: both swatches inert. (Blizzard Style
            -- keeps the CUI glyphs, so the tint stays live there.)
            local stockIcons = CludesUI.BlizzStyle.Active("damagemeters") == "classic"
                or CludesUI.BlizzStyle.Forever("damagemeters")
            local function refreshHdrIcon()
                updateCustom()
                updateAccent()
                if stockIcons then
                    customColorSwatch:SetAlpha(0.3)
                    accentColorSwatch:SetAlpha(0.3)
                    return
                end
                local accentOn = MeterGet("iconColorUseAccent")
                customColorSwatch:SetAlpha(accentOn and 0.3 or 1)
                accentColorSwatch:SetAlpha(accentOn and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(refreshHdrIcon)
            refreshHdrIcon()
            if stockIcons then
                CludesUI.BlizzStyle.BlockInline("damagemeters", customColorSwatch)
                CludesUI.BlizzStyle.BlockInline("damagemeters", accentColorSwatch)
            end
        end
        cursorY = cursorY - height

        -- Row 3: Top Text Size (+ inline dual swatches)
        local hdrRow2
        hdrRow2, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Text Size",
            min = 8,
            max = 18,
            step = 1,
            getValue = CfgOr("hdrFontSize", 11),
            setValue = function(val)
                MeterSet("hdrFontSize", val)
                ApplyHeaderBar()
            end,
        }, { type = "label", text = "" })
        -- Inline dual swatches on Text Size: right = Custom, left = Accent
        if not CludesUI._prebuilding then
            local region = hdrRow2._leftRegion
            local control = region._control

            -- Inline cog: header text X/Y offset
            CludesUI.BuildInlineCog(region, {
                title = "Title Position",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = CfgOr("hdrTextOffX", 0),
                        set = function(val)
                            MeterSet("hdrTextOffX", val)
                            ApplyHeaderBar()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = CfgOr("hdrTextOffY", 0),
                        set = function(val)
                            MeterSet("hdrTextOffY", val)
                            ApplyHeaderBar()
                        end,
                    },
                },
            })

            local customColorSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                hdrRow2:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("hdrTextColor")
                    if color then
                        return color.r or 1, color.g or 1, color.b or 1
                    end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    MeterSet("hdrTextUseAccent", false)
                    MeterSet("hdrTextColor", { r = red, g = green, b = blue })
                    ApplyHeaderBar()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            local origHdrTextClick = customColorSwatch:GetScript("OnClick")
            customColorSwatch:SetScript("OnClick", function(self, ...)
                if MeterGet("hdrTextUseAccent") ~= false then
                    MeterSet("hdrTextUseAccent", false)
                    ApplyHeaderBar()
                    CludesUI:RefreshPage()
                    return
                end
                if origHdrTextClick then
                    origHdrTextClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            local accentColorSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                hdrRow2:GetFrameLevel() + 3,
                function()
                    return CludesUI.ResolveActiveAccent()
                end,
                function()
                    MeterSet("hdrTextUseAccent", true)
                    ApplyHeaderBar()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(accentColorSwatch, "RIGHT", customColorSwatch, "LEFT", -8, 0)
            accentColorSwatch:SetScript("OnClick", function()
                MeterSet("hdrTextUseAccent", true)
                ApplyHeaderBar()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(accentColorSwatch, "Accent Color")
            region._lastInline = accentColorSwatch

            local function refreshHdrText()
                updateCustom()
                updateAccent()
                local accentOn = MeterGet("hdrTextUseAccent") ~= false
                customColorSwatch:SetAlpha(accentOn and 0.3 or 1)
                accentColorSwatch:SetAlpha(accentOn and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(refreshHdrText)
            refreshHdrText()
        end
        cursorY = cursorY - height

        -- ── BAR DESIGN ──────────────────────────────────────────────────
        _, height = W:SectionHeader(hostFrame, "BARS", cursorY)
        cursorY = cursorY - height

        -- Bar Texture | Bar Height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            DMBlizzGate({
                type = "dropdown",
                text = "Bar Texture",
                values = textureValues,
                order = dmTexOrder,
                getValue = CfgOr("barTexture", "none"),
                setValue = function(val)
                    MeterSet("barTexture", val)
                    RefreshMeters()
                    if mod.ApplySpellHistory then
                        mod.ApplySpellHistory()
                    end
                end,
            }),
            {
                type = "slider",
                text = "Bar Height",
                min = 8,
                max = 40,
                step = 1,
                getValue = CfgOr("barHeight", 18),
                setValue = function(val)
                    MeterSet("barHeight", val)
                    RefreshMeters()
                end,
            }
        )
        cursorY = cursorY - height

        -- Bar Color | Bar Fill Opacity
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "multiSwatch",
            text = "Color",
            swatches = {
                {
                    tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local classColor = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 0.96, 0.55, 0.73
                    end,
                    setValue = function() end,
                    onClick = function()
                        MeterSet("showClassColor", true)
                        RefreshMeters()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return MeterGet("showClassColor") ~= false and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = MeterGet("barColor")
                        if color then
                            return color.r or 0.35, color.g or 0.55, color.b or 0.8
                        end
                        return 0.35, 0.55, 0.8
                    end,
                    setValue = function(red, green, blue)
                        MeterSet("barColor", { r = red, g = green, b = blue })
                        MeterSet("showClassColor", false)
                        MeterSet("barColorUseAccent", false)
                        RefreshMeters()
                        CludesUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if MeterGet("showClassColor") ~= false or MeterGet("barColorUseAccent") ~= false then
                            MeterSet("showClassColor", false)
                            MeterSet("barColorUseAccent", false)
                            RefreshMeters()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        if MeterGet("showClassColor") ~= false then
                            return 0.15
                        end
                        return MeterGet("barColorUseAccent") ~= false and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return CludesUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        MeterSet("showClassColor", false)
                        MeterSet("barColorUseAccent", true)
                        RefreshMeters()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if MeterGet("showClassColor") ~= false then
                            return 0.15
                        end
                        return MeterGet("barColorUseAccent") ~= false and 1 or 0.3
                    end,
                },
            },
        }, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 1,
            step = 0.01,
            getValue = CfgOr("barFillAlpha", 1),
            setValue = function(val)
                MeterSet("barFillAlpha", val)
                RefreshMeters()
            end,
        })
        cursorY = cursorY - height

        -- Bar Spacing | Icon Style
        local iconRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            pixel = true,
            text = "Spacing",
            min = -1,
            max = 10,
            step = 1,
            getValue = CfgOr("barSpacing", 2),
            setValue = function(val)
                MeterSet("barSpacing", val)
                RefreshMeters()
            end,
        }, {
            type = "dropdown",
            text = "Icon Style",
            values = _G._CUDM_IconStyleValues or {},
            order = _G._CUDM_IconStyleOrder or {},
            getValue = CfgOr("iconStyle", "spec"),
            setValue = function(val)
                MeterSet("iconStyle", val)
                ApplyIconBorderLook()
                RefreshMeters()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Icon crop and the optional seam use the existing Icon Style cog.
        if not CludesUI._prebuilding then
            local region = iconRow._rightRegion
            local function ZoomKey()
                local style = MeterGet("iconStyle") or "spec"
                return (style == "spec" or style == "blizzard") and "classIconZoom" or "spriteIconZoom"
            end
            local rowList = {
                {
                    type = "slider",
                    label = "Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    get = function()
                        local settingKey = ZoomKey()
                        return MeterGet(settingKey) or (settingKey == "classIconZoom" and 0.06 or 0)
                    end,
                    set = function(val)
                        MeterSet(ZoomKey(), val)
                        RefreshMeters()
                    end,
                },
            }
            if CludesUI.GetBorderCompanion(MeterGet("borderTexture"), "sepV") then
                rowList[#rowList + 1] = CludesUI.BlizzStyle.Gate("damagemeters", {
                    type = "toggle",
                    label = "Separator",
                    tooltip = "Adds a divider between each icon and its bar.",
                    disabled = function()
                        return (MeterGet("borderSize") or 0) <= 0
                    end,
                    disabledTooltip = "Border Size",
                    get = CfgIs("iconSeparator"),
                    set = function(val)
                        MeterSet("iconSeparator", val)
                        RefreshMeters()
                    end,
                })
            end
            CludesUI.BuildInlineCog(region, {
                title = "Icon Settings",
                rows = rowList,
                chain = false,
                disabled = function()
                    return MeterGet("iconStyle") == "none"
                end,
                disabledTooltip = "Icon Style",
            })
        end

        -- Border Style (+ cog) | Border Size (+ inline swatch)
        -- Shadow (Glow rendered behind) needs Show Behind support, which DM lacks,
        -- so it is excluded from the Damage Meters border-style dropdown.
        local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
        texValues.shadow = nil
        for idx = #texOrder, 1, -1 do
            if texOrder[idx] == "shadow" then
                table.remove(texOrder, idx)
            end
        end
        local bsRow
        bsRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("damagemeters", {
                type = "dropdown",
                text = "Border Style",
                values = texValues,
                order = texOrder,
                getValue = CfgOr("borderTexture", "solid"),
                setValue = function(val)
                    MeterSet("borderTexture", val)
                    MeterSet("borderTextureOffset", nil)
                    MeterSet("borderTextureOffsetY", nil)
                    MeterSet("borderTextureShiftX", nil)
                    MeterSet("borderTextureShiftY", nil)
                    local selC = CludesUI.GetBorderSelectColor(val)
                    if selC then
                        -- The style's select colour (Pixels grey).
                        MeterSet("borderR", selC.r)
                        MeterSet("borderG", selC.g)
                        MeterSet("borderB", selC.b)
                        MeterSet("borderA", 1)
                    elseif val ~= "solid" then
                        MeterSet("borderR", 1)
                        MeterSet("borderG", 1)
                        MeterSet("borderB", 1)
                        MeterSet("borderA", 1)
                    else
                        MeterSet("borderR", 0)
                        MeterSet("borderG", 0)
                        MeterSet("borderB", 0)
                        MeterSet("borderA", 1)
                    end
                    local defSz = CludesUI.GetBorderDefaultSize("damagemeters", val)
                    if defSz then
                        MeterSet("borderSize", defSz)
                    end
                    -- A style pick returns the surface to its legacy step; clear a set exact size (false travels, nil would not).
                    if MeterGet("borderSizePx") then
                        MeterSet("borderSizePx", false)
                    end
                    -- force: the offset row below exists only for a textured style
                    ApplyBorderLook()
                    CludesUI:RefreshPage(true)
                    -- keepRow: the cog on this slot is the only home of the Custom
                    -- Icon Border toggle, which stays live under the style.
                end,
            }, true),
            CludesUI.BlizzStyle.Gate(
                "damagemeters",
                CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function()
                        return MeterGet("borderSize") or 0
                    end,
                    setStep = function(step)
                        MeterSet("borderSize", step)
                    end,
                    getTex = function()
                        return MeterGet("borderTexture") or "solid"
                    end,
                    getPx = function()
                        return MeterGet("borderSizePx")
                    end,
                    setPx = function(val)
                        MeterSet("borderSizePx", val)
                    end,
                    apply = ApplyBorderLook,
                })
            )
        )
        cursorY = cursorY - height
        -- Width Offset | Height Offset: only while a textured style is selected
        -- (a solid border has no outward offsets). Built during prebuild too so
        -- the y advance is identical whenever it is present.
        do
            local bTex = MeterGet("borderTexture") or "solid"
            if bTex ~= "" and bTex ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "damagemeters",
                    getTex = function()
                        return MeterGet("borderTexture") or "solid"
                    end,
                    getStep = function()
                        return MeterGet("borderSize") or 0
                    end,
                    getSizeKey = function()
                        return MeterGet("borderSize") or 0
                    end,
                    getPx = function()
                        return MeterGet("borderSizePx")
                    end,
                    getX = function()
                        return MeterGet("borderTextureOffset")
                    end,
                    setX = function(val)
                        MeterSet("borderTextureOffset", val)
                    end,
                    getY = function()
                        return MeterGet("borderTextureOffsetY")
                    end,
                    setY = function(val)
                        MeterSet("borderTextureOffsetY", val)
                    end,
                    apply = ApplyBorderLook,
                })
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    CludesUI.BlizzStyle.Gate("damagemeters", ocfgL),
                    CludesUI.BlizzStyle.Gate("damagemeters", ocfgR)
                )
                cursorY = cursorY - height
            end
        end
        -- Inline cog for border options (left region)
        if not CludesUI._prebuilding then
            local region = bsRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Border Options",
                rows = {
                    {
                        type = "slider",
                        label = "Shift X",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = MeterGet("borderTextureShiftX")
                            if val then
                                return val
                            end
                            local texture = MeterGet("borderTexture") or "solid"
                            local sz = MeterGet("borderSize") or 1
                            local _, _, dsx = CludesUI.GetBorderDefaults("damagemeters", texture, sz)
                            return dsx
                        end,
                        set = function(val)
                            MeterSet("borderTextureShiftX", val == 0 and nil or val)
                            ApplyBorderLook()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shift Y",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = function()
                            local val = MeterGet("borderTextureShiftY")
                            if val then
                                return val
                            end
                            local texture = MeterGet("borderTexture") or "solid"
                            local sz = MeterGet("borderSize") or 1
                            local _, _, _, dsy = CludesUI.GetBorderDefaults("damagemeters", texture, sz)
                            return dsy
                        end,
                        set = function(val)
                            MeterSet("borderTextureShiftY", val == 0 and nil or val)
                            ApplyBorderLook()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Icon Border",
                        get = CfgOr("customIconBorder", false),
                        set = function(val)
                            MeterSet("customIconBorder", val)
                            ApplyIconBorderLook()
                            -- force=true: the row is added/removed at build time,
                            -- so the fast refresh path is not enough
                            CludesUI:RefreshPage(true)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Border Follows Bar",
                        tooltip = "Border wraps only the filled portion of each bar instead of the whole row. Always renders as a solid border.",
                        get = CfgOr("borderFollowFill", false),
                        set = function(val)
                            MeterSet("borderFollowFill", val)
                            ApplyBorderLook()
                            CludesUI:RefreshPage()
                        end,
                    },
                    CludesUI.BlizzStyle.Gate("damagemeters", {
                        type = "toggle",
                        label = "Separators",
                        tooltip = "Replaces each bar's border with a divider under it.",
                        -- Pixels and Pixels Textured only: no other style has divider art.
                        hidden = function()
                            return not CludesUI.GetBorderCompanion(MeterGet("borderTexture"), "sepH")
                        end,
                        disabled = function()
                            return MeterGet("borderFollowFill") or (MeterGet("borderSize") or 0) <= 0
                        end,
                        disabledTooltip = function()
                            return MeterGet("borderFollowFill") and "Border Follows Bar" or "Border Size"
                        end,
                        requireState = function()
                            return MeterGet("borderFollowFill") and "disabled" or nil
                        end,
                        get = CfgIs("barSeparators"),
                        set = function(val)
                            MeterSet("barSeparators", val)
                            ApplyBorderLook()
                        end,
                    }),
                    {
                        type = "toggle",
                        label = "Include Icon in Bar Border",
                        tooltip = "Extends the follow-bar border to include the class icon.",
                        disabled = function()
                            return not MeterGet("borderFollowFill")
                        end,
                        get = CfgOr("borderFollowFillIcon", false),
                        set = function(val)
                            MeterSet("borderFollowFillIcon", val)
                            ApplyBorderLook()
                        end,
                    },
                },
                anchorTo = region._control,
            })
            -- Always visible: the popup hosts the Custom Icon Border toggle,
            -- which must stay reachable for the solid style too (the shift
            -- sliders are harmless no-ops for solid).
        end
        -- Inline color swatch on Border Size (right region)
        if not CludesUI._prebuilding then
            local region = bsRow._rightRegion
            local control = region._control
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                bsRow:GetFrameLevel() + 3,
                function()
                    return MeterGet("borderR") or 0, MeterGet("borderG") or 0, MeterGet("borderB") or 0, MeterGet("borderA") or 1
                end,
                function(red, green, blue, a)
                    MeterSet("borderR", red)
                    MeterSet("borderG", green)
                    MeterSet("borderB", blue)
                    MeterSet("borderA", a)
                    ApplyBorderLook()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
            CludesUI.RegisterWidgetRefresh(function()
                updateSwatch()
            end)
            CludesUI.BlizzStyle.BlockInline("damagemeters", colorSwatch)
        end

        -- Icon Border row: shown only while "Custom Icon Border" is enabled
        -- (the toggle lives in the Border Style inline cog above). The whole
        -- block is skipped at build time; the toggle's set() rebuilds the page.
        if MeterGet("customIconBorder") then
            local ibsRow
            ibsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                {
                    type = "dropdown",
                    text = "Icon Border Style",
                    values = texValues,
                    order = texOrder,
                    getValue = CfgOr("iconBorderTexture", "solid"),
                    setValue = function(val)
                        MeterSet("iconBorderTexture", val)
                        MeterSet("iconBorderTextureOffset", nil)
                        MeterSet("iconBorderTextureOffsetY", nil)
                        MeterSet("iconBorderTextureShiftX", nil)
                        MeterSet("iconBorderTextureShiftY", nil)
                        local selC = CludesUI.GetBorderSelectColor(val)
                        if selC then
                            -- The style's select colour (Pixels grey).
                            MeterSet("iconBorderR", selC.r)
                            MeterSet("iconBorderG", selC.g)
                            MeterSet("iconBorderB", selC.b)
                            MeterSet("iconBorderA", 1)
                        elseif val ~= "solid" then
                            MeterSet("iconBorderR", 1)
                            MeterSet("iconBorderG", 1)
                            MeterSet("iconBorderB", 1)
                            MeterSet("iconBorderA", 1)
                        else
                            MeterSet("iconBorderR", 0)
                            MeterSet("iconBorderG", 0)
                            MeterSet("iconBorderB", 0)
                            MeterSet("iconBorderA", 1)
                        end
                        local defSz = CludesUI.GetBorderDefaultSize("damagemeters_icon", val)
                        if defSz then
                            MeterSet("iconBorderSize", defSz)
                        end
                        -- A style pick returns the surface to its legacy step; clear a set exact size (false travels, nil would not).
                        if MeterGet("iconBorderSizePx") then
                            MeterSet("iconBorderSizePx", false)
                        end
                        -- force: the offset row below exists only for a textured style
                        ApplyIconBorderLook()
                        CludesUI:RefreshPage(true)
                    end,
                },
                CludesUI.BorderPxSliderCfg({
                    text = "Icon Border Size",
                    getStep = function()
                        return MeterGet("iconBorderSize") or 0
                    end,
                    setStep = function(step)
                        MeterSet("iconBorderSize", step)
                    end,
                    getTex = function()
                        return MeterGet("iconBorderTexture") or "solid"
                    end,
                    getPx = function()
                        return MeterGet("iconBorderSizePx")
                    end,
                    setPx = function(val)
                        MeterSet("iconBorderSizePx", val)
                    end,
                    apply = ApplyIconBorderLook,
                })
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: only while a textured style is selected
            -- (a solid border has no outward offsets). Built during prebuild too so
            -- the y advance is identical whenever it is present.
            do
                local iTex = MeterGet("iconBorderTexture") or "solid"
                if iTex ~= "" and iTex ~= "solid" then
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "damagemeters_icon",
                        getTex = function()
                            return MeterGet("iconBorderTexture") or "solid"
                        end,
                        getStep = function()
                            return MeterGet("iconBorderSize") or 0
                        end,
                        getSizeKey = function()
                            return MeterGet("iconBorderSize") or 0
                        end,
                        getPx = function()
                            return MeterGet("iconBorderSizePx")
                        end,
                        getX = function()
                            return MeterGet("iconBorderTextureOffset")
                        end,
                        setX = function(val)
                            MeterSet("iconBorderTextureOffset", val)
                        end,
                        getY = function()
                            return MeterGet("iconBorderTextureOffsetY")
                        end,
                        setY = function(val)
                            MeterSet("iconBorderTextureOffsetY", val)
                        end,
                        apply = ApplyIconBorderLook,
                    })
                    _, height = W:DualRow(hostFrame, cursorY, ocfgL, ocfgR)
                    cursorY = cursorY - height
                end
            end
            -- Inline cog for border options (left region)
            if not CludesUI._prebuilding then
                local region = ibsRow._leftRegion
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
                                local val = MeterGet("iconBorderTextureShiftX")
                                if val then
                                    return val
                                end
                                local texture = MeterGet("iconBorderTexture") or "solid"
                                local sz = MeterGet("iconBorderSize") or 1
                                local _, _, dsx = CludesUI.GetBorderDefaults("damagemeters_icon", texture, sz)
                                return dsx
                            end,
                            set = function(val)
                                MeterSet("iconBorderTextureShiftX", val == 0 and nil or val)
                                ApplyIconBorderLook()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local val = MeterGet("iconBorderTextureShiftY")
                                if val then
                                    return val
                                end
                                local texture = MeterGet("iconBorderTexture") or "solid"
                                local sz = MeterGet("iconBorderSize") or 1
                                local _, _, _, dsy =
                                    CludesUI.GetBorderDefaults("damagemeters_icon", texture, sz)
                                return dsy
                            end,
                            set = function(val)
                                MeterSet("iconBorderTextureShiftY", val == 0 and nil or val)
                                ApplyIconBorderLook()
                            end,
                        },
                    },
                    anchorTo = region._control,
                })
                local function UpdateCogVis()
                    local texture = MeterGet("iconBorderTexture") or "solid"
                    if texture == "solid" then
                        cogBtn:Hide()
                    else
                        cogBtn:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Inline color swatch on Border Size (right region)
            if not CludesUI._prebuilding then
                local region = ibsRow._rightRegion
                local control = region._control
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    ibsRow:GetFrameLevel() + 3,
                    function()
                        return MeterGet("iconBorderR") or 0,
                            MeterGet("iconBorderG") or 0,
                            MeterGet("iconBorderB") or 0,
                            MeterGet("iconBorderA") or 1
                    end,
                    function(red, green, blue, a)
                        MeterSet("iconBorderR", red)
                        MeterSet("iconBorderG", green)
                        MeterSet("iconBorderB", blue)
                        MeterSet("iconBorderA", a)
                        ApplyIconBorderLook()
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                end)
            end
        end -- if Cfg("customIconBorder")

        -- Show Breakdown on Hover (+ inline cog) | Background (opacity + swatch)
        local bdRow
        bdRow, height = W:DualRow(
            hostFrame,
            cursorY,
            {
                type = "toggle",
                text = "Show Breakdown on Hover",
                getValue = function()
                    return MeterGet("showHoverTooltip") ~= false
                end,
                setValue = SetRow("showHoverTooltip"),
            },
            DMBlizzGate({
                type = "slider",
                text = "Background",
                min = 0,
                max = 1,
                step = 0.01,
                getValue = CfgOr("barBgAlpha", 0),
                setValue = function(val)
                    MeterSet("barBgAlpha", val)
                    if mod.ApplyBarBg then
                        mod.ApplyBarBg()
                    end
                end,
            })
        )
        -- Inline custom + class color swatches on Background (right region).
        -- Custom paints a fixed track color; class tints each bar's track with
        -- that player's class color. Mirrors the Left/Right Text Size swatches.
        if not CludesUI._prebuilding then
            local region = bdRow._rightRegion
            local control = region._control
            local barBgSwatch, barBgSwatchRefresh = CludesUI.BuildColorSwatch(
                region,
                bdRow:GetFrameLevel() + 3,
                function()
                    return (MeterGet("barBgR") or 0), (MeterGet("barBgG") or 0), (MeterGet("barBgB") or 0)
                end,
                function(red, green, blue)
                    MeterSet("barBgUseClassColor", false)
                    MeterSet("barBgR", red)
                    MeterSet("barBgG", green)
                    MeterSet("barBgB", blue)
                    if mod.ApplyBarBg then
                        mod.ApplyBarBg()
                    end
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(barBgSwatch, "RIGHT", control, "LEFT", -8, 0)
            local origClick = barBgSwatch:GetScript("OnClick")
            barBgSwatch:SetScript("OnClick", function(self, ...)
                if MeterGet("barBgUseClassColor") then
                    MeterSet("barBgUseClassColor", false)
                    if mod.ApplyBarBg then
                        mod.ApplyBarBg()
                    end
                    CludesUI:RefreshPage()
                    return
                end
                if origClick then
                    origClick(self, ...)
                end
            end)
            CludesUI.HoverTip(barBgSwatch, "Custom Color")

            local barBgClassSwatch, barBgClassRefresh = CludesUI.BuildColorSwatch(
                region,
                bdRow:GetFrameLevel() + 3,
                function()
                    local clr = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                    if clr then
                        return clr.r, clr.g, clr.b
                    end
                    return 1, 1, 1
                end,
                function()
                    MeterSet("barBgUseClassColor", true)
                    if mod.ApplyBarBg then
                        mod.ApplyBarBg()
                    end
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(barBgClassSwatch, "RIGHT", barBgSwatch, "LEFT", -8, 0)
            barBgClassSwatch:SetScript("OnClick", function()
                MeterSet("barBgUseClassColor", true)
                if mod.ApplyBarBg then
                    mod.ApplyBarBg()
                end
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(barBgClassSwatch, "Class Color")

            local function refreshBarBg()
                barBgSwatchRefresh()
                barBgClassRefresh()
                -- Blizzard Style rows use the stock shadow track: both swatches inert.
                if DMBlizzArt() then
                    barBgSwatch:SetAlpha(0.3)
                    barBgClassSwatch:SetAlpha(0.3)
                    return
                end
                local classOn = MeterGet("barBgUseClassColor")
                barBgSwatch:SetAlpha(classOn and 0.3 or 1)
                barBgClassSwatch:SetAlpha(classOn and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(refreshBarBg)
            refreshBarBg()
            if DMBlizzArt() then
                CludesUI.BlizzStyle.BlockInline("damagemeters", barBgSwatch)
                CludesUI.BlizzStyle.BlockInline("damagemeters", barBgClassSwatch)
            end
        end
        if not CludesUI._prebuilding then
            local region = bdRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                title = "Breakdown Settings",
                rows = {
                    {
                        type = "dropdown",
                        label = "Bar Texture",
                        values = matchTexValues,
                        order = matchTexOrder,
                        get = CfgOr("breakdownBarTexture", "match"),
                        set = function(val)
                            MeterSet("breakdownBarTexture", val)
                            RefreshMeters()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Scale",
                        min = 80,
                        max = 150,
                        step = 1,
                        get = function()
                            return (MeterGet("hoverTooltipScale") or 100)
                        end,
                        set = SetRow("hoverTooltipScale"),
                    },
                    {
                        type = "dropdown",
                        label = "Anchor",
                        values = {
                            row = "Above Hovered Row",
                            center = "Center of Screen",
                            left = "Left of Window",
                            right = "Right of Window",
                        },
                        order = { "row", "center", "left", "right" },
                        get = CfgOr("breakdownAnchorPoint", "row"),
                        set = SetRow("breakdownAnchorPoint"),
                    },
                    {
                        type = "toggle",
                        label = "Show More Spells",
                        tooltip = "Show top 15 entries instead of 8.",
                        get = function()
                            return MeterGet("showAllBreakdownSpells") ~= false
                        end,
                        set = SetRow("showAllBreakdownSpells"),
                    },
                },
                anchorTo = region._control,
            })
        end
        cursorY = cursorY - height

        -- ── BAR TEXT ────────────────────────────────────────────────────
        _, height = W:SectionHeader(hostFrame, "BAR TEXT", cursorY)
        cursorY = cursorY - height

        -- Number Format | Hide Rank Numbers
        local hnRow
        hnRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Number Format",
            values = { [0] = "DPS", [1] = "Damage", [2] = "Damage (DPS)", [3] = "Damage | DPS" },
            order = { 0, 1, 2, 3 },
            getValue = CfgOr("numberFormat", 2),
            setValue = function(val)
                MeterSet("numberFormat", val)
                RefreshMeters()
            end,
        }, {
            type = "toggle",
            text = "Hide Rank Numbers",
            tooltip = "Hides the rank number (1. 2. 3.) before each player name.",
            getValue = CfgOr("hideNumbers", false),
            setValue = function(val)
                MeterSet("hideNumbers", val)
                RefreshMeters()
            end,
        })
        do
            local region = hnRow._rightRegion
            local tail = region:CreateFontString(nil, "OVERLAY")
            tail:SetFont(CludesUI.EXPRESSWAY, 11, "")
            tail:SetTextColor(1, 1, 1, 0.35)
            local hnLabel
            -- An idle pooled region keeps its last build's text: skip it.
            local regions = { region:GetRegions() }
            for idx = 1, #regions do
                local reg = regions[idx]
                if
                    reg
                    and reg.GetText
                    and not PoolIsIdle(reg)
                    and CludesUI.EnKey(reg:GetText()) == "Hide Rank Numbers"
                then
                    hnLabel = reg
                    break
                end
            end
            if hnLabel then
                tail:SetPoint("LEFT", hnLabel, "RIGHT", 5, 0)
            else
                tail:SetPoint("LEFT", region, "LEFT", 150, 0)
            end
            tail:SetText("(1, 2, 3)")
        end
        cursorY = cursorY - height

        -- Left Text Size (+ inline custom/class swatches) | Right Text Size (+ inline custom/class swatches)
        local btRow
        btRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Left Text Size",
            min = 8,
            max = 18,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return MeterGet("leftFontSize") or MeterGet("fontSize") or 11
            end,
            setValue = function(val)
                MeterSet("leftFontSize", val)
                RefreshMeters()
            end,
        }, {
            type = "slider",
            text = "Right Text Size",
            min = 8,
            max = 18,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return MeterGet("rightFontSize") or MeterGet("fontSize") or 11
            end,
            setValue = function(val)
                MeterSet("rightFontSize", val)
                RefreshMeters()
            end,
        })
        -- Left text inline swatches
        if not CludesUI._prebuilding then
            local region = btRow._leftRegion
            local control = region._control

            -- Inline cog: left text X/Y offsets (live via ns.ApplyBarTextOffsets),
            -- headed by the Name Format (players' names; in combat other players'
            -- names are secret and show whole).
            local leftRows = {
                {
                    type = "slider",
                    label = "X Offset",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = CfgOr("leftTextOffsetX", 0),
                    set = function(val)
                        MeterSet("leftTextOffsetX", val)
                        if mod.ApplyBarTextOffsets then
                            mod.ApplyBarTextOffsets()
                        end
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -20,
                    max = 20,
                    step = 1,
                    get = CfgOr("leftTextOffsetY", 0),
                    set = function(val)
                        MeterSet("leftTextOffsetY", val)
                        if mod.ApplyBarTextOffsets then
                            mod.ApplyBarTextOffsets()
                        end
                    end,
                },
            }
            local nameFormat = CludesUI.NameFormatCogRow(function()
                return MeterGet("nameFormat")
            end, function(val)
                MeterSet("nameFormat", val)
                mod.RefreshNames()
            end)
            nameFormat.tooltip = "Other players' names show in full during combat."
            table.insert(leftRows, 1, nameFormat)
            CludesUI.BuildInlineCog(region, {
                title = "Left Text",
                rows = leftRows,
            })

            local customColorSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                btRow:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("leftTextColor")
                    if color then
                        return color.r or 1, color.g or 1, color.b or 1
                    end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    MeterSet("leftTextUseClassColor", false)
                    MeterSet("leftTextColor", { r = red, g = green, b = blue })
                    RefreshMeters()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            local origClick = customColorSwatch:GetScript("OnClick")
            customColorSwatch:SetScript("OnClick", function(self, ...)
                if MeterGet("leftTextUseClassColor") then
                    MeterSet("leftTextUseClassColor", false)
                    RefreshMeters()
                    CludesUI:RefreshPage()
                    return
                end
                if origClick then
                    origClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            local classColorSwatch, updateClass = CludesUI.BuildColorSwatch(
                region,
                btRow:GetFrameLevel() + 3,
                function()
                    local clr = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                    if clr then
                        return clr.r, clr.g, clr.b
                    end
                    return 1, 1, 1
                end,
                function()
                    MeterSet("leftTextUseClassColor", true)
                    RefreshMeters()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(classColorSwatch, "RIGHT", customColorSwatch, "LEFT", -8, 0)
            classColorSwatch:SetScript("OnClick", function()
                MeterSet("leftTextUseClassColor", true)
                RefreshMeters()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(classColorSwatch, "Class Color")
            region._lastInline = classColorSwatch

            local function refreshLeft()
                updateCustom()
                updateClass()
                local classOn = MeterGet("leftTextUseClassColor")
                customColorSwatch:SetAlpha(classOn and 0.3 or 1)
                classColorSwatch:SetAlpha(classOn and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(refreshLeft)
            refreshLeft()
        end
        -- Right text inline swatches
        if not CludesUI._prebuilding then
            local region = btRow._rightRegion
            local control = region._control

            -- Inline cog: right text X/Y offsets (live via ns.ApplyBarTextOffsets)
            CludesUI.BuildInlineCog(region, {
                title = "Right Text",
                rows = {
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = CfgOr("rightTextOffsetX", 0),
                        set = function(val)
                            MeterSet("rightTextOffsetX", val)
                            if mod.ApplyBarTextOffsets then
                                mod.ApplyBarTextOffsets()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -20,
                        max = 20,
                        step = 1,
                        get = CfgOr("rightTextOffsetY", 0),
                        set = function(val)
                            MeterSet("rightTextOffsetY", val)
                            if mod.ApplyBarTextOffsets then
                                mod.ApplyBarTextOffsets()
                            end
                        end,
                    },
                },
            })

            local customColorSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                btRow:GetFrameLevel() + 3,
                function()
                    local color = MeterGet("rightTextColor")
                    if color then
                        return color.r or 1, color.g or 1, color.b or 1
                    end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    MeterSet("rightTextUseClassColor", false)
                    MeterSet("rightTextUseThreatGradient", false)
                    MeterSet("rightTextColor", { r = red, g = green, b = blue })
                    RefreshMeters()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            local origClick = customColorSwatch:GetScript("OnClick")
            customColorSwatch:SetScript("OnClick", function(self, ...)
                if MeterGet("rightTextUseClassColor") or MeterGet("rightTextUseThreatGradient") then
                    MeterSet("rightTextUseClassColor", false)
                    MeterSet("rightTextUseThreatGradient", false)
                    RefreshMeters()
                    CludesUI:RefreshPage()
                    return
                end
                if origClick then
                    origClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            local classColorSwatch, updateClass = CludesUI.BuildColorSwatch(
                region,
                btRow:GetFrameLevel() + 3,
                function()
                    local clr = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                    if clr then
                        return clr.r, clr.g, clr.b
                    end
                    return 1, 1, 1
                end,
                function()
                    MeterSet("rightTextUseClassColor", true)
                    MeterSet("rightTextUseThreatGradient", false)
                    RefreshMeters()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(classColorSwatch, "RIGHT", customColorSwatch, "LEFT", -8, 0)
            classColorSwatch:SetScript("OnClick", function()
                MeterSet("rightTextUseClassColor", true)
                MeterSet("rightTextUseThreatGradient", false)
                RefreshMeters()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(classColorSwatch, "Class Color")

            local function refreshRight()
                updateCustom()
                updateClass()
                local classOn = MeterGet("rightTextUseClassColor")
                local gradient = MeterGet("rightTextUseThreatGradient")
                customColorSwatch:SetAlpha((classOn or gradient) and 0.3 or 1)
                classColorSwatch:SetAlpha((classOn and not gradient) and 1 or 0.3)
            end
            CludesUI.RegisterWidgetRefresh(refreshRight)
            refreshRight()

            -- Value gradient: a swatch showing its colour scale, toggled by a click.
            region._lastInline = classColorSwatch
            CludesUI.BuildInlineSwatches(region, {
                {
                    tooltip = "Colors each value on a green to red scale.",
                    gradient = { { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
                    getValue = function()
                        return 1, 1, 1
                    end,
                    setValue = function() end,
                    refreshAlpha = function()
                        return MeterGet("rightTextUseThreatGradient") and 1 or 0.3
                    end,
                    onClick = function()
                        MeterSet("rightTextUseThreatGradient", not MeterGet("rightTextUseThreatGradient"))
                        RefreshMeters()
                        CludesUI:RefreshPage()
                    end,
                },
            }, { size = 20 })
        end
        cursorY = cursorY - height

        -- Force English Number Units (K/M/B) | (spacer)
        -- Only where the effective locale actually has its own abbreviation
        -- algorithm (currently the CJK wan/yi grouping tables in
        -- CludesUI_NumberFormat.lua): every other locale already gets
        -- K/M/B and the toggle would be a no-op, so the row is skipped for them.
        if CludesUI.LocaleHasNumberAbbreviation() then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Force English Units (K/M/B)",
                tooltip = "Always use K/M/B instead of localized units.",
                getValue = CfgOr("forceEnglishUnits", false),
                setValue = function(val)
                    MeterSet("forceEnglishUnits", val)
                    if mod.RebuildNumberFormat then
                        mod.RebuildNumberFormat()
                    end
                    RefreshMeters()
                end,
            }, { type = "spacer" })
            cursorY = cursorY - height
        end

        -- ── STANDALONE COMBAT TIMER ──────────────────────────────────
        heading, height = W:SectionHeader(hostFrame, "STANDALONE COMBAT TIMER", cursorY)
        cursorY = cursorY - height
        CludesUI.BuildSectionUnlockJump(heading, {
            key = "EDM_CombatTimer",
            disabled = function()
                return not MeterGet("standaloneTimer")
            end,
            disabledTooltip = "Standalone Combat Timer",
        })

        local function ApplyAttemptTimer()
            if mod.ApplySATimer then
                mod.ApplySATimer()
            end
        end

        -- Standalone Combat Timer (with inline cog) | Timer Text Color
        local satRow
        satRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Standalone Combat Timer",
            getValue = CfgOr("standaloneTimer", false),
            setValue = CludesUI.SectionToggleSetValue(function(val)
                MeterSet("standaloneTimer", val)
                ApplyAttemptTimer()
                -- Timer unlock element rides this toggle: (un)register live
                if mod.RegisterDMUnlock then
                    mod.RegisterDMUnlock()
                end
                if val and mod.ShowSATimerPreview then
                    mod.ShowSATimerPreview()
                elseif not val and mod.HideSATimerPreview then
                    mod.HideSATimerPreview()
                end
            end),
        }, {
            type = "multiSwatch",
            text = "Timer Text Color",
            disabled = function()
                return not MeterGet("standaloneTimer")
            end,
            disabledTooltip = "Standalone Combat Timer",
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = MeterGet("standaloneTimerColor")
                        if color then
                            return color.r or 1, color.g or 1, color.b or 1
                        end
                        return 1, 1, 1
                    end,
                    setValue = function(red, green, blue)
                        MeterSet("standaloneTimerColor", { r = red, g = green, b = blue })
                        ApplyAttemptTimer()
                    end,
                    onClick = function(self)
                        if MeterGet("standaloneTimerUseAccent") then
                            MeterSet("standaloneTimerUseAccent", false)
                            ApplyAttemptTimer()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        if not MeterGet("standaloneTimer") then
                            return 0.15
                        end
                        return MeterGet("standaloneTimerUseAccent") and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return CludesUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        MeterSet("standaloneTimerUseAccent", true)
                        ApplyAttemptTimer()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if not MeterGet("standaloneTimer") then
                            return 0.15
                        end
                        return MeterGet("standaloneTimerUseAccent") and 1 or 0.3
                    end,
                },
            },
        })
        -- Inline cog: focused visual controls for the standalone timer.
        if not CludesUI._prebuilding then
            local region = satRow._leftRegion
            local satFontValues, satFontOrder = CludesUI.BuildFontDropdownData()
            CludesUI.BuildInlineCog(region, {
                title = "Standalone Timer Settings",
                minWidth = 300,
                rows = {
                    {
                        type = "dropdown",
                        label = "Font",
                        values = satFontValues,
                        order = satFontOrder,
                        get = CfgOr("standaloneTimerFont", "__global"),
                        set = function(val)
                            MeterSet("standaloneTimerFont", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Font Size",
                        min = 10,
                        max = 40,
                        step = 1,
                        get = CfgOr("standaloneTimerSize", 26),
                        set = function(val)
                            MeterSet("standaloneTimerSize", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Font Outline",
                        values = {
                            INHERIT = "Default",
                            NONE = "None",
                            OUTLINE = "Thin",
                            THICKOUTLINE = "Thick",
                        },
                        order = { "INHERIT", "NONE", "OUTLINE", "THICKOUTLINE" },
                        get = CfgOr("standaloneTimerOutline", "INHERIT"),
                        set = function(val)
                            MeterSet("standaloneTimerOutline", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Alignment",
                        values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                        order = { "LEFT", "CENTER", "RIGHT" },
                        get = function()
                            local alignment = MeterGet("standaloneTimerTextAlign")
                            if alignment then
                                return alignment
                            end
                            local anchor = MeterGet("standaloneTimerAnchor") or "free"
                            if anchor == "free" then
                                return MeterGet("standaloneTimerAlignLeft") and "LEFT" or "RIGHT"
                            end
                            return (anchor == "topleft" or anchor == "bottomleft") and "LEFT" or "RIGHT"
                        end,
                        set = function(val)
                            MeterSet("standaloneTimerTextAlign", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Show Decimal",
                        get = CfgOr("standaloneTimerDecimal", false),
                        set = function(val)
                            MeterSet("standaloneTimerDecimal", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Frame Width",
                        min = 40,
                        max = 200,
                        step = 1,
                        get = CfgOr("standaloneTimerWidth", 70),
                        set = function(val)
                            MeterSet("standaloneTimerWidth", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Frame Height",
                        min = 20,
                        max = 80,
                        step = 1,
                        get = CfgOr("standaloneTimerHeight", 32),
                        set = function(val)
                            MeterSet("standaloneTimerHeight", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Background Color",
                        hasAlpha = true,
                        get = function()
                            local color = MeterGet("standaloneTimerBackgroundColor") or { r = 0, g = 0, b = 0, a = 0 }
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(red, green, blue, a)
                            MeterSet("standaloneTimerBackgroundColor", { r = red, g = green, b = blue, a = a })
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Border Color",
                        hasAlpha = true,
                        get = function()
                            local color = MeterGet("standaloneTimerBorderColor") or { r = 0, g = 0, b = 0, a = 1 }
                            return color.r, color.g, color.b, color.a
                        end,
                        set = function(red, green, blue, a)
                            MeterSet("standaloneTimerBorderColor", { r = red, g = green, b = blue, a = a })
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 0,
                        max = 4,
                        step = 1,
                        get = CfgOr("standaloneTimerBorderSize", 0),
                        set = function(val)
                            MeterSet("standaloneTimerBorderSize", val)
                            ApplyAttemptTimer()
                        end,
                    },
                    {
                        type = "dropdown",
                        label = "Frame Strata",
                        values = CludesUI.FRAME_STRATA_LABELS,
                        order = CludesUI.FRAME_STRATA_ORDER_BASE,
                        get = CfgOr("standaloneTimerStrata", "HIGH"),
                        set = function(val)
                            MeterSet("standaloneTimerStrata", val)
                            ApplyAttemptTimer()
                        end,
                    },
                },
            })
        end
        cursorY = cursorY - height

        -- Dependent rows: hidden entirely while the timer is disabled
        -- (SectionToggleSetValue on the master rebuilds the page).
        if MeterGet("standaloneTimer") then
            -- Show Out of Combat (with inline cog) | Anchor to Windows
            local oocRow
            oocRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Out of Combat",
                tooltip = "Keep the timer visible out of combat, showing the last fight's duration.",
                getValue = CfgOr("standaloneTimerShowOOC", false),
                setValue = function(val)
                    MeterSet("standaloneTimerShowOOC", val)
                    ApplyAttemptTimer()
                    -- Turning it OFF mid-session: resume the preview (it was
                    -- skipped at panel-open while Show OOC covered the display)
                    if not val and mod.ShowSATimerPreview then
                        mod.ShowSATimerPreview()
                    end
                end,
            }, {
                type = "dropdown",
                text = "Anchor to Windows",
                values = {
                    free = "Free Move",
                    topleft = "Top Left",
                    topright = "Top Right",
                    bottomleft = "Bottom Left",
                    bottomright = "Bottom Right",
                },
                order = { "free", "topleft", "topright", "bottomleft", "bottomright" },
                getValue = CfgOr("standaloneTimerAnchor", "free"),
                setValue = function(val)
                    MeterSet("standaloneTimerAnchor", val)
                    ApplyAttemptTimer()
                end,
            })
            -- Inline cog on Show Out of Combat for the desaturation option
            if not CludesUI._prebuilding then
                local region = oocRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Out of Combat Settings",
                    rows = {
                        {
                            type = "toggle",
                            label = "Desaturate Out of Combat",
                            disabled = function()
                                return not MeterGet("standaloneTimerShowOOC")
                            end,
                            disabledTooltip = "Show Out of Combat",
                            get = CfgOr("standaloneTimerDesatOOC", false),
                            set = function(val)
                                MeterSet("standaloneTimerDesatOOC", val)
                                ApplyAttemptTimer()
                            end,
                        },
                    },
                })
            end
            cursorY = cursorY - height

            -- "Hold Shift+Click..." label | Lock Position & Disable Click
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                { type = "label", text = "Hold Shift+Click to Freely Move Standalone Timer" },
                {
                    type = "toggle",
                    text = "Lock Position & Disable Click",
                    tooltip = "Lock the timer in place and make it click-through; no dragging and no mouse interaction until unlocked.",
                    getValue = CfgOr("standaloneTimerLocked", false),
                    setValue = function(val)
                        MeterSet("standaloneTimerLocked", val)
                        ApplyAttemptTimer()
                    end,
                }
            )
            cursorY = cursorY - height
        end

        -- ── EXTRAS ───────────────────────────────────────────────────
        _, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
        cursorY = cursorY - height

        -- Show Spell Tooltips | Show/Hide Windows Keybind (+ inline cog: what the keybind covers)
        local extrasRow
        extrasRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Spell Tooltips on Hover",
            tooltip = "Show the game's spell tooltip when you hover a spell in a breakdown window.",
            getValue = function()
                return MeterGet("showSpellTooltips") ~= false
            end,
            setValue = SetRow("showSpellTooltips"),
        }, { type = "label", text = "Show/Hide Windows Keybind" })

        if not CludesUI._prebuilding then
            local region = extrasRow._rightRegion
            local kbBtn = MakeKeybindButton(
                region,
                "toggleWindowsKey",
                "Hide and show every damage meter window at once. The state is not saved; a reload restores the configured visibility.\n\nThe bound key is taken over while it is set. Use the cog to include the combat timer and Spell History.\n\nLeft-click to set a keybind.\nRight-click to unbind."
            )

            -- Inline cog: which extra elements the keybind covers
            CludesUI.BuildInlineCog(region, {
                title = "Keybind Scope",
                rows = {
                    {
                        type = "toggle",
                        label = "Include Combat Timer",
                        get = CfgIs("toggleIncludeTimer"),
                        set = function(val)
                            MeterSet("toggleIncludeTimer", val)
                            if mod.ApplyDMToggleState then
                                mod.ApplyDMToggleState()
                            end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Include Spell History",
                        get = CfgIs("toggleIncludeSpellHistory"),
                        set = function(val)
                            MeterSet("toggleIncludeSpellHistory", val)
                            -- Forced: turning the option off has to reach Spell History
                            -- too, and by then the flag no longer asks for it
                            if mod.ApplyDMToggleState then
                                mod.ApplyDMToggleState(true)
                            end
                        end,
                    },
                },
                anchorTo = kbBtn,
            })
        end
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Spell History options page
    ---------------------------------------------------------------------------
    local PAGE_SH = "Spell History"

    local function SpellHistoryDB()
        local profile = DB()
        if not profile.spellHistory then
            profile.spellHistory = {}
        end
        return profile.spellHistory
    end

    local shGrowValues = {
        LEFT = "Left",
        RIGHT = "Right",
        UP = "Up",
        DOWN = "Down",
    }
    local shGrowOrder = { "LEFT", "RIGHT", "UP", "DOWN" }

    local function RefreshSH()
        if mod.ApplySpellHistory then
            mod.ApplySpellHistory()
        end
    end

    local function BuildSpellHistoryPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local cursorY = yOffset
        local _, height, heading

        hostFrame._showRowDivider = true

        local iconOff = function()
            return not SpellHistoryDB().iconEnabled
        end
        local barOff = function()
            return not SpellHistoryDB().barEnabled
        end

        -- =====================================================================
        --  ICON HISTORY
        -- =====================================================================
        heading, height = W:SectionHeader(hostFrame, "ICON HISTORY", cursorY)
        cursorY = cursorY - height
        CludesUI.BuildSectionUnlockJump(
            heading,
            { key = "EDM_IconHistory", disabled = iconOff, disabledTooltip = "Icon History" }
        )

        -- Row 1: Enable Icon History | "Hold Shift+Click..." label
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Icon History",
            tooltip = "Shows a movable strip of recent spell icons. Shift-drag to reposition.",
            getValue = function()
                return SpellHistoryDB().iconEnabled
            end,
            setValue = function(val)
                SpellHistoryDB().iconEnabled = val
                RefreshSH()
                if mod.RegisterDMUnlock then
                    mod.RegisterDMUnlock()
                end
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "Hold Shift+Click to Freely Move Icons" })
        cursorY = cursorY - height

        -- Row 2: Grow Direction | Visibility Options
        local SH_ICON_VIS_ITEMS = {
            { key = "iconHideInDungeon", label = "Hide in Dungeons" },
            { key = "iconHideInRaid", label = "Hide in Raids" },
            { key = "iconHideInDelve", label = "Hide in Delves" },
            { key = "iconHideInPvP", label = "Hide in PvP" },
            { key = "iconHideOutOfInstance", label = "Hide out of Instances" },
        }
        -- No delves on WoW Forever: the list drops its Delves entry there.
        if CludesUI.IS_FOREVER then
            for idx = #SH_ICON_VIS_ITEMS, 1, -1 do
                if SH_ICON_VIS_ITEMS[idx].key == "iconHideInDelve" then
                    table.remove(SH_ICON_VIS_ITEMS, idx)
                end
            end
        end
        local iconVisRow
        iconVisRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Grow Direction",
            tooltip = "Direction the icon strip grows as new spells are cast.",
            disabled = iconOff,
            disabledTooltip = "Icon History",
            values = shGrowValues,
            order = shGrowOrder,
            getValue = function()
                return SpellHistoryDB().growDirection or "LEFT"
            end,
            setValue = function(val)
                SpellHistoryDB().growDirection = val
                RefreshSH()
            end,
        }, {
            type = "dropdown",
            text = "Visibility Options",
            disabled = iconOff,
            disabledTooltip = "Icon History",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = iconVisRow._rightRegion
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                SH_ICON_VIS_ITEMS,
                function(keyName)
                    return SpellHistoryDB()[keyName] or false
                end,
                function(keyName, val)
                    SpellHistoryDB()[keyName] = val
                    RefreshSH()
                end
            )
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 3: Icon Size (+ icon zoom cog) | Max Icons
        local shSizeRow
        shSizeRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 20,
            max = 60,
            step = 1,
            disabled = iconOff,
            disabledTooltip = "Icon History",
            getValue = function()
                return SpellHistoryDB().iconSize or 36
            end,
            setValue = function(val)
                SpellHistoryDB().iconSize = val
                RefreshSH()
            end,
        }, {
            type = "slider",
            text = "Max Icons",
            tooltip = "Maximum number of spell icons to display.",
            min = 1,
            max = 10,
            step = 1,
            disabled = iconOff,
            disabledTooltip = "Icon History",
            getValue = function()
                return SpellHistoryDB().iconCount or 5
            end,
            setValue = function(val)
                SpellHistoryDB().iconCount = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on Icon Size: Icon Zoom (shared by the icon strip and the
        -- bar window, so it stays usable whenever either display is on).
        if not CludesUI._prebuilding then
            local region = shSizeRow._leftRegion
            local shZoomOff = function()
                return iconOff() and barOff()
            end
            CludesUI.BuildInlineCog(region, {
                title = "Icon Zoom",
                rows = {
                    {
                        type = "slider",
                        label = "Zoom",
                        min = 0,
                        max = 0.20,
                        step = 0.01,
                        get = function()
                            return SpellHistoryDB().iconZoom or 0.08
                        end,
                        set = function(val)
                            SpellHistoryDB().iconZoom = val
                            RefreshSH()
                        end,
                    },
                },
                disabled = shZoomOff,
                disabledTooltip = "Icon History or Bar History",
            })
        end

        -- Row 4: Icon Spacing | Opacity
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = 0,
            max = 10,
            step = 1,
            disabled = iconOff,
            disabledTooltip = "Icon History",
            getValue = function()
                return SpellHistoryDB().iconSpacing or 1
            end,
            setValue = function(val)
                SpellHistoryDB().iconSpacing = val
                RefreshSH()
            end,
        }, {
            type = "slider",
            text = "Opacity",
            min = 0.1,
            max = 1,
            step = 0.01,
            disabled = iconOff,
            disabledTooltip = "Icon History",
            getValue = function()
                return SpellHistoryDB().iconOpacity or 1
            end,
            setValue = function(val)
                SpellHistoryDB().iconOpacity = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height

        -- Row 5: Animation Style | Fade-Out Time
        local shAnimValues = {
            none = "None",
            slide = "Slide In",
            fly = "Fly In",
        }
        local shAnimOrder = { "none", "slide", "fly" }
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Animation Style",
            disabled = iconOff,
            disabledTooltip = "Icon History",
            values = shAnimValues,
            order = shAnimOrder,
            getValue = function()
                return SpellHistoryDB().iconAnimation or "slide"
            end,
            setValue = function(val)
                SpellHistoryDB().iconAnimation = val
            end,
        }, {
            type = "slider",
            text = "Fade-Out Time",
            tooltip = "Seconds after which history icons fade out. The timer pauses during combat. 0 = never.",
            min = 0,
            max = 60,
            step = 1,
            disabled = iconOff,
            disabledTooltip = "Icon History",
            getValue = function()
                return SpellHistoryDB().iconFadeTime or 0
            end,
            setValue = function(val)
                SpellHistoryDB().iconFadeTime = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height

        -- =====================================================================
        --  BAR HISTORY
        -- =====================================================================
        _, height = W:SectionHeader(hostFrame, "BAR HISTORY", cursorY)
        cursorY = cursorY - height

        -- Row 1: Enable Bar History | Visibility Options
        local SH_BAR_VIS_ITEMS = {
            { key = "barHideInDungeon", label = "Hide in Dungeons" },
            { key = "barHideInRaid", label = "Hide in Raids" },
            { key = "barHideInDelve", label = "Hide in Delves" },
            { key = "barHideInPvP", label = "Hide in PvP" },
            { key = "barHideOutOfInstance", label = "Hide out of Instances" },
        }
        -- No delves on WoW Forever: the list drops its Delves entry there.
        if CludesUI.IS_FOREVER then
            for idx = #SH_BAR_VIS_ITEMS, 1, -1 do
                if SH_BAR_VIS_ITEMS[idx].key == "barHideInDelve" then
                    table.remove(SH_BAR_VIS_ITEMS, idx)
                end
            end
        end
        local barVisRow
        barVisRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Bar History",
            tooltip = "Shows a standalone window with spell cast history as bars. Matches your Damage Meters styling.",
            getValue = function()
                return SpellHistoryDB().barEnabled
            end,
            setValue = function(val)
                SpellHistoryDB().barEnabled = val
                RefreshSH()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Visibility Options",
            disabled = barOff,
            disabledTooltip = "Bar History",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            local region = barVisRow._rightRegion
            if region._control then
                region._control:Hide()
            end
            local checkDrop, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                SH_BAR_VIS_ITEMS,
                function(keyName)
                    return SpellHistoryDB()[keyName] or false
                end,
                function(keyName, val)
                    SpellHistoryDB()[keyName] = val
                    RefreshSH()
                end
            )
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 2: Background Opacity (+ inline color swatch) | Hide Top Bar
        local bgRow
        bgRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Background Opacity",
            min = 0,
            max = 1,
            step = 0.01,
            disabled = barOff,
            disabledTooltip = "Bar History",
            getValue = function()
                return SpellHistoryDB().bgAlpha or 0.25
            end,
            setValue = function(val)
                SpellHistoryDB().bgAlpha = val
                RefreshSH()
            end,
        }, {
            type = "toggle",
            text = "Hide Top Bar",
            disabled = barOff,
            disabledTooltip = "Bar History",
            getValue = function()
                return SpellHistoryDB().hideTopBar
            end,
            setValue = function(val)
                SpellHistoryDB().hideTopBar = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height
        -- Background colour swatch on the opacity slider; none in the search
        -- pre-build (it indexes nothing, and the row is a stand-in there)
        if not CludesUI._prebuilding then
            local region = bgRow._leftRegion
            local control = region._control
            local colorSwatch, swatchRefresh = CludesUI.BuildColorSwatch(
                region,
                bgRow:GetFrameLevel() + 3,
                function()
                    return (SpellHistoryDB().bgR or 0), (SpellHistoryDB().bgG or 0), (SpellHistoryDB().bgB or 0)
                end,
                function(red, green, blue)
                    SpellHistoryDB().bgR = red
                    SpellHistoryDB().bgG = green
                    SpellHistoryDB().bgB = blue
                    RefreshSH()
                end,
                false,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", control, "LEFT", -8, 0)
            -- Blizzard Style paints the stock window art (colour unused); the
            -- classic box is tinted by this colour.
            if DMBlizzArt() then
                CludesUI.BlizzStyle.BlockInline("damagemeters", colorSwatch)
            end
            local block = CludesUI.NewSwatchBlocker(colorSwatch)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip("Bar History"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            CludesUI.RegisterWidgetRefresh(function()
                local off = barOff()
                colorSwatch:SetAlpha(off and 0.3 or 1)
                if off then
                    block:Show()
                else
                    block:Hide()
                end
                swatchRefresh()
            end)
            local initOff = barOff()
            colorSwatch:SetAlpha(initOff and 0.3 or 1)
            if initOff then
                block:Show()
            else
                block:Hide()
            end
        end

        -- Row 3: Bar Height | Max Bars
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Bar Height",
            min = 12,
            max = 32,
            step = 1,
            disabled = barOff,
            disabledTooltip = "Bar History",
            getValue = function()
                return SpellHistoryDB().shBarHeight or 18
            end,
            setValue = function(val)
                SpellHistoryDB().shBarHeight = val
                RefreshSH()
            end,
        }, {
            type = "slider",
            text = "Max Bars",
            tooltip = "Maximum number of bars to display. Window height adjusts automatically.",
            min = 1,
            max = 10,
            step = 1,
            disabled = barOff,
            disabledTooltip = "Bar History",
            getValue = function()
                return SpellHistoryDB().maxBars or 5
            end,
            setValue = function(val)
                SpellHistoryDB().maxBars = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height

        -- Row 4: Bar Texture | Text Size (+ inline dual swatches)
        local textRow
        textRow, height = W:DualRow(
            hostFrame,
            cursorY,
            DMBlizzGate({
                type = "dropdown",
                text = "Bar Texture",
                disabled = barOff,
                disabledTooltip = "Bar History",
                values = matchTexValues,
                order = matchTexOrder,
                getValue = function()
                    return SpellHistoryDB().spellHistoryBarTexture or "match"
                end,
                setValue = function(val)
                    SpellHistoryDB().spellHistoryBarTexture = val
                    RefreshSH()
                end,
            }),
            {
                type = "slider",
                text = "Text Size",
                min = 8,
                max = 16,
                step = 1,
                disabled = barOff,
                disabledTooltip = "Bar History",
                getValue = function()
                    return SpellHistoryDB().textSize or 11
                end,
                setValue = function(val)
                    SpellHistoryDB().textSize = val
                    RefreshSH()
                end,
            }
        )
        cursorY = cursorY - height

        -- Row 5: Bar Color | Opacity
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "multiSwatch",
            text = "Bar Color",
            disabled = barOff,
            disabledTooltip = "Bar History",
            swatches = {
                {
                    tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local classColor = CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
                        if classColor then
                            return classColor.r, classColor.g, classColor.b
                        end
                        return 0.96, 0.55, 0.73
                    end,
                    setValue = function() end,
                    onClick = function()
                        SpellHistoryDB().barColorUseClass = true
                        SpellHistoryDB().barColorUseAccent = false
                        RefreshSH()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return SpellHistoryDB().barColorUseClass and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = SpellHistoryDB().barColor
                        if color then
                            return color.r or 0.298, color.g or 0.565, color.b or 0.494
                        end
                        return 0.298, 0.565, 0.494
                    end,
                    setValue = function(red, green, blue)
                        SpellHistoryDB().barColor = { r = red, g = green, b = blue }
                        SpellHistoryDB().barColorUseClass = false
                        SpellHistoryDB().barColorUseAccent = false
                        RefreshSH()
                        CludesUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if SpellHistoryDB().barColorUseClass or SpellHistoryDB().barColorUseAccent then
                            SpellHistoryDB().barColorUseClass = false
                            SpellHistoryDB().barColorUseAccent = false
                            RefreshSH()
                            CludesUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then
                            self._eabOrigClick(self)
                        end
                    end,
                    refreshAlpha = function()
                        if SpellHistoryDB().barColorUseClass then
                            return 0.15
                        end
                        return SpellHistoryDB().barColorUseAccent and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return CludesUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        SpellHistoryDB().barColorUseClass = false
                        SpellHistoryDB().barColorUseAccent = true
                        RefreshSH()
                        CludesUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if SpellHistoryDB().barColorUseClass then
                            return 0.15
                        end
                        return SpellHistoryDB().barColorUseAccent and 1 or 0.3
                    end,
                },
            },
        }, {
            type = "slider",
            text = "Opacity",
            min = 0.1,
            max = 1,
            step = 0.01,
            disabled = barOff,
            disabledTooltip = "Bar History",
            getValue = function()
                return SpellHistoryDB().barOpacity or 1
            end,
            setValue = function(val)
                SpellHistoryDB().barOpacity = val
                RefreshSH()
            end,
        })
        cursorY = cursorY - height

        if not CludesUI._prebuilding then
            local region = textRow._rightRegion
            local control = region._control

            local customColorSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                textRow:GetFrameLevel() + 3,
                function()
                    local color = SpellHistoryDB().textColor
                    if color then
                        return color.r or 1, color.g or 1, color.b or 1
                    end
                    return 1, 1, 1
                end,
                function(red, green, blue)
                    SpellHistoryDB().textColorUseAccent = false
                    SpellHistoryDB().textColor = { r = red, g = green, b = blue }
                    RefreshSH()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", control, "LEFT", -8, 0)
            local origClick = customColorSwatch:GetScript("OnClick")
            customColorSwatch:SetScript("OnClick", function(self, ...)
                if SpellHistoryDB().textColorUseAccent then
                    SpellHistoryDB().textColorUseAccent = false
                    RefreshSH()
                    CludesUI:RefreshPage()
                    return
                end
                if origClick then
                    origClick(self, ...)
                end
            end)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            local accentColorSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                textRow:GetFrameLevel() + 3,
                function()
                    return CludesUI.ResolveActiveAccent()
                end,
                function()
                    SpellHistoryDB().textColorUseAccent = true
                    RefreshSH()
                    CludesUI:RefreshPage()
                end,
                false,
                20
            )
            Pix.Point(accentColorSwatch, "RIGHT", customColorSwatch, "LEFT", -8, 0)
            accentColorSwatch:SetScript("OnClick", function()
                SpellHistoryDB().textColorUseAccent = true
                RefreshSH()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(accentColorSwatch, "Accent Color")

            local function MakeSwatchBlock(colorSwatch)
                local block = CludesUI.NewSwatchBlocker(colorSwatch)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip("Bar History"))
                end)
                block:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                return block
            end
            local customBlock = MakeSwatchBlock(customColorSwatch)
            local accentBlock = MakeSwatchBlock(accentColorSwatch)

            local function refreshTextSwatches()
                updateCustom()
                updateAccent()
                local off = barOff()
                local accentOn = SpellHistoryDB().textColorUseAccent
                customColorSwatch:SetAlpha(off and 0.3 or (accentOn and 0.3 or 1))
                accentColorSwatch:SetAlpha(off and 0.3 or (accentOn and 1 or 0.3))
                if off then
                    customBlock:Show()
                    accentBlock:Show()
                else
                    customBlock:Hide()
                    accentBlock:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(refreshTextSwatches)
            refreshTextSwatches()
        end

        return math.abs(cursorY)
    end

    CludesUI:RegisterModule("CludesUIDamageMeters", {
        title = "Damage Meters",
        description = "Custom damage meter using Blizzard's built-in combat data.",
        searchTerms = "damage meters dps hps healing interrupts dispels spell history",
        pages = { "Damage Meters", PAGE_SH },
        buildPage = function(page, p, yOffset)
            -- This unconditionally forces every real damage-meter window (ns._windows,
            -- parented to UIParent) and the standalone timer preview live and
            -- mouse-interactive on screen -- not scoped to `p`/the hidden pre-build
            -- wrapper at all. During an off-screen search pre-build this would pop the
            -- player's real meter windows onto the screen with no interaction. Skip it;
            -- BuildPage/ BuildSpellHistoryPage build purely onto `p`, so still index
            -- normally during the hidden pass.
            if not CludesUI._prebuilding then
                mod._optionsOpen = true
                if mod.ShowSATimerPreview and MeterGet("standaloneTimer") then
                    mod.ShowSATimerPreview()
                end
                if mod.ApplySpellHistory then
                    mod.ApplySpellHistory()
                end
                for _, wid in ipairs(mod._windows or {}) do
                    if wid.frame then
                        wid.frame:SetAlpha(1)
                        wid.frame:EnableMouse(true)
                        wid.frame:Show()
                    end
                end
            end
            if page == PAGE_SH then
                return BuildSpellHistoryPage(page, p, yOffset)
            end
            return BuildPage(page, p, yOffset)
        end,
        onPageCacheRestore = function()
            mod._optionsOpen = true
            if mod.ShowSATimerPreview and MeterGet("standaloneTimer") then
                mod.ShowSATimerPreview()
            end
            if mod.ApplySpellHistory then
                mod.ApplySpellHistory()
            end
            for _, wid in ipairs(mod._windows or {}) do
                if wid.frame then
                    wid.frame:SetAlpha(1)
                    wid.frame:EnableMouse(true)
                    wid.frame:Show()
                end
            end
        end,
        onReset = function()
            local db = _G._CUDM_DB
            if db and db.ResetProfile then
                db:ResetProfile()
            end
        end,
        -- Mirrors RegisterOnHide below: SA Timer Preview + forced-visible
        -- meter windows, on module switch instead of just window close.
        onModuleLeave = function()
            if mod.HideSATimerPreview then
                mod.HideSATimerPreview()
            end
            mod._optionsOpen = false
            for _, wid in ipairs(mod._windows or {}) do
                if wid.UpdateVisibility then
                    wid.UpdateVisibility()
                end
            end
            if mod.ApplySpellHistory then
                mod.ApplySpellHistory()
            end
        end,
    })

    -- Show preview when panel opens on DM page, hide when panel closes
    CludesUI:RegisterOnShow(function()
        if CludesUI:GetActiveModule() == "CludesUIDamageMeters" then
            if mod.ShowSATimerPreview and MeterGet("standaloneTimer") then
                mod.ShowSATimerPreview()
            end
            mod._optionsOpen = true
            for _, wid in ipairs(mod._windows or {}) do
                if wid.frame then
                    wid.frame:SetAlpha(1)
                    wid.frame:EnableMouse(true)
                    wid.frame:Show()
                end
            end
            if mod.ApplySpellHistory then
                mod.ApplySpellHistory()
            end
        end
    end)
    CludesUI:RegisterOnHide(function()
        if mod.HideSATimerPreview then
            mod.HideSATimerPreview()
        end
        mod._optionsOpen = false
        for _, wid in ipairs(mod._windows or {}) do
            if wid.UpdateVisibility then
                wid.UpdateVisibility()
            end
        end
        if mod.ApplySpellHistory then
            mod.ApplySpellHistory()
        end
    end)
end)
