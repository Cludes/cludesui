if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  RaidFrames_Options\VisualBars_Options.lua
--  Raid Frames options: the Health Bar, Absorbs, Power Bar and Text Display
--  sections of the raid and party pages. Called by BuildVisualSections; returns
--  y and the Health Bar custom-border gates Dispels reuses. Shared helpers come
--  from ns._RFO_OptEnv.
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIRaidFrames"]
if not mod then return end -- module disabled: no options page

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host (a kept page wrapper and every frame it hands out) are reset and
-- dressed again by the next build instead of made anew; elsewhere this is
-- CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- The eyeball hint's tip callout: built by the first raid build that shows it,
-- then kept for the session (every later raid build points it at its own eye).
local eyeHintTip

-- Panel close stops the health and power animations and resets the eye of each
-- tab's latest build (ns._eye[ctx]): registered once for the session, by the
-- first build that has the eyes.
local animEyesOnHide
local function StopAnimEyesOnHide()
    local eyes = mod._eye
    if mod._healthAnimActive then
        if mod.StopHealthAnim then mod.StopHealthAnim() end
        if eyes then
            for _, eye in pairs(eyes) do
                if eye.refreshHealthEye then eye.refreshHealthEye() end
            end
        end
    end
    if mod._powerAnimActive then
        if mod.StopPowerAnim then mod.StopPowerAnim() end
        if eyes then
            for _, eye in pairs(eyes) do
                if eye.refreshPowerEye then eye.refreshPowerEye() end
            end
        end
    end
end

