if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_CursorLite_Options.lua
--  Registers the Cursor Lite module with CludesUI.
--  All get/set calls go to the addon's DB profile.
--  Does NOT touch cursor tracking logic.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIQoL"
local mod = CUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then return end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

local PAGE_CURSOR = "Cursor"
local PAGE_UNLOCK = "Layout Mode"

local SECTION_APPEARANCE = "CURSOR"
local SECTION_GCD = "GLOBAL COOLDOWN"
local SECTION_CAST = "CAST BAR"

local strupper, strgsub, strmatch, strsub = string.upper, string.gsub, string.match, string.sub
local floor = math.floor

CUI.AtOptionsLogin(function()
    local Pix = CUI.PP

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local saved

    C_Timer.After(0, function() saved = _G._CUCL_AceDB end)

    local function DB()
        if not saved then saved = _G._CUCL_AceDB end
        return saved and saved.profile
    end

    local function GcdCfg()
        local profile = DB()
        if not profile then return {} end
        if not profile.gcd then profile.gcd = {} end
        return profile.gcd
    end

    local function CastCfg()
        local profile = DB()
        if not profile then return {} end
        if not profile.castCircle then profile.castCircle = {} end
        return profile.castCircle
    end

    ---------------------------------------------------------------------------
    --  Hex color helpers
    ---------------------------------------------------------------------------
    local function HexToRGB(hex)
        hex = strupper(strgsub(hex or "4CC9F0", "#", ""))
        if not strmatch(hex, "^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then hex = "4CC9F0" end
        return tonumber(strsub(hex, 1, 2), 16) / 255,
            tonumber(strsub(hex, 3, 4), 16) / 255,
            tonumber(strsub(hex, 5, 6), 16) / 255
    end

    local function RGBToHex(red, green, blue)
        return string.format(
            "%02X%02X%02X",
            floor(red * 255 + 0.5),
            floor(green * 255 + 0.5),
            floor(blue * 255 + 0.5)
        )
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function ApplyCursor()
        if _G._CUCL_Apply then _G._CUCL_Apply() end
    end

    local function ApplyGcdCircle()
        if _G._CUCL_ApplyGCDCircle then _G._CUCL_ApplyGCDCircle() end
        if _G._CUCL_RegisterUnlock then _G._CUCL_RegisterUnlock() end
    end

    local function ApplyCastCircle()
        if _G._CUCL_ApplyCastCircle then _G._CUCL_ApplyCastCircle() end
        if _G._CUCL_RegisterUnlock then _G._CUCL_RegisterUnlock() end
    end

    ---------------------------------------------------------------------------
    --  Ring texture dropdown values (shared by GCD + Cast)
    ---------------------------------------------------------------------------
    local ringTexValues = {
        normal = "Ring Normal",
        light = "Ring Light",
        thin = "Ring Thin",
        heavy = "Ring Heavy",
        thick = "Ring Thick",
    }
    local ringTexOrder = { "normal", "light", "---", "thin", "heavy", "thick" }

    ---------------------------------------------------------------------------
    --  Cursor Circle page  (Appearance + GCD + Cast Bar sections)
    ---------------------------------------------------------------------------
    local function BuildCursorPage(page, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height, row, heading

        CUI:ClearContentHeader()

        -----------------------------------------------------------------------
        --  APPEARANCE
        -----------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, SECTION_APPEARANCE, cursorY)
        cursorY = cursorY - height

        -- Enable Cursor Circle ---- Color (multiSwatch: custom left, class colored right)
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Cursor Circle",
            tooltip = "Shows a circle around your cursor.",
            getValue = function()
                local profile = DB()
                return profile and (profile.enabled ~= false)
            end,
            -- DependentSetValue: the rows below Row 1 are hidden while the
            -- circle is off; the flip forces the full rebuild.
            setValue = CUI.DependentSetValue(function()
                local profile = DB()
                return profile and (profile.enabled ~= false)
            end, function(val)
                local profile = DB()
                if not profile then return end
                profile.enabled = val
                ApplyCursor()
                CUI:RefreshPage()
            end),
        }, {
            type = "multiSwatch",
            text = "Color",
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local profile = DB()
                        if not profile then return 76 / 255, 201 / 255, 240 / 255 end
                        local red, green, b = HexToRGB(profile.hex)
                        return red, green, b
                    end,
                    setValue = function(red, green, blue)
                        local profile = DB()
                        if not profile then return end
                        profile.hex = RGBToHex(red, green, blue)
                        ApplyCursor()
                    end,
                    onClick = function(self)
                        local profile = DB()
                        if not profile then return end
                        if profile.useClassColor or profile.useAccentColor then
                            profile.useClassColor = false
                            profile.useAccentColor = false
                            ApplyCursor()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local profile = DB()
                        if not profile or profile.enabled == false then return 0.15 end
                        return (profile.useClassColor or profile.useAccentColor) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 76 / 255, 201 / 255, 240 / 255
                    end,
                    setValue = function() end,
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        profile.useClassColor = true
                        profile.useAccentColor = false
                        ApplyCursor()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local profile = DB()
                        if not profile or profile.enabled == false then return 0.15 end
                        return profile.useClassColor and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        local ar, ag, ab = CUI.GetAccentColor()
                        return ar, ag, ab
                    end,
                    setValue = function() end,
                    onClick = function()
                        local profile = DB()
                        if not profile then return end
                        profile.useAccentColor = true
                        profile.useClassColor = false
                        ApplyCursor()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local profile = DB()
                        if not profile or profile.enabled == false then return 0.15 end
                        return profile.useAccentColor and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height
        -- Block overlay on the right region when Cursor Circle is disabled
        if not CUI._prebuilding then
            local rightRegion = row._rightRegion
            local circleBlock = CreateFrame("Frame", nil, rightRegion)
            circleBlock:SetAllPoints()
            circleBlock:SetFrameLevel(rightRegion:GetFrameLevel() + 20)
            circleBlock:EnableMouse(true)
            circleBlock:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(rightRegion, CUI.DisabledTooltip("Cursor Circle")) end
            )
            circleBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function UpdateCircleBlock()
                local profile = DB()
                local off = not profile or profile.enabled == false
                circleBlock:SetShown(off)
                -- Dim the "Color" label with its swatches
                if rightRegion._label then rightRegion._label:SetAlpha(off and 0.3 or 1) end
            end
            UpdateCircleBlock()
            CUI.RegisterWidgetRefresh(UpdateCircleBlock)
        end

        -- Rows below are HIDDEN entirely while the Cursor Circle is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if DB() and DB().enabled ~= false then
            -- Texture ---- Scale
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Texture",
                values = {
                    ring_normal = "Ring Normal",
                    ring_light = "Ring Light",
                    custom = "Cludes Logo",
                    ring_thin = "Ring Thin",
                    ring_heavy = "Ring Heavy",
                    ring_thick = "Ring Thick",
                },
                order = {
                    "ring_normal",
                    "ring_light",
                    "custom",
                    "---",
                    "ring_thin",
                    "ring_heavy",
                    "ring_thick",
                },
                getValue = function()
                    local profile = DB()
                    return profile and profile.texture or "ring_normal"
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.texture = val
                    ApplyCursor()
                end,
            }, {
                type = "slider",
                text = "Scale",
                min = 0.5,
                max = 2.0,
                step = 0.1,
                getValue = function()
                    local profile = DB()
                    return profile and profile.scale or 1
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.scale = val
                    ApplyCursor()
                end,
            })
            cursorY = cursorY - height

            -- Circle Opacity ---- Cursor Trail
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Circle Opacity",
                tooltip = "How visible the circle is.",
                min = 0,
                max = 100,
                step = 1,
                getValue = function()
                    local profile = DB()
                    return profile and (profile.alpha or 100)
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.alpha = val
                    ApplyCursor()
                end,
            }, {
                type = "toggle",
                text = "Cursor Trail",
                tooltip = "A trail that follows your cursor.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.trail or false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.trail = val
                    if _G._CUCL_ApplyTrail then _G._CUCL_ApplyTrail() end
                end,
            })
            cursorY = cursorY - height

            -- Only Show in Instances ---- Only Show When Hidden
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Only Show in Instances",
                tooltip = "Shows it only in dungeons and raids.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.instanceOnly
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.instanceOnly = val
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            }, {
                type = "toggle",
                text = "Only Show When Hidden",
                tooltip = "Only shows the cursor circle while the mouse is hidden -- that is, while you hold the left and/or right mouse button to pan the camera or move your character.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.onlyWhenHidden or false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.onlyWhenHidden = val
                    if _G._CUCL_ApplyOnlyWhenHidden then _G._CUCL_ApplyOnlyWhenHidden() end
                end,
            })
            cursorY = cursorY - height

            -- Combat Only ---- Center Reticle
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Combat Only",
                tooltip = "Only shows the cursor circle while you are in combat.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.combatOnly or false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.combatOnly = val
                    if _G._CUCL_ApplyCombatOnlyEvents then _G._CUCL_ApplyCombatOnlyEvents() end
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            }, {
                type = "toggle",
                text = "Center Reticle",
                tooltip = "Adds a small filled dot at the center of the cursor circle. Uses the same color and opacity as the circle.",
                getValue = function()
                    local profile = DB()
                    return profile and profile.reticle or false
                end,
                setValue = function(val)
                    local profile = DB()
                    if not profile then return end
                    profile.reticle = val
                    ApplyCursor()
                end,
            })
            cursorY = cursorY - height
        end -- close Cursor Circle hidden-while-disabled gate

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -----------------------------------------------------------------------
        --  GLOBAL COOLDOWN
        -----------------------------------------------------------------------
        heading, height = W:SectionHeader(hostFrame, SECTION_GCD, cursorY)
        cursorY = cursorY - height
        -- The circle has a mover only while enabled and detached from the
        -- cursor, so the button names whichever of the two it still needs.
        CUI.BuildSectionUnlockJump(heading, {
            key = "ECL_GCD",
            disabled = function()
                local gcdCfg = GcdCfg()
                return not (gcdCfg.enabled and gcdCfg.attached == false)
            end,
            disabledTooltip = function() return GcdCfg().enabled and "Attach to Cursor" or "GCD Circle" end,
            requireState = function() return GcdCfg().enabled and "disabled" or "enabled" end,
        })

        -- Enable GCD Circle ---- Color (multiSwatch: custom left, class colored right)
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable GCD Circle",
            tooltip = "Shows the global cooldown as a circle at the cursor.",
            getValue = function() return GcdCfg().enabled or false end,
            -- DependentSetValue: the rows below Row 1 are hidden while the
            -- circle is off; the flip forces the full rebuild.
            setValue = CUI.DependentSetValue(
                function() return GcdCfg().enabled or false end,
                function(val)
                    GcdCfg().enabled = val
                    ApplyGcdCircle()
                    CUI:RefreshPage()
                end
            ),
        }, {
            type = "multiSwatch",
            text = "Color",
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local gcdCfg = GcdCfg()
                        local r, ng, b = HexToRGB(gcdCfg.hex)
                        return r, ng, b
                    end,
                    setValue = function(red, green, blue)
                        local gd = GcdCfg()
                        gd.hex = RGBToHex(red, green, blue)
                        ApplyGcdCircle()
                    end,
                    onClick = function(self)
                        local gcdCfg = GcdCfg()
                        if gcdCfg.useClassColor or gcdCfg.useAccentColor then
                            gcdCfg.useClassColor = false
                            gcdCfg.useAccentColor = false
                            ApplyGcdCircle()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local gcdCfg = GcdCfg()
                        if not gcdCfg.enabled then return 0.15 end
                        return (gcdCfg.useClassColor or gcdCfg.useAccentColor) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 76 / 255, 201 / 255, 240 / 255
                    end,
                    setValue = function() end,
                    onClick = function()
                        local gcdCfg = GcdCfg()
                        gcdCfg.useClassColor = true
                        gcdCfg.useAccentColor = false
                        ApplyGcdCircle()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local gcdCfg = GcdCfg()
                        if not gcdCfg.enabled then return 0.15 end
                        return gcdCfg.useClassColor and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        local ar, ag, ab = CUI.GetAccentColor()
                        return ar, ag, ab
                    end,
                    setValue = function() end,
                    onClick = function()
                        local gcdCfg = GcdCfg()
                        gcdCfg.useAccentColor = true
                        gcdCfg.useClassColor = false
                        ApplyGcdCircle()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local gcdCfg = GcdCfg()
                        if not gcdCfg.enabled then return 0.15 end
                        return gcdCfg.useAccentColor and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height
        -- Block overlay on the right region when GCD Circle is disabled
        if not CUI._prebuilding then
            local rightRegion = row._rightRegion
            local gcdBlock = CreateFrame("Frame", nil, rightRegion)
            gcdBlock:SetAllPoints()
            gcdBlock:SetFrameLevel(rightRegion:GetFrameLevel() + 20)
            gcdBlock:EnableMouse(true)
            gcdBlock:SetScript(
                "OnEnter",
                function() CUI.ShowWidgetTooltip(rightRegion, CUI.DisabledTooltip("GCD Circle")) end
            )
            gcdBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function UpdateGCDBlock()
                local off = not GcdCfg().enabled
                gcdBlock:SetShown(off)
                -- Dim the "Color" label with its swatches
                if rightRegion._label then rightRegion._label:SetAlpha(off and 0.3 or 1) end
            end
            UpdateGCDBlock()
            CUI.RegisterWidgetRefresh(UpdateGCDBlock)
        end

        -- Rows below are HIDDEN entirely while the GCD Circle is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if GcdCfg().enabled then
            -- Ring Texture ---- Scale
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Ring Texture",
                values = ringTexValues,
                order = ringTexOrder,
                getValue = function() return GcdCfg().ringTex or "light" end,
                setValue = function(val)
                    GcdCfg().ringTex = val
                    ApplyGcdCircle()
                end,
            }, {
                type = "slider",
                text = "Scale",
                min = 10,
                max = 100,
                step = 1,
                getValue = function() return GcdCfg().radius or 21 end,
                setValue = function(val)
                    GcdCfg().radius = val
                    ApplyGcdCircle()
                end,
            })
            cursorY = cursorY - height

            -- Circle Opacity ---- Attach to Cursor
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Circle Opacity",
                tooltip = "How visible the circle is.",
                min = 0,
                max = 100,
                step = 1,
                getValue = function() return GcdCfg().alpha or 80 end,
                setValue = function(val)
                    GcdCfg().alpha = val
                    ApplyGcdCircle()
                end,
            }, {
                type = "toggle",
                text = "Attach to Cursor",
                getValue = function() return GcdCfg().attached ~= false end,
                setValue = function(val)
                    GcdCfg().attached = val
                    ApplyGcdCircle()
                    CUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height

            -- Only Show in Instances ---- Combat Only
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Only Show in Instances",
                tooltip = "Shows it only in dungeons and raids.",
                getValue = function() return GcdCfg().instanceOnly or false end,
                setValue = function(val)
                    GcdCfg().instanceOnly = val
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            }, {
                type = "toggle",
                text = "Combat Only",
                tooltip = "Only shows the GCD circle while you are in combat.",
                getValue = function() return GcdCfg().combatOnly or false end,
                setValue = function(val)
                    GcdCfg().combatOnly = val
                    if _G._CUCL_ApplyCombatOnlyEvents then _G._CUCL_ApplyCombatOnlyEvents() end
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            })
            cursorY = cursorY - height
        end -- close GCD Circle hidden-while-disabled gate

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -----------------------------------------------------------------------
        --  CAST BAR
        -----------------------------------------------------------------------
        heading, height = W:SectionHeader(hostFrame, SECTION_CAST, cursorY)
        cursorY = cursorY - height
        -- As the GCD circle: a mover only while enabled and detached.
        CUI.BuildSectionUnlockJump(heading, {
            key = "ECL_Cast",
            disabled = function()
                local cfg = CastCfg()
                return not (cfg.enabled and cfg.attached == false)
            end,
            disabledTooltip = function() return CastCfg().enabled and "Attach to Cursor" or "Cast Bar Circle" end,
            requireState = function() return CastCfg().enabled and "disabled" or "enabled" end,
        })

        -- Enable Cast Bar Circle ---- Color (multiSwatch: custom left, class colored right)
        row, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Enable Cast Bar Circle",
            tooltip = "Shows your cast progress as a circle at the cursor.",
            getValue = function() return CastCfg().enabled or false end,
            -- DependentSetValue: the rows below Row 1 are hidden while the
            -- circle is off; the flip forces the full rebuild.
            setValue = CUI.DependentSetValue(
                function() return CastCfg().enabled or false end,
                function(val)
                    CastCfg().enabled = val
                    ApplyCastCircle()
                    CUI:RefreshPage()
                end
            ),
        }, {
            type = "multiSwatch",
            text = "Color",
            swatches = {
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local cfg = CastCfg()
                        local r, ng, b = HexToRGB(cfg.hex)
                        return r, ng, b
                    end,
                    setValue = function(red, green, blue)
                        local cd = CastCfg()
                        cd.hex = RGBToHex(red, green, blue)
                        ApplyCastCircle()
                    end,
                    onClick = function(self)
                        local cfg = CastCfg()
                        if cfg.useClassColor or cfg.useAccentColor then
                            cfg.useClassColor = false
                            cfg.useAccentColor = false
                            ApplyCastCircle()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local cfg = CastCfg()
                        if not cfg.enabled then return 0.15 end
                        return (cfg.useClassColor or cfg.useAccentColor) and 0.3 or 1
                    end,
                },
                {
                    tooltip = "Class Colored",
                    hasAlpha = false,
                    getValue = function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 76 / 255, 201 / 255, 240 / 255
                    end,
                    setValue = function() end,
                    onClick = function()
                        local cfg = CastCfg()
                        cfg.useClassColor = true
                        cfg.useAccentColor = false
                        ApplyCastCircle()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local cfg = CastCfg()
                        if not cfg.enabled then return 0.15 end
                        return cfg.useClassColor and 1 or 0.3
                    end,
                },
                {
                    tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        local ar, ag, ab = CUI.GetAccentColor()
                        return ar, ag, ab
                    end,
                    setValue = function() end,
                    onClick = function()
                        local cfg = CastCfg()
                        cfg.useAccentColor = true
                        cfg.useClassColor = false
                        ApplyCastCircle()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local cfg = CastCfg()
                        if not cfg.enabled then return 0.15 end
                        return cfg.useAccentColor and 1 or 0.3
                    end,
                },
            },
        })
        cursorY = cursorY - height
        -- Block overlay on the right region when Cast Bar Circle is disabled
        if not CUI._prebuilding then
            local rightRegion = row._rightRegion
            local castBlock = CreateFrame("Frame", nil, rightRegion)
            castBlock:SetAllPoints()
            castBlock:SetFrameLevel(rightRegion:GetFrameLevel() + 20)
            castBlock:EnableMouse(true)
            castBlock:SetScript(
                "OnEnter",
                function()
                    CUI.ShowWidgetTooltip(rightRegion, CUI.DisabledTooltip("Cast Bar Circle"))
                end
            )
            castBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            local function UpdateCastBlock()
                local off = not CastCfg().enabled
                castBlock:SetShown(off)
                -- Dim the "Color" label with its swatches
                if rightRegion._label then rightRegion._label:SetAlpha(off and 0.3 or 1) end
            end
            UpdateCastBlock()
            CUI.RegisterWidgetRefresh(UpdateCastBlock)
        end

        -- Inline cog on Enable Cast Bar Circle for "Show Spark"
        CUI.BuildInlineCog(row._leftRegion, {
            title = "Cast Bar Settings",
            disabled = function() return not CastCfg().enabled end,
            disabledTooltip = "Cast Bar Circle",
            rows = {
                {
                    type = "toggle",
                    label = "Show Spark",
                    get = function()
                        local cfg = CastCfg()
                        return cfg.sparkEnabled ~= false
                    end,
                    set = function(val)
                        CastCfg().sparkEnabled = val
                        ApplyCastCircle()
                    end,
                },
            },
        })

        -- Rows below are HIDDEN entirely while the Cast Bar Circle is off
        -- (the toggle's DependentSetValue forces the rebuild on flips).
        if CastCfg().enabled then
            -- Ring Texture ---- Scale
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Ring Texture",
                values = ringTexValues,
                order = ringTexOrder,
                getValue = function() return CastCfg().ringTex or "normal" end,
                setValue = function(val)
                    CastCfg().ringTex = val
                    ApplyCastCircle()
                end,
            }, {
                type = "slider",
                text = "Scale",
                min = 10,
                max = 100,
                step = 1,
                getValue = function() return CastCfg().radius or 30 end,
                setValue = function(val)
                    CastCfg().radius = val
                    ApplyCastCircle()
                end,
            })
            cursorY = cursorY - height

            -- Circle Opacity ---- Attach to Cursor
            row, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Circle Opacity",
                tooltip = "How visible the circle is.",
                min = 0,
                max = 100,
                step = 1,
                getValue = function() return CastCfg().alpha or 80 end,
                setValue = function(val)
                    CastCfg().alpha = val
                    ApplyCastCircle()
                end,
            }, {
                type = "toggle",
                text = "Attach to Cursor",
                getValue = function() return CastCfg().attached ~= false end,
                setValue = function(val)
                    CastCfg().attached = val
                    ApplyCastCircle()
                    CUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height

            -- Only Show in Instances ---- Combat Only
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Only Show in Instances",
                tooltip = "Shows it only in dungeons and raids.",
                getValue = function() return CastCfg().instanceOnly or false end,
                setValue = function(val)
                    CastCfg().instanceOnly = val
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            }, {
                type = "toggle",
                text = "Combat Only",
                tooltip = "Only shows the cast bar circle while you are in combat.",
                getValue = function() return CastCfg().combatOnly or false end,
                setValue = function(val)
                    CastCfg().combatOnly = val
                    if _G._CUCL_ApplyCombatOnlyEvents then _G._CUCL_ApplyCombatOnlyEvents() end
                    if _G._CUCL_UpdateVisibility then _G._CUCL_UpdateVisibility() end
                end,
            })
            cursorY = cursorY - height
        end -- close Cast Bar Circle hidden-while-disabled gate

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Cross-file bus: CUI_QoL_Options.lua builds the Cursor page and fires the
    --  reset through these (_EBS_ names are historical; consumers match them).
    ---------------------------------------------------------------------------
    _G._CUBS_BuildCursorPage = BuildCursorPage
    _G._CUBS_ResetCursor = function()
        if _G._CUCL_AceDB then _G._CUCL_AceDB:ResetProfile() end
        ApplyCursor()
        ApplyGcdCircle()
        ApplyCastCircle()
        if _G._CUCL_ApplyTrail then _G._CUCL_ApplyTrail() end
    end
end)