local function BuildVisualBars(hostFrame, cursorY, W, onSection, EYE)
    local environ = mod._RFO_OptEnv
    local AbbreviateNumbers, absorbStyleOrder, absorbStyleValues, saved =
        environ.AbbreviateNumbers, environ.absorbStyleOrder, environ.absorbStyleValues, environ.db
    local hbtOrder, hbtValues, healAbsorbStyleOrder, healthColorOrder =
        environ.hbtOrder, environ.hbtValues, environ.healAbsorbStyleOrder, environ.healthColorOrder
    local healthColorValues, IsPreviewOff, maxHealthStyleOrder =
        environ.healthColorValues, environ.IsPreviewOff, environ.maxHealthStyleOrder
    local optionState, Pix, RebuildAndReload = environ.optState, environ.PP, environ.ReloadAndUpdate
    local ReadSetting, SGetPx, WriteSetting, SettingOr = environ.SGet, environ.SGetPx, environ.SSet, environ.SVal
    -- A row getter over SVal: the key's value, or the default given.
    local function SValRow(key, default)
        return function() return SettingOr(key, default) end
    end
    -- Row setters over SSet: the key written with the row's value.
    local function SSetRow(key)
        return function(value) WriteSetting(key, value) end
    end
    local StoreSetting = environ.SWrite
    local TexBgRowCfg = environ.TexBgRowCfg
    local _, height
    local row
    local _secY -- section start tracker
    -------------------------------------------------------------------
    --  HEALTH BAR
    -------------------------------------------------------------------
    _secY = cursorY
    local healthHeader
    healthHeader, height = W:SectionHeader(hostFrame, "HEALTH BAR", cursorY)
    cursorY = cursorY - height

    -- Eyeball: animate health bars (damage/healing simulation); built on raid + party pages, reads the active frame set via ns.PvActiveFrames().
    if not CUI._prebuilding then
        local EYE_VISIBLE = CUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CUI.EYE_INVISIBLE_ICON
        -- State lives on ns (single shared ticker) so raid and party eyeball builds drive one animation and start/stop works across both. ns._healthAnimActive is the truth the renderer reads.
        mod._healthAnimState = mod._healthAnimState or {}

        local function StopHealthAnim()
            if mod._healthAnimTicker then
                mod._healthAnimTicker:Cancel()
                mod._healthAnimTicker = nil
            end
            mod._healthAnimActive = false
            -- Pause: persist animated values so they stay on screen.
            local phv = mod.PvHealthValues()
            if phv then
                for idx, st in ipairs(mod._healthAnimState) do
                    phv[idx] = st.current
                end
            end
        end
        -- Exposed for onModuleLeave below.
        mod.StopHealthAnim = StopHealthAnim

        local function StartHealthAnim()
            if mod._healthAnimTicker then return end
            mod._healthAnimActive = true
            wipe(mod._healthAnimState)

            local frameList = mod.PvActiveFrames()
            for idx = 1, 20 do
                local f = frameList[idx]
                if f and f._health then
                    mod._healthAnimState[idx] = {
                        frame = f,
                        current = f._healthPct or (40 + math.random(60)),
                        target = 20 + math.random(80),
                        snapTimer = math.random() * 2,
                        nextSnap = 1.2 + math.random() * 1.6,
                    }
                end
            end

            local smoothInterp = Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            mod._healthAnimTicker = C_Timer.NewTicker(0.1, function()
                if not mod._healthAnimActive then return end
                -- Real preview contract: ticks must render effective-overlay values only, never the panel view's swapped values.
                local cfg = mod.PvSettings()
                local smooth = cfg.smoothBars
                local invert = mod.RF_IsInvertedFill(cfg)

                for idx, st in ipairs(mod._healthAnimState) do
                    local f = st.frame
                    if f and f._health and not f._pvHideHealthText then
                        -- Per-unit staggered timer, same cadence smooth or not.
                        st.snapTimer = st.snapTimer + 0.1
                        if st.snapTimer < st.nextSnap then
                        else
                            st.snapTimer = 0
                            st.nextSnap = 1.2 + math.random() * 1.6
                            st.current = st.target
                            st.target = 15 + math.random(85)

                            local barPct = invert and (100 - st.current) or st.current
                            if smooth and smoothInterp then
                                f._health:SetValue(barPct, smoothInterp)
                            else
                                f._health:SetValue(barPct)
                            end

                            -- The texts following health (Custom texts reading it included).
                            local preview = f._pv
                            if preview then
                                preview.hpPct = st.current
                                mod.RF_TextPreviewTick(f, "hp")
                            end

                            -- Fill color only moves in gradient modes.
                            if cfg.healthColorMode == "classic" then
                                local pct = st.current / 100
                                local r = pct < 0.5 and 1 or (1 - (pct - 0.5) * 2)
                                local g = pct > 0.5 and 1 or (pct * 2)
                                f._health:SetStatusBarColor(r, g, 0, (cfg.healthBarOpacity or 100) / 100)
                            elseif cfg.healthColorMode == "customDynamic" then
                                local red, green, blue = mod.ResolveDynamicColor(cfg, st.current / 100)
                                f._health:SetStatusBarColor(
                                    red,
                                    green,
                                    blue,
                                    (cfg.healthBarOpacity or 100) / 100
                                )
                            elseif cfg.healthColorMode == "classReactive" then
                                local red, green, blue =
                                    mod.ResolveClassReactiveColor(cfg, f._classToken, st.current / 100)
                                f._health:SetStatusBarColor(
                                    red,
                                    green,
                                    blue,
                                    (cfg.healthBarOpacity or 100) / 100
                                )
                            end
                        end -- snapTimer ready
                    end
                end
            end)
        end

        -- Eye button anchors to the section header's label FontString.
        local headerLabel
        for _, region in ipairs({ healthHeader:GetRegions() }) do
            if region.GetText and CUI.EnKey(region:GetText()) == "HEALTH BAR" then
                headerLabel = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, healthHeader)
        eyeButton:SetSize(24, 24)
        if headerLabel then
            eyeButton:SetPoint("LEFT", headerLabel, "RIGHT", 5, 0)
        else
            eyeButton:SetPoint("LEFT", healthHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(healthHeader:GetFrameLevel() + 5)
        CUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function SyncHealthEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                CUI.SetGlyphAlpha(eyeButton, 0.15)
                return
            end
            eyeTex:SetTexture(mod._healthAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
            CUI.SetGlyphAlpha(eyeButton, 0.4)
        end
        SyncHealthEye()
        EYE.refreshHealthEye = SyncHealthEye
        mod._stopHealthAnim = StopHealthAnim
        mod._startHealthAnim = StartHealthAnim
        eyeButton:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            if mod._healthAnimActive then
                StopHealthAnim()
            else
                if mod._indicatorsVisible then
                    mod._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
                StartHealthAnim()
            end
            SyncHealthEye()
            if mod.PvRefresh then mod.PvRefresh() end
        end)
        eyeButton:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                CUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            CUI.SetGlyphAlpha(self, 0.7)
            CUI.ShowWidgetTooltip(
                self,
                mod._healthAnimActive and "Stop health bar effects" or "Preview health bar effects"
            )
        end)
        eyeButton:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then CUI.SetGlyphAlpha(self, 0.4) end
            CUI.HideWidgetTooltip()
        end)

        if not animEyesOnHide then
            animEyesOnHide = true
            CUI:RegisterOnHide(StopAnimEyesOnHide)
        end

        -- One-time eyeball hint, raid/main page only. On the panel body like
        -- the other panel tips: it hides with the window when it collapses and
        -- rides the panel scale. One tip for the session, anchored to the eye
        -- of the build that shows it and faded in only when it was hidden.
        -- ns._rfEyeHintTip holds it while undismissed (the page, module and
        -- panel hooks show and hide it through that field); Okay clears it.
        if not optionState._partyCtx and not (CludesUIDB and CludesUIDB.rfEyeHintSeen) then
            if not eyeHintTip then
                eyeHintTip = CUI.BuildTipCallout(CUI._panelBody, {
                    width = 310,
                    height = 82,
                    pp = Pix,
                    text = CUI.L(
                        "Click this eye icon to preview live\nhealth bar effects like absorbs and healing."
                    ),
                    fontSize = 10,
                    textTop = 12,
                    textInset = 24,
                    spacing = 4,
                    bgAlpha = 0.95,
                    btnW = 70,
                    btnH = 22,
                    btnBottom = 10,
                    btnFontSize = 10,
                    onOkay = function()
                        mod._rfEyeHintTip = nil
                        CludesUIDB = CludesUIDB or {}
                        CludesUIDB.rfEyeHintSeen = true
                    end,
                })
            end
            eyeHintTip:ClearAllPoints()
            eyeHintTip:SetPoint("TOP", eyeButton, "BOTTOM", 0, -14)
            mod._rfEyeHintTip = eyeHintTip
            if not eyeHintTip:IsShown() then CUI.ShowTipCallout(eyeHintTip) end
        end
    end -- health eyeball

    local texRow
    texRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Health Bar Texture",
        values = hbtValues,
        order = hbtOrder,
        getValue = SValRow("healthBarTexture", "atrocity"),
        setValue = SSetRow("healthBarTexture"),
    }, {
        type = "slider",
        text = "Fill Opacity",
        min = 0,
        max = 100,
        step = 1,
        disabled = function() return SettingOr("healthColorMode", "class") == "dark" end,
        disabledTooltip = "Not available in Dark Mode",
        rawTooltip = true,
        getValue = SValRow("healthBarOpacity", 100),
        setValue = SSetRow("healthBarOpacity"),
    })
    -- Vertical Fill cog lives in the Health Bar party-sync section, so an unsynced party tab keeps its own value.
    if not CUI._prebuilding then
        local lrgn = texRow._leftRegion
        CUI.BuildInlineCog(lrgn, {
            title = "Health Bar Fill",
            rows = {
                mod.RF_PartyKitGate({
                    type = "toggle",
                    label = "Vertical Fill",
                    tooltip = "Fill the health bar bottom-to-top instead of left-to-right. Absorbs, heal prediction and the bar background follow the same axis.",
                    get = SValRow("healthVerticalFill", false),
                    -- RefreshPage re-labels Absorbs Placement for the new axis; cog popups bake labels in on first build.
                    set = function(val)
                        WriteSetting("healthVerticalFill", val)
                        CUI:RefreshPage()
                    end,
                }),
                mod.RF_PartyKitGate({
                    type = "toggle",
                    label = "Fill Missing Health",
                    tooltip = "The bar fills with missing health, growing as the unit takes damage.",
                    get = SValRow("healthInvertFill", false),
                    set = SSetRow("healthInvertFill"),
                }),
                TexBgRowCfg(SettingOr, WriteSetting),
            },
        })
    end
    cursorY = cursorY - height

    row, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Fill Color",
        values = healthColorValues,
        order = healthColorOrder,
        tooltip = "Custom Dynamic Colors: the health bar smoothly blends between three colors you pick -- one for full health (100%), one for half (50%), and one for empty (0%) -- shifting through them as the unit takes damage or is healed.",
        getValue = SValRow("healthColorMode", "class"),
        setValue = function(val)
            WriteSetting("healthColorMode", val)
            -- "dark" feeds the Dark Mode conditional-override condition.
            CUI.Conditions_Recheck()
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        disabled = function() return SettingOr("healthColorMode", "class") == "dark" end,
        disabledTooltip = "Not available in Dark Mode. Dark Mode colors can be adjusted in Core Settings > Colors.",
        rawTooltip = true,
        getValue = SValRow("bgDarkness", 50),
        setValue = SSetRow("bgDarkness"),
    })
    cursorY = cursorY - height
    -- Fill Color's "dark" choice IS the Dark Mode condition's input, so lock the dropdown while a Dark Mode conditional is being edited -- else the override could capture a mode change that flips its own condition.
    if CUI.SpecOverrides_AttachEditLock and not CUI._prebuilding then
        CUI.SpecOverrides_AttachEditLock(
            row._leftRegion,
            "Fill Color's Dark Mode choice drives a Dark Mode override condition, so it can't be changed while editing an override",
            CUI.SpecOverrides_DarkCondEditActive
        )
    end
    -- Custom fill swatch plus the three Custom Dynamic stop swatches (100/50/0%) share one inline slot; the Fill Color mode decides which set is interactive.
    if not CUI._prebuilding then
        local region = row._leftRegion

        local colorSwatch = CUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local color = ReadSetting("customFillColor")
            if color then return color.r, color.g, color.b, 1 end
            return 37 / 255, 193 / 255, 29 / 255, 1
        end, function(red, green, blue)
            StoreSetting("customFillColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        -- Blocking overlay: non-clickable + tooltip unless Fill Color is Custom.
        local block = CUI.NewSwatchBlocker(colorSwatch)
        block:SetScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(colorSwatch, "Only available with Custom fill color") end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

        -- Three gradient-stop swatches, built right-to-left so the visual order reads 100% | 50% | 0%; tooltips carry the pct.
        local dynDefs = {
            {
                key = "dynamicColor100",
                def = { r = 0, g = 1, b = 0 },
                label = "100%",
                tip = "Health bar color at full (100%) health",
            },
            {
                key = "dynamicColor50",
                def = { r = 0xEC / 255, g = 0xEC / 255, b = 0x32 / 255 },
                label = "50%",
                tip = "Health bar color at half (50%) health",
            },
            {
                key = "dynamicColor0",
                def = { r = 0xE3 / 255, g = 0x30 / 255, b = 0x30 / 255 },
                label = "0%",
                tip = "Health bar color at empty (0%) health",
            },
        }
        local dynSwatches = {}
        local prevAnchor = region._control
        for idx = #dynDefs, 1, -1 do
            local dropdown = dynDefs[idx]
            local sw = CUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
                local color = ReadSetting(dropdown.key) or dropdown.def
                return color.r, color.g, color.b, 1
            end, function(red, green, blue)
                StoreSetting(dropdown.key, { r = red, g = green, b = blue })
                RebuildAndReload()
            end, false, 18)
            sw:SetPoint("RIGHT", prevAnchor, "LEFT", (prevAnchor == region._control) and -8 or -6, 0)
            sw:HookScript("OnEnter", function() CUI.ShowWidgetTooltip(sw, dropdown.tip) end)
            sw:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            dynSwatches[idx] = sw
            prevAnchor = sw
        end

        local function UpdateSwatchVis()
            local mode = SettingOr("healthColorMode", "class")
            local isDynamic = mode == "customDynamic"
            -- Class Reactive shares the dynamic stops but its 100% color IS
            -- the class color: only the 0%/50% swatches apply there.
            local isClassReactive = mode == "classReactive"
            -- Single custom swatch: live only in Custom mode, dimmed+blocked in other modes, fully HIDDEN in Dynamic/Class Reactive modes so it doesn't sit behind the dynamic swatches.
            if isDynamic or isClassReactive then
                colorSwatch:Hide()
                block:Hide()
            else
                colorSwatch:Show()
                if mode == "custom" then
                    colorSwatch:SetAlpha(1)
                    block:Hide()
                else
                    colorSwatch:SetAlpha(0.3)
                    block:Show()
                end
            end
            for idx, sw in ipairs(dynSwatches) do
                -- dynSwatches[1] = the 100% stop (class-driven in Class Reactive).
                if isDynamic or (isClassReactive and idx > 1) then
                    sw:Show()
                else
                    sw:Hide()
                end
            end
        end
        CUI.RegisterWidgetRefresh(UpdateSwatchVis)
        UpdateSwatchVis()
    end
    -- Background Custom + Class swatch pair: clicking either toggles bgClassColored, the inactive one dims (mirrors the fill picker).
    if not CUI._prebuilding then
        local region = row._rightRegion
        -- Class swatch shows the player's class color and is not editable.
        local bgClassSwatch = CUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local _, classTok = UnitClass("player")
            local classColor = classTok and CUI.GetClassColor(classTok)
            if classColor then return classColor.r, classColor.g, classColor.b, 1 end
            return 1, 1, 1, 1
        end, function() end, false, 20)
        bgClassSwatch:SetScript("OnClick", function()
            WriteSetting("bgClassColored", true)
            RebuildAndReload()
            CUI:RefreshPage()
        end)
        bgClassSwatch:HookScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(bgClassSwatch, "Class Colored Background") end
        )
        bgClassSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        bgClassSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgClassSwatch

        local bgSwatch = CUI.BuildColorSwatch(region, row:GetFrameLevel() + 3, function()
            local color = ReadSetting("customBgColor")
            if color then return color.r, color.g, color.b, 1 end
            return 17 / 255, 17 / 255, 17 / 255, 1
        end, function(red, green, blue)
            StoreSetting("customBgColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if SettingOr("bgClassColored", false) then
                WriteSetting("bgClassColored", false)
                RebuildAndReload()
                CUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        bgSwatch:HookScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(bgSwatch, "Custom Background Color") end
        )
        bgSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgSwatch
        -- Blocking overlay spans BOTH swatches: Dark Mode has no background.
        local bgBlock = CreateFrame("Frame", nil, region)
        bgBlock:SetPoint("TOPLEFT", bgSwatch, "TOPLEFT", 0, 0)
        bgBlock:SetPoint("BOTTOMRIGHT", bgClassSwatch, "BOTTOMRIGHT", 0, 0)
        bgBlock:SetFrameLevel(bgClassSwatch:GetFrameLevel() + 10)
        bgBlock:EnableMouse(true)
        bgBlock:SetScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    bgSwatch,
                    "Not available in Dark Mode. Dark Mode colors can be adjusted in Core Settings > Colors."
                )
            end
        )
        bgBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function UpdateBgSwatchVis()
            if SettingOr("healthColorMode", "class") == "dark" then
                bgSwatch:SetAlpha(0.3)
                bgClassSwatch:SetAlpha(0.3)
                bgBlock:Show()
            else
                bgBlock:Hide()
                local classOn = SettingOr("bgClassColored", false)
                bgSwatch:SetAlpha(classOn and 0.3 or 1)
                bgClassSwatch:SetAlpha(classOn and 1 or 0.3)
            end
        end
        CUI.RegisterWidgetRefresh(UpdateBgSwatchVis)
        UpdateBgSwatchVis()
    end

    -- Rows the test panel's Edit buttons scroll to. The search prebuild's rows
    -- are stand-ins, so it records them in a scratch table instead.
    mod._editTargets = mod._editTargets or {}
    local editTargets = CUI._prebuilding and {} or mod._editTargets

    local healPredRow
    healPredRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Heal Prediction",
        tooltip = "Shows incoming heals on the health bar.",
        getValue = SValRow("healPrediction", false),
        setValue = function(val)
            WriteSetting("healPrediction", val)
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Prediction Opacity",
        tooltip = "How visible incoming heals are.",
        min = 5,
        max = 100,
        step = 1,
        disabled = function() return not SettingOr("healPrediction", false) end,
        disabledTooltip = "Heal Prediction",
        getValue = SValRow("healPredOpacity", 75),
        setValue = SSetRow("healPredOpacity"),
    })
    cursorY = cursorY - height
    editTargets.healPrediction = healPredRow
    if not CUI._prebuilding then
        local region = healPredRow._leftRegion
        local colorSwatch = CUI.BuildColorSwatch(region, healPredRow:GetFrameLevel() + 3, function()
            local color = ReadSetting("healPredColor")
            if color then return color.r, color.g, color.b, 1 end
            return 102 / 255, 243 / 255, 102 / 255, 1
        end, function(red, green, blue)
            StoreSetting("healPredColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        local function UpdateHealPredSwatchVis()
            colorSwatch:SetAlpha(SettingOr("healPrediction", false) and 1 or 0.3)
        end
        CUI.RegisterWidgetRefresh(UpdateHealPredSwatchVis)
        UpdateHealPredSwatchVis()
    end

    -- Color Custom Borders (the Threat Borders and Dispel Border cogs) recolors the
    -- frame's own border, so it needs one to recolor: the CludesUI style, a Border
    -- Style other than Solid and a Border Size above 0 (runtime twin:
    -- ns.RF_CustomBorderOn), and no Compact Mode, whose shared outline stands in for
    -- the frame's border. Cog rows re-check this on every open.
    local function CustomBorderOff()
        if mod.RF_CompactOnTab(optionState._partyCtx) then return true end
        if mod.RF_Stock and mod.RF_Stock() then return true end
        local texture = ReadSetting("borderTexture")
        return texture == nil or texture == "" or texture == "solid" or SettingOr("borderSize", 1) <= 0
    end
    local function CustomBorderOffTip()
        if mod.RF_CompactOnTab(optionState._partyCtx) then return "Compact Mode" end
        if mod.RF_Stock and mod.RF_Stock() then
            return CUI.BlizzStyle and CUI.BlizzStyle.Label("raidframes")
        end
        local texture = ReadSetting("borderTexture")
        if texture == nil or texture == "" or texture == "solid" then
            return "This option requires a Border Style other than Solid."
        end
        return "This option requires a Border Size above 0."
    end

    local smoothThreatRow
    smoothThreatRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Smooth Health Bars",
        getValue = SValRow("smoothBars", true),
        setValue = SSetRow("smoothBars"),
    }, {
        type = "slider",
        text = "Threat Borders",
        tooltip = "Colors a frame's border by its threat.",
        min = 0,
        max = 4,
        step = 1,
        getValue = SValRow("threatBorderSize", 2),
        setValue = SSetRow("threatBorderSize"),
    })
    cursorY = cursorY - height
    editTargets.threat = smoothThreatRow
    editTargets.animateBars = smoothThreatRow
    -- Cog on Threat Borders: Color Custom Borders recolors the frame's own border in
    -- the threat color on aggro, drawn instead of the inner border (the slider's
    -- size still applies whenever the recolor cannot).
    if not CUI._prebuilding then
        local region = smoothThreatRow._rightRegion
        -- Its only row needs a custom border: dimmed, with the reason, until there is one.
        CUI.BuildInlineCog(region, {
            disabled = CustomBorderOff,
            disabledTooltip = CustomBorderOffTip,
            requireState = "disabled",
            title = "Threat Borders",
            rows = {
                {
                    type = "toggle",
                    label = "Color Custom Borders",
                    tooltip = "Recolors the frame border in the threat color while the unit has aggro instead of drawing a separate border.",
                    disabled = CustomBorderOff,
                    disabledTooltip = CustomBorderOffTip,
                    requireState = "disabled",
                    get = function()
                        return not mod.RF_CompactOnTab(optionState._partyCtx)
                            and SettingOr("threatCustomBorder", false)
                    end,
                    set = function(val)
                        if val and CustomBorderOff() then return end
                        WriteSetting("threatCustomBorder", val)
                    end,
                },
            },
        })
    end

    -------------------------------------------------------------------
    --  ABSORBS
    --  Own party-sync section ("absorbs"); pre-split profiles inherit the
    --  Health Bar sync state via ns._NormalizePartySyncSections.
    -------------------------------------------------------------------
    local absorbsHeader
    if onSection then onSection("healthBar", _secY, cursorY) end
    _secY = cursorY
    absorbsHeader, height = W:SectionHeader(hostFrame, "ABSORBS", cursorY)
    cursorY = cursorY - height

    -- Eyeball: toggle shield/heal-absorb effects on the preview frames.
    if not CUI._prebuilding then
        local EYE_VISIBLE = CUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CUI.EYE_INVISIBLE_ICON

        local abLabel
        for _, region in ipairs({ absorbsHeader:GetRegions() }) do
            if region.GetText and CUI.EnKey(region:GetText()) == "ABSORBS" then
                abLabel = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, absorbsHeader)
        eyeButton:SetSize(24, 24)
        if abLabel then
            eyeButton:SetPoint("LEFT", abLabel, "RIGHT", 5, 0)
        else
            eyeButton:SetPoint("LEFT", absorbsHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(absorbsHeader:GetFrameLevel() + 5)
        CUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()

        -- On ns so the preview renderer can read it.
        if mod._absorbsPreviewVisible == nil then mod._absorbsPreviewVisible = false end

        local function SyncAbsorbEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                CUI.SetGlyphAlpha(eyeButton, 0.15)
                return
            end
            eyeTex:SetTexture(mod._absorbsPreviewVisible and EYE_INVISIBLE or EYE_VISIBLE)
            CUI.SetGlyphAlpha(eyeButton, 0.4)
        end
        EYE.refreshAbsorbEye = SyncAbsorbEye
        SyncAbsorbEye()
        eyeButton:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            mod._absorbsPreviewVisible = not mod._absorbsPreviewVisible
            -- Indicators suppress bar effects, so clear them.
            if mod._absorbsPreviewVisible and mod._indicatorsVisible then
                mod._indicatorsVisible = false
                if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
            end
            SyncAbsorbEye()
            if mod.PvRefresh then mod.PvRefresh() end
        end)
        eyeButton:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                CUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            CUI.SetGlyphAlpha(self, 0.7)
            CUI.ShowWidgetTooltip(
                self,
                mod._absorbsPreviewVisible and "Hide shield effects on preview"
                    or "Show shield effects on preview"
            )
        end)
        eyeButton:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then CUI.SetGlyphAlpha(self, 0.4) end
            CUI.HideWidgetTooltip()
        end)
    end -- absorbs eyeball

    local absorbRow
    absorbRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Absorb Style",
        tooltip = "How shields are drawn on the health bar.",
        values = absorbStyleValues,
        order = absorbStyleOrder,
        getValue = SValRow("absorbStyle", "none"),
        setValue = function(val)
            -- Blizzard Glow Line follows the pick: on with Default Blizz Frames, off when
            -- leaving it, else kept. A set value is stored explicitly, so a party that
            -- starts keeping its own style here keeps the line it showed; an unset one
            -- stays unset and keeps following the style.
            local was = SettingOr("absorbStyle", "none")
            local glow = SGetPx("absorbGlowLine", "absorbStyle")
            if val == "blizzardModern" then
                glow = true
            elseif was == "blizzardModern" then
                glow = false
            end
            if glow ~= nil then StoreSetting("absorbGlowLine", glow == true) end
            WriteSetting("absorbStyle", val)
            if val == "clean" then
                WriteSetting("absorbOpacity", 30)
            elseif val ~= "blizzardModern" then
                -- Blizzard (Modern) hardcodes color+opacity in the renderer; leave saved opacity untouched.
                WriteSetting("absorbOpacity", 90)
            end
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Absorb Opacity",
        tooltip = "How visible the shield overlay is.",
        min = 5,
        max = 100,
        step = 1,
        disabled = function()
            local st = SettingOr("absorbStyle", "none")
            return st == "none" or st == "blizzardModern"
        end,
        disabledTooltip = "Absorb Style",
        getValue = SValRow("absorbOpacity", 90),
        setValue = SSetRow("absorbOpacity"),
    })
    cursorY = cursorY - height
    editTargets.absorbs = absorbRow
    -- Inline cog: absorb placement (overlay / right edge / left edge)
    do
        local region = absorbRow._leftRegion
        -- Placement labels follow the FILL AXIS: saved values stay right/left (meaning the FAR/NEAR end of the fill), worded top/bottom on a vertical bar.
        -- MUTATE IN PLACE, never rebuild this table: RefreshPage's fast path skips a full rebuild and the cog popup is built once then cached, so a fresh table would never reach the widget. The popup re-reads values[get()] every show; _invalidateMenu makes an already-built menu re-read entries from this same table on next click.
        local absorbEdgeLabels = {
            overlay = "Overlay",
            overlayReverse = "Overlay Reverse",
            overlayReverseFull = "Overlay Reverse (Full)",
        }
        local absorbEdgeLabelsVert -- last applied axis; nil until first sync
        -- (The Party Frames kit's bar always fills horizontally; decided at build.)
        local kitPage = mod.RF_OptPartyKit()
        -- Returns true ONLY when the axis flipped, so callers skip _invalidateMenu on unrelated refreshes -- it nils the cached menu and would break an open menu's wired click.
        local function SyncShieldEdgeLabels()
            local vert = (not kitPage) and SettingOr("healthVerticalFill", false) and true or false
            if absorbEdgeLabelsVert == vert then return false end
            absorbEdgeLabelsVert = vert
            absorbEdgeLabels.right = vert and "From Top Edge" or "From Right Edge"
            absorbEdgeLabels.left = vert and "From Bottom Edge" or "From Left Edge"
            return true
        end
        SyncShieldEdgeLabels()
        local _, cogShow = CUI.BuildInlineCog(region, {
            title = "Absorb Rendering",
            rows = {
                {
                    type = "dropdown",
                    label = "Placement",
                    values = absorbEdgeLabels,
                    -- Wide enough for "Overlay Reverse (Full)".
                    ddWidth = 190,
                    order = { "overlay", "overlayReverse", "overlayReverseFull", "right", "left" },
                    disabled = function() return SettingOr("absorbStyle", "none") == "blizzardModern" end,
                    disabledTooltip = "Default Blizz Frames uses a fixed placement",
                    rawTooltip = true,
                    get = function()
                        SyncShieldEdgeLabels()
                        return SettingOr("absorbEdgeMode", "overlay")
                    end,
                    set = SSetRow("absorbEdgeMode"),
                },
                {
                    type = "dropdown",
                    label = "Show Overshield",
                    tooltip = "Overshield is the part of an absorb exceeding your empty health. Always backfills it over current health from the shield's edge; From Left grows it from the opposite end of the bar; Never hides it.",
                    values = { never = "Never", always = "Always", fromleft = "From Left" },
                    order = { "never", "always", "fromleft" },
                    -- From Left only exists in the plain Overlay placement:
                    -- edge modes have no overshield, Overlay Reverse
                    -- already clamps the whole absorb inside the fill and
                    -- its Full variant draws the excess from the origin edge.
                    itemDisabled = function(val)
                        return val == "fromleft" and SettingOr("absorbEdgeMode", "overlay") ~= "overlay"
                    end,
                    get = function()
                        -- Legacy boolean fallback: profiles saved before the
                        -- dropdown keep their toggle's meaning.
                        local m = SettingOr("overshieldMode", nil)
                        if m == nil then
                            m = (SettingOr("showOvershield", true) == false) and "never" or "always"
                        end
                        return m
                    end,
                    set = function(val)
                        -- Mirror the legacy boolean so pre-dropdown readers
                        -- (incl. the live-client profile) track Never/Always.
                        WriteSetting("showOvershield", val ~= "never")
                        WriteSetting("overshieldMode", val)
                    end,
                },
                {
                    type = "toggle",
                    label = "Blizzard Glow Line",
                    tooltip = "Adds the Default Blizz Frames glow line where the shield meets current health.",
                    disabled = function()
                        if (not kitPage) and SettingOr("healthVerticalFill", false) == true then return true end
                        return SettingOr("absorbEdgeMode", "overlay") == "left"
                            and SettingOr("absorbStyle", "none") ~= "blizzardModern"
                    end,
                    disabledTooltip = "The glow line is not shown on a vertical fill or with the From Left Edge placement",
                    rawTooltip = true,
                    get = function()
                        -- Unset follows the style: on for Default Blizz Frames only.
                        local g = SGetPx("absorbGlowLine", "absorbStyle")
                        if g == nil then return SettingOr("absorbStyle", "none") == "blizzardModern" end
                        return g == true
                    end,
                    set = function(val) WriteSetting("absorbGlowLine", val and true or false) end,
                },
            },
        })
        -- Re-label on page refresh (Vertical Fill fires one) and drop any built menu so its entries rebuild with the new wording.
        CUI.RegisterWidgetRefresh(function()
            if not SyncShieldEdgeLabels() then return end
            local popFrame = cogShow and cogShow._popupFrame
            if popFrame and popFrame.GetChildren then
                for _, childFrame in ipairs({ popFrame:GetChildren() }) do
                    if childFrame._invalidateMenu then childFrame._invalidateMenu() end
                end
            end
        end)
    end
    if not CUI._prebuilding then
        local region = absorbRow._leftRegion
        local colorSwatch = CUI.BuildColorSwatch(region, absorbRow:GetFrameLevel() + 3, function()
            local color = ReadSetting("absorbColor")
            if color then return color.r, color.g, color.b, 1 end
            return 1, 1, 1, 1
        end, function(red, green, blue)
            StoreSetting("absorbColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        -- BuildColorSwatch has no disabled state, so a mouse-enabled frame on top eats clicks when the color isn't user-editable (no absorb, or hardcoded-color "Blizzard (Modern)").
        local swatchBlock = CUI.NewSwatchBlocker(colorSwatch)
        swatchBlock:Hide()
        local function UpdateAbsorbSwatchVis()
            local st = SettingOr("absorbStyle", "none")
            local off = (st == "none" or st == "blizzardModern")
            colorSwatch:SetAlpha(off and 0.3 or 1)
            if off then
                swatchBlock:Show()
            else
                swatchBlock:Hide()
            end
        end
        CUI.RegisterWidgetRefresh(UpdateAbsorbSwatchVis)
        UpdateAbsorbSwatchVis()
    end

    local function CurrentAbsorbPos()
        local p = ReadSetting("absorbBarPosition")
        if p then return p end
        return SettingOr("absorbBarEnabled", false) and "aboveRight" or "none"
    end
    local absorbBarRow
    absorbBarRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Absorb Bar",
        tooltip = "Shows shields over the health bar.",
        values = {
            none = "None",
            aboveRight = "Above Frame Right",
            aboveLeft = "Above Frame Left",
            topRight = "Top Right",
            topLeft = "Top Left",
            rightVertical = "Right Edge (Vertical)",
            leftVertical = "Left Edge (Vertical)",
        },
        order = { "none", "aboveRight", "aboveLeft", "topRight", "topLeft", "rightVertical", "leftVertical" },
        getValue = function() return CurrentAbsorbPos() end,
        setValue = function(val)
            StoreSetting("absorbBarEnabled", val ~= "none") -- keep legacy flag in sync
            WriteSetting("absorbBarPosition", val)
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Bar Height",
        min = 1,
        max = 20,
        step = 1,
        disabled = function() return CurrentAbsorbPos() == "none" end,
        disabledTooltip = "Absorb Bar",
        getValue = SValRow("absorbBarHeight", 4),
        setValue = SSetRow("absorbBarHeight"),
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local region = absorbBarRow._leftRegion
        CUI.BuildInlineCog(region, {
            -- Vertical Grow, its only setting, has no effect off the vertical positions.
            disabled = function()
                local p = CurrentAbsorbPos()
                return p ~= "rightVertical" and p ~= "leftVertical"
            end,
            disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
            rawTooltip = true,
            title = "Absorb Bar Rendering",
            rows = {
                {
                    type = "dropdown",
                    label = "Vertical Grow",
                    values = { up = "Up", down = "Down" },
                    order = { "up", "down" },
                    disabled = function()
                        local p = CurrentAbsorbPos()
                        return p ~= "rightVertical" and p ~= "leftVertical"
                    end,
                    disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                    rawTooltip = true,
                    get = SValRow("absorbBarGrowDir", "up"),
                    set = SSetRow("absorbBarGrowDir"),
                },
            },
        })
    end
    -- The size slider reads as width for the vertical positions; retitle live.
    do
        local labelFS = absorbBarRow._rightRegion._label
        local function UpdateAbsorbBarSizeLabel()
            local p = CurrentAbsorbPos()
            local vertical = p == "rightVertical" or p == "leftVertical"
            labelFS:SetText(CUI.L(vertical and "Bar Width" or "Bar Height"))
        end
        CUI.RegisterWidgetRefresh(UpdateAbsorbBarSizeLabel)
        UpdateAbsorbBarSizeLabel()
    end
    if not CUI._prebuilding then
        local region = absorbBarRow._rightRegion
        local colorSwatch = CUI.BuildColorSwatch(region, absorbBarRow:GetFrameLevel() + 3, function()
            local color = ReadSetting("absorbBarColor")
            if color then return color.r, color.g, color.b, color.a or 1 end
            return 1, 1, 1, 1
        end, function(red, green, blue, a)
            StoreSetting("absorbBarColor", { r = red, g = green, b = blue, a = a })
            RebuildAndReload()
        end, true, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        local function UpdateAbsorbBarSwatchVis()
            colorSwatch:SetAlpha(CurrentAbsorbPos() ~= "none" and 1 or 0.3)
        end
        CUI.RegisterWidgetRefresh(UpdateAbsorbBarSwatchVis)
        UpdateAbsorbBarSwatchVis()
    end

    local healAbsorbRow
    healAbsorbRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Heal Absorb Style",
        tooltip = "How heal absorbs are drawn on the health bar.",
        values = absorbStyleValues,
        order = healAbsorbStyleOrder,
        getValue = SValRow("healAbsorbStyle", "clean"),
        setValue = function(val)
            WriteSetting("healAbsorbStyle", val)
            if val == "clean" then
                WriteSetting("healAbsorbOpacity", 50)
            else
                WriteSetting("healAbsorbOpacity", 75)
            end
            CUI:RefreshPage()
        end,
    }, {
        type = "slider",
        text = "Heal Absorb Opacity",
        tooltip = "How visible the heal absorb overlay is.",
        min = 5,
        max = 100,
        step = 1,
        disabled = function() return SettingOr("healAbsorbStyle", "clean") == "none" end,
        disabledTooltip = "Heal Absorb Style",
        getValue = SValRow("healAbsorbOpacity", 75),
        setValue = SSetRow("healAbsorbOpacity"),
    })
    cursorY = cursorY - height
    editTargets.healAbsorbs = healAbsorbRow
    -- Inline cog: heal absorb placement (independent of shield absorb)
    do
        local region = healAbsorbRow._leftRegion
        -- Same axis-labelling contract as the shield absorb cog above (MUTATE IN PLACE; return true only on a real axis flip).
        local healAbsorbEdgeLabels = { overlay = "Overlay" }
        local healAbsorbEdgeLabelsVert -- last applied axis; nil until first sync
        local kitPage = mod.RF_OptPartyKit()
        local function SyncHealEdgeLabels()
            local vert = (not kitPage) and SettingOr("healthVerticalFill", false) and true or false
            if healAbsorbEdgeLabelsVert == vert then return false end
            healAbsorbEdgeLabelsVert = vert
            healAbsorbEdgeLabels.right = vert and "From Top Edge" or "From Right Edge"
            healAbsorbEdgeLabels.left = vert and "From Bottom Edge" or "From Left Edge"
            return true
        end
        SyncHealEdgeLabels()
        local _, cogShow = CUI.BuildInlineCog(region, {
            title = "Heal Absorb Rendering",
            rows = {
                {
                    type = "dropdown",
                    label = "Placement",
                    values = healAbsorbEdgeLabels,
                    order = { "overlay", "right", "left" },
                    get = function()
                        SyncHealEdgeLabels()
                        return SettingOr("healAbsorbEdgeMode", "overlay")
                    end,
                    set = SSetRow("healAbsorbEdgeMode"),
                },
                {
                    type = "slider",
                    label = "Backing Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                    get = SValRow("healAbsorbBgOpacity", 25),
                    set = SSetRow("healAbsorbBgOpacity"),
                },
                {
                    type = "toggle",
                    label = "Show Over Dispels",
                    get = function() return SettingOr("healAbsorbOverDispel", false) == true end,
                    set = SSetRow("healAbsorbOverDispel"),
                },
            },
        })
        CUI.RegisterWidgetRefresh(function()
            if not SyncHealEdgeLabels() then return end
            local popFrame = cogShow and cogShow._popupFrame
            if popFrame and popFrame.GetChildren then
                for _, childFrame in ipairs({ popFrame:GetChildren() }) do
                    if childFrame._invalidateMenu then childFrame._invalidateMenu() end
                end
            end
        end)
    end
    if not CUI._prebuilding then
        local region = healAbsorbRow._leftRegion
        local colorSwatch = CUI.BuildColorSwatch(region, healAbsorbRow:GetFrameLevel() + 3, function()
            local color = ReadSetting("healAbsorbColor")
            if color then return color.r or 0.8, color.g or 0.15, color.b or 0.15, 1 end
            return 0.8, 0.15, 0.15, 1
        end, function(red, green, blue)
            StoreSetting("healAbsorbColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        -- Blocked for "none" and the pre-colored heal styles (healBlizzModern is hardcoded white).
        local swatchBlock = CUI.NewSwatchBlocker(colorSwatch)
        swatchBlock:Hide()
        local function UpdateHealAbsorbSwatchVis()
            local st = SettingOr("healAbsorbStyle", "clean")
            local off = (
                st == "none"
                or st == "healBlizzModern"
                or st == "largeOutlinedStripes"
                or st == "largeOutlinedStripesR"
            )
            colorSwatch:SetAlpha(off and 0.3 or 1)
            if off then
                swatchBlock:Show()
            else
                swatchBlock:Hide()
            end
        end
        CUI.RegisterWidgetRefresh(UpdateHealAbsorbSwatchVis)
        UpdateHealAbsorbSwatchVis()
    end

    do
        local function CurHealAbsorbBarPos() return ReadSetting("healAbsorbBarPosition") or "none" end
        local healAbsorbBarRow
        healAbsorbBarRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Heal Absorb Bar",
            tooltip = "Shows heal absorbs over the health bar.",
            values = {
                none = "None",
                belowAbsorb = "Below Absorb Bar",
                aboveRight = "Above Frame Right",
                aboveLeft = "Above Frame Left",
                topRight = "Top Right",
                topLeft = "Top Left",
                rightVertical = "Right Edge (Vertical)",
                leftVertical = "Left Edge (Vertical)",
            },
            order = {
                "none",
                "belowAbsorb",
                "aboveRight",
                "aboveLeft",
                "topRight",
                "topLeft",
                "rightVertical",
                "leftVertical",
            },
            getValue = function() return CurHealAbsorbBarPos() end,
            setValue = function(val)
                WriteSetting("healAbsorbBarPosition", val)
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Bar Height",
            min = 1,
            max = 20,
            step = 1,
            disabled = function() return CurHealAbsorbBarPos() == "none" end,
            disabledTooltip = "Heal Absorb Bar",
            getValue = SValRow("healAbsorbBarHeight", 4),
            setValue = SSetRow("healAbsorbBarHeight"),
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            local region = healAbsorbBarRow._rightRegion
            local colorSwatch = CUI.BuildColorSwatch(
                region,
                healAbsorbBarRow:GetFrameLevel() + 3,
                function()
                    local color = ReadSetting("healAbsorbBarColor")
                    if color then return color.r, color.g, color.b, color.a or 1 end
                    return 200 / 255, 29 / 255, 29 / 255, 1
                end,
                function(red, green, blue, a)
                    StoreSetting("healAbsorbBarColor", { r = red, g = green, b = blue, a = a })
                    RebuildAndReload()
                end,
                true,
                20
            )
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local function UpdateHealAbsorbBarSwatchVis()
                colorSwatch:SetAlpha(CurHealAbsorbBarPos() ~= "none" and 1 or 0.3)
            end
            CUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSwatchVis)
            UpdateHealAbsorbBarSwatchVis()
        end
        if not CUI._prebuilding then
            local region = healAbsorbBarRow._leftRegion
            CUI.BuildInlineCog(region, {
                -- Vertical Grow is inert off the vertical positions.
                disabled = function()
                    local p = CurHealAbsorbBarPos()
                    return p ~= "rightVertical" and p ~= "leftVertical"
                end,
                disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                rawTooltip = true,
                title = "Heal Absorb Bar Rendering",
                rows = {
                    {
                        type = "dropdown",
                        label = "Vertical Grow",
                        values = { up = "Up", down = "Down" },
                        order = { "up", "down" },
                        disabled = function()
                            local p = CurHealAbsorbBarPos()
                            return p ~= "rightVertical" and p ~= "leftVertical"
                        end,
                        disabledTooltip = "Only affects the vertical (Right/Left Edge) positions",
                        rawTooltip = true,
                        get = SValRow("healAbsorbBarGrowDir", "up"),
                        set = SSetRow("healAbsorbBarGrowDir"),
                    },
                },
            })
        end
        -- The size slider reads as width for the vertical positions; retitle live.
        do
            local labelFS = healAbsorbBarRow._rightRegion._label
            local function UpdateHealAbsorbBarSizeLabel()
                local p = CurHealAbsorbBarPos()
                local vertical = p == "rightVertical" or p == "leftVertical"
                labelFS:SetText(CUI.L(vertical and "Bar Width" or "Bar Height"))
            end
            CUI.RegisterWidgetRefresh(UpdateHealAbsorbBarSizeLabel)
            UpdateHealAbsorbBarSizeLabel()
        end
    end

    -- Max Health Texture (+cog+swatch) | Max Health Opacity. Styles mirror Heal Absorb plus "Max Health Stripes" first; no placement control, overlay is always right-anchored.
    do
        local maxHealthRow
        maxHealthRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Max Health Style",
            tooltip = "How lost maximum health is drawn at the end of the bar.",
            values = absorbStyleValues,
            order = maxHealthStyleOrder,
            getValue = SValRow("maxHealthStyle", "maxHealthStripes"),
            setValue = function(val)
                WriteSetting("maxHealthStyle", val)
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Max Health Opacity",
            tooltip = "How visible the lost maximum health overlay is.",
            min = 5,
            max = 100,
            step = 1,
            disabled = function() return SettingOr("maxHealthStyle", "maxHealthStripes") == "none" end,
            disabledTooltip = "Max Health Style",
            getValue = SValRow("maxHealthOpacity", 100),
            setValue = SSetRow("maxHealthOpacity"),
        })
        cursorY = cursorY - height
        -- Cog carries backing opacity only; placement is fixed right-side.
        if not CUI._prebuilding then
            local region = maxHealthRow._leftRegion
            CUI.BuildInlineCog(region, {
                title = "Max Health Rendering",
                rows = {
                    {
                        type = "slider",
                        label = "Backing Opacity",
                        min = 0,
                        max = 100,
                        step = 1,
                        get = SValRow("maxHealthBgOpacity", 100),
                        set = SSetRow("maxHealthBgOpacity"),
                    },
                },
            })
        end
        -- Swatch tints the max health texture.
        if not CUI._prebuilding then
            local region = maxHealthRow._leftRegion
            local colorSwatch = CUI.BuildColorSwatch(region, maxHealthRow:GetFrameLevel() + 3, function()
                local color = ReadSetting("maxHealthColor")
                if color then return color.r or 0.7, color.g or 0.1, color.b or 0.1, 1 end
                return 0.7, 0.1, 0.1, 1
            end, function(red, green, blue)
                StoreSetting("maxHealthColor", { r = red, g = green, b = blue })
                RebuildAndReload()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            -- Blocked for "none" and the pre-colored styles.
            local swatchBlock = CUI.NewSwatchBlocker(colorSwatch)
            swatchBlock:Hide()
            local function UpdateMaxHealthSwatchVis()
                local st = SettingOr("maxHealthStyle", "maxHealthStripes")
                local off = (
                    st == "none"
                    or st == "healBlizzModern"
                    or st == "largeOutlinedStripes"
                    or st == "largeOutlinedStripesR"
                )
                colorSwatch:SetAlpha(off and 0.3 or 1)
                if off then
                    swatchBlock:Show()
                else
                    swatchBlock:Hide()
                end
            end
            CUI.RegisterWidgetRefresh(UpdateMaxHealthSwatchVis)
            UpdateMaxHealthSwatchVis()
        end
    end

    -------------------------------------------------------------------
    --  POWER BAR
    -------------------------------------------------------------------
    local powerHeader
    if onSection then onSection("absorbs", _secY, cursorY) end
    _secY = cursorY
    powerHeader, height = W:SectionHeader(hostFrame, "POWER BAR", cursorY)
    cursorY = cursorY - height

    -- Power bar animation: same pattern as health, serves raid + party.
    if not CUI._prebuilding then
        local EYE_VISIBLE = CUI.EYE_VISIBLE_ICON
        local EYE_INVISIBLE = CUI.EYE_INVISIBLE_ICON
        -- On ns: single ticker, resolves the active preview at call time.
        mod._powerAnimState = mod._powerAnimState or {}

        local function StopPowerAnim()
            if mod._powerAnimTicker then
                mod._powerAnimTicker:Cancel()
                mod._powerAnimTicker = nil
            end
            mod._powerAnimActive = false
            local ppv = mod.PvPowerValues()
            if ppv then
                for idx, st in ipairs(mod._powerAnimState) do
                    ppv[idx] = st.current
                end
            end
        end
        -- Exposed for onModuleLeave below.
        mod.StopPowerAnim = StopPowerAnim

        local function StartPowerAnim()
            if mod._powerAnimTicker then return end
            mod._powerAnimActive = true
            wipe(mod._powerAnimState)

            local frameList = mod.PvActiveFrames()
            for idx = 1, 20 do
                local f = frameList[idx]
                if f and f._power and f._power:IsShown() then
                    local cur = f._powerPct or (50 + math.random(50))
                    mod._powerAnimState[idx] = {
                        frame = f,
                        current = cur,
                        target = math.max(10, math.min(100, cur + math.random(-8, 8))),
                        snapTimer = math.random() * 3,
                        nextSnap = 1.8 + math.random() * 2.3,
                    }
                end
            end

            local pwSmoothInterp = Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            mod._powerAnimTicker = C_Timer.NewTicker(0.1, function()
                if not mod._powerAnimActive then return end
                -- Effective overlay; see the health ticker note above.
                local smooth = ((mod.PvEffectiveProfile and mod.PvEffectiveProfile()) or saved.profile).smoothPowerBars

                for idx, st in pairs(mod._powerAnimState) do
                    local f = st.frame
                    if f and f._power then
                        st.snapTimer = st.snapTimer + 0.1
                        if st.snapTimer < st.nextSnap then
                        else
                            st.snapTimer = 0
                            st.nextSnap = 2.5 + math.random() * 3
                            st.current = st.target
                            st.target = math.max(10, math.min(100, st.current + math.random(-8, 8)))

                            if smooth and pwSmoothInterp then
                                f._power:SetValue(st.current, pwSmoothInterp)
                            else
                                f._power:SetValue(st.current)
                            end
                            -- The texts following power (Custom texts reading it included).
                            local preview = f._pv
                            if preview then
                                preview.ppPct = st.current
                                mod.RF_TextPreviewTick(f, "pp")
                            end
                        end
                    end
                end
            end)
        end

        local pwLabel
        for _, region in ipairs({ powerHeader:GetRegions() }) do
            if region.GetText and CUI.EnKey(region:GetText()) == "POWER BAR" then
                pwLabel = region
                break
            end
        end
        local eyeButton = CreateFrame("Button", nil, powerHeader)
        eyeButton:SetSize(24, 24)
        if pwLabel then
            eyeButton:SetPoint("LEFT", pwLabel, "RIGHT", 5, 0)
        else
            eyeButton:SetPoint("LEFT", powerHeader, "BOTTOMLEFT", 85, 8)
        end
        eyeButton:SetFrameLevel(powerHeader:GetFrameLevel() + 5)
        CUI.SetGlyphAlpha(eyeButton, 0.4)
        local eyeTex = eyeButton:CreateTexture(nil, "OVERLAY")
        eyeTex:SetAllPoints()
        local function SyncPowerEye()
            if IsPreviewOff() then
                eyeTex:SetTexture(EYE_VISIBLE)
                CUI.SetGlyphAlpha(eyeButton, 0.15)
                return
            end
            eyeTex:SetTexture(mod._powerAnimActive and EYE_INVISIBLE or EYE_VISIBLE)
            CUI.SetGlyphAlpha(eyeButton, 0.4)
        end
        EYE.refreshPowerEye = SyncPowerEye
        mod._stopPowerAnim = StopPowerAnim
        SyncPowerEye()
        eyeButton:SetScript("OnClick", function()
            if IsPreviewOff() then return end
            if mod._powerAnimActive then
                StopPowerAnim()
            else
                if mod._indicatorsVisible then
                    mod._indicatorsVisible = false
                    if EYE.refreshIndicatorEye then EYE.refreshIndicatorEye() end
                end
                StartPowerAnim()
            end
            SyncPowerEye()
        end)
        eyeButton:SetScript("OnEnter", function(self)
            if IsPreviewOff() then
                CUI.ShowWidgetTooltip(self, "Enable preview to use")
                return
            end
            CUI.SetGlyphAlpha(self, 0.7)
            CUI.ShowWidgetTooltip(
                self,
                mod._powerAnimActive and "Stop power animation" or "Animate power bars"
            )
        end)
        eyeButton:SetScript("OnLeave", function(self)
            if not IsPreviewOff() then CUI.SetGlyphAlpha(self, 0.4) end
            CUI.HideWidgetTooltip()
        end)
        -- (The panel-close stop and eye reset: StopAnimEyesOnHide, at the top.)
    end -- power eyeball

    -- Power bar is off when no role is selected.
    -- The Party Frames kit's mana bar always shows. Decided at build time:
    -- the page being built is only known then, and this runs on refreshes.
    local IsPowerOff = mod.RF_OptPartyKit() and function() return false end
        or function()
            return not SettingOr("powerShowForHealer", true)
                and not SettingOr("powerShowForTank", true)
                and not SettingOr("powerShowForDPS", false)
        end

    do
        local showForItems = {
            { key = "healer", label = "Healers" },
            { key = "tank", label = "Tanks" },
            { key = "dps", label = "DPS" },
        }
        local showForKeyMap =
            { healer = "powerShowForHealer", tank = "powerShowForTank", dps = "powerShowForDPS" }
        -- Party Frames kit: the stock mana bar always shows at the stock
        -- size, so this row (and its cog) hides on the Party page.
        row, height = W:DualRow(
            hostFrame,
            cursorY,
            mod.RF_PartyKitGate({
                type = "dropdown",
                text = "Show Power Bar For",
                tooltip = "Which roles show a power bar.",
                values = { __placeholder = "Healers, Tanks" },
                order = { "__placeholder" },
                getValue = function() return "__placeholder" end,
                setValue = function() end,
            }),
            mod.RF_PartyKitGate({
                type = "slider",
                text = "Power Height",
                min = 1,
                max = 20,
                step = 1,
                disabled = function() return IsPowerOff() end,
                disabledTooltip = "Show Power Bar For",
                getValue = SValRow("powerHeight", 4),
                setValue = SSetRow("powerHeight"),
            })
        )
        cursorY = cursorY - height
        -- Cog: uniform icon anchoring. Greyed + blocked while no role shows a power bar (nothing to ignore then).
        do
            local region = row._rightRegion
            CUI.BuildInlineCog(region, {
                disabled = IsPowerOff,
                disabledTooltip = "Show Power Bar For",
                title = "Power Height",
                rows = {
                    {
                        type = "toggle",
                        label = "Icons Ignore Power Bar",
                        tooltip = "Anchor icons and text as if no power bar existed, so frames with and without one line up identically.",
                        get = SValRow("powerUniformAnchors", false),
                        set = SSetRow("powerUniformAnchors"),
                    },
                    {
                        type = "toggle",
                        label = "Extend Health Bar Behind Power",
                        tooltip = "Health bar spans the full frame height and the power bar draws on top of it.",
                        get = SValRow("extendHealthBehindPower", false),
                        set = SSetRow("extendHealthBehindPower"),
                    },
                },
            })
        end
        if not CUI._prebuilding then
            local region = row._leftRegion
            if region._control then region._control:Hide() end
            local checkDrop = CUI.BuildVisOptsCBDropdown(
                region,
                170,
                region:GetFrameLevel() + 2,
                showForItems,
                function(keyName) return SettingOr(showForKeyMap[keyName], true) end,
                function(keyName, val)
                    WriteSetting(showForKeyMap[keyName], val)
                    if mod.UpdatePowerEventRegistration then mod.UpdatePowerEventRegistration() end
                    CUI:RefreshPage()
                end
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
        end
    end

    local pwBorderStyleValues = {
        cui = "CludesUI",
        divider = "Divider",
        border = "Border",
    }
    local pwBorderStyleOrder = { "cui", "divider", "border" }
    -- Classic WoW UI draws the stock health/power divider in place of the
    -- power border (Blizzard Style has none, so the row stays there).
    local function PwClassicGate(rowConf)
        if CUI.BlizzStyle and CUI.BlizzStyle.Active("raidframes") == "classic" then
            return CUI.BlizzStyle.Gate("raidframes", rowConf)
        end
        return rowConf
    end
    local pwBdrRow
    local function CanMatchPowerBorder()
        local key = ReadSetting("borderTexture")
        return not CUI.BlizzStyle.Get("raidframes") and CUI._pixelArtBorders[key] == true
    end
    local function MatchingPowerBorder()
        return SettingOr("powerBorderMatchFrame", false)
            and CanMatchPowerBorder()
            and SettingOr("powerBorderStyle", "cui") ~= "cui"
    end
    local pwSizeCfg
    if MatchingPowerBorder() then
        pwSizeCfg = CUI.BorderPxSliderCfg({
            getStep = function() return SettingOr("borderSize", 1) end,
            setStep = function() end,
            getTex = function() return ReadSetting("borderTexture") end,
            getPx = function() return SGetPx("borderSizePx", "borderSize") end,
            setPx = function() end,
            disabled = function() return true end,
            disabledTooltip = "Size and color follow the frame border while Match Frame Border is enabled.",
            rawTooltip = true,
        })
    else
        pwSizeCfg = {
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 4,
            step = 1,
            disabled = function() return IsPowerOff() or SettingOr("powerBorderStyle", "cui") == "cui" end,
            disabledTooltip = "Show Power Bar For",
            getValue = SValRow("powerBorderSize", 1),
            setValue = SSetRow("powerBorderSize"),
        }
    end
    pwBdrRow, height = W:DualRow(
        hostFrame,
        cursorY,
        mod.RF_PartyKitGate(PwClassicGate({
            type = "dropdown",
            text = "Border Style",
            values = pwBorderStyleValues,
            order = pwBorderStyleOrder,
            disabled = function() return IsPowerOff() end,
            disabledTooltip = "Show Power Bar For",
            getValue = SValRow("powerBorderStyle", "divider"),
            setValue = function(val)
                WriteSetting("powerBorderStyle", val)
                CUI:RefreshPage(SettingOr("powerBorderMatchFrame", false) and CanMatchPowerBorder())
            end,
        })),
        mod.RF_PartyKitGate(PwClassicGate(pwSizeCfg))
    )
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(pwBdrRow._leftRegion, {
            disabled = function() return IsPowerOff() or not CanMatchPowerBorder() end,
            disabledTooltip = function()
                return IsPowerOff() and "Show Power Bar For" or "Pixels or Pixels Textured Border Style"
            end,
            title = "Power Border Options",
            rows = {
                mod.RF_PartyKitGate({
                    type = "toggle",
                    label = "Match Frame Border",
                    tooltip = "Uses the frame border's art, size and color.",
                    get = SValRow("powerBorderMatchFrame", false),
                    set = function(val)
                        WriteSetting("powerBorderMatchFrame", val)
                        CUI:RefreshPage(true)
                    end,
                }),
                mod.RF_PartyKitGate({
                    type = "toggle",
                    label = "Match Highlight Colors",
                    tooltip = "The divider follows hover and target colors.",
                    disabled = function()
                        return not MatchingPowerBorder() or SettingOr("powerBorderStyle", "cui") ~= "divider"
                    end,
                    disabledTooltip = "Requires Match Frame Border and Divider.",
                    rawTooltip = true,
                    get = SValRow("powerBorderMatchColor", false),
                    set = SSetRow("powerBorderMatchColor"),
                }),
            },
        })
        local region = pwBdrRow._rightRegion
        local colorSwatch, updateSwatch = CUI.BuildColorSwatch(
            region,
            pwBdrRow:GetFrameLevel() + 3,
            function()
                if MatchingPowerBorder() then
                    local color = ReadSetting("borderColor")
                    return color and color.r or 0,
                        color and color.g or 0,
                        color and color.b or 0,
                        SettingOr("borderAlpha", 1)
                end
                local color = ReadSetting("powerBorderColor")
                if color then return color.r, color.g, color.b, SettingOr("powerBorderAlpha", 1) end
                return 0, 0, 0, 1
            end,
            function(red, green, blue, a)
                StoreSetting("powerBorderColor", { r = red, g = green, b = blue })
                StoreSetting("powerBorderAlpha", a)
                RebuildAndReload()
            end,
            true,
            20
        )
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        local block = CUI.NewSwatchBlocker(colorSwatch)
        block:SetScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    colorSwatch,
                    MatchingPowerBorder()
                            and "Size and color follow the frame border while Match Frame Border is enabled."
                        or CUI.DisabledTooltip("Border Style")
                )
            end
        )
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function UpdatePwBdrSwatchState()
            local off = IsPowerOff()
                or SettingOr("powerBorderSize", 1) == 0
                or SettingOr("powerBorderStyle", "cui") == "cui"
                or MatchingPowerBorder()
            if off then
                colorSwatch:SetAlpha(0.3)
                block:Show()
            else
                colorSwatch:SetAlpha(1)
                block:Hide()
            end
        end
        CUI.RegisterWidgetRefresh(function()
            if updateSwatch then updateSwatch() end
            UpdatePwBdrSwatchState()
        end)
        UpdatePwBdrSwatchState()
    end

    local pwBgRow
    pwBgRow, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Smooth Power Bars",
        tooltip = "Power changes slide smoothly instead of jumping.",
        disabled = function() return IsPowerOff() end,
        disabledTooltip = "Show Power Bar For",
        getValue = SValRow("smoothPowerBars", true),
        setValue = SSetRow("smoothPowerBars"),
    }, {
        type = "slider",
        text = "Background",
        min = 0,
        max = 100,
        step = 1,
        disabled = function() return IsPowerOff() end,
        disabledTooltip = "Show Power Bar For",
        getValue = SValRow("powerBgDarkness", 70),
        setValue = SSetRow("powerBgDarkness"),
    })
    cursorY = cursorY - height
    -- Power bg Custom + Power Colored swatch pair: clicking either toggles powerBgPowerColored, the inactive one dims (mirrors the health bg).
    if not CUI._prebuilding then
        local region = pwBgRow._rightRegion
        -- Power swatch shows the player's power color and is not editable.
        local bgPwrSwatch = CUI.BuildColorSwatch(region, pwBgRow:GetFrameLevel() + 3, function()
            local _, pToken = UnitPowerType("player")
            local details = CUI.GetPowerColor(pToken or "MANA")
            local f = CUI.GetPowerBgDarkenFactor()
            if details then return details.r * f, details.g * f, details.b * f, 1 end
            return 0, 0.5 * f, f, 1
        end, function() end, false, 20)
        bgPwrSwatch:SetScript("OnClick", function()
            WriteSetting("powerBgPowerColored", true)
            CUI:RefreshPage()
        end)
        bgPwrSwatch:HookScript(
            "OnEnter",
            function()
                CUI.ShowWidgetTooltip(
                    bgPwrSwatch,
                    "Power Colored Background. Power colors can be adjusted in Core Settings > Colors."
                )
            end
        )
        bgPwrSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        bgPwrSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgPwrSwatch

        local bgSwatch = CUI.BuildColorSwatch(region, pwBgRow:GetFrameLevel() + 3, function()
            local color = ReadSetting("powerBgColor")
            if color then return color.r, color.g, color.b, 1 end
            return 0, 0, 0, 1
        end, function(red, green, blue)
            StoreSetting("powerBgColor", { r = red, g = green, b = blue })
            RebuildAndReload()
        end, false, 20)
        bgSwatch._eabOrigClick = bgSwatch:GetScript("OnClick")
        bgSwatch:SetScript("OnClick", function(self)
            if SettingOr("powerBgPowerColored", false) then
                WriteSetting("powerBgPowerColored", false)
                CUI:RefreshPage()
                return
            end
            if self._eabOrigClick then self._eabOrigClick(self) end
        end)
        bgSwatch:HookScript(
            "OnEnter",
            function() CUI.ShowWidgetTooltip(bgSwatch, "Custom Colored Background") end
        )
        bgSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        bgSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = bgSwatch

        local function UpdatePwBgSwatchVis()
            local pwrOn = SettingOr("powerBgPowerColored", false)
            bgSwatch:SetAlpha(pwrOn and 0.3 or 1)
            bgPwrSwatch:SetAlpha(pwrOn and 1 or 0.3)
        end
        CUI.RegisterWidgetRefresh(UpdatePwBgSwatchVis)
        UpdatePwBgSwatchVis()
    end

    -------------------------------------------------------------------
    --  TEXT DISPLAY
    -------------------------------------------------------------------
    if onSection then onSection("powerBar", _secY, cursorY) end
    _secY = cursorY
    _, height = W:SectionHeader(hostFrame, "TEXT DISPLAY", cursorY)
    cursorY = cursorY - height

    cursorY = mod.RFO_BuildTextDisplay(
        W,
        hostFrame,
        cursorY,
        { page = CUI._buildingPage, party = optionState._partyCtx }
    )
    -- The Name Format also shapes the Top Name Bar, so it has a row of its own,
    -- not a place on the Name tile. Raid Frames saves "full" (an unset party
    -- key reads the raid's).
    do
        local function Set(val) WriteSetting("nameFormat", val) end
        local values, sequence, getValue = CUI.NameFormatMenu(
            function() return SettingOr("nameFormat", "full") end,
            Set
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Name Format",
            tooltip = "How names are shortened.",
            values = values,
            order = sequence,
            getValue = getValue,
            setValue = Set,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height
    end
    if onSection then onSection("textDisplay", _secY, cursorY) end
    _secY = cursorY
    return cursorY, CustomBorderOff, CustomBorderOffTip
end

-- Used by CUI_RaidFrames_Options.lua
mod.RFO_BuildVisualBars = BuildVisualBars
