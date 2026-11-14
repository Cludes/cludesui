if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  UnitFrames_Options\UnitPreview_Options.lua
--  Unit Frames options: the unit frame preview in the page header
--  (BuildUnitPreview). Definitions only; shared helpers and the
--  preview state come from ns._UFO_OptEnv (filled by
--  CUI_UnitFrames_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIUnitFrames"]
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the frames this file builds under a kept header root go through
-- the options frame pool (CludesUI_FramePool.lua), which hands the next
-- build the previous build's frames reset to new; on any other parent it
-- is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
-- The pool's other calls this file makes, read once here as CreateFrame is:
-- the page path never calls the pool through its public slot, which
-- another addon could replace.
local PoolOwned = CludesUI._Pool.Owned

function mod.UFO_BuildUnitPreview(hostFrame, unitKey, sideName)
    local environ = mod._UFO_OptEnv
    local ApplyClassIconTexture_Preview, ApplyPreviewPortraitShape, BlizzPreviewScale, CLASS_FULL_COORDS =
        environ.ApplyClassIconTexture_Preview,
        environ.ApplyPreviewPortraitShape,
        environ.BlizzPreviewScale,
        environ.CLASS_FULL_COORDS
    local Pix, PREVIEW_FONT, ResolveBlizzPreview =
        environ.PP, environ.PREVIEW_FONT, environ.ResolveBlizzPreview
    local SOLID_BACKDROP, SetPVFont, _previewBuffIcons, _previewCreatureNames =
        environ.SOLID_BACKDROP, environ.SetPVFont, environ._previewBuffIcons, environ._previewCreatureNames
    local allPreviews, saved, optionState, unitSide =
        environ.allPreviews, environ.db, environ.optState, environ.unitSide
    -- Preview clamps the aura Y offset to this magnitude so a large offset
    -- can't balloon the preview/content header; real frames apply it in full.
    local PREVIEW_Y_CAP = 50
    -- Preview fill coloring with optional additive gradient (mirrors real frames).
    local function PV_FillColor(texture, texPath, br, backdrop, bb, gEnabled, gColor, gDir, alpha)
        if not texture then
            return
        end
        if gEnabled then
            local gr, gg, gbb = 0.20, 0.20, 0.80
            if gColor then
                gr, gg, gbb = gColor.r, gColor.g, gColor.b
            end
            if texPath then
                texture:SetTexture(texPath)
            else
                texture:SetColorTexture(1, 1, 1, 1)
            end
            texture:SetVertexColor(1, 1, 1, 1)
            -- Gradient overrides region alpha, so Bar Opacity is baked into
            -- the gradient endpoint alphas.
            local a = alpha or 1
            texture:SetGradient(
                gDir or "HORIZONTAL",
                CreateColor(br, backdrop, bb, a),
                CreateColor(gr, gg, gbb, a)
            )
        elseif texPath then
            texture:SetTexture(texPath)
            texture:SetVertexColor(br, backdrop, bb, 1)
        else
            texture:SetColorTexture(br, backdrop, bb, 1)
        end
    end
    local p = saved.profile
    local prefs
    if unitKey == "player" then
        prefs = p.player
    elseif unitKey == "target" then
        prefs = p.target
    elseif unitKey == "focus" then
        prefs = p.focus
    elseif unitKey == "pet" then
        prefs = p.pet
    elseif unitKey == "boss" then
        prefs = p.boss
    elseif unitKey == "targettarget" then
        prefs = p.targettarget
    elseif unitKey == "focustarget" then
        prefs = p.focustarget
    else
        prefs = p.player
    end

    sideName = sideName or "left"

    -- Mini frames (ToT/FoT/Pet) have no power bar, cast bar or auras at
    -- runtime, so the preview draws none, except the pet's opt-in buffs and
    -- debuffs (drawn while their Location is set) and, on WoW Forever, the
    -- pet's power bar in the CUI look (the stock styles paint their own).
    local isMiniPreview = (unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "pet")
    local noPowerPreview = isMiniPreview
        and not (unitKey == "pet" and mod.UF_PetHasPower and not ResolveBlizzPreview(unitKey, prefs))
    local noDebuffPreview = isMiniPreview and unitKey ~= "pet"
    local noCastbarPreview = isMiniPreview

    local hasPortraitSupport = (prefs.showPortrait ~= nil or prefs.portraitMode ~= nil)
    local portraitShownByUser = prefs.showPortrait ~= false
    local showPortrait = hasPortraitSupport
        and (prefs.portraitStyle or saved.profile.portraitStyle or "attached") ~= "none"
        and portraitShownByUser
    local frameW = prefs.frameWidth or 181
    local healthH = prefs.healthHeight or 46
    local powerH = noPowerPreview and 0 or (prefs.powerHeight or 6)
    local initPpPos = noPowerPreview and "none" or mod.UF_PowerPos(prefs)
    local initPpIsAtt = (initPpPos == "below" or initPpPos == "above")
    local initPpExtra = initPpIsAtt and powerH or 0
    -- Castbar gate: player = showPlayerCastbar (always locked to the frame),
    -- target/focus = showCastbar, mini frames never.
    local castbarH
    if noCastbarPreview then
        castbarH = 0
    elseif unitKey == "player" then
        local pch = prefs.playerCastbarHeight
        castbarH = prefs.showPlayerCastbar and (pch and pch > 0 and pch or 14) or 0
    else
        castbarH = (prefs.showCastbar ~= false) and (prefs.castbarHeight or 14) or 0
    end
    -- A cast bar moved out of the strip below the frame reserves no space in
    -- the live layout, so the preview must not draw it there either (same
    -- decision, one helper: CludesUIUnitFrames/CUI_UnitFrames_AuraContainers.lua).
    if castbarH > 0 and CludesUI.UF_CastbarBelowFrame and not CludesUI.UF_CastbarBelowFrame(unitKey) then
        castbarH = 0
    end
    local barH = healthH + initPpExtra
    local isAttachedInit = (prefs.portraitStyle or saved.profile.portraitStyle or "attached") == "attached"
    local portraitW = (showPortrait and isAttachedInit) and barH or 0
    local totalW = frameW + portraitW
    local totalH = barH

    -- Compute initial aura extra height (buffs/debuffs extend beyond frame)
    local initBuffExtra = 0
    local initBuffTopPad = 0
    if prefs.showBuffs then
        local ba = prefs.buffAnchor or "topleft"
        -- Only top/bottom anchors extend vertically; left/right columns grow sideways.
        if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" then
            initBuffExtra = (prefs.buffSize or 22) + 1 + 2
        end
        if ba == "topleft" or ba == "topright" then
            initBuffTopPad = initBuffExtra
        end
        -- Mirror pf:Update's Y-offset overflow reserve (auraTopOv/auraBotOv) so the
        -- first build spaces content correctly; else it's wrong until a slider nudge.
        local boy = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, prefs.buffOffsetY or 0))
        if ba == "topleft" or ba == "topright" then
            if boy > 0 then
                initBuffTopPad = initBuffTopPad + boy
            end
        elseif ba == "bottomleft" or ba == "bottomright" then
            if boy < 0 then
                initBuffExtra = initBuffExtra - boy
            end
        else
            if boy > 0 then
                initBuffTopPad = initBuffTopPad + boy
            elseif boy < 0 then
                initBuffExtra = initBuffExtra - boy
            end
        end
    end
    do
        local da = prefs.debuffAnchor or "none"
        if da == "topleft" or da == "topright" or da == "bottomleft" or da == "bottomright" then
            local debuffH = (prefs.debuffSize or 22) + 1 + 2
            initBuffExtra = initBuffExtra + debuffH
            if da == "topleft" or da == "topright" then
                initBuffTopPad = initBuffTopPad + debuffH
            end
        end
        -- Mirror the debuff Y-offset overflow reserved in pf:Update.
        local doy = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, prefs.debuffOffsetY or 0))
        if da == "topleft" or da == "topright" then
            if doy > 0 then
                initBuffTopPad = initBuffTopPad + doy
            end
        elseif da == "bottomleft" or da == "bottomright" then
            if doy < 0 then
                initBuffExtra = initBuffExtra - doy
            end
        elseif da ~= "none" then
            if doy > 0 then
                initBuffTopPad = initBuffTopPad + doy
            elseif doy < 0 then
                initBuffExtra = initBuffExtra - doy
            end
        end
    end

    local popFrame = CreateFrame("Frame", nil, hostFrame)
    -- The unit this dress shows: a kept header root hands the same frame to the
    -- next unit, so an allPreviews entry whose frame now shows another unit is stale.
    popFrame._pvUnit = unitKey
    -- Real frames render at UIParent's effective scale vs. the panel's smaller one;
    -- this ratio makes every pixel value match the real frames' physical size.
    local previewScale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    popFrame._previewBaseScale = previewScale
    -- Blizzard Style: Frame Scale rides the preview scale (the live frame is
    -- SetScale'd the same way), so anchors and the header math stay in step.
    if ResolveBlizzPreview(unitKey, prefs) then
        previewScale = previewScale * BlizzPreviewScale(prefs)
    end
    popFrame:SetScale(previewScale)
    popFrame._buffExtra = initBuffExtra
    popFrame._buffTopPad = initBuffTopPad
    popFrame._previewScale = previewScale
    Pix.Point(popFrame, "TOP", hostFrame, "TOP", 0, -(25 + initBuffTopPad) / previewScale)

    -- barArea: child of pf sized to health+power only (excludes castbar).
    local barArea = CreateFrame("Frame", nil, popFrame)
    Pix.Size(barArea, totalW, barH)
    Pix.Point(barArea, "TOPLEFT", popFrame, "TOPLEFT", 0, 0)

    -- Portrait
    local portraitFrame
    if hasPortraitSupport then
        portraitFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(portraitFrame, barH, barH)
        portraitFrame:SetClipsChildren(true)
        local portraitBg = portraitFrame:CreateTexture(nil, "BACKGROUND")
        portraitBg:SetAllPoints()
        portraitBg:SetColorTexture(0.082, 0.082, 0.082, 1)
        portraitFrame._previewBg = portraitBg
        if sideName == "left" then
            Pix.Point(portraitFrame, "TOPLEFT", barArea, "TOPLEFT", 0, 0)
        else
            Pix.Point(portraitFrame, "TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
        end

        local portraitTex = portraitFrame:CreateTexture(nil, "ARTWORK")
        portraitTex:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
        portraitTex:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
        portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)

        -- Lazy model for 3D preview or enabled 2D mirror eligibility checks.
        local portraitModel = nil

        local function EnsurePreviewModel()
            if portraitModel then
                return portraitModel
            end
            portraitModel = CreateFrame("PlayerModel", nil, portraitFrame)
            portraitModel:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
            portraitModel:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
            portraitModel:SetUnit("player")
            portraitModel:SetCamera(0)
            portraitModel:Hide()
            portraitFrame._previewModel = portraitModel
            return portraitModel
        end

        -- Track last applied mode+style+zoom+mirror to avoid redundant re-init
        local _lastAppliedMode = nil
        local _lastAppliedStyle = nil
        local _lastAppliedZoom = nil
        local _lastAppliedMirror = nil

        local function ApplyPortraitMode()
            -- Read settings fresh from DB; a captured table goes stale after a
            -- preview switch or cache restore.
            local curSettings
            if unitKey == "player" then
                curSettings = saved.profile.player
            elseif unitKey == "target" then
                curSettings = saved.profile.target
            elseif unitKey == "focus" then
                curSettings = saved.profile.focus
            elseif unitKey == "pet" then
                curSettings = saved.profile.pet
            elseif unitKey == "boss" then
                curSettings = saved.profile.boss
            elseif unitKey == "targettarget" then
                curSettings = saved.profile.targettarget
            elseif unitKey == "focustarget" then
                curSettings = saved.profile.focustarget
            else
                curSettings = saved.profile.player
            end
            local modeName = curSettings.portraitMode or "2d"
            -- A non-player frame that opted in previews its Class art fallback
            -- (the stock styles keep their own portrait). The resolved mode is
            -- the memo key, so every input of the fallback rides it.
            if
                modeName == "class"
                and unitKey ~= "player"
                and curSettings.portraitNonPlayerOn
                and not CludesUI.BlizzStyle.Get("unitframes")
            then
                modeName = mod.UF_ClassFallback(curSettings)
            end
            local look = curSettings.classThemeStyle or "modern"
            local zoom = (curSettings.portraitArtScale or 100) + (curSettings.portrait3dZoom or 100) * 1000
            -- Mirror Portrait also turns 3D models; never under a stock style.
            local mirror = (curSettings.portraitMirror and not CludesUI.BlizzStyle.Get("unitframes")) and true
                or false
            -- Skip unchanged: re-initializing PlayerModel every Update() blinks
            -- and costs massive GPU.
            if modeName == _lastAppliedMode and look == _lastAppliedStyle and zoom == _lastAppliedZoom then
                if mirror == _lastAppliedMirror then
                    return
                end
                if modeName == "3d" and portraitModel then
                    _lastAppliedMirror = mirror
                    mod.UF_ApplyPortraitRotation(portraitModel, mirror)
                    return
                end
            end
            _lastAppliedMode = modeName
            _lastAppliedStyle = look
            _lastAppliedZoom = zoom
            _lastAppliedMirror = mirror
            portraitFrame._previewMode = modeName
            -- The preview reuses one texture for class art and 2D portraits.
            if modeName ~= "class" and portraitTex._classZoomMasked then
                portraitTex:RemoveMaskTexture(portraitTex._classZoomMask)
                portraitTex._classZoomMask:Hide()
                portraitTex._classZoomMasked = nil
            end
            if modeName == "3d" then
                portraitFrame:Show()
                portraitTex:Hide()
                local pm = EnsurePreviewModel()
                pm:SetUnit("player")
                pm:SetCamera(0)
                pm:SetPortraitZoom(1)
                pm:SetPosition(0, 0, 0)
                local camScale = (curSettings.portrait3dZoom or 100) / 100
                pm:SetCamDistanceScale(camScale)
                pm:Show()
                mod.UF_ApplyPortraitRotation(pm, mirror)
            elseif modeName == "class" then
                portraitFrame:Show()
                if portraitModel then
                    portraitModel:Hide()
                end
                portraitTex:Show()
                local _, ct = UnitClass("player")
                ApplyClassIconTexture_Preview(portraitTex, ct or "WARRIOR", look, mirror)
                portraitTex:SetAlpha(0.9)
                -- Use current portrait frame height for inset (not captured barH)
                local curBH = portraitFrame:GetHeight()
                if curBH < 1 then
                    curBH = barH
                end
                local inset = math.floor(curBH * 0.08)
                portraitTex:ClearAllPoints()
                Pix.Point(portraitTex, "TOPLEFT", portraitFrame, "TOPLEFT", inset, -inset)
                Pix.Point(portraitTex, "BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -inset, inset)
            elseif modeName == "none" then
                -- Non-player fallback "Nothing": the empty backdrop.
                portraitFrame:Show()
                if portraitModel then
                    portraitModel:Hide()
                end
                portraitTex:Hide()
            else
                portraitFrame:Show()
                if portraitModel then
                    portraitModel:Hide()
                end
                portraitTex:Show()
                SetPortraitTexture(portraitTex, "player")
                mirror = mirror and mod.UF_CanMirrorPortrait2D(EnsurePreviewModel(), "player")
                if mirror then
                    portraitTex:SetTexCoord(0.85, 0.15, 0.15, 0.85)
                else
                    portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
                end
                portraitTex:SetAlpha(1)
                portraitTex:ClearAllPoints()
                Pix.Point(portraitTex, "TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
                Pix.Point(portraitTex, "BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
            end
        end
        portraitFrame._applyMode = ApplyPortraitMode
        portraitFrame._isPreview = true
        portraitFrame._previewTex = portraitTex
        portraitFrame._previewModel = portraitModel
        ApplyPortraitMode()

        if not showPortrait then
            portraitFrame:Hide()
        end
    end

    -- Health bar color
    local hR, hG, hB, hA, bgR, bgG, bgB, bgA
    local isDarkTheme = mod.UF_DarkThemeOn(prefs)
    if isDarkTheme then
        hR, hG, hB, hA = CludesUI.GetDarkModeFill()
        bgR, bgG, bgB, bgA = CludesUI.GetDarkModeBg()
    else
        local barOpacity = (prefs.healthBarOpacity or 90) / 100
        hA = barOpacity
        -- Custom fill color is skipped when class-colored. Boss preview is
        -- always hostile-red: the real boss frame never class-colors.
        local cFill = prefs.customFillColor
        local isClassColored = prefs.healthClassColored and unitKey ~= "boss"
        if isClassColored then
            local _, classToken = UnitClass("player")
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then
                hR, hG, hB = cc.r, cc.g, cc.b
            else
                hR, hG, hB = 37 / 255, 193 / 255, 29 / 255
            end
        elseif cFill then
            hR, hG, hB = cFill.r, cFill.g, cFill.b
        elseif unitKey == "player" then
            local _, classToken = UnitClass("player")
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then
                hR, hG, hB = cc.r, cc.g, cc.b
            else
                hR, hG, hB = 37 / 255, 193 / 255, 29 / 255
            end
        elseif unitKey == "pet" then
            hR, hG, hB = 37 / 255, 193 / 255, 29 / 255
        else
            hR, hG, hB = 0.8, 0.2, 0.2
        end
        -- Dynamic Health Color outranks every flat source above, exactly as it
        -- does on the live bar. The preview's health percent is a known fake,
        -- so this takes the clean-number twin of the engine curve rather than
        -- UnitHealthPercent.
        local pvDynR, pvDynG, pvDynB =
            mod.UF_PreviewDynamicColor(prefs, optionState._previewHealthPct or 0.70)
        if pvDynR then
            hR, hG, hB = pvDynR, pvDynG, pvDynB
        end
        -- Class-colored background (designer shows the player's class), else custom.
        local bgClassCC
        if prefs.bgClassColored then
            local _, ct = UnitClass("player")
            bgClassCC = ct and CludesUI.GetClassColor(ct)
        end
        if bgClassCC then
            bgR, bgG, bgB = bgClassCC.r, bgClassCC.g, bgClassCC.b
        else
            local cBg = prefs.customBgColor
            if cBg then
                bgR, bgG, bgB = cBg.r, cBg.g, cBg.b
            else
                bgR, bgG, bgB = 17 / 255, 17 / 255, 17 / 255
            end
        end
        bgA = (prefs.customBgAlpha or 100) / 100
    end

    -- Health bar
    local healthBar = CreateFrame("Frame", nil, popFrame)
    Pix.Size(healthBar, frameW, healthH)
    local healthBgColor = healthBar:CreateTexture(nil, "BACKGROUND")
    -- Cover only the empty (missing-health) portion so a reduced fill opacity
    -- shows the backdrop through the fill, not the bg color. The live-update
    -- pass below re-anchors this for reverse fill (matches live frames).
    healthBgColor:SetPoint(
        "TOPLEFT",
        healthBar,
        "TOPLEFT",
        math.floor(frameW * (optionState._previewHealthPct or 0.70) + 0.5),
        0
    )
    healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    healthBgColor:SetColorTexture(bgR, bgG, bgB, 1)
    healthBgColor:SetAlpha(bgA)
    local pvPowerAboveOff = (initPpPos == "above") and powerH or 0
    if showPortrait and portraitFrame then
        if sideName == "left" then
            Pix.Point(healthBar, "TOPLEFT", portraitFrame, "TOPRIGHT", 0, -pvPowerAboveOff)
        else
            Pix.Point(healthBar, "TOPRIGHT", portraitFrame, "TOPLEFT", 0, -pvPowerAboveOff)
        end
    else
        Pix.Point(healthBar, "TOPLEFT", barArea, "TOPLEFT", 0, -pvPowerAboveOff)
    end

    local healthBg = healthBar:CreateTexture(nil, "BACKGROUND", nil, -1)
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(0.1, 0.1, 0.1, 0.75)

    local healthFill = healthBar:CreateTexture(nil, "ARTWORK")
    healthFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    healthFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    healthFill:SetWidth(math.floor(frameW * (optionState._previewHealthPct or 0.70) + 0.5))
    PV_FillColor(
        healthFill,
        nil,
        hR,
        hG,
        hB,
        (not isDarkTheme) and prefs.gradientEnabled,
        prefs.gradientColor,
        prefs.gradientDir,
        hA
    )
    healthFill:SetAlpha(hA)
    popFrame._healthFill = healthFill
    popFrame._hR, popFrame._hG, popFrame._hB, popFrame._hA = hR, hG, hB, hA

    local dispelOverlayPreview
    if unitKey == "player" then
        dispelOverlayPreview = healthBar:CreateTexture(nil, "ARTWORK", nil, 3)
        dispelOverlayPreview:SetTexture("Interface\\Buttons\\WHITE8X8")
        dispelOverlayPreview:Hide()
    end

    -- Text overlay frame (sits above absorb StatusBar and border)
    local textOverlay = CreateFrame("Frame", nil, popFrame)
    textOverlay:SetAllPoints(healthBar)
    textOverlay:SetFrameStrata(popFrame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(popFrame:GetFrameLevel() + 20, healthBar:GetFrameLevel() + 12))

    -- Left text
    local leftContent = prefs.leftTextContent or "name"
    local rightContent = prefs.rightTextContent or (unitKey == "focus" and "perhp" or "both")
    local leftTS = prefs.leftTextSize or prefs.textSize or 12
    local rightTS = prefs.rightTextSize or prefs.textSize or 12
    local leftFS = textOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(leftFS, PREVIEW_FONT, leftTS)
    leftFS:SetTextColor(1, 1, 1)
    leftFS:SetWordWrap(false)

    -- Right text
    local rightFS = textOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(rightFS, PREVIEW_FONT, rightTS)
    rightFS:SetTextColor(1, 1, 1)
    rightFS:SetWordWrap(false)

    local centerFS = textOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(centerFS, PREVIEW_FONT, prefs.centerTextSize or prefs.textSize or 12)
    centerFS:SetTextColor(1, 1, 1)
    centerFS:SetWordWrap(false)

    -- Extra Text FontString: anchored per extraTextAlign, never width-constrained
    -- (live frames never truncate it either).
    local extraFS = textOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(extraFS, PREVIEW_FONT, prefs.extraTextSize or prefs.textSize or 12)
    extraFS:SetTextColor(1, 1, 1)
    extraFS:SetWordWrap(false)

    -- Resolve preview text for a content key
    local function PreviewTextForContent(contentFrame, s, prefixText)
        -- Mirror "Show Decimal on Text": one decimal on abbrevs/percents when the
        -- global flag is on, else the Number Format for valueType like the live
        -- tags (boss frames read "bossHealth" for health).
        local function _pvAbbrev(val, valueType)
            local conf = _G._CUI_AbbrevDecimalCfg
            -- The live tags' function (WoW Forever: none under 10,000 abbreviates).
            if conf then
                return mod.AbbreviateNumbers(val, conf)
            end
            if valueType ~= "absorb" and unitKey:match("^boss") then
                valueType = "bossHealth"
            end
            return mod.AbbreviateValue(val, valueType)
        end
        local function _pvPct(p01)
            if not _G._CUI_TextDecimals then
                return tostring(math.floor(p01 * 100))
            end
            local trim = _G._CUI_PctTrim
            if trim then
                return AbbreviateNumbers(trim.curve:Evaluate(p01), trim.cfg)
            end
            return string.format("%.1f", p01 * 100)
        end
        local function _pvName()
            -- The player's name as the live frame shows it (Forever surname).
            local num = (unitKey == "player") and (CludesUI.WithSurname(UnitName("player")) or "Player")
                or (_previewCreatureNames[unitKey] or unitKey)
            -- The slot's Name Format.
            if prefixText and s then
                num = CludesUI.ShortName(num, s[prefixText .. "NameFormat"])
            end
            return num
        end
        -- literal: the Target content's padded prefix in place of the
        -- separator ("" = none); plain: the name in the slot colour.
        local function _pvTargetSuffix(literal, plain)
            local _, ct = UnitClass("player")
            local cc = ct and CludesUI.GetClassColor(ct)
            local tgt = "Target"
            if cc and not plain then
                tgt = string.format("%s%s|r", CludesUI.HexColor(cc.r, cc.g, cc.b), tgt)
            end
            -- Mirror the live [cui-tgtsep(...)] tag: per-slot space-padded
            -- separator, class-colored (preview target = player's class) or
            -- custom (default white).
            local sep = literal
            if not sep then
                sep = prefixText and s[prefixText .. "TargetSep"]
                if type(sep) ~= "string" or sep == "" then
                    sep = ">"
                end
                sep = " " .. sep .. " "
            end
            if sep == "" then
                return tgt
            end
            if prefixText and s[prefixText .. "TargetSepClassColor"] then
                if cc then
                    sep = string.format("%s%s|r", CludesUI.HexColor(cc.r, cc.g, cc.b), sep)
                end
            else
                local c = prefixText and s[prefixText .. "TargetSepColor"]
                local r, g, b = 1, 1, 1
                if type(c) == "table" then
                    r, g, b = c.r or 1, c.g or 1, c.b or 1
                end
                sep = string.format("%s%s|r", CludesUI.HexColor(r, g, b), sep)
            end
            return sep .. tgt
        end
        -- Live frames truncate names by width (per-slot Width % clamp in the
        -- position code); the preview relies on its own FontString width.
        if contentFrame == "name" then
            return _pvName()
        elseif contentFrame == "nametotarget" then
            return _pvName() .. _pvTargetSuffix()
        elseif contentFrame == "targetname" then
            -- Live twin: ns.ContentToZone's Target branch (Prefix nil = "T:",
            -- "" = none; the name class colored only while the slot is).
            local pre = prefixText and s[prefixText .. "TargetPrefix"]
            if type(pre) ~= "string" then
                pre = "T:"
            end
            return _pvTargetSuffix(
                pre ~= "" and (pre .. " ") or "",
                not (prefixText and s[prefixText .. "ClassColor"])
            )
        elseif contentFrame == "level" or contentFrame == "levelname" or contentFrame == "namelevel" then
            local lvl = UnitLevel("player")
            lvl = (type(lvl) == "number" and lvl > 0) and tostring(lvl) or "80"
            -- Level Difficulty Color: sample as an attackable unit of your level.
            if s and s.levelDifficultyColor then
                lvl = CludesUI.ColorText(lvl, CludesUI.GetLevelDifficultyColor(tonumber(lvl), true))
            end
            if contentFrame == "level" then
                return lvl
            elseif contentFrame == "levelname" then
                return lvl .. " | " .. _pvName()
            else
                return _pvName() .. " | " .. lvl
            end
        elseif
            contentFrame == "both"
            or contentFrame == "bothdash"
            or contentFrame == "curhpshort"
            or contentFrame == "healthshort"
            or contentFrame == "curmaxhp"
            or contentFrame == "perhp"
            or contentFrame == "perhpnosign"
            or contentFrame == "perhpnum"
            or contentFrame == "perhpnumdash"
        then
            local maxHP = UnitHealthMax("player") or 1
            local pct = optionState._previewHealthPct or 0.70
            local curHP = math.floor(maxHP * pct)
            if contentFrame == "healthshort" then
                return mod.AbbreviateShortHealth(curHP)
            elseif contentFrame == "curhpshort" then
                return _pvAbbrev(curHP, "health")
            elseif contentFrame == "curmaxhp" then
                return _pvAbbrev(curHP, "health") .. " / " .. _pvAbbrev(maxHP, "maxHealth")
            elseif contentFrame == "perhp" then
                return _pvPct(pct) .. "%"
            elseif contentFrame == "perhpnosign" then
                return _pvPct(pct)
            elseif contentFrame == "perhpnum" then
                return _pvPct(pct) .. "% | " .. _pvAbbrev(curHP, "health")
            elseif contentFrame == "perhpnumdash" then
                return _pvPct(pct) .. "% - " .. _pvAbbrev(curHP, "health")
            elseif contentFrame == "bothdash" then
                return _pvAbbrev(curHP, "health") .. " - " .. _pvPct(pct) .. "%"
            else
                return _pvAbbrev(curHP, "health") .. " | " .. _pvPct(pct) .. "%"
            end
        elseif contentFrame == "perpp" then
            local ppPct = optionState._previewPowerPct or 0.85
            return math.floor(ppPct * 100) .. "%"
        elseif contentFrame == "curpp" then
            local maxPP = UnitPowerMax("player") or 100
            local ppPct = optionState._previewPowerPct or 0.85
            return mod.AbbreviateNumbers(math.floor(maxPP * ppPct))
        elseif contentFrame == "curmaxpp" then
            local maxPP = UnitPowerMax("player") or 100
            local ppPct = optionState._previewPowerPct or 0.85
            return mod.AbbreviateNumbers(math.floor(maxPP * ppPct)) .. " / " .. mod.AbbreviateNumbers(maxPP)
        elseif contentFrame == "curhp_curpp" then
            local maxHP = UnitHealthMax("player") or 1
            local pct = optionState._previewHealthPct or 0.70
            local curHP = math.floor(maxHP * pct)
            local maxPP = UnitPowerMax("player") or 100
            local ppPct2 = optionState._previewPowerPct or 0.85
            return _pvAbbrev(curHP, "health") .. " | " .. mod.AbbreviateNumbers(math.floor(maxPP * ppPct2))
        elseif contentFrame == "perhp_perpp" then
            local pct = optionState._previewHealthPct or 0.70
            local ppPct3 = optionState._previewPowerPct or 0.85
            return _pvPct(pct) .. "% | " .. math.floor(ppPct3 * 100) .. "%"
        elseif contentFrame == "absorb" then
            local maxHP = UnitHealthMax("player") or 1
            return string.format("%d", math.floor(maxHP * 0.14))
        elseif contentFrame == "absorbshort" then
            local maxHP = UnitHealthMax("player") or 1
            return _pvAbbrev(math.floor(maxHP * 0.14), "absorb")
        elseif contentFrame == "healabsorb" then
            local maxHP = UnitHealthMax("player") or 1
            return string.format("%d", math.floor(maxHP * 0.08))
        elseif contentFrame == "healabsorbshort" then
            local maxHP = UnitHealthMax("player") or 1
            return _pvAbbrev(math.floor(maxHP * 0.08), "absorb")
        elseif contentFrame == "group" then
            return "3"
        elseif contentFrame == "custom" then
            -- Live twin: ns.ContentToZone's custom branch, the engine's parse
            -- filled with one sample per schema key.
            local str = prefixText and s and s[prefixText .. "CustomFormat"]
            local parsed = CludesUI.TextTags.Parse(mod.UF_TextTags, str)
            if not parsed then
                return ""
            end
            local keyList, vals = parsed.keys, {}
            local maxHP = UnitHealthMax("player") or 1
            local curHP = math.floor(maxHP * (optionState._previewHealthPct or 0.70))
            local maxPP = UnitPowerMax("player") or 100
            local ppPct = optionState._previewPowerPct or 0.85
            local curPP = math.floor(maxPP * ppPct)
            for idx = 1, #keyList do
                local key, val = keyList[idx]
                if key == "name" then
                    val = _pvName()
                elseif key == "target" then
                    val = "Target"
                elseif key == "group" then
                    val = "3"
                elseif key == "level" then
                    val = PreviewTextForContent("level", s, prefixText)
                elseif key == "hp" then
                    val = tostring(curHP)
                elseif key == "hp:abr" then
                    val = _pvAbbrev(curHP, "health")
                elseif key == "hp:max" then
                    val = tostring(maxHP)
                elseif key == "hp:max:abr" then
                    val = _pvAbbrev(maxHP, "maxHealth")
                elseif key == "hp:pct" then
                    val = _pvPct(optionState._previewHealthPct or 0.70)
                elseif key == "pp" then
                    val = tostring(curPP)
                elseif key == "pp:abr" then
                    val = mod.AbbreviateNumbers(curPP)
                elseif key == "pp:max" then
                    val = tostring(maxPP)
                elseif key == "pp:max:abr" then
                    val = mod.AbbreviateNumbers(maxPP)
                elseif key == "pp:pct" then
                    val = tostring(math.floor(ppPct * 100))
                elseif key == "absorb" then
                    val = PreviewTextForContent("absorb", s, prefixText)
                elseif key == "absorb:abr" then
                    val = PreviewTextForContent("absorbshort", s, prefixText)
                elseif key == "healabsorb" then
                    val = PreviewTextForContent("healabsorb", s, prefixText)
                else
                    val = PreviewTextForContent("healabsorbshort", s, prefixText)
                end
                vals[idx] = val
            end
            return string.format(parsed.fmt, unpack(vals, 1, #keyList))
        else
            return ""
        end
    end

    -- Class color helper for preview
    local function PreviewClassColor(fontStr, useCC, customR, customG, customB)
        if not fontStr then
            return
        end
        if useCC then
            if unitKey == "player" then
                local _, cls = UnitClass("player")
                if cls then
                    local c = CludesUI.GetClassColor(cls)
                    if c then
                        fontStr:SetTextColor(c.r, c.g, c.b)
                        return
                    end
                end
            else
                fontStr:SetTextColor(0.9, 0.3, 0.3)
                return
            end
        end
        fontStr:SetTextColor(customR or 1, customG or 1, customB or 1)
    end

    -- Power color override for preview (takes priority over class color for power-related text)
    local function PreviewPowerColor(fontStr, contentKey, usePowerColor, customFmt)
        if not fontStr or not usePowerColor then
            return
        end
        if mod.UF_IsPowerContent(contentKey, customFmt) then
            local pcR, pcG, pcB = CludesUI.ResolveUnitPowerColor("player")
            local details = pcR and { r = pcR, g = pcG, b = pcB }
            if details then
                fontStr:SetTextColor(details.r, details.g, details.b)
            else
                fontStr:SetTextColor(1, 1, 1)
            end
        end
    end
    local function ApplyPreviewTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or (unitKey == "focus" and "perhp" or "both")
        local cc = s.centerTextContent or "none"
        -- Sizes come from the unit's OWN settings, exactly like the live
        -- frames (settings.xTextSize or settings.textSize or 12). The old
        -- donor read here made the mini/boss previews render the DONOR
        -- frame's sizes while live honored the unit's own -- the boss
        -- health-bar text size cogs moved only the in-world preview.
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0

        local ec = s.extraTextContent or "none"
        SetPVFont(extraFS, PREVIEW_FONT, (s.extraTextSize or s.textSize or 12))
        extraFS:ClearAllPoints()
        extraFS:SetWidth(0)
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraFS:SetJustifyH("RIGHT")
                Pix.Point(extraFS, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraFS:SetJustifyH("CENTER")
                Pix.Point(extraFS, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraFS:SetJustifyH("LEFT")
                Pix.Point(extraFS, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            extraFS:SetText(PreviewTextForContent(ec, s, "extraText"))
            extraFS:Show()
            PreviewClassColor(
                extraFS,
                s.extraTextClassColor,
                s.extraTextColorR,
                s.extraTextColorG,
                s.extraTextColorB
            )
        else
            extraFS:Hide()
        end

        -- Each text position renders independently; Center does not hide Left/Right.
        SetPVFont(centerFS, PREVIEW_FONT, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            Pix.Point(centerFS, "CENTER", textOverlay, "CENTER", cxo, cyo)
            centerFS:SetText(PreviewTextForContent(cc, s, "centerText"))
            centerFS:Show()
            PreviewClassColor(
                centerFS,
                s.centerTextClassColor,
                s.centerTextColorR,
                s.centerTextColorG,
                s.centerTextColorB
            )
        else
            centerFS:Hide()
        end

        SetPVFont(leftFS, PREVIEW_FONT, lsz)
        leftFS:ClearAllPoints()
        if lc ~= "none" then
            leftFS:SetJustifyH("LEFT")
            Pix.Point(leftFS, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
            -- Constrain width when opposing right text exists (matches live frame truncation)
            local barW = s.frameWidth or 181
            if rc ~= "none" then
                local UF_TEXT_PADDING = 10
                local ufTW = {
                    both = 75,
                    curhpshort = 38,
                    healthshort = 38,
                    curmaxhp = 75,
                    curmaxpp = 75,
                    perhp = 38,
                    perpp = 38,
                    curpp = 38,
                    curhp_curpp = 75,
                    perhp_perpp = 75,
                    level = 24,
                }
                local rightUsed = (ufTW[rc] or 0) + UF_TEXT_PADDING
                if rc == "custom" then
                    rightUsed = mod.UF_EstimateTextWidth(rc, s.rightTextCustomFormat, true)
                end
                Pix.Width(leftFS, math.max(barW - rightUsed - 10, 20))
            else
                leftFS:SetWidth(0)
            end
            leftFS:SetText(PreviewTextForContent(lc, s, "leftText"))
            leftFS:Show()
            PreviewClassColor(
                leftFS,
                s.leftTextClassColor,
                s.leftTextColorR,
                s.leftTextColorG,
                s.leftTextColorB
            )
        else
            leftFS:Hide()
        end

        SetPVFont(rightFS, PREVIEW_FONT, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            Pix.Point(rightFS, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
            rightFS:SetText(PreviewTextForContent(rc, s, "rightText"))
            rightFS:Show()
            PreviewClassColor(
                rightFS,
                s.rightTextClassColor,
                s.rightTextColorR,
                s.rightTextColorG,
                s.rightTextColorB
            )
        else
            rightFS:Hide()
        end
    end
    ApplyPreviewTextPositions(prefs)

    -- Power bar
    local power
    local ppPreviewFS
    -- Create the bar + text overlay for any power-supporting unit even at height
    -- 0, so "power bar 0 + text" works and the bar survives 0 -> back up.
    if not noPowerPreview then
        power = CreateFrame("Frame", nil, popFrame)
        Pix.Size(power, frameW, powerH)
        local powerBg = power:CreateTexture(nil, "BACKGROUND")
        powerBg:SetAllPoints()
        popFrame._powerBg = powerBg
        local powerFill = power:CreateTexture(nil, "ARTWORK")
        powerFill:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
        powerFill:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", 0, 0)
        powerFill:SetWidth(math.floor(frameW * (optionState._previewPowerPct or 0.85) + 0.5))
        popFrame._powerFill = powerFill

        local isPowerColored = prefs.powerPercentPowerColor ~= false
        local customPFill = prefs.customPowerFillColor
        local customPBg = prefs.customPowerBgColor
        local pfR, pfG, pfB
        if isPowerColored and prefs.powerClassColored then
            local _, ct = UnitClass("player")
            local cc = CludesUI.GetClassColor(ct)
            pfR, pfG, pfB = cc.r, cc.g, cc.b
        elseif isPowerColored then
            local _, pToken = UnitPowerType("player")
            local details = CludesUI.GetPowerColor(pToken or "MANA")
            pfR, pfG, pfB = details.r, details.g, details.b
        elseif customPFill then
            pfR, pfG, pfB = customPFill.r, customPFill.g, customPFill.b
        else
            pfR, pfG, pfB = 0, 0, 1
        end
        local pbR, pbG, pbB
        if prefs.powerBgPowerColored then
            local _, pbToken = UnitPowerType("player")
            local pbInfo = CludesUI.GetPowerColor(pbToken or "MANA")
            local pbF = CludesUI.GetPowerBgDarkenFactor()
            pbR, pbG, pbB = pbInfo.r * pbF, pbInfo.g * pbF, pbInfo.b * pbF
        elseif customPBg then
            pbR, pbG, pbB = customPBg.r, customPBg.g, customPBg.b
        else
            pbR, pbG, pbB = 17 / 255, 17 / 255, 17 / 255
        end
        local powerOpacity = (prefs.powerBarOpacity or 100) / 100
        powerBg:SetColorTexture(pbR, pbG, pbB, 1)
        powerBg:SetAlpha((prefs.customPowerBgAlpha or 100) / 100)
        PV_FillColor(
            powerFill,
            nil,
            pfR,
            pfG,
            pfB,
            prefs.powerGradientEnabled,
            prefs.powerGradientColor,
            prefs.powerGradientDir,
            powerOpacity
        )
        powerFill:SetAlpha(powerOpacity)
        -- Fill Opacity < 100: bg covers only the empty portion, mirroring the live
        -- world-show-through behavior.
        if powerOpacity < 1 then
            popFrame._powerBgOpAnchored = true
            powerBg:ClearAllPoints()
            if prefs.powerReverseFill then
                powerBg:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                powerBg:SetPoint("BOTTOMRIGHT", powerFill, "BOTTOMLEFT", 0, 0)
            else
                powerBg:SetPoint("TOPLEFT", powerFill, "TOPRIGHT", 0, 0)
                powerBg:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
            end
        end
        -- Initial anchor based on power position
        if initPpPos == "none" then
            power:Hide()
        elseif initPpPos == "above" then
            Pix.Point(power, "BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
            Pix.Point(power, "BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
        elseif initPpPos == "detached_top" then
            power:SetPoint("BOTTOM", healthBar, "TOP", prefs.powerX or 0, 15 + (prefs.powerY or 0))
        elseif initPpPos == "detached_bottom" then
            power:SetPoint("TOP", healthBar, "BOTTOM", prefs.powerX or 0, -15 + (prefs.powerY or 0))
        else
            Pix.Point(power, "TOPLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            Pix.Point(power, "TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        end

        -- Power percent text overlay in preview (parented to pf, above border)
        local ppOvr = CreateFrame("Frame", nil, popFrame)
        ppOvr:SetAllPoints(power)
        ppOvr:SetFrameLevel(barArea:GetFrameLevel() + 8)
        ppPreviewFS = ppOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(ppPreviewFS, PREVIEW_FONT, 9)
        ppPreviewFS:Hide()
    end

    -- Bar texture: applied to the fill textures directly (preview uses plain Frames, not StatusBars)
    do
        local texKey = prefs.healthBarTexture or saved.profile.healthBarTexture or "none"
        local texPath = (mod.healthBarTextures or {})[texKey]

        if texPath then
            PV_FillColor(
                healthFill,
                texPath,
                hR,
                hG,
                hB,
                (not isDarkTheme) and prefs.gradientEnabled,
                prefs.gradientColor,
                prefs.gradientDir,
                hA
            )
        end
        if popFrame._powerFill and powerH > 0 then
            local txR, txG, txB
            local isPwrC = prefs.powerPercentPowerColor ~= false
            if isPwrC and prefs.powerClassColored then
                local _, ct = UnitClass("player")
                local cc = CludesUI.GetClassColor(ct)
                txR, txG, txB = cc.r, cc.g, cc.b
            elseif isPwrC then
                local _, pToken = UnitPowerType("player")
                local details = CludesUI.GetPowerColor(pToken or "MANA")
                txR, txG, txB = details.r, details.g, details.b
            else
                local cpf = prefs.customPowerFillColor
                if cpf then
                    txR, txG, txB = cpf.r, cpf.g, cpf.b
                else
                    txR, txG, txB = 0, 0, 1
                end
            end
            popFrame._pR, popFrame._pG, popFrame._pB = txR, txG, txB
            PV_FillColor(
                popFrame._powerFill,
                texPath,
                txR,
                txG,
                txB,
                prefs.powerGradientEnabled,
                prefs.powerGradientColor,
                prefs.powerGradientDir,
                (prefs.powerBarOpacity or 100) / 100
            )
        end
    end

    -- Castbar -- always created for player (toggled in Update); conditional for others
    local castBar, castFill, castNameFS2, castIconFrame
    local shouldCreateCastbar = (unitKey == "player") or (castbarH > 0)
    local castTimeFS, castTargetFS
    if shouldCreateCastbar then
        local initCH = (unitKey == "player") and (castbarH > 0 and castbarH or 14) or castbarH
        -- Cast icon "part of the bar": bar (bg + border + fill) shrinks and the
        -- icon fills the freed space with the outer edge fixed, as on the real
        -- cast bar. Off = icon hangs outside, bar at full width.
        local pvCastIconW = initCH
        -- "Part of the bar" resolves through the module's own rule (the
        -- stock styles force it for a shown icon), so the preview lays
        -- the icon out exactly as live does.
        local pvCastIconInWidth = mod.UF_CastIconInWidth(unitKey, prefs)
        local pvCastIconOnRight, pvCastIconOffX, pvCastIconOffY
        if unitKey == "player" then
            pvCastIconOnRight = prefs.playerCastbarIconRight == true
            pvCastIconOffX = prefs.playerCastIconOffsetX or 0
            pvCastIconOffY = prefs.playerCastIconOffsetY or 0
        else
            pvCastIconOnRight = prefs.castbarIconRight == true
            pvCastIconOffX = prefs.castIconOffsetX or 0
            pvCastIconOffY = prefs.castIconOffsetY or 0
        end
        -- Boss: castbarWidth > 0 overrides the frame-matched width (0 = match).
        -- Clamped here to frameW + 120 so an extreme value can't spill across the
        -- options panel (pf doesn't clip children); real frames use the true width.
        local pvCbBaseW = totalW
        if unitKey == "boss" and (prefs.castbarWidth or 0) > 0 then
            pvCbBaseW = math.min(math.max(prefs.castbarWidth, 30), totalW + 120)
        end
        local pvBarW = pvCastIconInWidth and math.max(1, pvCbBaseW - pvCastIconW) or pvCbBaseW
        castBar = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castBar, pvBarW, initCH)
        local cbAnchor = power or healthBar
        local cbOffset = 0
        if showPortrait and sideName == "right" then
            cbOffset = portraitW / 2
        elseif showPortrait and sideName == "left" then
            cbOffset = -(portraitW / 2)
        end
        castBar._cbAnchor = cbAnchor
        castBar._cbOffset = cbOffset
        -- Icon-in-width shifts the narrowed bar toward the icon-free side by half
        -- the icon width, so the footprint stays where the full bar was.
        Pix.Point(
            castBar,
            "TOP",
            cbAnchor,
            "BOTTOM",
            cbOffset
                + (pvCastIconInWidth and (pvCastIconOnRight and -(pvCastIconW / 2) or (pvCastIconW / 2)) or 0),
            0
        )
        if castbarH > 0 then
            totalH = totalH + castbarH
        end

        -- Background matching real castbar: black 50% alpha
        local cbBg = castBar:CreateTexture(nil, "BACKGROUND")
        cbBg:SetAllPoints(castBar)
        cbBg:SetColorTexture(0, 0, 0, 0.5)
        castBar._previewBgTex = cbBg

        -- Black borders via unified PP system
        Pix.CreateBorder(castBar, 0, 0, 0, 1, 1, "OVERLAY", 0)

        -- Cast fill fills the (possibly shortened) bar.
        castFill = castBar:CreateTexture(nil, "ARTWORK")
        Pix.Point(castFill, "TOPLEFT", castBar, "TOPLEFT", 1, 0)
        Pix.Point(castFill, "BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
        Pix.Width(castFill, math.max(0, pvBarW - 2) * (optionState._previewCastFill or 0.6))
        -- Initial placeholder; real color + bar texture applied in the Update closure.
        castFill:SetColorTexture(0.114, 0.655, 0.514, 1)

        -- Cast spell name and icon -- class spell for player, generic for enemies
        local castSpellName, castSpellIcon
        if unitKey == "player" then
            castSpellName = optionState._previewCastSpell and optionState._previewCastSpell.name
                or "Spell Name"
            castSpellIcon = optionState._previewCastSpell and optionState._previewCastSpell.icon or 136197
        else
            castSpellName = "Spell Name"
            castSpellIcon = 136197 -- Shadow Bolt icon as generic
        end

        -- Text overlay above both castbar border (+1) and main frame border
        local cbTextOvr = CreateFrame("Frame", nil, castBar)
        cbTextOvr:SetAllPoints(castBar)
        cbTextOvr:SetFrameLevel(popFrame:GetFrameLevel() + 11)

        -- Three-zone layout: all zones truncate (no word wrap)
        castNameFS2 = cbTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(castNameFS2, PREVIEW_FONT, 11)
        castNameFS2:SetJustifyH("LEFT")
        castNameFS2:SetWordWrap(false)
        castNameFS2:SetMaxLines(1)
        castNameFS2:SetTextColor(1, 1, 1)
        castNameFS2:SetText(castSpellName)

        castTimeFS = cbTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(castTimeFS, PREVIEW_FONT, 11)
        castTimeFS:SetJustifyH("RIGHT")
        castTimeFS:SetWordWrap(false)
        castTimeFS:SetMaxLines(1)
        castTimeFS:SetTextColor(1, 1, 1)
        local spellCastTime = (optionState._previewCastSpell and optionState._previewCastSpell.castTime)
            or 3.0
        castTimeFS:SetText(string.format("%.1f", spellCastTime * (1 - (optionState._previewCastFill or 0.6))))

        if unitKey ~= "player" then
            castTargetFS = cbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(castTargetFS, PREVIEW_FONT, 10)
            castTargetFS:SetJustifyH("RIGHT")
            castTargetFS:SetWordWrap(false)
            castTargetFS:SetMaxLines(1)
            castTargetFS:SetText(UnitName("player") or "Player")
            local _, ct = UnitClass("player")
            local cc = ct and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ct]
            if cc then
                castTargetFS:SetTextColor(cc.r, cc.g, cc.b)
            else
                castTargetFS:SetTextColor(1, 1, 1)
            end
        end

        -- Initial three-zone positioning
        do
            local barW = castBar:GetWidth() or totalW
            local timerW = 11 * 2.2
            castNameFS2:SetWidth(barW * 0.42)
            castNameFS2:SetPoint("LEFT", castBar, "LEFT", 5, 1)
            castTimeFS:SetWidth(timerW)
            castTimeFS:SetPoint("RIGHT", castBar, "RIGHT", -3, 0)
            if castTargetFS then
                castTargetFS:SetWidth(barW * 0.42)
                castTargetFS:SetPoint("RIGHT", castBar, "RIGHT", -3 - timerW, 0)
            end
        end

        -- Cast spell icon: left of the castbar, right when "Show Icon on Right".
        -- Plain frame + edge textures (not BackdropTemplate) for pixel-perfect rendering.
        local iconSize = initCH
        castIconFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castIconFrame, iconSize, iconSize)
        -- Icon hangs off the bar's chosen edge; with "part of the bar" the bar is
        -- narrower and shifted, so the icon sits inside the footprint.
        if pvCastIconOnRight then
            Pix.Point(castIconFrame, "TOPLEFT", castBar, "TOPRIGHT", pvCastIconOffX, pvCastIconOffY)
        else
            Pix.Point(castIconFrame, "TOPRIGHT", castBar, "TOPLEFT", pvCastIconOffX, pvCastIconOffY)
        end
        local iconBg = castIconFrame:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints()
        iconBg:SetColorTexture(0, 0, 0, 1)
        castIconFrame._bg = iconBg
        -- 1px black border via unified PP system
        Pix.CreateBorder(castIconFrame, 0, 0, 0, 1)
        local castIconTex = castIconFrame:CreateTexture(nil, "ARTWORK")
        Pix.Point(castIconTex, "TOPLEFT", castIconFrame, "TOPLEFT", 1, -1)
        Pix.Point(castIconTex, "BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", -1, 1)
        castIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castIconTex:SetTexture(castSpellIcon)
        castIconFrame._iconTex = castIconTex

        -- Hide initially if player castbar not enabled
        if unitKey == "player" and castbarH <= 0 then
            castBar:Hide()
            castIconFrame:Hide()
        end
    end

    -- Text Bar (preview) -- mirrors real CreateBottomTextBar
    local btbFrame, btbBg, btbLeftFS, btbRightFS, btbCenterFS, btbClassIconTex
    local ApplyBTBPreviewTexts
    do
        local btbH = prefs.bottomTextBarHeight or 16
        local initPos = prefs.btbPosition or "bottom"
        local initIsDetached = (initPos == "detached_top" or initPos == "detached_bottom")
        local initBtbW = initIsDetached and (prefs.btbWidth or 0) or 0
        local initBtbTW = (initBtbW > 0 and initIsDetached) and initBtbW or totalW
        btbFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(btbFrame, initBtbTW, btbH)
        local btbAnchor = (initPpIsAtt and power) and power or healthBar
        local btbXOff = 0
        local initBtbIsAtt = (initPos == "top" or initPos == "bottom")
        if initBtbIsAtt and showPortrait and isAttachedInit then
            if sideName == "right" then
                btbXOff = portraitW / 2
            elseif sideName == "left" then
                btbXOff = -(portraitW / 2)
            end
        end
        if initPos == "top" then
            Pix.Point(btbFrame, "BOTTOM", healthBar, "TOP", btbXOff, 0)
        elseif initPos == "detached_top" then
            btbFrame:SetPoint("BOTTOM", healthBar, "TOP", prefs.btbX or 0, 15 + (prefs.btbY or 0))
        elseif initPos == "detached_bottom" then
            btbFrame:SetPoint("TOP", btbAnchor, "BOTTOM", prefs.btbX or 0, -15 + (prefs.btbY or 0))
        else
            Pix.Point(btbFrame, "TOP", btbAnchor, "BOTTOM", btbXOff, 0)
        end

        local bgc = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
        local bga = prefs.btbBgOpacity or 1.0
        btbBg = btbFrame:CreateTexture(nil, "BACKGROUND")
        btbBg:SetAllPoints()
        btbBg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)

        -- No BTB border of its own: the main frame border encompasses the BTB.

        -- Text overlay (above border at barArea+5)
        local btbTextOvr = CreateFrame("Frame", nil, btbFrame)
        btbTextOvr:SetAllPoints()
        btbTextOvr:SetFrameLevel(barArea:GetFrameLevel() + 10)

        btbLeftFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(btbLeftFS, PREVIEW_FONT, prefs.btbLeftSize or 11)
        btbLeftFS:SetTextColor(1, 1, 1)
        btbLeftFS:SetWordWrap(false)

        btbRightFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(btbRightFS, PREVIEW_FONT, prefs.btbRightSize or 11)
        btbRightFS:SetTextColor(1, 1, 1)
        btbRightFS:SetWordWrap(false)

        btbCenterFS = btbTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(btbCenterFS, PREVIEW_FONT, prefs.btbCenterSize or 11)
        btbCenterFS:SetTextColor(1, 1, 1)
        btbCenterFS:SetWordWrap(false)

        -- Class icon texture on BTB preview on a high-level frame so it renders above the border
        local btbClassIconHolder = CreateFrame("Frame", nil, btbFrame)
        btbClassIconHolder:SetAllPoints(btbTextOvr)
        btbClassIconHolder:SetFrameLevel(barArea:GetFrameLevel() + 12)
        btbClassIconTex = btbClassIconHolder:CreateTexture(nil, "ARTWORK")
        btbClassIconTex:SetTexCoord(0, 1, 0, 1)
        btbClassIconTex:Hide()

        -- Position BTB texts
        ApplyBTBPreviewTexts = function(s)
            local lc = s.btbLeftContent or "none"
            local rc = s.btbRightContent or "none"
            local cc = s.btbCenterContent or "none"
            local lsz = s.btbLeftSize or 11
            local rsz = s.btbRightSize or 11
            local csz = s.btbCenterSize or 11

            SetPVFont(btbLeftFS, PREVIEW_FONT, lsz)
            btbLeftFS:ClearAllPoints()
            if lc ~= "none" then
                btbLeftFS:SetJustifyH("LEFT")
                Pix.Point(btbLeftFS, "LEFT", btbTextOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
                btbLeftFS:SetText(PreviewTextForContent(lc, s, "btbLeft"))
                btbLeftFS:Show()
                PreviewClassColor(
                    btbLeftFS,
                    s.btbLeftClassColor,
                    s.btbLeftColorR,
                    s.btbLeftColorG,
                    s.btbLeftColorB
                )
                PreviewPowerColor(btbLeftFS, lc, s.btbLeftPowerColor, s.btbLeftCustomFormat)
            else
                btbLeftFS:Hide()
            end

            SetPVFont(btbRightFS, PREVIEW_FONT, rsz)
            btbRightFS:ClearAllPoints()
            if rc ~= "none" then
                btbRightFS:SetJustifyH("RIGHT")
                Pix.Point(btbRightFS, "RIGHT", btbTextOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
                btbRightFS:SetText(PreviewTextForContent(rc, s, "btbRight"))
                btbRightFS:Show()
                PreviewClassColor(
                    btbRightFS,
                    s.btbRightClassColor,
                    s.btbRightColorR,
                    s.btbRightColorG,
                    s.btbRightColorB
                )
                PreviewPowerColor(btbRightFS, rc, s.btbRightPowerColor, s.btbRightCustomFormat)
            else
                btbRightFS:Hide()
            end

            SetPVFont(btbCenterFS, PREVIEW_FONT, csz)
            btbCenterFS:ClearAllPoints()
            if cc ~= "none" then
                btbCenterFS:SetJustifyH("CENTER")
                Pix.Point(btbCenterFS, "CENTER", btbTextOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
                btbCenterFS:SetText(PreviewTextForContent(cc, s, "btbCenter"))
                btbCenterFS:Show()
                PreviewClassColor(
                    btbCenterFS,
                    s.btbCenterClassColor,
                    s.btbCenterColorR,
                    s.btbCenterColorG,
                    s.btbCenterColorB
                )
                PreviewPowerColor(btbCenterFS, cc, s.btbCenterPowerColor, s.btbCenterCustomFormat)
            else
                btbCenterFS:Hide()
            end

            -- Class icon in BTB preview
            local ciStyle = s.btbClassIcon or "none"
            if ciStyle ~= "none" then
                local _, classToken = UnitClass("player")
                if classToken and ApplyClassIconTexture_Preview(btbClassIconTex, classToken, ciStyle) then
                    local ciSz = s.btbClassIconSize or 14
                    Pix.Size(btbClassIconTex, ciSz, ciSz)
                    btbClassIconTex:ClearAllPoints()
                    local ciLoc = s.btbClassIconLocation or "left"
                    local ciOx = s.btbClassIconX or 0
                    local ciOy = s.btbClassIconY or 0
                    if ciLoc == "center" then
                        Pix.Point(btbClassIconTex, "CENTER", btbTextOvr, "CENTER", ciOx, ciOy)
                    elseif ciLoc == "right" then
                        Pix.Point(btbClassIconTex, "RIGHT", btbTextOvr, "RIGHT", -3 + ciOx, ciOy)
                    else
                        Pix.Point(btbClassIconTex, "LEFT", btbTextOvr, "LEFT", 3 + ciOx, ciOy)
                    end
                    btbClassIconTex:Show()
                    if popFrame._btbClassIconOv then
                        popFrame._btbClassIconOv:Show()
                    end
                else
                    btbClassIconTex:Hide()
                    if popFrame._btbClassIconOv then
                        popFrame._btbClassIconOv:Hide()
                    end
                end
            else
                btbClassIconTex:Hide()
                if popFrame._btbClassIconOv then
                    popFrame._btbClassIconOv:Hide()
                end
            end
        end
        ApplyBTBPreviewTexts(prefs)

        local initBtbPos = prefs.btbPosition or "bottom"
        local initBtbIsAtt = (initBtbPos == "top" or initBtbPos == "bottom")
        if not prefs.bottomTextBar then
            btbFrame:Hide()
        else
            if initBtbIsAtt then
                totalH = totalH + btbH
            end
        end
    end

    -- Class Power Pips (player only preview) -- matches nameplate pip style
    local cpPipContainer, cpPips
    if unitKey == "player" then
        local CLASS_POWER_MAP = {
            ROGUE = { 5 },
            DRUID = { [103] = 5, [104] = 5, [105] = 5 },
            PALADIN = { 5 },
            MONK = { 5 },
            WARLOCK = { 5 },
            MAGE = { 4 },
            EVOKER = { 5 },
            DEATHKNIGHT = { 6 },
            DEMONHUNTER = { [581] = 6, [1480] = 5 },
            SHAMAN = { [263] = 10 },
            HUNTER = { [255] = 3 },
            WARRIOR = { [72] = 4 },
        }
        local _, playerClass = UnitClass("player")
        local cpInfo = CLASS_POWER_MAP[playerClass]
        local cpMax = 0
        if cpInfo then
            if cpInfo[1] then
                cpMax = cpInfo[1]
            else
                local specInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
                local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
                cpMax = specID and cpInfo[specID] or 0
            end
        end
        -- Resolve fill color from global system
        local cpColor = { 1.00, 0.84, 0.30 }
        if CludesUI.GetResourceColor then
            local rc = CludesUI.GetResourceColor(playerClass)
            if rc then
                cpColor = { rc.r, rc.g, rc.b }
            end
        elseif CludesUI.GetClassColor then
            local cc = CludesUI.GetClassColor(playerClass)
            if cc then
                cpColor = { cc.r, cc.g, cc.b }
            end
        end

        if cpMax > 0 then
            cpPipContainer = CreateFrame("Frame", nil, popFrame)
            cpPipContainer:SetFrameLevel(popFrame:GetFrameLevel() + 4)
            -- Background texture behind all pips
            local cpBgTex = cpPipContainer:CreateTexture(nil, "BACKGROUND")
            cpBgTex:SetAllPoints()
            local initBg = prefs.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
            cpBgTex:SetColorTexture(initBg.r, initBg.g, initBg.b, initBg.a)
            cpPipContainer._bgTex = cpBgTex
            cpPips = {}
            for idx = 1, cpMax do
                local pipTex = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 3)
                pipTex:SetColorTexture(1, 1, 1, 1)
                Pix.Size(pipTex, 8, 3)
                cpPips[idx] = pipTex
            end
            -- Color pips: first 3 filled, rest empty (preview)
            local previewFilled = math.min(3, cpMax)
            for idx = 1, cpMax do
                if idx <= previewFilled then
                    cpPips[idx]:SetColorTexture(cpColor[1], cpColor[2], cpColor[3], 1)
                end
            end
            cpPipContainer:Hide() -- shown in Update() if style ~= "none"

            -- 1px inset bottom border for "above" (frame border color); sublevel 7 so
            -- it renders over the pip fills (sublevel 3).
            local cpBottomBdr = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 7)
            cpBottomBdr:SetHeight(1)
            Pix.Point(cpBottomBdr, "BOTTOMLEFT", cpPipContainer, "BOTTOMLEFT", 0, 0)
            Pix.Point(cpBottomBdr, "BOTTOMRIGHT", cpPipContainer, "BOTTOMRIGHT", 0, 0)
            local initBdrC = prefs.borderColor or { r = 0, g = 0, b = 0 }
            cpBottomBdr:SetColorTexture(initBdrC.r, initBdrC.g, initBdrC.b, 1)
            cpBottomBdr:Hide() -- shown only when position is "above"
            cpPipContainer._bottomBdr = cpBottomBdr
        end -- cpMax > 0
    end

    -- Border: plain frame child of barArea with 4 edge textures, PixelUtil sized.
    -- Never BackdropTemplate -- its edgeSize clipping drops sides on small frames
    -- and its internal snapping can't be disabled.
    local bdrSize = prefs.borderSize or 1
    local bdrColor = prefs.borderColor or { r = 0, g = 0, b = 0 }
    local bdrTexKey = prefs.borderTexture or "solid"
    local border = CreateFrame("Frame", nil, popFrame)
    border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
    border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
    local initBdrBtbPos = prefs.btbPosition or "bottom"
    local initBdrBtbAtt = (initBdrBtbPos == "top" or initBdrBtbPos == "bottom")
    border:SetHeight(
        prefs.healthHeight
            + initPpExtra
            + (prefs.bottomTextBar and initBdrBtbAtt and (prefs.bottomTextBarHeight or 16) or 0)
    )
    border:SetFrameLevel(barArea:GetFrameLevel() + 5)
    CludesUI.ApplyBorderStyle(
        border,
        bdrSize,
        bdrColor.r,
        bdrColor.g,
        bdrColor.b,
        prefs.borderAlpha or 1,
        bdrTexKey,
        prefs.borderTextureOffset,
        prefs.borderTextureOffsetY,
        prefs.borderTextureShiftX,
        prefs.borderTextureShiftY,
        "unitframes",
        bdrSize,
        nil,
        CludesUI.BorderPx(prefs.borderSizePx, bdrSize, bdrTexKey)
    )
    if bdrSize == 0 and bdrTexKey == "solid" then
        border:Hide()
    end

    -- Position an absorb StatusBar per edge mode (mirrors UpdateAbsorbBarReverseFill
    -- in CUI_UnitFrames_Absorb.lua): overlay = fills missing-health from the
    -- current-HP edge (backfills over filled health only for overshields);
    -- right/left = pinned to that edge, fills toward center, ignoring reverse fill.
    local function PositionPreviewAbsorb(barFrame, modeName, isRev, isVert)
        if not barFrame then
            return
        end
        barFrame:ClearAllPoints()
        barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        mod.ApplyFillRotation(barFrame)
        if isVert then
            -- Vertical fill: same rules, axis swapped. Key names persist --
            -- "right" = far edge of the fill axis (top), "left" = near (bottom).
            if modeName == "right" then
                barFrame:SetReverseFill(true)
                barFrame:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                barFrame:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            elseif modeName == "left" then
                barFrame:SetReverseFill(false)
                barFrame:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                barFrame:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            elseif modeName == "overlayReverse" or modeName == "overlayReverseFull" then
                -- Overlay Reverse: shield fills INTO the health fill from
                -- its leading edge; the preview clip masks excess. The
                -- preview shield never exceeds health, so Full matches.
                if isRev then
                    barFrame:SetReverseFill(false)
                    barFrame:SetPoint("BOTTOMLEFT", healthFill, "BOTTOMLEFT", 0, 0)
                    barFrame:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
                else
                    barFrame:SetReverseFill(true)
                    barFrame:SetPoint("TOPLEFT", healthFill, "TOPLEFT", 0, 0)
                    barFrame:SetPoint("TOPRIGHT", healthFill, "TOPRIGHT", 0, 0)
                end
            elseif isRev then
                -- Reverse: missing health is BELOW, shield grows down from the health fill's bottom.
                barFrame:SetReverseFill(true)
                barFrame:SetPoint("TOPLEFT", healthFill, "BOTTOMLEFT", 0, 0)
                barFrame:SetPoint("TOPRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
            else
                -- Normal: missing health is ABOVE, shield grows up from the health fill's top.
                barFrame:SetReverseFill(false)
                barFrame:SetPoint("BOTTOMLEFT", healthFill, "TOPLEFT", 0, 0)
                barFrame:SetPoint("BOTTOMRIGHT", healthFill, "TOPRIGHT", 0, 0)
            end
            return
        end
        if modeName == "right" then
            barFrame:SetReverseFill(true)
            barFrame:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            barFrame:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        elseif modeName == "left" then
            barFrame:SetReverseFill(false)
            barFrame:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            barFrame:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        elseif modeName == "overlayReverse" or modeName == "overlayReverseFull" then
            -- Overlay Reverse: shield fills INTO the health fill from its
            -- leading edge; the preview clip masks excess. The preview
            -- shield never exceeds health, so Full matches.
            if isRev then
                barFrame:SetReverseFill(false)
                barFrame:SetPoint("TOPLEFT", healthFill, "TOPLEFT", 0, 0)
                barFrame:SetPoint("BOTTOMLEFT", healthFill, "BOTTOMLEFT", 0, 0)
            else
                barFrame:SetReverseFill(true)
                barFrame:SetPoint("TOPRIGHT", healthFill, "TOPRIGHT", 0, 0)
                barFrame:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMRIGHT", 0, 0)
            end
        elseif isRev then
            -- Reverse: missing health is on the LEFT, shield grows left from the health fill's left.
            barFrame:SetReverseFill(true)
            barFrame:SetPoint("TOPRIGHT", healthFill, "TOPLEFT", 0, 0)
            barFrame:SetPoint("BOTTOMRIGHT", healthFill, "BOTTOMLEFT", 0, 0)
        else
            -- Normal: missing health is on the RIGHT, shield grows right from the health fill's right.
            barFrame:SetReverseFill(false)
            barFrame:SetPoint("TOPLEFT", healthFill, "TOPRIGHT", 0, 0)
            barFrame:SetPoint("BOTTOMLEFT", healthFill, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Absorb bars (style-aware preview for player, target, focus):
    --   absorbBar     = shield (damage) absorb, white/shield, drawn below
    --   healAbsorbBar = heal absorb, red, one sublevel above; shown only while
    --                   the Heal Absorb Style eyeball is on
    local absorbBar, healAbsorbBar, absorbTopBar, healAbsorbTopBar
    if unitKey == "player" or unitKey == "target" or unitKey == "focus" then
        local PREV_ABS_TEX = {
            striped = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga",
            stripedReversed = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-5-reversed.png",
            clean = "Interface\\Buttons\\WHITE8X8",
            blizzard = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\blizzard.tga",
            largeOutlinedStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-left.png",
            largeOutlinedStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-right.png",
            largeStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-left.png",
            largeStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-right.png",
        }
        -- Clip container: absorb fills anchor off the health fill's current-HP
        -- edge at full frame width, so a high preview fill overruns the bar.
        -- Real frames clamp; mirror that by clipping to the health bar's rect.
        local absClip = CreateFrame("Frame", nil, healthBar)
        absClip:SetAllPoints(healthBar)
        absClip:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        absClip:SetClipsChildren(true)

        -- Shield (damage) absorb
        local absStyle = prefs.showPlayerAbsorb
        local PREV_ABS_ALPHA = {
            striped = 0.8,
            stripedReversed = 0.8,
            clean = (prefs.absorbCleanAlpha or 30) / 100,
            blizzard = 0.8,
        }
        -- SharedMedia keys fall through to the health-bar texture lookup.
        local texture = mod.ResolveAbsorbStyleTex(absStyle, PREV_ABS_TEX.striped)
        -- Effective opacity/color: mirrors GetAbsorbOpacity in CUI_UnitFrames_Absorb.lua
        local alpha = prefs.absorbOpacity and (prefs.absorbOpacity / 100) or PREV_ABS_ALPHA[absStyle] or 0.8
        local ac = prefs.absorbColor or { r = 1, g = 1, b = 1 }
        absorbBar = CreateFrame("StatusBar", nil, absClip)
        absorbBar:SetStatusBarTexture(texture)
        local absFillTex = absorbBar:GetStatusBarTexture()
        if absFillTex then
            absFillTex:SetDrawLayer("ARTWORK", 1)
            local absTiled = (mod.ABSORB_TILED_STYLES[absStyle] == true)
            absFillTex:SetHorizTile(absTiled)
            absFillTex:SetVertTile(absTiled)
        end
        absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
        PositionPreviewAbsorb(
            absorbBar,
            prefs.absorbEdgeMode or "overlay",
            prefs.healthReverseFill,
            prefs.healthVerticalFill
        )
        Pix.Width(absorbBar, frameW)
        Pix.Height(absorbBar, healthH)
        absorbBar:SetMinMaxValues(0, 1)
        absorbBar:SetValue(0.14)
        absorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        if not absStyle or absStyle == "none" then
            absorbBar:Hide()
        end

        -- Heal absorb (red, one sublevel above the shield absorb); on the preview
        -- the two are mutually exclusive -- visible only while the eyeball is on,
        -- which hides absorbBar.
        local haStyle = prefs.healAbsorbStyle or "clean"
        local haTex = mod.ResolveAbsorbStyleTex(haStyle, "Interface\\Buttons\\WHITE8X8")
        local haAlpha = (prefs.healAbsorbOpacity or 65) / 100
        local hc = prefs.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
        if haStyle == "largeOutlinedStripes" or haStyle == "largeOutlinedStripesR" then
            hc = { r = 1, g = 1, b = 1 }
        end
        healAbsorbBar = CreateFrame("StatusBar", nil, absClip)
        healAbsorbBar:SetStatusBarTexture(haTex)
        local haFillTex = healAbsorbBar:GetStatusBarTexture()
        if haFillTex then
            haFillTex:SetDrawLayer("ARTWORK", 2)
            local haTiled = (mod.ABSORB_TILED_STYLES[haStyle] == true)
            haFillTex:SetHorizTile(haTiled)
            haFillTex:SetVertTile(haTiled)
        end
        healAbsorbBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, haAlpha)
        PositionPreviewAbsorb(
            healAbsorbBar,
            prefs.healAbsorbEdgeMode or "overlay",
            prefs.healthReverseFill,
            prefs.healthVerticalFill
        )
        Pix.Width(healAbsorbBar, frameW)
        Pix.Height(healAbsorbBar, healthH)
        healAbsorbBar:SetMinMaxValues(0, 1)
        healAbsorbBar:SetValue(0.14)
        healAbsorbBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        healAbsorbBar:Hide()
        -- Black backing under the heal-absorb fill (healAbsorbBgOpacity), one
        -- sublevel below it and tracking its rect.
        local haBgPv = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
        haBgPv:SetColorTexture(0, 0, 0, (prefs.healAbsorbBgOpacity or 15) / 100)
        haBgPv:SetAllPoints(healAbsorbBar:GetStatusBarTexture())
        healAbsorbBar._bg = haBgPv

        -- Max Health Style preview (its eyeball): a fixed reduced maximum on the
        -- bar's far end, styled by the live frames' function. Driven in pf:Update.
        popFrame._pvMaxHp = CreateFrame("StatusBar", nil, healthBar)
        popFrame._pvMaxHp:SetAllPoints(healthBar)
        popFrame._pvMaxHp:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        popFrame._pvMaxHp:SetMinMaxValues(0, 1)
        popFrame._pvMaxHp:SetValue(0.2)
        popFrame._pvMaxHp._bg = popFrame._pvMaxHp:CreateTexture(nil, "ARTWORK", nil, 2)
        popFrame._pvMaxHp:Hide()

        -- Heal prediction preview (Heal Prediction eyeball): others' heals at the
        -- full incoming total underneath, yours on top, from the HP edge. The
        -- holder clips at the bar's end unless Overheal lets them run past it.
        -- Fields on pf, not locals: this builder is long. Driven in pf:Update.
        popFrame._pvPredHolder = CreateFrame("Frame", nil, healthBar)
        popFrame._pvPredHolder:SetAllPoints(healthBar)
        popFrame._pvPredHolder:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        for idx, key in ipairs({ "_pvPredOther", "_pvPredMy" }) do
            local barFrame = CreateFrame("StatusBar", nil, popFrame._pvPredHolder)
            barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            barFrame:SetMinMaxValues(0, 1)
            barFrame:SetFrameLevel(healthBar:GetFrameLevel() + idx)
            barFrame:Hide()
            popFrame[key] = barFrame
        end

        -- Absorb / Heal Absorb preview strips, parented to the frame so "above"
        -- positions sit outside the health bar. Driven below.
        absorbTopBar = CreateFrame("StatusBar", nil, popFrame)
        absorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        absorbTopBar:SetMinMaxValues(0, 1)
        absorbTopBar:SetValue(0.45)
        absorbTopBar:Hide()
        healAbsorbTopBar = CreateFrame("StatusBar", nil, popFrame)
        healAbsorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        healAbsorbTopBar:SetMinMaxValues(0, 1)
        healAbsorbTopBar:SetValue(0.45)
        healAbsorbTopBar:Hide()
    end
    popFrame._absorbBar = absorbBar
    popFrame._healAbsorbBar = healAbsorbBar
    popFrame._absorbTopBar = absorbTopBar
    popFrame._healAbsorbTopBar = healAbsorbTopBar

    -- Fake buff icons (all units, shown when showBuffs is on and anchor is not "none")
    local buffIcons = {}
    do
        local buffSize = prefs.buffSize or 22
        local buffGap = 1
        for idx = 1, 2 do
            local bf = CreateFrame("Frame", nil, popFrame, "BackdropTemplate")
            Pix.Size(bf, buffSize, buffSize)
            bf:SetBackdrop(SOLID_BACKDROP)
            bf:SetBackdropColor(0, 0, 0, 1)
            -- Clear the border frame (barArea+5) and its solid PP border
            -- sub-container (barArea+6) so the icons render above both.
            bf:SetFrameLevel(barArea:GetFrameLevel() + 7)
            Pix.Point(bf, "BOTTOMLEFT", popFrame, "TOPLEFT", (idx - 1) * (buffSize + buffGap), buffGap)
            local texture = bf:CreateTexture(nil, "ARTWORK")
            Pix.Point(texture, "TOPLEFT", bf, "TOPLEFT", 1, -1)
            Pix.Point(texture, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
            texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            texture:SetTexture(_previewBuffIcons[idx] or 135932)
            bf._iconTex = texture
            buffIcons[idx] = bf
            local showB = prefs.showBuffs and (prefs.buffAnchor or "topleft") ~= "none"
            if not showB then
                bf:Hide()
            end
        end
    end

    -- Fake debuff icons (all units, shown when debuffAnchor is not "none")
    local debuffIcons = {}
    do
        local debuffSize = prefs.debuffSize or 22
        local debuffGap = 1
        local previewDebuffIcons = {
            136116,
            132099,
            136182,
            136214,
            132155,
            136201,
            136148,
            136175,
            136130,
            136160,
            136195,
            136133,
            136222,
            136168,
            136205,
            136186,
            136124,
            136151,
            136210,
            136143,
        }
        for idx = 1, 20 do
            local df = CreateFrame("Frame", nil, popFrame, "BackdropTemplate")
            Pix.Size(df, debuffSize, debuffSize)
            df:SetBackdrop(SOLID_BACKDROP)
            -- Black 1px edge (backdrop showing through the icon's 1px inset),
            -- matching the buff icons and the live frames' black border.
            df:SetBackdropColor(0, 0, 0, 1)
            -- Clear the border frame (barArea+5) and its PP border container
            -- (barArea+6); df's cd (+1) and text host (+2) ride up with it.
            df:SetFrameLevel(barArea:GetFrameLevel() + 7)
            Pix.Point(df, "TOPLEFT", popFrame, "BOTTOMLEFT", (idx - 1) * (debuffSize + debuffGap), -debuffGap)
            local texture = df:CreateTexture(nil, "ARTWORK")
            Pix.Point(texture, "TOPLEFT", df, "TOPLEFT", 1, -1)
            Pix.Point(texture, "BOTTOMRIGHT", df, "BOTTOMRIGHT", -1, 1)
            texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            texture:SetTexture(previewDebuffIcons[idx] or 136116)
            df._iconTex = texture
            -- Static fake cooldown swipe (huge duration parked at a fixed fraction
            -- so the wedge never moves) plus static duration/stack text. Shown only
            -- on the boss preview in pf:Update, sized per the boss aura settings.
            local cd = CreateFrame("Cooldown", nil, df, "CooldownFrameTemplate")
            cd:SetPoint("TOPLEFT", df, "TOPLEFT", 1, -1)
            cd:SetPoint("BOTTOMRIGHT", df, "BOTTOMRIGHT", -1, 1)
            cd:SetFrameLevel(df:GetFrameLevel() + 1)
            cd:SetDrawEdge(false)
            cd:SetDrawBling(false)
            cd:SetReverse(false)
            cd:SetDrawSwipe(true)
            cd:SetSwipeColor(0, 0, 0, 0.6)
            cd:SetHideCountdownNumbers(true)
            local frac = 0.25 + (((idx - 1) % 5) * 0.15)
            cd:SetCooldown(GetTime() - 3600 * (1 - frac), 3600)
            cd:Hide()
            df._previewCD = cd
            local textHost = CreateFrame("Frame", nil, df)
            textHost:SetAllPoints(df)
            textHost:SetFrameLevel(cd:GetFrameLevel() + 1)
            local pvFontP = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
            local durText = textHost:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(durText, pvFontP, 10, "unitFrames")
            durText:SetPoint("CENTER", df, "CENTER", 0, 0)
            durText:SetText(4 + ((idx - 1) % 5) * 5)
            durText:Hide()
            df._durText = durText
            local stackText = textHost:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(stackText, pvFontP, 14, "unitFrames")
            stackText:SetText(2 + ((idx - 1) % 5))
            stackText:Hide()
            df._stackText = stackText
            debuffIcons[idx] = df
            if noDebuffPreview or (prefs.debuffAnchor or "bottomleft") == "none" then
                df:Hide()
            end
        end
    end

    -- Disabled overlay: parented to UIParent (pf's strata would clamp it) so it
    -- renders above ALL other child frames. Owned by pf: the next dress of the
    -- same preview frame gets the same overlay back (hidden at pf's reset).
    local disabledOverlay = PoolOwned(popFrame, "disabled", "Frame", UIParent, "BackdropTemplate")
    disabledOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    disabledOverlay:SetBackdrop(SOLID_BACKDROP)
    disabledOverlay:SetBackdropColor(0, 0, 0, 0.6)
    disabledOverlay:Hide()
    local disabledText = disabledOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(disabledText, PREVIEW_FONT, 11)
    disabledText:SetTextColor(1, 1, 1)
    disabledText:SetText(CludesUI.L("Disabled"))
    -- Position overlay and text relative to pf/health (updated in Update and on show)
    local function SyncDisabledOverlay()
        disabledOverlay:ClearAllPoints()
        disabledOverlay:SetScale(popFrame:GetScale())
        disabledOverlay:SetPoint("TOPLEFT", popFrame, "TOPLEFT", 0, 0)
        disabledOverlay:SetPoint("BOTTOMRIGHT", popFrame, "BOTTOMRIGHT", 0, 0)
        disabledText:ClearAllPoints()
        disabledText:SetPoint("CENTER", disabledOverlay, "CENTER", 0, 0)
    end
    SyncDisabledOverlay()

    -- Auto-hide the UIParent-parented overlay when the preview hides (tab switch,
    -- module switch, page cache stash, the panel folding to its mini window).
    popFrame:HookScript("OnHide", function()
        disabledOverlay:Hide()
    end)
    -- And bring it back when the preview re-shows without an Update (the panel
    -- unfolding from its mini window runs no OnShow callback).
    popFrame:HookScript("OnShow", function()
        local uk = unitKey:match("^boss") and "boss" or unitKey
        if mod.GetUnitFrameSource(uk) ~= "cui" then
            SyncDisabledOverlay()
            disabledOverlay:Show()
        end
    end)

    -- Combat indicator preview texture (highest frame level)
    local COMBAT_MEDIA_P = "Interface\\AddOns\\CludesUI\\media\\combat\\"
    local combatIndHolder = CreateFrame("Frame", nil, popFrame)
    combatIndHolder:SetAllPoints(popFrame)
    combatIndHolder:SetFrameLevel(popFrame:GetFrameLevel() + 20)
    local combatInd = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 7)
    combatInd:SetSize(24, 24)
    combatInd:SetPoint("CENTER", portraitFrame or healthBar, "CENTER", 0, 0)
    combatInd:Hide()
    popFrame._combatIndicator = combatInd
    -- Faction indicator preview (player + target), on the same raised holder
    local factionInd = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 6)
    factionInd:Hide()
    popFrame._factionIndicator = factionInd
    -- Raid marker / leader / elite previews, each behind its row's eye toggle
    -- (pf fields, not locals: this builder is long).
    popFrame._pvRaid = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 6)
    popFrame._pvRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    popFrame._pvRaid:Hide()
    popFrame._pvLeader = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 6)
    popFrame._pvLeader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    popFrame._pvLeader:Hide()
    popFrame._pvElite = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, 6)
    popFrame._pvElite:SetAtlas("nameplates-icon-elite-gold")
    popFrame._pvElite:Hide()
    -- WoW Forever: the pet's happiness icon (the happy face as the sample),
    -- placed each Update beside the frame as the live icon is. It sits on
    -- its own frame so the page's click overlay shows and hides with it.
    if unitKey == "pet" and CludesUI.IS_FOREVER == true then
        local happyInd = CreateFrame("Frame", nil, popFrame)
        happyInd:SetFrameLevel(popFrame:GetFrameLevel() + 20)
        local happyTex = happyInd:CreateTexture(nil, "OVERLAY")
        happyTex:SetAllPoints()
        happyTex:SetAtlas("UI-PetHappiness")
        happyInd:Hide()
        popFrame._happyInd = happyInd
    end
    popFrame:SetSize(totalW, totalH)

    -- Blizzard Style: the stock look laid over the built mock at the end of
    -- every Update, the way the live layout pass lays it over the built
    -- frame -- same geometry table, art painter, masks and bar shadow from
    -- the module, so it overrides the CUI-look pass instead of forking it.
    -- Nothing here runs while the style is off. Draw order (levels above
    -- pf, nothing goes under it): portrait +1 < art +2 < bars +3 < absorb
    -- pieces +4; text, class power and icons sit higher already. The cast
    -- bar keeps its CUI placement below the frame and takes the stock chrome.
    local function ApplyBlizzPreview(s, G, mirror, extras, ch, drop)
        local lvl = popFrame:GetFrameLevel()
        local pct = optionState._previewHealthPct or 0.70
        local ppct = optionState._previewPowerPct or 0.85
        local isMini = G.small and true or false
        -- Hide Power Bar: a main frame's health bar takes the power track too,
        -- as live (with the cut art where the art draws over the bars).
        local merged = not isMini
            and G.power ~= nil
            and mod.UF_IsMainSettings(s)
            and mod.UF_StockHidesPower(s)
        local HB = merged and mod.UF_MergedHealth(G) or G.health
        barArea._blizzMerged = merged or nil
        barArea._blizzMergeCut = (merged and G.merge) or nil

        -- Art box: the stock box, hung so its transparent top rows sit above
        -- pf (pf spans only the visible art, plus the cast bar strip below).
        local padTop = G.pad and G.pad.top or 0
        local padBottom = G.pad and G.pad.bottom or 0
        barArea:ClearAllPoints()
        barArea:SetPoint("TOPLEFT", popFrame, "TOPLEFT", 0, padTop)
        barArea:SetSize(G.w, G.h)

        -- Art: one texture on its own child frame, centred on the art box
        -- (the module painter reads the mirror stamp and the texture host
        -- off the box frame it is handed).
        local af = popFrame._blizzArtFrame
        if not af then
            af = CreateFrame("Frame", nil, popFrame)
            af:SetAllPoints(barArea)
            af:EnableMouse(false)
            popFrame._blizzArtFrame = af
        end
        -- Art over or under the bars as the kit layers it (the classic
        -- target and pet arts draw over their transparent bar windows).
        af:SetFrameLevel(G.artAbove and (lvl + 5) or (lvl + 2))
        barArea._blizzArtFrame = af
        barArea._blizzMirror = mirror
        -- The boss preview wears the classic kit's whole-frame boss art.
        local artEntry = (extras and unitKey == "boss" and G.artByClass and G.artByClass.boss) or G.art
        -- Hide Power Bar repaints it too: the stock atlas art's cut has no kit spec.
        local cut, mergedArt = barArea._blizzMergeCut, merged or nil
        if
            af._artAtlas ~= artEntry
            or af._artMirror ~= mirror
            or af._artCutSpec ~= cut
            or af._artMerged ~= mergedArt
        then
            af._artAtlas, af._artMirror, af._artCutSpec, af._artMerged = artEntry, mirror, cut, mergedArt
            mod.UF_PaintBlizzArt(barArea, artEntry)
        end
        -- The dark plaque behind the name and bars (classic kit), under the art.
        if G.back then
            local bk = popFrame._blizzBack
            if not bk then
                bk = barArea:CreateTexture(nil, "BACKGROUND", nil, -2)
                bk:SetColorTexture(0, 0, 0, 0.5)
                popFrame._blizzBack = bk
            end
            bk:ClearAllPoints()
            mod.UF_BlizzPoint(bk, "TOPLEFT", barArea, "TOPLEFT", G.back.x, -G.back.y, mirror)
            bk:SetSize(G.back.w, G.back.h)
            bk:Show()
        elseif popFrame._blizzBack then
            popFrame._blizzBack:Hide()
        end
        -- Type strip (the preview's target is hostile: the stock strip over
        -- the art, or the classic name plaque under it) and the boss dragon.
        local repArt = extras and G.rep and (G.rep.art or G.rep.atlas)
        if repArt and mod.UF_ArtOK(repArt) and mod.UF_BlizzHeaderOn(s) then
            local rep = af._rep
            if not rep then
                rep = af:CreateTexture(nil, "BACKGROUND", nil, 1)
                af._rep = rep
            end
            mod.UF_SetArt(rep, repArt, true)
            rep:SetDrawLayer("BACKGROUND", G.rep.below and -1 or 1)
            rep:ClearAllPoints()
            local rp = G.rep.point or "TOPRIGHT"
            rep:SetPoint(rp, barArea, rp, G.rep.x, G.rep.y)
            rep:SetVertexColor(1, 0, 0)
            rep:Show()
        elseif af._rep then
            af._rep:Hide()
        end
        local dragon = extras and unitKey == "boss" and G.boss and G.boss.winged
        if dragon and mod.UF_AtlasOK(dragon) then
            local d = af._dragon
            if not d then
                d = af:CreateTexture(nil, "BACKGROUND", nil, 2)
                af._dragon = d
            end
            mod.UF_StockAtlas(d, dragon, true)
            d:ClearAllPoints()
            -- The kit's own spot where it has one (WoW Forever).
            local dp = G.boss.pos and G.boss.pos.winged
            d:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", dp and dp[1] or 8, dp and dp[2] or -8)
            d:Show()
        elseif af._dragon then
            af._dragon:Hide()
        end
        -- Level number in the art's level circle (the player's own level
        -- as the sample), honouring Show Level and the level's own size
        -- and offsets. The string exists whenever the art has a circle
        -- (hidden while off), so its click overlay is built once with the
        -- page and follows the toggle.
        local Lv = G.level
        local lf = af._level
        if Lv and not lf then
            lf = af:CreateFontString(nil, "OVERLAY")
            lf:SetFontObject(GameNormalNumberFont)
            af._level = lf
            popFrame._levelFS = lf
        end
        -- WoW Forever: the round level badge behind the number.
        local B = G.badge
        local lb = af._levelBadge
        if B and not lb then
            lb = af:CreateTexture(nil, "OVERLAY", nil, -1)
            mod.UF_SetArt(lb, B.atlas)
            af._levelBadge = lb
        end
        local lvOn = Lv and s.blizzShowLevel ~= false
        if lb then
            lb:SetShown((lvOn and B) and true or false)
        end
        if lvOn then
            -- The name's font object (shadow) and face, as live: a name on a
            -- font family gives its roman member's face. (A plain call:
            -- `nf and nf:GetFont()` would keep only the face.)
            local nf = popFrame._nameFS
            if nf then
                local fo = nf:GetFontObject()
                local source = (fo and CludesUI._fontFamilySet[fo] and fo:GetFontObjectForAlphabet("roman"))
                    or nf
                local face, dim, flags = source:GetFont()
                if face then
                    if fo then
                        lf:SetFontObject(fo)
                    end
                    lf:SetFont(face, s.blizzLevelSize or dim, flags)
                end
            end
            lf:ClearAllPoints()
            lf:SetJustifyH(Lv.justify or "CENTER")
            -- The badge takes the level's offsets and the number centres on it.
            local rel, lx, ly = barArea, s.blizzLevelX or 0, s.blizzLevelY or 0
            if B then
                lb:SetSize(B.size, B.size)
                lb:ClearAllPoints()
                mod.UF_BlizzPoint(lb, B.point, barArea, B.point, B.x + lx, B.y + ly, mirror)
                rel, lx, ly = lb, 0, 0
            end
            mod.UF_BlizzPoint(lf, Lv.point, rel, Lv.relPoint or Lv.point, Lv.x + lx, Lv.y + ly, mirror)
            -- WoW Forever paints the player's own level white.
            if B and unitKey == "player" then
                lf:SetTextColor(1, 1, 1)
            else
                lf:SetTextColor(1, 0.82, 0)
            end
            lf:SetText(UnitLevel("player"))
            lf:Show()
        elseif lf then
            lf:Hide()
        end
        if popFrame._levelOv then
            popFrame._levelOv:SetShown(lvOn and true or false)
        end

        -- Health bar at the stock spot; horizontal fill (the stock track has
        -- no vertical variant); colours, texture, gradient, opacity as set.
        healthBar:ClearAllPoints()
        mod.UF_BlizzPoint(healthBar, "TOPLEFT", barArea, "TOPLEFT", HB.x, -HB.y, mirror)
        healthBar:SetSize(HB.w, HB.h)
        healthBar:SetFrameLevel(lvl + 3)
        local absClip = absorbBar and absorbBar:GetParent()
        if absClip and absClip ~= healthBar then
            absClip:SetFrameLevel(lvl + 4)
        end
        if absorbBar then
            absorbBar:SetFrameLevel(lvl + 4)
        end
        if healAbsorbBar then
            healAbsorbBar:SetFrameLevel(lvl + 4)
        end
        if absorbTopBar then
            absorbTopBar:SetFrameLevel(lvl + 4)
        end
        if healAbsorbTopBar then
            healAbsorbTopBar:SetFrameLevel(lvl + 4)
        end
        local hpW = math.floor(HB.w * pct + 0.5)
        healthFill:ClearAllPoints()
        healthBgColor:ClearAllPoints()
        if s.healthReverseFill then
            healthFill:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            healthFill:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -hpW, 0)
        else
            healthFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            healthFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", hpW, 0)
            healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        end
        healthFill:SetWidth(hpW)
        if absorbBar then
            absorbBar:SetSize(HB.w, HB.h)
        end
        if healAbsorbBar then
            healAbsorbBar:SetSize(HB.w, HB.h)
        end
        -- Stock rounded mask on everything in the track (a mirrored small
        -- frame runs unmasked: masks cannot flip), then the bar's own bevel.
        local hm = healthBar._blizzMask
        local hMaskOK = not mirror and mod.UF_AtlasOK(G.health.mask)
        -- Everything drawn in the track (list reused; absorb fills can be
        -- swapped by a style change, so it is refilled each pass).
        local hTex = popFrame._blizzTrackTex
        if not hTex then
            hTex = {}
            popFrame._blizzTrackTex = hTex
        end
        table.wipe(hTex)
        hTex[#hTex + 1] = healthFill
        hTex[#hTex + 1] = healthBg
        hTex[#hTex + 1] = healthBgColor
        if healthBar._cuiBgTex then
            hTex[#hTex + 1] = healthBar._cuiBgTex
        end -- Textured Background layer
        if dispelOverlayPreview then
            hTex[#hTex + 1] = dispelOverlayPreview
        end
        if absorbBar and absorbBar:GetStatusBarTexture() then
            hTex[#hTex + 1] = absorbBar:GetStatusBarTexture()
        end
        if healAbsorbBar then
            if healAbsorbBar:GetStatusBarTexture() then
                hTex[#hTex + 1] = healAbsorbBar:GetStatusBarTexture()
            end
            if healAbsorbBar._bg then
                hTex[#hTex + 1] = healAbsorbBar._bg
            end
        end
        if hMaskOK then
            if not hm then
                hm = healthBar:CreateMaskTexture()
                healthBar._blizzMask = hm
            end
            mod.UF_SeatBarMask(hm, healthBar, HB)
            for idx = 1, #hTex do
                mod.UF_SetMask(hTex[idx], hm)
            end
        elseif hm then
            for idx = 1, #hTex do
                pcall(hTex[idx].RemoveMaskTexture, hTex[idx], hm)
            end
        end
        mod.UF_BlizzBarShadow(healthBar, hMaskOK and hm or nil, HB.h)

        -- Power: the small frames carry the stock bar (the mock builds none,
        -- so a plain one is built here once); a main frame's attached bar
        -- moves into the track, a detached one keeps its own spot.
        local pw = power
        if isMini then
            pw = popFrame._blizzPower
            if not pw then
                pw = CreateFrame("Frame", nil, popFrame)
                local backdrop = pw:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                backdrop:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
                local fillTex = pw:CreateTexture(nil, "ARTWORK")
                fillTex:SetPoint("TOPLEFT", pw, "TOPLEFT", 0, 0)
                fillTex:SetPoint("BOTTOMLEFT", pw, "BOTTOMLEFT", 0, 0)
                pw._bg, pw._fill = backdrop, fillTex
                popFrame._blizzPower = pw
            end
            -- The small frames' bar takes the donor's texture, as live.
            local texKey = mod.ResolveHealthBarTextureKey(
                s,
                mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitKey) or saved.profile.player
            )
            local texPath = (mod.healthBarTextures or {})[texKey]
            local _, pToken = UnitPowerType("player")
            local pc = CludesUI.GetPowerColor(pToken or "MANA")
            PV_FillColor(pw._fill, texPath, pc.r, pc.g, pc.b, nil, nil, nil, 1)
            -- Textured Background, as live.
            local _, mpTex = mod.UF_TexBgPaths(unitKey, s, texKey)
            mod.UF_TexBgPaint(pw._bg, mpTex, 17 / 255, 17 / 255, 17 / 255, 1)
        end
        local pPos = mod.UF_PowerPos(s)
        local inTrack = pw and (isMini or pPos == "below" or pPos == "above")
        if inTrack then
            -- A mirrored small frame's bar runs unmasked, so it stops where
            -- the health bar does (as live, UF_ApplyBlizzardLayout).
            local px, pwid = G.power.x, G.power.w
            if isMini and mirror and px < HB.x then
                pwid = pwid - (HB.x - px)
                px = HB.x
            end
            pw:ClearAllPoints()
            mod.UF_BlizzPoint(pw, "TOPLEFT", barArea, "TOPLEFT", px, -G.power.y, mirror)
            pw:SetSize(pwid, G.power.h)
            pw:SetFrameLevel(lvl + 3)
            local fillTex = pw._fill or popFrame._powerFill
            local backdrop = pw._bg or popFrame._powerBg
            if fillTex then
                fillTex:ClearAllPoints()
                if not isMini and s.powerReverseFill then
                    fillTex:SetPoint("TOPRIGHT", pw, "TOPRIGHT", 0, 0)
                    fillTex:SetPoint("BOTTOMRIGHT", pw, "BOTTOMRIGHT", 0, 0)
                else
                    fillTex:SetPoint("TOPLEFT", pw, "TOPLEFT", 0, 0)
                    fillTex:SetPoint("BOTTOMLEFT", pw, "BOTTOMLEFT", 0, 0)
                end
                fillTex:SetWidth(math.floor(pwid * ppct + 0.5))
            end
            local pm = pw._blizzMask
            local pMaskOK = not mirror and mod.UF_AtlasOK(G.power.mask)
            if pMaskOK then
                if not pm then
                    pm = pw:CreateMaskTexture()
                    pw._blizzMask = pm
                end
                mod.UF_SeatBarMask(pm, pw, G.power)
                mod.UF_SetMask(fillTex, pm)
                mod.UF_SetMask(backdrop, pm)
                mod.UF_SetMask(popFrame._pvCostSeg, pm)
            elseif pm then
                if fillTex then
                    pcall(fillTex.RemoveMaskTexture, fillTex, pm)
                end
                if backdrop then
                    pcall(backdrop.RemoveMaskTexture, backdrop, pm)
                end
                local cs = popFrame._pvCostSeg
                if cs then
                    pcall(cs.RemoveMaskTexture, cs, pm)
                end
            end
            mod.UF_BlizzBarShadow(pw, pMaskOK and pm or nil, G.power.h)
            if isMini or (s.powerHeight or 6) > 0 then
                pw:Show()
            end
        elseif pw and pw._blizzMask then
            -- Detached now: the track pieces come off.
            local fillTex = popFrame._powerFill
            if fillTex then
                pcall(fillTex.RemoveMaskTexture, fillTex, pw._blizzMask)
            end
            if popFrame._powerBg then
                pcall(popFrame._powerBg.RemoveMaskTexture, popFrame._powerBg, pw._blizzMask)
            end
            if pw._blizzShadow then
                for idx = 1, 4 do
                    pw._blizzShadow[idx]:Hide()
                end
            end
        end
        -- Hide Power Bar: the bar stays down, and so does its text (its own
        -- frame, with its click overlay).
        if merged and pw then
            pw:Hide()
        end
        local ppOv = ppPreviewFS and ppPreviewFS:GetParent()
        if ppOv then
            ppOv:SetShown(not merged)
        end

        -- Portrait: always on, stock spot and size, stock mask, under the
        -- art; 3D cannot be masked, so 2D art stands in as on the live frame.
        if portraitFrame then
            portraitFrame:Show()
            portraitFrame:ClearAllPoints()
            mod.UF_BlizzPoint(
                portraitFrame,
                G.portrait.point,
                barArea,
                G.portrait.point,
                G.portrait.x,
                G.portrait.y,
                mirror
            )
            portraitFrame:SetSize(G.portrait.size, G.portrait.size)
            portraitFrame:SetFrameLevel(lvl + 1)
            portraitFrame:SetClipsChildren(false)
            if portraitFrame._previewBg then
                portraitFrame._previewBg:Hide()
            end
            if portraitFrame._shapeBorderTex then
                portraitFrame._shapeBorderTex:Hide()
            end
            if portraitFrame._sqBorderTexs then
                for _, t in ipairs(portraitFrame._sqBorderTexs) do
                    t:Hide()
                end
            end
            mod.UF_PortraitExtras(portraitFrame, nil)
            mod.UF_PortraitDragon(portraitFrame, nil)
            local texture = portraitFrame._previewTex
            if portraitFrame._shapeMask then
                if texture then
                    pcall(texture.RemoveMaskTexture, texture, portraitFrame._shapeMask)
                end
                portraitFrame._shapeMask:Hide()
            end
            local model = portraitFrame._previewModel
            if model and model:IsShown() then
                model:Hide()
            end
            if texture then
                texture:Show()
                if (s.portraitMode or "2d") ~= "class" then
                    -- Third argument: the client's own round crop off where the
                    -- stock mask is not a circle (the player frame).
                    SetPortraitTexture(texture, "player", G.portrait.rawArt)
                    texture:SetTexCoord(0, 1, 0, 1)
                    texture:SetAlpha(1)
                    texture:ClearAllPoints()
                    texture:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
                    texture:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
                end
                if mod.UF_AtlasOK(G.portrait.mask) then
                    local m = portraitFrame._blizzMask
                    if not m then
                        m = portraitFrame:CreateMaskTexture()
                        m:SetAllPoints(portraitFrame)
                        portraitFrame._blizzMask = m
                    end
                    mod.UF_StockMask(m, G.portrait.mask)
                    m:Show()
                    mod.UF_SetMask(texture, m)
                end
            end
        end

        -- Left text zone on the name strip; the others stay bar-relative.
        if G.name and leftFS:IsShown() then
            leftFS:ClearAllPoints()
            leftFS:SetJustifyH(G.name.justify or "LEFT")
            local xOffset, yOffset = s.leftTextX or 0, s.leftTextY or 0
            -- Keep the user's X offset screen-relative when UF_BlizzPoint mirrors it.
            local posX = G.name.x + (mirror and -xOffset or xOffset)
            mod.UF_BlizzPoint(leftFS, G.name.point, barArea, G.name.point, posX, G.name.y + yOffset, mirror)
            leftFS:SetWidth(G.name.w)
        end

        -- No CUI chrome: the border and text bar step aside for the art.
        border:Hide()
        if btbFrame then
            btbFrame:Hide()
        end

        -- Cast bar: under the art box (the text bar no longer sits between)
        -- -- or, on the frames whose bar hangs off the aura block, under the
        -- lowest bottom aura stack (`drop`, from Update) -- with the stock
        -- background, fill art, frame and text box.
        if castBar and castBar:IsShown() and ch > 0 then
            local inW, onRight = mod.UF_CastIconInWidth(unitKey, s)
            if unitKey == "player" then
                onRight = s.playerCastbarIconRight == true
            else
                onRight = s.castbarIconRight == true
            end
            local UFC = mod.UF_CAST_BLIZZ
            -- The classic kit's cast chrome (nil on the stock kit): the
            -- vanilla frame round the user's own fill, no stock
            -- background, fill art or text box.
            local CK = mod.UF_BLIZZ.cast
            -- The stock text box (spell name shown) hangs 13px under the
            -- bar and the icon spans bar + box, as live; an in-width icon
            -- shifts the bar by half that width to keep the pair centred.
            local tbAtlas = (not CK) and UFC and mod.UF_BlizzAtlas(UFC.textbox)
            local nameSide = s.castSpellNameSide or "left"
            local tbOn = tbAtlas and castNameFS2 and nameSide ~= "none"
            local icoW = ch + (tbOn and 13 or 0)
            castBar:ClearAllPoints()
            castBar:SetPoint(
                "TOP",
                barArea,
                "BOTTOM",
                inW and (onRight and -(icoW / 2) or (icoW / 2)) or 0,
                padBottom - (drop or 0)
            )
            if castIconFrame then
                castIconFrame:SetSize(icoW, icoW)
            end
            -- The retail background under WoW Forever too, as live.
            local bgAtlas = (not CK) and UFC and mod.UF_BlizzAtlas(UFC.bg)
            if bgAtlas and castBar._previewBgTex then
                CludesUI.StockAtlas(castBar._previewBgTex, bgAtlas)
                castBar._previewBgTex:ClearAllPoints()
                castBar._previewBgTex:SetPoint("TOPLEFT", castBar, "TOPLEFT", -1, 1)
                castBar._previewBgTex:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 1, -1)
            end
            local fillAtlas = (not CK) and UFC and mod.UF_BlizzAtlas(UFC.cast)
            if fillAtlas and castFill then
                castFill:SetAtlas(fillAtlas)
                castFill:SetVertexColor(1, 1, 1, 1)
            end
            Pix.HideBorder(castBar)
            if castIconFrame then
                -- Bare art, as live: no plate, no border, no 1px inset
                -- (Update re-snaps the inset every pass; this runs after).
                Pix.HideBorder(castIconFrame)
                if castIconFrame._bg then
                    castIconFrame._bg:Hide()
                end
                if castIconFrame._iconTex then
                    castIconFrame._iconTex:ClearAllPoints()
                    castIconFrame._iconTex:SetAllPoints(castIconFrame)
                    castIconFrame._iconTex:SetTexCoord(0, 1, 0, 1)
                end
            end
            local frAtlas = (not CK) and UFC and mod.UF_BlizzAtlas(UFC.frame)
            if CK then
                -- The vanilla frame round the footprint: bar plus icon
                -- while the icon is part of the bar (as live, the icon
                -- sits inside the frame's window), on an art frame
                -- above both so the rim overlaps the icon's edges too.
                local af = castBar._classicArt
                if not af then
                    af = CreateFrame("Frame", nil, popFrame)
                    af:EnableMouse(false)
                    af:SetFrameLevel(popFrame:GetFrameLevel() + 3)
                    castBar._classicArt = af
                    castBar._blizzFrame = af:CreateTexture(nil, "OVERLAY", nil, 2)
                end
                af:ClearAllPoints()
                if inW and castIconFrame and castIconFrame:IsShown() then
                    if onRight then
                        af:SetPoint("TOPLEFT", castBar, "TOPLEFT", 0, 0)
                        af:SetPoint("BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", 0, 0)
                    else
                        af:SetPoint("TOPLEFT", castIconFrame, "TOPLEFT", 0, 0)
                        af:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 0, 0)
                    end
                else
                    af:SetAllPoints(castBar)
                end
                mod.UF_SeatClassicCastFrame(castBar._blizzFrame, af, ch, s[mod.UF_CastClassicKey(unitKey)])
            elseif frAtlas then
                local fr = castBar._blizzFrame
                if not fr then
                    fr = castBar:CreateTexture(nil, "OVERLAY", nil, 2)
                    castBar._blizzFrame = fr
                end
                mod.UF_StockAtlas(fr, frAtlas)
                fr:ClearAllPoints()
                fr:SetPoint("TOPLEFT", castBar, "TOPLEFT", -2, 2)
                fr:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 2, -2)
                fr:Show()
            end
            if tbOn then
                local tb = castBar._blizzTextBox
                if not tb then
                    tb = castBar:CreateTexture(nil, "BACKGROUND", nil, -1)
                    castBar._blizzTextBox = tb
                end
                mod.UF_StockAtlas(tb, tbAtlas)
                tb:ClearAllPoints()
                tb:SetPoint("TOPLEFT", castBar, "BOTTOMLEFT", 0, 3)
                tb:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 0, -13)
                tb:Show()
                local ox, oy = s.castSpellNameX or 0, s.castSpellNameY or 0
                castNameFS2:ClearAllPoints()
                if nameSide == "right" then
                    castNameFS2:SetJustifyH("RIGHT")
                    castNameFS2:SetPoint("RIGHT", tb, "RIGHT", -8 + ox, oy)
                elseif nameSide == "center" then
                    castNameFS2:SetJustifyH("CENTER")
                    castNameFS2:SetPoint("CENTER", tb, "CENTER", ox, oy)
                else
                    castNameFS2:SetJustifyH("LEFT")
                    castNameFS2:SetPoint("LEFT", tb, "LEFT", 8 + ox, oy)
                end
                local wid = castBar:GetWidth() or 0
                if wid > 20 then
                    castNameFS2:SetWidth(wid - 16)
                end
            elseif castBar._blizzTextBox then
                castBar._blizzTextBox:Hide()
            end
        end
    end
    -- Blizzard Style: the preview frame is the stock box's width (its
    -- transparent rows trimmed on the full frames), so an aura anchor
    -- moves in to the visible art's edges the way the live containers do
    -- (AnchorContainer's vis insets). `am` is the pass's own anchor entry.
    local function BlizzInsetAnchor(am, anchorFrame, G, mirror)
        local val = G.vis
        if not val then
            return
        end
        local pad = G.pad
        local vl, vr = val.l, val.r
        if mirror then
            vl, vr = vr, vl
        end
        if anchorFrame == "topleft" or anchorFrame == "bottomleft" or anchorFrame == "left" then
            am.ox = am.ox + vl
        elseif anchorFrame == "topright" or anchorFrame == "bottomright" or anchorFrame == "right" then
            am.ox = am.ox - vr
        end
        if anchorFrame == "topleft" or anchorFrame == "topright" then
            am.oy = am.oy - (val.t - (pad and pad.top or 0))
        elseif anchorFrame == "bottomleft" or anchorFrame == "bottomright" then
            am.oy = am.oy + (val.b - (pad and pad.bottom or 0))
        end
    end

    -- Update is at Lua's 60-upvalue cap: it reaches the style helpers
    -- through pf instead of capturing them.
    popFrame._blizzResolve = ResolveBlizzPreview
    popFrame._blizzScale = BlizzPreviewScale
    popFrame._blizzApply = ApplyBlizzPreview
    popFrame._blizzInset = BlizzInsetAnchor

    -- Update method
    function popFrame:Update()
        -- Skip while stashed (hidden on tab switch): updating re-anchors the
        -- preview to _chStash via GetParent() and breaks its restored position.
        -- Visible, not shown: a kept header root keeps its preview's own shown
        -- flag while the root itself is hidden on another page.
        if not popFrame:IsVisible() then
            if disabledOverlay then
                disabledOverlay:Hide()
            end
            return
        end
        local s
        if unitKey == "player" then
            s = saved.profile.player
        elseif unitKey == "target" then
            s = saved.profile.target
        elseif unitKey == "focus" then
            s = saved.profile.focus
        elseif unitKey == "pet" then
            s = saved.profile.pet
        elseif unitKey == "boss" then
            s = saved.profile.boss
        elseif unitKey == "targettarget" then
            s = saved.profile.targettarget
        elseif unitKey == "focustarget" then
            s = saved.profile.focustarget
        else
            s = saved.profile.player
        end

        -- Blizzard Style: stock geometry (nil = CUI look); Frame Scale rides
        -- the preview scale so every anchor and the header math follow it.
        local blizzG, blizzMirror, blizzExtras = popFrame._blizzResolve(unitKey, s)
        popFrame._previewScale = (popFrame._previewBaseScale or popFrame._previewScale or 1)
            * (blizzG and popFrame._blizzScale(s) or 1)

        -- The aura settings the live containers read: the pet's through its
        -- Copy Auras From view (its own size, crop and placement, the source
        -- frame's look), every other unit's own table.
        local as = s
        if unitKey == "pet" then
            as = mod.UF_AuraSettings("pet") or s
        end

        -- Aura preview: mirror the live shared aura border style.
        if
            unitKey == "player"
            or unitKey == "target"
            or unitKey == "focus"
            or unitKey == "boss"
            or unitKey == "pet"
        then
            -- Blizzard Style: the live frames draw no custom aura border, so
            -- the preview keeps the plain 1px edge and hides it too.
            local blizzAura = blizzG ~= nil
            local function ApplyPreviewAuraBorder(glyph)
                if glyph._iconTex then
                    glyph._iconTex:ClearAllPoints()
                    local inset = (blizzAura or (as.auraBorderSize or 1) > 0) and 1 or 0
                    Pix.Point(glyph._iconTex, "TOPLEFT", glyph, "TOPLEFT", inset, -inset)
                    Pix.Point(glyph._iconTex, "BOTTOMRIGHT", glyph, "BOTTOMRIGHT", -inset, inset)
                end
                local border = glyph._cuiAuraBorder
                if blizzAura then
                    if border then
                        border:Hide()
                    end
                    return
                end
                if not border then
                    border = CreateFrame("Frame", nil, glyph)
                    border:SetAllPoints(glyph)
                    border:EnableMouse(false)
                    glyph._cuiAuraBorder = border
                end
                local aboveEffects = unitKey == "boss" and mod.UF_BossAuraBorderAboveEffects(s)
                if as.auraBorderBehindUnitFrame then
                    border:SetFrameLevel(0)
                elseif aboveEffects then
                    border:SetFrameLevel(glyph:GetFrameLevel() + 20)
                else
                    border:SetFrameLevel(
                        as.auraBorderBehind and math.max(0, glyph:GetFrameLevel() - 1)
                            or (glyph:GetFrameLevel() + 1)
                    )
                end
                if glyph._durText and (aboveEffects or glyph._borderAboveEffects) then
                    glyph._durText
                        :GetParent()
                        :SetFrameLevel(glyph:GetFrameLevel() + (aboveEffects and 25 or 2))
                    glyph._borderAboveEffects = aboveEffects or nil
                end
                CludesUI.ApplyBorderStyle(
                    border,
                    as.auraBorderSize or 1,
                    as.auraBorderR or 0,
                    as.auraBorderG or 0,
                    as.auraBorderB or 0,
                    as.auraBorderA or 1,
                    as.auraBorderTexture or "solid",
                    as.auraBorderTextureOffset,
                    as.auraBorderTextureOffsetY,
                    as.auraBorderTextureShiftX,
                    as.auraBorderTextureShiftY,
                    "unitframes",
                    as.auraBorderSize or 1,
                    nil,
                    CludesUI.BorderPx(
                        as.auraBorderSizePx,
                        as.auraBorderSize or 1,
                        as.auraBorderTexture or "solid"
                    )
                )
            end
            for idx = 1, #buffIcons do
                ApplyPreviewAuraBorder(buffIcons[idx])
            end
            for idx = 1, #debuffIcons do
                ApplyPreviewAuraBorder(debuffIcons[idx])
            end
        end

        -- Donor settings for mini frames (border/texture inherit from the
        -- frame Copy Look From picks; text SIZES are the unit's own -- see
        -- ApplyPreviewTextPositions)
        local isMini = (
            unitKey == "pet"
            or unitKey == "boss"
            or unitKey == "targettarget"
            or unitKey == "focustarget"
        )
        local ds = s
        if isMini then
            ds = mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitKey) or saved.profile.player
        end
        -- The frame border's settings: the donor's for the minis; the boss
        -- frames' own once the boss Border Style leaves Inherit (the live
        -- frames' ns.UF_BossBorderSettings).
        local bds = (unitKey == "boss") and mod.UF_BossBorderSettings() or ds

        -- The preview mocks the CUI frame, so it counts as "enabled" only when the
        -- unit's source is the CUI frame.
        local unitKey2 = unitKey:match("^boss") and "boss" or unitKey
        local isEnabled = mod.GetUnitFrameSource(unitKey2) == "cui"
        if isEnabled then
            disabledOverlay:Hide()
            popFrame:SetAlpha(1)
        else
            popFrame:SetAlpha(0.5)
        end

        -- Reposition name and health text based on settings
        sideName = s.portraitSide or unitSide[unitKey] or "left"
        local pvPStyle = s.portraitStyle or saved.profile.portraitStyle or "attached"
        local sp = hasPortraitSupport and pvPStyle ~= "none" and s.showPortrait ~= false
        local isAttached = pvPStyle == "attached"
        local fw = s.frameWidth or 181
        local hh = s.healthHeight or 46
        local ph = noPowerPreview and 0 or (s.powerHeight or 6)
        local pvPpPos = noPowerPreview and "none" or mod.UF_PowerPos(s)
        local pvPpIsAtt = (pvPpPos == "below" or pvPpPos == "above")
        local pvPpExtra = pvPpIsAtt and ph or 0
        local ch = (unitKey == "player")
                and (s.showPlayerCastbar and (s.playerCastbarHeight and s.playerCastbarHeight > 0 and s.playerCastbarHeight or 14) or 0)
            or ((s.showCastbar ~= false) and (s.castbarHeight or 14) or 0)
        -- Mirrors the live reserve decision (see the build path above).
        if ch > 0 and CludesUI.UF_CastbarBelowFrame and not CludesUI.UF_CastbarBelowFrame(unitKey) then
            ch = 0
        end
        -- Blizzard Style: on the frames with a movable cast bar the bar
        -- hangs below the bottom aura stacks, off the frame's aura block
        -- (live: AnchorContainer plus the unlock follow provider), and
        -- those stacks reserve nothing for it. Only with the engine's
        -- layout aspect; a client without it keeps the bar on the art's
        -- bottom with the stacks under it, as the boss frames always do.
        local blizzBelow = blizzG ~= nil
            and ch > 0
            and (unitKey == "player" or unitKey == "target" or unitKey == "focus")
            and mod.UF_LayoutAspectOK ~= nil
            and mod.UF_LayoutAspectOK() == true
        -- The strip the bar takes under the art (plus the stock text box).
        local cbStrip = 0
        local bh = hh + pvPpExtra
        -- Class power "above" position adds height above health bar ("top" floats outside)
        local cpStyle = (unitKey == "player") and (s.classPowerStyle or "none") or "none"
        -- The style that builds (WoW Forever reads a saved "blizzard" as modern,
        -- and a rogue's own style); only the player frame has a class resource.
        if unitKey == "player" and mod.UF_ForeverCPStyle then
            cpStyle = mod.UF_ForeverCPStyle(cpStyle)
        end
        local cpPos = (cpStyle == "modern") and (s.classPowerPosition or "top") or "none"
        local cpAboveH = 0
        if cpStyle == "modern" and cpPos == "above" and cpPips then
            local cpSizeAdj = s.classPowerSize or 8
            local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
            cpAboveH = cpPipH
        end
        local bh2 = bh + cpAboveH -- total bar area height including above pips
        -- "top"/"bottom" pips float outside the frame, but their height still
        -- counts toward the content header so they push content above/below.
        local cpTopH = 0
        local cpBottomH = 0
        if cpStyle == "modern" and (cpPos == "top" or cpPos == "bottom") then
            local cpSizeAdj = s.classPowerSize or 8
            local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
            local cpYOff = s.classPowerBarY or 0
            if cpPos == "top" then
                cpTopH = cpPipH + cpYOff
            else
                cpBottomH = cpPipH
            end
        end
        -- Portrait size/offset from DB
        local pSizeAdj = sp and (s.portraitSize or 0) or 0
        local pXOff = sp and (s.portraitX or 0) or 0
        local pYOff = sp and (s.portraitY or 0) or 0
        local pvIsInside = (
            sideName == "insideleft"
            or sideName == "insideright"
            or sideName == "insidecenter"
        )
        if not isAttached and not pvIsInside then
            pSizeAdj = pSizeAdj + 10
            pYOff = pYOff + 5
        end
        local portraitDim = bh2 + pSizeAdj -- portrait width & height
        if portraitDim < 8 then
            portraitDim = 8
        end
        -- For attached, "top" and "inside*" fall back to default side
        local effectiveSide = sideName
        if isAttached and (sideName == "top" or pvIsInside) then
            effectiveSide = unitSide[unitKey] or "left"
            pvIsInside = false
        end
        local pw = (sp and isAttached and effectiveSide ~= "top") and portraitDim or 0
        local tw = fw + pw
        -- Blizzard Style: the stock footprint (cast bar width, pf size, fit).
        if blizzG then
            tw = blizzG.w
        end

        Pix.Size(healthBar, fw, hh)

        -- Re-anchor portrait + health every update (no caching) to avoid circular
        -- dependency errors on style switches: clear BOTH first, then anchor in
        -- dependency order.
        if portraitFrame then
            portraitFrame:ClearAllPoints()
        end
        healthBar:ClearAllPoints()
        local btbTopOff = (s.bottomTextBar and (s.btbPosition or "bottom") == "top")
                and (s.bottomTextBarHeight or 16)
            or 0
        local pvPwAbove = (pvPpPos == "above") and ph or 0

        if portraitFrame and sp then
            if pvIsInside then
                Pix.Size(portraitFrame, portraitDim, bh2)
            else
                Pix.Size(portraitFrame, portraitDim, portraitDim)
            end
            if pvIsInside then
                -- Inside: portrait overlays the health bar
                Pix.Point(healthBar, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                portraitFrame:SetClipsChildren(true)
                if portraitFrame._previewBg then
                    portraitFrame._previewBg:Hide()
                end
                if effectiveSide == "insideleft" then
                    portraitFrame:SetPoint("TOPLEFT", healthBar, "TOPLEFT", pXOff, pYOff)
                elseif effectiveSide == "insideright" then
                    portraitFrame:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", pXOff, pYOff)
                else -- insidecenter
                    portraitFrame:SetPoint("TOP", healthBar, "TOP", pXOff, pYOff)
                end
            elseif isAttached then
                -- Attached: portrait to barArea, then health to portrait
                portraitFrame:SetClipsChildren(true)
                if portraitFrame._previewBg then
                    portraitFrame._previewBg:Show()
                end
                if effectiveSide == "left" then
                    portraitFrame:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
                    Pix.Point(
                        healthBar,
                        "TOPLEFT",
                        portraitFrame,
                        "TOPRIGHT",
                        0,
                        -cpAboveH - btbTopOff - pvPwAbove
                    )
                else
                    portraitFrame:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
                    Pix.Point(
                        healthBar,
                        "TOPRIGHT",
                        portraitFrame,
                        "TOPLEFT",
                        0,
                        -cpAboveH - btbTopOff - pvPwAbove
                    )
                end
            else
                -- Detached: health to barArea, then portrait floats. Clip back
                -- on; ApplyPreviewPortraitShape (later this Update) turns it off
                -- again for Pixels Circle or a shown Outer Ring.
                portraitFrame:SetClipsChildren(true)
                if portraitFrame._previewBg then
                    portraitFrame._previewBg:Show()
                end
                Pix.Point(healthBar, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                if effectiveSide == "top" then
                    -- Top: portrait centered above health bar
                    portraitFrame:SetPoint("BOTTOM", healthBar, "TOP", pXOff, 15 + pYOff)
                elseif effectiveSide == "left" then
                    portraitFrame:SetPoint("TOPRIGHT", healthBar, "TOPLEFT", -15 + pXOff, pYOff)
                else
                    portraitFrame:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", 15 + pXOff, pYOff)
                end
            end
            portraitFrame._anchored = true
            portraitFrame._anchoredAttached = isAttached
            -- Raise detached portrait above the border, capped so it can't overlap
            -- dropdown menus and other UI controls.
            if isAttached then
                portraitFrame:SetFrameLevel(popFrame:GetFrameLevel() + 1)
            else
                portraitFrame:SetFrameLevel(popFrame:GetFrameLevel() + 3)
            end
        else
            Pix.Point(healthBar, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
            if portraitFrame then
                portraitFrame._anchored = false
            end
        end
        healthFill:ClearAllPoints()
        -- Vertical Fill swaps the fill axis (grows up from bottom; Reverse Fill flips
        -- it to grow down from top). Anchors sit on the non-growth axis; the other
        -- dimension comes from the explicit PP.Width / PP.Height below.
        if s.healthVerticalFill then
            if s.healthReverseFill then
                healthFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healthFill:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            else
                healthFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                healthFill:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
            Pix.Height(healthFill, math.floor(hh * (optionState._previewHealthPct or 0.70) + 0.5))
        else
            if s.healthReverseFill then
                healthFill:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
                healthFill:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            else
                healthFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healthFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            end
            Pix.Width(healthFill, math.floor(fw * (optionState._previewHealthPct or 0.70) + 0.5))
        end

        -- Live-update dark mode colors
        do
            local isDark = mod.UF_DarkThemeOn(s)
            local uHR, uHG, uHB, uBgR, uBgG, uBgB
            if isDark then
                uHR, uHG, uHB = CludesUI.GetDarkModeFill()
                uBgR, uBgG, uBgB = CludesUI.GetDarkModeBg()
            else
                -- Custom fill skipped when class-colored; boss is always hostile-red.
                local cFill = s.customFillColor
                local isCC = s.healthClassColored and unitKey ~= "boss"
                if isCC then
                    local _, ct = UnitClass("player")
                    local cc = RAID_CLASS_COLORS[ct]
                    if cc then
                        uHR, uHG, uHB = cc.r, cc.g, cc.b
                    else
                        uHR, uHG, uHB = 37 / 255, 193 / 255, 29 / 255
                    end
                elseif cFill then
                    uHR, uHG, uHB = cFill.r, cFill.g, cFill.b
                elseif unitKey == "player" then
                    local _, ct = UnitClass("player")
                    local cc = RAID_CLASS_COLORS[ct]
                    if cc then
                        uHR, uHG, uHB = cc.r, cc.g, cc.b
                    else
                        uHR, uHG, uHB = 37 / 255, 193 / 255, 29 / 255
                    end
                elseif unitKey == "pet" then
                    uHR, uHG, uHB = 37 / 255, 193 / 255, 29 / 255
                else
                    uHR, uHG, uHB = 0.8, 0.2, 0.2
                end
                -- Dynamic Health Color overrides the flat sources above (see the
                -- build-time twin); resolved at the preview's fake health percent.
                local uDynR, uDynG, uDynB =
                    mod.UF_PreviewDynamicColor(s, optionState._previewHealthPct or 0.70)
                if uDynR then
                    uHR, uHG, uHB = uDynR, uDynG, uDynB
                end
                -- Class-colored background (designer shows the player's class), else custom.
                local uBgClassCC
                if s.bgClassColored then
                    local _, ct = UnitClass("player")
                    uBgClassCC = ct and CludesUI.GetClassColor(ct)
                end
                if uBgClassCC then
                    uBgR, uBgG, uBgB = uBgClassCC.r, uBgClassCC.g, uBgClassCC.b
                else
                    local cBg = s.customBgColor
                    if cBg then
                        uBgR, uBgG, uBgB = cBg.r, cBg.g, cBg.b
                    else
                        uBgR, uBgG, uBgB = 17 / 255, 17 / 255, 17 / 255
                    end
                end
            end
            healthFill:SetColorTexture(uHR, uHG, uHB, 1)
            -- Bg covers only the empty portion so a reduced fill opacity reveals
            -- the backdrop, not the bg color (live frame edge-anchor).
            healthBgColor:ClearAllPoints()
            do
                if s.healthVerticalFill then
                    local hpH = math.floor(hh * (optionState._previewHealthPct or 0.70) + 0.5)
                    if s.healthReverseFill then
                        healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, -hpH)
                        healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                    else
                        healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                        healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, hpH)
                    end
                else
                    local hpW = math.floor(fw * (optionState._previewHealthPct or 0.70) + 0.5)
                    if s.healthReverseFill then
                        healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                        healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -hpW, 0)
                    else
                        healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", hpW, 0)
                        healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                    end
                end
            end
            healthBgColor:SetColorTexture(uBgR, uBgG, uBgB, 1)
            -- Bar texture on the fills; mini frames use the donor texture unless
            -- they set their own override.
            do
                local curTexKey = mod.ResolveHealthBarTextureKey(s, isMini and ds or nil)
                local curTexPath = (mod.healthBarTextures or {})[curTexKey]
                if healthFill then
                    local hGA = s.healthBarOpacity or 90
                    if hGA > 1.0 then
                        hGA = hGA / 100
                    end
                    PV_FillColor(
                        healthFill,
                        curTexPath,
                        uHR,
                        uHG,
                        uHB,
                        (not isDark) and s.gradientEnabled,
                        s.gradientColor,
                        s.gradientDir,
                        hGA
                    )
                end
                if popFrame._powerFill then
                    local pvFR, pvFG, pvFB
                    local isPwrC2 = s.powerPercentPowerColor ~= false
                    if isPwrC2 and s.powerClassColored then
                        local _, ct = UnitClass("player")
                        local cc = CludesUI.GetClassColor(ct)
                        pvFR, pvFG, pvFB = cc.r, cc.g, cc.b
                    elseif isPwrC2 then
                        local _, pToken = UnitPowerType("player")
                        local details = CludesUI.GetPowerColor(pToken or "MANA")
                        pvFR, pvFG, pvFB = details.r, details.g, details.b
                    else
                        local cpf2 = s.customPowerFillColor
                        if cpf2 then
                            pvFR, pvFG, pvFB = cpf2.r, cpf2.g, cpf2.b
                        else
                            pvFR, pvFG, pvFB = 0, 0, 1
                        end
                    end
                    popFrame._pR, popFrame._pG, popFrame._pB = pvFR, pvFG, pvFB
                    if curTexPath then
                        popFrame._powerFill:SetTexture(curTexPath)
                        popFrame._powerFill:SetVertexColor(pvFR, pvFG, pvFB, 1)
                    else
                        popFrame._powerFill:SetVertexColor(1, 1, 1, 1)
                        popFrame._powerFill:SetColorTexture(pvFR, pvFG, pvFB, 1)
                    end
                end
            end

            -- Apply health bar alpha from unified opacity setting
            local hFillA, hBgA
            if isDark then
                hFillA = 0.90
                hBgA = 1
            else
                local barOp = (s.healthBarOpacity or 90) / 100
                hFillA = barOp
                hBgA = (s.customBgAlpha or 100) / 100
            end
            if healthFill then
                healthFill:SetAlpha(hFillA)
            end
            if healthBgColor then
                healthBgColor:SetAlpha(hBgA)
            end
            -- Textured Background, as live: a fixed full-size layer while the fill is opaque.
            local tbPath =
                mod.UF_TexBgPaths(unitKey, s, mod.ResolveHealthBarTextureKey(s, isMini and ds or nil))
            if tbPath then
                local tb = mod.UF_TexBgLayer(healthBar, tbPath, s.healthVerticalFill and not blizzG)
                tb:SetVertexColor(uBgR, uBgG, uBgB, 1)
                tb:SetAlpha(hBgA)
            elseif healthBar._cuiBgTex then
                healthBar._cuiBgTex:Hide()
            end
        end

        -- Text sizes deliberately NOT donor-sourced (see the function):
        -- live frames read the unit's own size keys, and these pages all
        -- carry their own size cogs. ds keeps serving border/texture.
        ApplyPreviewTextPositions(s)

        -- Resize barArea to health+power area (+ above pips if active)
        Pix.Size(barArea, tw, bh2 + btbTopOff)

        if power then
            local pvPw = fw
            local pvPpIsDet = (pvPpPos == "detached_top" or pvPpPos == "detached_bottom")
            if pvPpIsDet and (s.powerWidth or 0) > 0 then
                pvPw = s.powerWidth
            end
            Pix.Size(power, pvPw, ph)
            if pvPpIsDet and saved.profile.enableCustomBarStratas then
                power:SetFrameLevel(popFrame:GetFrameLevel() + 40)
            elseif pvPpIsDet then
                power:SetFrameLevel(popFrame:GetFrameLevel() + 3)
            end
            power:ClearAllPoints()
            if pvPpPos == "none" then
                power:Hide()
            elseif pvPpPos == "above" then
                Pix.Point(power, "BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
                Pix.Point(power, "BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            elseif pvPpPos == "detached_top" then
                power:SetPoint("BOTTOM", healthBar, "TOP", s.powerX or 0, 15 + (s.powerY or 0))
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            elseif pvPpPos == "detached_bottom" then
                power:SetPoint("TOP", healthBar, "BOTTOM", s.powerX or 0, -15 + (s.powerY or 0))
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            else -- "below"
                Pix.Point(power, "TOPLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                Pix.Point(power, "TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            end
            -- Live-frame rule: attached bars get only the Solid seam facing health;
            -- detached bars keep their selected full style.
            if mod.UpdatePowerBorder then
                mod.UpdatePowerBorder(power, s)
            end
            if popFrame._powerFill then
                popFrame._powerFill:ClearAllPoints()
                if s.powerReverseFill then
                    popFrame._powerFill:SetPoint("TOPRIGHT", power, "TOPRIGHT", 0, 0)
                    popFrame._powerFill:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
                else
                    popFrame._powerFill:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                    popFrame._powerFill:SetPoint("BOTTOMLEFT", power, "BOTTOMLEFT", 0, 0)
                end
                Pix.Width(
                    popFrame._powerFill,
                    math.floor(pvPw * (optionState._previewPowerPct or 0.85) + 0.5)
                )
            end

            -- Power bar opacity: the fill's region alpha is set AFTER PV_FillColor
            -- below, which would otherwise leave it at full opacity (mirrors
            -- ApplyPowerBarAlpha on the real frame).
            local pOpacity = (s.powerBarOpacity or 100) / 100
            if popFrame._powerBg then
                popFrame._powerBg:SetAlpha((s.customPowerBgAlpha or 100) / 100)
            end
            -- Fill Opacity < 100: bg covers only the empty portion (live
            -- world-show-through); restore the full-size anchors at 100.
            if popFrame._powerBg and popFrame._powerFill then
                if pOpacity < 1 then
                    popFrame._powerBgOpAnchored = true
                    popFrame._powerBg:ClearAllPoints()
                    if s.powerReverseFill then
                        popFrame._powerBg:SetPoint("TOPLEFT", power, "TOPLEFT", 0, 0)
                        popFrame._powerBg:SetPoint("BOTTOMRIGHT", popFrame._powerFill, "BOTTOMLEFT", 0, 0)
                    else
                        popFrame._powerBg:SetPoint("TOPLEFT", popFrame._powerFill, "TOPRIGHT", 0, 0)
                        popFrame._powerBg:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT", 0, 0)
                    end
                elseif popFrame._powerBgOpAnchored then
                    popFrame._powerBgOpAnchored = nil
                    popFrame._powerBg:ClearAllPoints()
                    popFrame._powerBg:SetAllPoints(power)
                end
            end

            local pvPfR, pvPfG, pvPfB
            local pvUsePowerColor = s.powerPercentPowerColor ~= false
            if pvUsePowerColor and s.powerClassColored then
                local _, ct = UnitClass("player")
                local cc = CludesUI.GetClassColor(ct)
                pvPfR, pvPfG, pvPfB = cc.r, cc.g, cc.b
            elseif pvUsePowerColor then
                local _, pToken = UnitPowerType("player")
                local details = CludesUI.GetPowerColor(pToken or "MANA")
                pvPfR, pvPfG, pvPfB = details.r, details.g, details.b
            else
                local cpFill = s.customPowerFillColor
                if cpFill then
                    pvPfR, pvPfG, pvPfB = cpFill.r, cpFill.g, cpFill.b
                else
                    pvPfR, pvPfG, pvPfB = 0, 0, 1
                end
            end
            local pvPbR, pvPbG, pvPbB
            local cpBg = s.customPowerBgColor
            if s.powerBgPowerColored then
                local _, pbToken = UnitPowerType("player")
                local pbInfo = CludesUI.GetPowerColor(pbToken or "MANA")
                local pbF = CludesUI.GetPowerBgDarkenFactor()
                pvPbR, pvPbG, pvPbB = pbInfo.r * pbF, pbInfo.g * pbF, pbInfo.b * pbF
            elseif cpBg then
                pvPbR, pvPbG, pvPbB = cpBg.r, cpBg.g, cpBg.b
            else
                pvPbR, pvPbG, pvPbB = 17 / 255, 17 / 255, 17 / 255
            end
            if popFrame._powerFill then
                local curTK = s.healthBarTexture or saved.profile.healthBarTexture or "none"
                local curTP = (mod.healthBarTextures or {})[curTK]
                PV_FillColor(
                    popFrame._powerFill,
                    curTP,
                    pvPfR,
                    pvPfG,
                    pvPfB,
                    s.powerGradientEnabled,
                    s.powerGradientColor,
                    s.powerGradientDir,
                    pOpacity
                )
                -- Region alpha last; a gradient bakes opacity into its endpoints, so
                -- keep it at 1 there to avoid double-dimming (as the real frame does).
                popFrame._powerFill:SetAlpha(s.powerGradientEnabled and 1 or pOpacity)
            end
            if popFrame._powerBg then
                -- Textured Background, as live.
                local _, tp = mod.UF_TexBgPaths(
                    unitKey,
                    s,
                    s.healthBarTexture or saved.profile.healthBarTexture or "none"
                )
                mod.UF_TexBgPaint(popFrame._powerBg, tp, pvPbR, pvPbG, pvPbB, 1)
            end
            -- Spell Cost Prediction eyeball (player, WoW Forever): the last
            -- third of the fill in the prediction color, as during a cast.
            -- Mana only, as live.
            if
                unitKey == "player"
                and CludesUI.SpellCostPrediction
                and popFrame._powerFill
                and mod._ufShowPowerCostPreview
                and s.powerCostPrediction == true
                and UnitPowerType("player") == Enum.PowerType.Mana
            then
                local seg = popFrame._pvCostSeg
                if not seg then
                    seg = power:CreateTexture(nil, "ARTWORK", nil, 2)
                    popFrame._pvCostSeg = seg
                end
                local r, g, b = mod.UF_PowerCostColor(s)
                local curTP = (mod.healthBarTextures or {})[s.healthBarTexture or saved.profile.healthBarTexture or "none"]
                if curTP then
                    seg:SetTexture(curTP)
                    seg:SetVertexColor(r, g, b, 1)
                else
                    seg:SetColorTexture(r, g, b, 1)
                end
                seg:SetAlpha(pOpacity)
                seg:ClearAllPoints()
                if s.powerReverseFill then
                    seg:SetPoint("TOPLEFT", popFrame._powerFill, "TOPLEFT", 0, 0)
                    seg:SetPoint("BOTTOMLEFT", popFrame._powerFill, "BOTTOMLEFT", 0, 0)
                else
                    seg:SetPoint("TOPRIGHT", popFrame._powerFill, "TOPRIGHT", 0, 0)
                    seg:SetPoint("BOTTOMRIGHT", popFrame._powerFill, "BOTTOMRIGHT", 0, 0)
                end
                seg:SetWidth(math.floor(popFrame._powerFill:GetWidth() / 3 + 0.5))
                seg:Show()
            elseif popFrame._pvCostSeg then
                popFrame._pvCostSeg:Hide()
            end
        end

        -- Power percent text in preview
        if ppPreviewFS then
            local ppPos = s.powerPercentText or "none"
            local ppFmt = CludesUI.PowerTextFormat(s.powerTextFormat or "perpp")
            if ppPos ~= "none" and ppFmt ~= "none" and power then
                local ppSz = s.powerPercentSize or 9
                local ppOx = s.powerPercentX or 0
                local ppOy = s.powerPercentY or 0
                SetPVFont(ppPreviewFS, PREVIEW_FONT, ppSz)
                ppPreviewFS:ClearAllPoints()
                if ph > 0 then
                    if ppPos == "left" then
                        ppPreviewFS:SetJustifyH("LEFT")
                        Pix.Point(ppPreviewFS, "LEFT", power, "LEFT", 2 + ppOx, ppOy)
                    elseif ppPos == "right" then
                        ppPreviewFS:SetJustifyH("RIGHT")
                        Pix.Point(ppPreviewFS, "RIGHT", power, "RIGHT", -2 + ppOx, ppOy)
                    else
                        ppPreviewFS:SetJustifyH("CENTER")
                        Pix.Point(ppPreviewFS, "CENTER", power, "CENTER", ppOx, ppOy)
                    end
                else
                    -- Power Bar Height 0: the zero-height frame's rect won't resolve,
                    -- so anchor the text to the HEALTH bar in the power row instead
                    -- (mirrors the real frame).
                    local above = (pvPpPos == "above" or pvPpPos == "detached_top")
                    local hEdge = above and "TOP" or "BOTTOM" -- health edge to meet
                    local fEdge = above and "BOTTOM" or "TOP" -- text edge that meets it
                    if ppPos == "left" then
                        ppPreviewFS:SetJustifyH("LEFT")
                        Pix.Point(ppPreviewFS, fEdge .. "LEFT", healthBar, hEdge .. "LEFT", 2 + ppOx, ppOy)
                    elseif ppPos == "right" then
                        ppPreviewFS:SetJustifyH("RIGHT")
                        Pix.Point(ppPreviewFS, fEdge .. "RIGHT", healthBar, hEdge .. "RIGHT", -2 + ppOx, ppOy)
                    else
                        ppPreviewFS:SetJustifyH("CENTER")
                        Pix.Point(ppPreviewFS, fEdge, healthBar, hEdge, ppOx, ppOy)
                    end
                end
                local ppPctVal = optionState._previewPowerPct or 0.85
                local ppPctRaw = math.floor(ppPctVal * 100)
                local ppSuffix = (s.powerShowPercent == false) and "" or "%"
                local ppCurFake = mod.AbbreviateNumbers(18200)
                local ppTxt
                if ppFmt == "custom" then
                    ppTxt = PreviewTextForContent("custom", s, "powerText")
                elseif ppFmt == "smart" then
                    ppTxt = ppPctRaw .. ppSuffix -- preview always shows percent for smart
                elseif ppFmt == "curpp" then
                    ppTxt = ppCurFake
                elseif ppFmt == "curmaxpp" then
                    ppTxt = ppCurFake .. " / " .. mod.AbbreviateNumbers(22000)
                elseif ppFmt == "both" then
                    ppTxt = ppCurFake .. " | " .. ppPctRaw .. ppSuffix
                else -- "perpp"
                    ppTxt = ppPctRaw .. ppSuffix
                end
                ppPreviewFS:SetText(ppTxt)
                if s.powerPercentTextPowerColor then
                    -- CUI global power color (player's current power) as the swatch
                    -- and real frame use, not hardcoded blue.
                    local _, pToken = UnitPowerType("player")
                    local details = CludesUI.GetPowerColor(pToken or "MANA")
                    if details then
                        ppPreviewFS:SetTextColor(details.r, details.g, details.b)
                    else
                        ppPreviewFS:SetTextColor(1, 1, 1)
                    end
                else
                    local ptc = s.powerTextColor
                    if ptc then
                        ppPreviewFS:SetTextColor(ptc.r, ptc.g, ptc.b)
                    else
                        ppPreviewFS:SetTextColor(1, 1, 1)
                    end
                end
                ppPreviewFS:Show()
            else
                ppPreviewFS:Hide()
            end
        end

        if portraitFrame then
            if sp then
                if not portraitFrame:IsShown() then
                    portraitFrame:Show()
                end
                if portraitFrame._applyMode then
                    portraitFrame._applyMode()
                end
                ApplyPreviewPortraitShape(portraitFrame, s)
                -- Portrait Dragon (player, target, focus; any shape, attached
                -- or detached, never a stock style): the live helper at the
                -- preview's strata, the enemy frames showing the gold sample.
                -- It reaches past the frame, so the preview stops clipping.
                local pvDragon = not blizzG
                    and (unitKey == "player" or unitKey == "target" or unitKey == "focus")
                    and mod.UF_DragonSettings(unitKey, s)
                if pvDragon and pvDragon.on then
                    local dt =
                        mod.UF_PortraitDragon(portraitFrame, pvDragon, (unitKey == "player") ~= pvDragon.flip)
                    if dt then
                        dt:Show()
                        portraitFrame:SetClipsChildren(false)
                    end
                else
                    mod.UF_PortraitDragon(portraitFrame, nil)
                end
            else
                if portraitFrame:IsShown() then
                    portraitFrame:Hide()
                    portraitFrame._anchored = false
                end
            end
        end

        -- Bottom Text Bar update (before castbar so castbar can anchor to it)
        local cbOff = 0
        if sp and isAttached and sideName == "right" then
            cbOff = pw / 2
        elseif sp and isAttached and sideName == "left" then
            cbOff = -(pw / 2)
        end
        local btbPos = s.btbPosition or "bottom"
        local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
        if btbFrame then
            local btbH2 = s.bottomTextBarHeight or 16
            if s.bottomTextBar then
                local btbIsDetached = not btbIsAtt
                local btbW2 = btbIsDetached and (s.btbWidth or 0) or 0
                local btbTW = (btbW2 > 0 and btbIsDetached) and btbW2 or tw
                Pix.Size(btbFrame, btbTW, btbH2)
                if btbIsDetached and saved.profile.enableCustomBarStratas then
                    btbFrame:SetFrameLevel(popFrame:GetFrameLevel() + 50)
                elseif btbIsDetached then
                    btbFrame:SetFrameLevel(popFrame:GetFrameLevel() + 3)
                end
                btbFrame:ClearAllPoints()
                local btbPvAnchor = (pvPpIsAtt and power and power:IsShown()) and power or healthBar
                if btbPos == "top" then
                    Pix.Point(btbFrame, "BOTTOM", healthBar, "TOP", cbOff, 0)
                elseif btbPos == "detached_top" then
                    btbFrame:SetPoint("BOTTOM", popFrame, "TOP", s.btbX or 0, 15 + (s.btbY or 0))
                elseif btbPos == "detached_bottom" then
                    btbFrame:SetPoint("TOP", popFrame, "BOTTOM", s.btbX or 0, -15 + (s.btbY or 0))
                else
                    Pix.Point(btbFrame, "TOP", btbPvAnchor, "BOTTOM", cbOff, 0)
                end
                local bgc = s.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
                local bga = s.btbBgOpacity or 1.0
                btbBg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
                ApplyBTBPreviewTexts(s)
                if not btbFrame:IsShown() then
                    btbFrame:Show()
                end
            else
                if btbFrame:IsShown() then
                    btbFrame:Hide()
                end
            end
        end

        if castBar then
            if ch > 0 then
                -- Cast icon "part of the bar": narrow + shift the bar so the icon
                -- sits inside the width; off = full width, icon hangs outside.
                local ciInWidth = mod.UF_CastIconInWidth(unitKey, s)
                local ciOnRight, ciOffX, ciOffY
                if unitKey == "player" then
                    ciOnRight = s.playerCastbarIconRight == true
                    ciOffX = s.playerCastIconOffsetX or 0
                    ciOffY = s.playerCastIconOffsetY or 0
                else
                    ciOnRight = s.castbarIconRight == true
                    ciOffX = s.castIconOffsetX or 0
                    ciOffY = s.castIconOffsetY or 0
                end
                local ciIconW = ch
                -- Boss castbarWidth > 0 overrides the frame-matched width, clamped
                -- to tw + 120 (see the creation-time note).
                local cbBaseW = tw
                if unitKey == "boss" and (s.castbarWidth or 0) > 0 then
                    cbBaseW = math.min(math.max(s.castbarWidth, 30), tw + 120)
                end
                local ciBarW = ciInWidth and math.max(1, cbBaseW - ciIconW) or cbBaseW
                castBar:SetSize(ciBarW, ch)
                -- Authoritative anchoring happens once below (handles the BTB /
                -- attached-power cases plus the icon-in-width shift).
                castBar:Show()
                -- Re-apply bg color/alpha so Bar Background updates live.
                if castBar._previewBgTex then
                    local cbgC = s.castBgColor
                    -- Textured Background, as live (never over the stock cast art).
                    local cbPath = mod.UF_TexBgCastPath(
                        s,
                        s.healthBarTexture or saved.profile.healthBarTexture or "none",
                        CludesUI.BlizzStyle.Active("unitframes") == "blizzard"
                    )
                    mod.UF_TexBgPaint(
                        castBar._previewBgTex,
                        cbPath,
                        cbgC and cbgC.r or 0,
                        cbgC and cbgC.g or 0,
                        cbgC and cbgC.b or 0,
                        s.castBgAlpha or 0.5
                    )
                end
                if castFill then
                    castFill:ClearAllPoints()
                    if s.castReverseFill then
                        Pix.Point(castFill, "TOPRIGHT", castBar, "TOPRIGHT", -1, 0)
                        Pix.Point(castFill, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", -1, 1)
                    else
                        Pix.Point(castFill, "TOPLEFT", castBar, "TOPLEFT", 1, 0)
                        Pix.Point(castFill, "BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
                    end
                    castFill:SetWidth(
                        math.floor(math.max(0, ciBarW - 2) * (optionState._previewCastFill or 0.6) + 0.5)
                    )
                    -- Update fill color from per-unit settings (class colored only for player)
                    local fillC
                    if unitKey == "player" and s.castbarClassColored then
                        local _, classToken = UnitClass("player")
                        if classToken then
                            fillC = RAID_CLASS_COLORS[classToken]
                        end
                    end
                    if not fillC then
                        fillC = s.castbarFillColor
                    end
                    -- Cast fill reuses the unit's health bar texture unless the cast
                    -- bars carry one of their own (matches real frames).
                    -- WHITE8X8 fallback ensures PV_FillColor always sets vertex color fresh.
                    local cbTexKey = s.healthBarTexture or saved.profile.healthBarTexture or "none"
                    local ownCb = saved.profile.castBarTexture
                    if ownCb and ownCb ~= "inherit" then
                        cbTexKey = ownCb
                    end
                    local cbTexPath = (mod.healthBarTextures or {})[cbTexKey]
                        or "Interface\\Buttons\\WHITE8X8"
                    local fc = fillC or saved.profile.castbarColor or { r = 0.114, g = 0.655, b = 0.514 }
                    PV_FillColor(castFill, cbTexPath, fc.r, fc.g, fc.b, nil, nil, nil, 1)
                    -- The "Blizzard" fill is the vanilla cast bar's own art, tinted.
                    if cbTexKey == "blizzard" then
                        castFill:SetAtlas("UI-CastingBar-Fill", true)
                    end
                end
                if castIconFrame then
                    castIconFrame:SetSize(ch, ch)
                    castIconFrame:ClearAllPoints()
                    if ciOnRight then
                        Pix.Point(castIconFrame, "TOPLEFT", castBar, "TOPRIGHT", ciOffX, ciOffY)
                    else
                        Pix.Point(castIconFrame, "TOPRIGHT", castBar, "TOPLEFT", ciOffX, ciOffY)
                    end
                    local showIcon
                    if unitKey == "player" then
                        showIcon = s.showPlayerCastIcon ~= false
                    else
                        showIcon = s.showCastIcon ~= false
                    end
                    if showIcon then
                        castIconFrame:Show()
                    else
                        castIconFrame:Hide()
                    end
                    if castIconFrame._iconTex then
                        local spellIcon = (unitKey == "player")
                                and (optionState._previewCastSpell and optionState._previewCastSpell.icon or 136197)
                            or 136197
                        castIconFrame._iconTex:SetTexture(spellIcon)
                    end
                end
                -- Side-aware three-zone layout as on the live cast bar; name and
                -- duration apply to every unit, player has no target zone.
                local pvNameSide = s.castSpellNameSide or "left"
                local pvTgtSide = s.castSpellTargetSide or "right"
                local pvDurSide = s.castDurationSide or "right"
                local showDur = s.showCastDuration ~= false
                local showTgt = s.showCastTarget ~= false
                local pvBarW = castBar:GetWidth()
                local pvHasW = pvBarW and pvBarW > 0
                local pvTimerW = (s.castDurationSize or 10) * 2.2
                local pvTextW = pvHasW and (pvBarW * 0.42) or 0
                if castNameFS2 then
                    local spellName = (unitKey == "player")
                            and (optionState._previewCastSpell and optionState._previewCastSpell.name or "Spell Name")
                        or "Spell Name"
                    castNameFS2:SetText(spellName)
                    SetPVFont(castNameFS2, PREVIEW_FONT, s.castSpellNameSize or 11)
                    local snC = s.castSpellNameColor or { r = 1, g = 1, b = 1 }
                    castNameFS2:SetTextColor(snC.r, snC.g, snC.b)
                    castNameFS2:ClearAllPoints()
                    if pvNameSide == "none" then
                        castNameFS2:Hide()
                    elseif pvHasW then
                        local pt, xb, jh = mod.GetCastTextAnchor(
                            pvNameSide,
                            showDur and pvDurSide == pvNameSide,
                            pvTimerW,
                            false
                        )
                        castNameFS2:SetWidth(pvTextW)
                        castNameFS2:SetJustifyH(jh)
                        castNameFS2:SetPoint(
                            pt,
                            castBar,
                            pt,
                            xb + (s.castSpellNameX or 0),
                            1 + (s.castSpellNameY or 0)
                        )
                        castNameFS2:Show()
                    end
                end
                if castTimeFS then
                    local spCastTime = (
                        optionState._previewCastSpell and optionState._previewCastSpell.castTime
                    ) or 3.0
                    castTimeFS:SetText(
                        string.format("%.1f", spCastTime * (1 - (optionState._previewCastFill or 0.6)))
                    )
                    SetPVFont(castTimeFS, PREVIEW_FONT, s.castDurationSize or 10)
                    local dtC = s.castDurationColor or { r = 1, g = 1, b = 1 }
                    castTimeFS:SetTextColor(dtC.r, dtC.g, dtC.b)
                    castTimeFS:SetShown(showDur)
                    if pvHasW then
                        local pt, xb, jh = mod.GetCastTextAnchor(pvDurSide, false, pvTimerW, true)
                        castTimeFS:SetWidth(pvTimerW)
                        castTimeFS:SetJustifyH(jh)
                        castTimeFS:ClearAllPoints()
                        castTimeFS:SetPoint(
                            pt,
                            castBar,
                            pt,
                            xb + (s.castDurationX or 0),
                            (s.castDurationY or 0)
                        )
                    end
                end
                if castTargetFS then
                    SetPVFont(castTargetFS, PREVIEW_FONT, s.castSpellTargetSize or 11)
                    local tsC = s.castSpellTargetColor or { r = 1, g = 1, b = 1 }
                    castTargetFS:SetTextColor(tsC.r, tsC.g, tsC.b)
                    castTargetFS:SetShown(showTgt)
                    if pvHasW then
                        local pt, xb, jh = mod.GetCastTextAnchor(
                            pvTgtSide,
                            showDur and pvDurSide == pvTgtSide,
                            pvTimerW,
                            false
                        )
                        castTargetFS:SetWidth(pvTextW)
                        castTargetFS:SetJustifyH(jh)
                        castTargetFS:ClearAllPoints()
                        castTargetFS:SetPoint(
                            pt,
                            castBar,
                            pt,
                            xb + (s.castSpellTargetX or 0),
                            (s.castSpellTargetY or 0)
                        )
                    end
                end
                -- Re-flow so a live JustifyH change takes effect on already-rendered text.
                if castNameFS2 then
                    mod.ReflowFontString(castNameFS2)
                end
                if castTimeFS then
                    mod.ReflowFontString(castTimeFS)
                end
                if castTargetFS then
                    mod.ReflowFontString(castTargetFS)
                end
                castBar:ClearAllPoints()
                local pvBtbVisible = (btbFrame and s.bottomTextBar and btbPos == "bottom")
                local cbAnchorFrame = pvBtbVisible and btbFrame
                    or ((pvPpIsAtt and power and power:IsShown()) and power or healthBar)
                local cbAnchorOff = pvBtbVisible and 0 or cbOff
                -- Icon-in-width: shift the narrowed bar half an icon width toward
                -- the icon-free side (left icon -> right, right icon -> left) so the
                -- footprint stays flush under the frame, as on the real frame.
                Pix.Point(
                    castBar,
                    "TOP",
                    cbAnchorFrame,
                    "BOTTOM",
                    cbAnchorOff + (ciInWidth and (ciOnRight and -(ciIconW / 2) or (ciIconW / 2)) or 0),
                    0
                )
            else
                castBar:Hide()
                if castIconFrame then
                    castIconFrame:Hide()
                end
            end
        end

        -- Border size and color (encompasses health+power+BTB+above pips); a mini
        -- frame's Border Size override replaces the donor's size, as live.
        local bs = s.borderSizeOverride or bds.borderSize or 1
        local bc = bds.borderColor or { r = 0, g = 0, b = 0 }
        local bTexKey = bds.borderTexture or "solid"
        local borderH = bh2 + (s.bottomTextBar and btbIsAtt and (s.bottomTextBarHeight or 16) or 0)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
        border:SetHeight(borderH)
        CludesUI.ApplyBorderStyle(
            border,
            bs,
            bc.r,
            bc.g,
            bc.b,
            bds.borderAlpha or 1,
            bTexKey,
            bds.borderTextureOffset,
            bds.borderTextureOffsetY,
            bds.borderTextureShiftX,
            bds.borderTextureShiftY,
            "unitframes",
            bs,
            nil,
            CludesUI.BorderPx((not s.borderSizeOverride) and bds.borderSizePx, bs, bTexKey)
        )

        -- Class Power Pips update (player only)
        if cpPipContainer and cpPips then
            if cpStyle == "modern" then
                local cpPos = s.classPowerPosition or "top"
                local cpMax = #cpPips
                local cpSizeAdj = s.classPowerSize or 8
                local cpSpacingAdj = s.classPowerSpacing or 2
                local pipW = cpSizeAdj
                local pipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                local pipGap = cpSpacingAdj

                local cpBgCol = s.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
                if cpPipContainer._bgTex then
                    cpPipContainer._bgTex:SetColorTexture(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                end

                cpPipContainer:ClearAllPoints()
                if cpPos == "above" then
                    -- Flush with the health bar edges; Snap() rounds every position
                    -- to physical pixel boundaries so pip gaps are identical.
                    local efs = cpPipContainer:GetEffectiveScale()
                    if efs <= 0 then
                        efs = 1
                    end
                    local function Snap(val)
                        return math.floor(val * efs + 0.5) / efs
                    end
                    local intW = math.floor(fw)
                    -- Pip boundaries: n pips with (n-1) snapped gaps of pipGap.
                    local gapPx = Snap(pipGap)
                    local totalGapW = (cpMax - 1) * gapPx
                    local totalPipW = intW - totalGapW
                    local basePipW = totalPipW / cpMax
                    cpPipContainer:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
                    cpPipContainer:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
                    cpPipContainer:SetHeight(pipH)
                    for idx = 1, cpMax do
                        -- Snap pip i's proportional left/right edges.
                        local leftEdge = Snap((idx - 1) * (basePipW + gapPx))
                        local rightEdge = Snap((idx - 1) * (basePipW + gapPx) + basePipW)
                        local wid = rightEdge - leftEdge
                        cpPips[idx]:ClearAllPoints()
                        cpPips[idx]:SetSize(wid, pipH)
                        cpPips[idx]:SetPoint("TOPLEFT", cpPipContainer, "TOPLEFT", leftEdge, 0)
                        cpPips[idx]:Show()
                    end
                else
                    -- "top" / "bottom" floating, pixel-perfect sizing
                    local efs = cpPipContainer:GetEffectiveScale()
                    if efs <= 0 then
                        efs = 1
                    end
                    local function Snap(val)
                        return math.floor(val * efs + 0.5) / efs
                    end
                    local snappedW = Snap(pipW)
                    local snappedH = Snap(pipH)
                    local snappedGap = Snap(pipGap)
                    local totalPipW = cpMax * snappedW + (cpMax - 1) * snappedGap
                    Pix.Size(cpPipContainer, totalPipW, snappedH)
                    if cpPos == "top" then
                        local cpXOff = s.classPowerBarX or 0
                        local cpYOff = s.classPowerBarY or 0
                        Pix.Point(cpPipContainer, "BOTTOM", healthBar, "TOP", cpXOff, cpYOff)
                    else
                        local cpXOff = s.classPowerBarX or 0
                        local cpYOff = s.classPowerBarY or 0
                        local cpBaseY = -1
                        if cpYOff == 0 and castBar and ch > 0 and s.showPlayerCastbar then
                            cpBaseY = -1 - ch
                        end
                        -- Blizzard Style: live measures from the stock box's
                        -- bottom (barArea here), whatever hangs under the art.
                        Pix.Point(
                            cpPipContainer,
                            "TOP",
                            blizzG and barArea or popFrame,
                            "BOTTOM",
                            cpXOff,
                            cpBaseY + cpYOff
                        )
                    end
                    local posX = 0
                    for idx = 1, cpMax do
                        cpPips[idx]:ClearAllPoints()
                        cpPips[idx]:SetSize(snappedW, snappedH)
                        cpPips[idx]:SetPoint("TOPLEFT", cpPipContainer, "TOPLEFT", Snap(posX), 0)
                        cpPips[idx]:Show()
                        posX = posX + snappedW + snappedGap
                    end
                end
                -- 1px bottom border on pip container (only for "above" position)
                if cpPipContainer._bottomBdr then
                    if cpPos == "above" then
                        cpPipContainer._bottomBdr:SetColorTexture(bc.r, bc.g, bc.b, 1)
                        cpPipContainer._bottomBdr:Show()
                    else
                        cpPipContainer._bottomBdr:Hide()
                    end
                end
                -- Re-color pips based on class color toggle
                local _, cpPlayerClass = UnitClass("player")
                local cpUseCC = s.classPowerClassColor ~= false
                local cpCr, cpCg, cpCb
                if not cpUseCC then
                    local cc = s.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
                    cpCr, cpCg, cpCb = cc.r, cc.g, cc.b
                else
                    local rc = CludesUI.GetResourceColor(cpPlayerClass)
                    if rc then
                        cpCr, cpCg, cpCb = rc.r, rc.g, rc.b
                    else
                        local cc = CludesUI.GetClassColor(cpPlayerClass)
                        if cc then
                            cpCr, cpCg, cpCb = cc.r, cc.g, cc.b
                        else
                            cpCr, cpCg, cpCb = 1, 0.84, 0.30
                        end
                    end
                end
                local cpEmptyCol = s.classPowerEmptyColor or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }
                local previewFilled = math.min(3, cpMax)
                for idx = 1, cpMax do
                    if idx <= previewFilled then
                        cpPips[idx]:SetColorTexture(cpCr, cpCg, cpCb, 1)
                        cpPips[idx]:SetAlpha(1)
                    else
                        cpPips[idx]:SetColorTexture(cpEmptyCol.r, cpEmptyCol.g, cpEmptyCol.b, cpEmptyCol.a)
                        cpPips[idx]:SetAlpha(1)
                    end
                end
                cpPipContainer:Show()
                if popFrame._cpPipOv then
                    popFrame._cpPipOv:Show()
                end
            else
                cpPipContainer:Hide()
                for idx = 1, #cpPips do
                    cpPips[idx]:Hide()
                end
                if popFrame._cpPipOv then
                    popFrame._cpPipOv:Hide()
                end
            end
        end

        -- Absorb bars (player/target/focus): the Heal Absorb Style eyeball
        -- replaces the shield absorb with the heal absorb. Both honor their
        -- placement cog (absorbEdgeMode / healAbsorbEdgeMode).
        local _healPrev = optionState.showHealAbsorbPreview
        -- Only replace when there IS a heal absorb to show; with style "none"
        -- keep the shield preview instead of blanking the absorb area.
        local _healWillShow = _healPrev and (s.healAbsorbStyle or "clean") ~= "none"
        if absorbBar then
            local absS = s.showPlayerAbsorb
            if (not _healWillShow) and absS and absS ~= "none" then
                local _paTex = {
                    striped = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga",
                    stripedReversed = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-5-reversed.png",
                    clean = "Interface\\Buttons\\WHITE8X8",
                    blizzard = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\blizzard.tga",
                    largeOutlinedStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-left.png",
                    largeOutlinedStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-right.png",
                    largeStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-left.png",
                    largeStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-right.png",
                }
                local _paAlpha = {
                    striped = 0.8,
                    stripedReversed = 0.8,
                    clean = (s.absorbCleanAlpha or 30) / 100,
                    blizzard = 0.8,
                }
                -- Effective opacity/color: mirrors GetAbsorbOpacity in CUI_UnitFrames_Absorb.lua
                local _paA = s.absorbOpacity and (s.absorbOpacity / 100) or _paAlpha[absS] or 0.8
                local _paC = s.absorbColor or { r = 1, g = 1, b = 1 }
                absorbBar:SetStatusBarTexture(mod.ResolveAbsorbStyleTex(absS, _paTex.striped))
                local _paFill = absorbBar:GetStatusBarTexture()
                if _paFill then
                    _paFill:SetDrawLayer("ARTWORK", 1)
                    local _paTiled = (mod.ABSORB_TILED_STYLES[absS] == true)
                    _paFill:SetHorizTile(_paTiled)
                    _paFill:SetVertTile(_paTiled)
                end
                absorbBar:SetStatusBarColor(_paC.r, _paC.g, _paC.b, _paA)
                PositionPreviewAbsorb(
                    absorbBar,
                    s.absorbEdgeMode or "overlay",
                    s.healthReverseFill,
                    s.healthVerticalFill
                )
                absorbBar:SetWidth(fw)
                absorbBar:SetHeight(hh)
                absorbBar:Show()
                -- Blizzard Glow Line: the preview shield never reaches current
                -- health, so only the seam placements draw it (Overlay and
                -- Overlay Reverse), on the fill's inner end. Built on first use;
                -- a child of the bar, so it hides with it.
                local pvGl = popFrame._pvGlowLine
                local glEm = s.absorbEdgeMode or "overlay"
                if
                    s.absorbGlowLine == true
                    and not s.healthVerticalFill
                    and (glEm == "overlay" or glEm == "overlayReverse" or glEm == "overlayReverseFull")
                then
                    if not pvGl then
                        pvGl = absorbBar:CreateTexture(nil, "OVERLAY")
                        popFrame._pvGlowLine = pvGl
                    end
                    local glArt = mod.UF_GLOW_LINE_ART[s.absorbGlowLineTexture]
                        or mod.UF_GLOW_LINE_ART.blizzard
                    pvGl:SetTexture(glArt[1])
                    pvGl:SetBlendMode(glArt[2])
                    pvGl:SetSize(mod.UF_GlowLineWidth(glArt), hh)
                    local glRev = s.healthReverseFill and true or false
                    pvGl:ClearAllPoints()
                    pvGl:SetPoint(
                        "CENTER",
                        absorbBar:GetStatusBarTexture(),
                        glRev and "RIGHT" or "LEFT",
                        glRev and 1 or -1,
                        0
                    )
                    pvGl:Show()
                elseif pvGl then
                    pvGl:Hide()
                end
            else
                absorbBar:Hide()
            end
        end
        if healAbsorbBar then
            local haS = s.healAbsorbStyle or "clean"
            if _healPrev and haS ~= "none" then
                local _haA = (s.healAbsorbOpacity or 65) / 100
                local _haC = s.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
                if haS == "largeOutlinedStripes" or haS == "largeOutlinedStripesR" then
                    _haC = { r = 1, g = 1, b = 1 }
                end
                healAbsorbBar:SetStatusBarTexture(
                    mod.ResolveAbsorbStyleTex(haS, "Interface\\Buttons\\WHITE8X8")
                )
                local _haFill = healAbsorbBar:GetStatusBarTexture()
                if _haFill then
                    _haFill:SetDrawLayer("ARTWORK", 2)
                    local _haTiled = (mod.ABSORB_TILED_STYLES[haS] == true)
                    _haFill:SetHorizTile(_haTiled)
                    _haFill:SetVertTile(_haTiled)
                end
                healAbsorbBar:SetStatusBarColor(_haC.r or 0.8, _haC.g or 0.15, _haC.b or 0.15, _haA)
                PositionPreviewAbsorb(
                    healAbsorbBar,
                    s.healAbsorbEdgeMode or "overlay",
                    s.healthReverseFill,
                    s.healthVerticalFill
                )
                healAbsorbBar:SetWidth(fw)
                healAbsorbBar:SetHeight(hh)
                healAbsorbBar:Show()
                if healAbsorbBar._bg then
                    healAbsorbBar._bg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 15) / 100)
                    healAbsorbBar._bg:SetAllPoints(healAbsorbBar:GetStatusBarTexture())
                    healAbsorbBar._bg:Show()
                end
            else
                healAbsorbBar:Hide()
            end
        end
        local mhPv = popFrame._pvMaxHp
        if mhPv then
            local mhS = s.maxHealthStyle or "none"
            if optionState.showMaxHealthPreview and mhS ~= "none" and mod.UF_ApplyMaxHealthStyle then
                mod.UF_ApplyMaxHealthStyle(mhPv, mhS, s)
                mod.UF_OrientMaxHealth(mhPv, s.healthReverseFill, s.healthVerticalFill)
                mhPv:Show()
            else
                mhPv:Hide()
            end
        end

        -- Heal prediction eyeball: shows the two segments (and hides the shield
        -- absorb, like the heal absorb eyeball). The incoming total fills most
        -- of the missing health, or runs past the bar's end by the full
        -- Overheal allowance when that is set.
        if popFrame._pvPredMy then
            if mod._ufShowHealPredPreview and s.healPrediction == true then
                local over = (tonumber(s.healPredOverheal) or 0) / 100
                local missing = 1 - (optionState._previewHealthPct or 0.70)
                local sum = (over > 0) and (missing + over) or (missing * 0.85)
                local alpha = (s.healPredOpacity or 60) / 100
                local mc = s.healPredColor
                    or mod.UF_HEAL_PRED_MY
                    or { r = 102 / 255, g = 243 / 255, b = 102 / 255 }
                local oc = s.healPredOtherColor
                    or mod.UF_HEAL_PRED_OTHER
                    or { r = 40 / 255, g = 170 / 255, b = 40 / 255 }
                popFrame._pvPredHolder:SetClipsChildren(over == 0)
                -- Texture as render resolves it; Health Bar reads the unit's health texture key.
                local texKey = s.healPredTexture or "health"
                if texKey == "health" then
                    texKey = mod.ResolveHealthBarTextureKey and mod.ResolveHealthBarTextureKey(s) or "none"
                end
                local texPath = (texKey ~= "flat")
                        and CludesUI.ResolveTexturePath(mod.healthBarTextures, texKey, nil)
                    or "Interface\\Buttons\\WHITE8X8"
                for _, e in ipairs({
                    { popFrame._pvPredOther, oc, sum },
                    { popFrame._pvPredMy, mc, sum * 0.55 },
                }) do
                    local barFrame, c, val = e[1], e[2], e[3]
                    barFrame:SetStatusBarTexture(texPath)
                    barFrame:SetStatusBarColor(c.r, c.g, c.b, alpha)
                    PositionPreviewAbsorb(barFrame, "forward", s.healthReverseFill, s.healthVerticalFill)
                    barFrame:SetWidth(fw)
                    barFrame:SetHeight(hh)
                    barFrame:SetValue(val)
                    barFrame:Show()
                end
                if absorbBar then
                    absorbBar:Hide()
                end
            else
                popFrame._pvPredOther:Hide()
                popFrame._pvPredMy:Hide()
            end
        end

        -- Absorb / Heal Absorb strips: independent of the overlay styles,
        -- anchored to the preview health bar.
        local _absStripHp = absorbBar and absorbBar:GetParent()
        if absorbTopBar and _absStripHp then
            local place = s.absorbBarPosition or "none"
            if place ~= "none" then
                local bc = s.absorbBarColor or { r = 1, g = 1, b = 1 }
                mod.UF_ApplyStripBarLayout(
                    absorbTopBar,
                    _absStripHp,
                    place,
                    s.absorbBarHeight or 4,
                    _absStripHp:GetFrameLevel() + 1
                )
                absorbTopBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                absorbTopBar:Show()
            else
                absorbTopBar:Hide()
            end
        end
        if healAbsorbTopBar and _absStripHp then
            local place = s.healAbsorbBarPosition or "none"
            if place ~= "none" then
                local hbc = s.healAbsorbBarColor or { r = 200 / 255, g = 29 / 255, b = 29 / 255 }
                mod.UF_ApplyStripBarLayout(
                    healAbsorbTopBar,
                    _absStripHp,
                    place,
                    s.healAbsorbBarHeight or 4,
                    _absStripHp:GetFrameLevel() + 1,
                    s.absorbBarPosition or "none",
                    s.absorbBarHeight or 4
                )
                healAbsorbTopBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                healAbsorbTopBar:Show()
            else
                healAbsorbTopBar:Hide()
            end
        end

        if dispelOverlayPreview then
            local modeName = saved.profile.dispelOverlay or "none"
            if optionState.showDispelOverlayPreview and modeName ~= "none" then
                local c = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                local alpha = (saved.profile.dispelOverlayOpacity or 100) / 100
                dispelOverlayPreview:ClearAllPoints()
                dispelOverlayPreview:SetVertexColor(1, 1, 1, 1)
                dispelOverlayPreview:SetTexCoord(0, 1, 0, 1)
                if modeName == "full" then
                    dispelOverlayPreview:SetAllPoints(healthBar)
                    dispelOverlayPreview:SetColorTexture(c.r, c.g, c.b, alpha)
                elseif
                    modeName == "gradient"
                    or modeName == "gradient_sharp"
                    or modeName == "gradient_reverse"
                then
                    dispelOverlayPreview:SetAllPoints(healthBar)
                    dispelOverlayPreview:SetTexture(
                        modeName == "gradient"
                                and "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
                            or "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"
                    )
                    if modeName == "gradient_reverse" then
                        dispelOverlayPreview:SetTexCoord(0, 1, 1, 0)
                    end
                    dispelOverlayPreview:SetVertexColor(c.r, c.g, c.b, alpha)
                else
                    dispelOverlayPreview:SetAllPoints(healthFill)
                    dispelOverlayPreview:SetColorTexture(c.r, c.g, c.b, alpha)
                end
                dispelOverlayPreview:Show()
            else
                dispelOverlayPreview:Hide()
            end
            -- Color Custom Borders: the eye also shows the Magic copy of the
            -- frame border, drawn over the preview border in its own style.
            -- Built on first use; overlay None still previews it.
            local cbPv = popFrame._pvDispelBorder
            if
                optionState.showDispelOverlayPreview
                and saved.profile.dispelCustomBorder == true
                and mod.UF_CustomBorderOn(s)
            then
                if not cbPv then
                    cbPv = CreateFrame("Frame", nil, popFrame)
                    cbPv:SetAllPoints(border)
                    popFrame._pvDispelBorder = cbPv
                end
                local mc = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                local cbs, cbt = s.borderSize or 1, s.borderTexture
                cbPv:SetFrameLevel(border:GetFrameLevel() + 1)
                CludesUI.ApplyBorderStyle(
                    cbPv,
                    cbs,
                    mc.r,
                    mc.g,
                    mc.b,
                    1,
                    cbt,
                    s.borderTextureOffset,
                    s.borderTextureOffsetY,
                    s.borderTextureShiftX,
                    s.borderTextureShiftY,
                    "unitframes",
                    cbs,
                    nil,
                    CludesUI.BorderPx(s.borderSizePx, cbs, cbt)
                )
                cbPv:Show()
            elseif cbPv then
                cbPv:Hide()
            end
            -- Type Icon Position: the eye also shows the Magic type icon on its
            -- corner of the health bar, over the border (runtime twin:
            -- ApplyDispelSlotStyle). Built on first use.
            local tiPv = popFrame._pvDispelIcon
            local dp = saved.profile
            if optionState.showDispelOverlayPreview and dp.showDispelIcons == true then
                if not tiPv then
                    tiPv = CreateFrame("Frame", nil, popFrame)
                    local texture = tiPv:CreateTexture(nil, "ARTWORK")
                    texture:SetAllPoints(tiPv)
                    texture:SetAtlas("RaidFrame-Icon-DebuffMagic")
                    popFrame._pvDispelIcon = tiPv
                end
                local sz = dp.dispelIconSize or 16
                local corner = (dp.dispelIconPosition or "right"):upper()
                tiPv:SetFrameLevel(border:GetFrameLevel() + 2)
                tiPv:SetSize(sz, sz)
                tiPv:ClearAllPoints()
                tiPv:SetPoint(corner, healthBar, corner, dp.dispelIconOffsetX or 0, dp.dispelIconOffsetY or 0)
                tiPv:Show()
            elseif tiPv then
                tiPv:Hide()
            end
            -- Growth Direction: Poison and Bleed icons follow Magic along the row, as live.
            local grow = dp.dispelIconGrowth or "none"
            local growOn = tiPv and tiPv:IsShown() and grow ~= "none"
            local extra = popFrame._pvDispelIconRow
            if growOn and not extra then
                extra = {}
                local atlases = { "RaidFrame-Icon-DebuffPoison", "RaidFrame-Icon-DebuffBleed" }
                for idx = 1, #atlases do
                    local f = CreateFrame("Frame", nil, popFrame)
                    local texture = f:CreateTexture(nil, "ARTWORK")
                    texture:SetAllPoints(f)
                    texture:SetAtlas(atlases[idx])
                    extra[idx] = f
                end
                popFrame._pvDispelIconRow = extra
            end
            if extra then
                local sz = dp.dispelIconSize or 16
                local step = sz + CludesUI.PP.FromPixels(1)
                local dx = (grow == "left" and -step) or (grow == "right" and step) or 0
                local dy = (grow == "down" and -step) or (grow == "up" and step) or 0
                for idx = 1, #extra do
                    local f = extra[idx]
                    if growOn then
                        f:SetFrameLevel(tiPv:GetFrameLevel())
                        f:SetSize(sz, sz)
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", tiPv, "CENTER", dx * idx, dy * idx)
                        f:Show()
                    else
                        f:Hide()
                    end
                end
            end
        end

        -- Buff icons -- reposition based on anchor/growth/size/offset settings
        local buffExtra = 0
        -- Blizzard Style: how far a bottom-anchored stack reaches below the
        -- art (nil = not a bottom stack); the cast bar hangs under the
        -- lowest one.
        local buffDrop, debuffDrop
        -- Vertical overflow (px) reserved when a Y offset pushes auras past their
        -- footprint; feeds the dynamic header below so the preview grows instead
        -- of icons spilling onto neighboring options.
        local auraTopOv, auraBotOv = 0, 0
        if #buffIcons > 0 then
            -- Boss Simple Buff Display forces one Left/Right column matched to the
            -- frame height (mirrors the live runtime override).
            local simpleBuffMode = (unitKey == "boss") and mod.GetBossSimpleBuffMode(s) or "none"
            local simpleBuffOn = simpleBuffMode ~= "none"
            local maxBuf = s.maxBuffs or 4
            local visibleBuffCount = math.min(2, maxBuf)
            -- Boss preview always shows exactly 2 buffs regardless of Max Count.
            if unitKey == "boss" then
                visibleBuffCount = math.min(#buffIcons, 2)
            end
            local showB = simpleBuffOn or (s.showBuffs and (s.buffAnchor or "topleft") ~= "none")
            if showB and visibleBuffCount > 0 then
                local buffSize = s.buffSize or 22
                if simpleBuffOn then
                    local pvPowerPos = s.powerPosition or "below"
                    local pvPowerIsAtt = (pvPowerPos == "below" or pvPowerPos == "above")
                    local pvPowerH = pvPowerIsAtt and (s.powerHeight or 0) or 0
                    buffSize = (s.healthHeight or 34) + pvPowerH
                end
                -- Crop never applies in simple mode (runtime parity).
                local buffCrop = (not simpleBuffOn) and (as.buffCropIcons or false) or false
                local buffH = mod.GetAuraCropHeight(buffCrop, buffSize)
                -- Boss spacing from its slider (simple display has its own key);
                -- other units keep the 1px schematic gap.
                local buffGapX = (unitKey == "boss") and mod.GetBossBuffSpacing(s, simpleBuffOn)
                    or (s.buffSpacingX or 1)
                local buffGapY = (unitKey == "boss") and mod.GetBossBuffSpacing(s, simpleBuffOn)
                    or (s.buffSpacingY or 1)
                local bOffX = s.buffOffsetX or 0
                -- Preview mirrors the real frame's Y offset; the header below
                -- reserves room so offset auras never overflow.
                local bOffY = s.buffOffsetY or 0
                -- Simple mode has its own X/Y offsets (falling back to the regular
                -- buff offsets) to match the live column.
                if simpleBuffOn then
                    bOffX, bOffY = mod.GetBossSimpleBuffOffset(s)
                end
                -- Cap the preview's Y offset so it can't over-expand the preview.
                bOffY = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, bOffY))
                local ba = simpleBuffOn and simpleBuffMode or (s.buffAnchor or "topleft")
                local backdrop = s.buffGrowth or "auto"

                -- Determine growth direction for icon 2 placement
                local autoGrowth = {
                    topleft = "right",
                    topright = "left",
                    bottomleft = "right",
                    bottomright = "left",
                    left = "left",
                    right = "right",
                }
                local gDir = (backdrop == "auto") and (autoGrowth[ba] or "right") or backdrop

                -- Anchor point on pf and offset for first icon
                local anchorMap = {
                    topleft = { pt = "TOPLEFT", ox = bOffX, oy = buffGapY + bOffY },
                    topright = {
                        pt = "TOPRIGHT",
                        ox = bOffX,
                        oy = buffGapY + bOffY,
                    },
                    bottomleft = {
                        pt = "BOTTOMLEFT",
                        ox = bOffX,
                        oy = -(buffH + buffGapY) + bOffY,
                    },
                    bottomright = {
                        pt = "BOTTOMRIGHT",
                        ox = bOffX,
                        oy = -(buffH + buffGapY) + bOffY,
                    },
                    left = { pt = "LEFT", ox = -buffGapX + bOffX, oy = bOffY },
                    right = { pt = "RIGHT", ox = buffGapX + bOffX, oy = bOffY },
                }
                local am = anchorMap[ba] or anchorMap.topleft
                if blizzG then
                    popFrame._blizzInset(am, ba, blizzG, blizzMirror)
                end

                -- Growth offset for icon 2 relative to icon 1
                local dx, dy = 0, 0
                if gDir == "right" then
                    dx = buffSize + buffGapX
                elseif gDir == "left" then
                    dx = -(buffSize + buffGapX)
                elseif gDir == "up" then
                    dy = buffH + buffGapY
                elseif gDir == "down" then
                    dy = -(buffH + buffGapY)
                else
                    dx = buffSize + buffGapX
                end

                -- Determine justifyH for SetPoint (which corner of the icon anchors)
                local justH = "BOTTOMLEFT"
                if ba == "topright" or ba == "bottomright" then
                    justH = "BOTTOMRIGHT"
                elseif ba == "left" then
                    justH = "RIGHT"
                elseif ba == "right" then
                    justH = "LEFT"
                end

                -- Boss Simple Buff Display: anchor the column to the health bar's
                -- top (not pf, which includes the cast bar) so icons align with the
                -- bar area, matching the runtime layout.
                local useSimpleBossAnchor = simpleBuffOn
                local bossSimpleAnchorFrame = useSimpleBossAnchor and healthBar or popFrame
                local simpleIconPt = (simpleBuffMode == "right") and "TOPLEFT" or "TOPRIGHT"
                local simpleParentPt = (simpleBuffMode == "right") and "TOPRIGHT" or "TOPLEFT"
                local simpleEdgeSign = (simpleBuffMode == "right") and 1 or -1

                -- Cache key so we reanchor only on real anchor changes: ClearAllPoints
                -- + SetPoint leaves a one-frame gap that blinks the icons. Show()/Hide()
                -- are guarded too -- Show() on a visible frame re-renders (shutter).
                local anchorKey = justH
                    .. am.pt
                    .. am.ox
                    .. am.oy
                    .. dx
                    .. dy
                    .. buffSize
                    .. buffH
                    .. (useSimpleBossAnchor and "S" or "N")
                    .. simpleBuffMode
                    .. bOffX
                    .. "gx"
                    .. buffGapX
                    .. "gy"
                    .. buffGapY
                for idx, bf in ipairs(buffIcons) do
                    if idx <= visibleBuffCount then
                        if bf._anchorKey ~= anchorKey then
                            Pix.Size(bf, buffSize, buffH)
                            bf:ClearAllPoints()
                            if idx == 1 then
                                if useSimpleBossAnchor then
                                    Pix.Point(
                                        bf,
                                        simpleIconPt,
                                        bossSimpleAnchorFrame,
                                        simpleParentPt,
                                        simpleEdgeSign * buffGapX + bOffX,
                                        bOffY
                                    )
                                else
                                    -- Left/Right center on barArea only, not pf (which
                                    -- includes the cast bar), as on the real frames.
                                    Pix.Point(
                                        bf,
                                        justH,
                                        (ba == "left" or ba == "right") and barArea or popFrame,
                                        am.pt,
                                        am.ox,
                                        am.oy
                                    )
                                end
                            else
                                if useSimpleBossAnchor then
                                    Pix.Point(
                                        bf,
                                        simpleIconPt,
                                        buffIcons[1],
                                        simpleIconPt,
                                        simpleEdgeSign * (idx - 1) * (buffSize + buffGapX),
                                        0
                                    )
                                else
                                    Pix.Point(bf, justH, buffIcons[1], justH, dx * (idx - 1), dy * (idx - 1))
                                end
                            end
                            bf._anchorKey = anchorKey
                        end
                        if not bf:IsShown() then
                            bf:Show()
                        end
                        if bf._iconTex then
                            bf._iconTex:SetTexture(_previewBuffIcons[idx] or 135932)
                            -- SetTexture resets texcoord, so re-apply the crop each update.
                            mod.SetAuraIconCrop(
                                bf._iconTex,
                                buffCrop,
                                buffSize,
                                buffH,
                                as.buffIconZoom or 0.07
                            )
                        end
                        if idx == 1 then
                            mod.UFOpt_PreviewPurgeGlow(bf, unitKey, s, buffSize, buffH)
                        end
                    else
                        if bf:IsShown() then
                            bf:Hide()
                        end
                    end
                end

                -- Reserve buff height only for top/bottom anchors; Left/Right
                -- columns grow sideways and need no vertical room.
                if ba == "topleft" or ba == "topright" or ba == "bottomleft" or ba == "bottomright" then
                    buffExtra = buffH + buffGapY + 2
                end
                -- The stack's lowest visible icon edge below the art (a
                -- downward column adds its rows), for the cast bar under it.
                if ba == "bottomleft" or ba == "bottomright" then
                    buffDrop = buffH + buffGapY - bOffY
                    if gDir == "down" then
                        buffDrop = buffDrop + (visibleBuffCount - 1) * (buffH + buffGapY)
                    end
                end
                -- Reserve Y-offset overflow beyond that footprint: top anchors push
                -- up, bottom push down; side anchors have none, so all of it counts.
                if ba == "topleft" or ba == "topright" then
                    if bOffY > 0 then
                        auraTopOv = auraTopOv + bOffY
                    end
                elseif ba == "bottomleft" or ba == "bottomright" then
                    if bOffY < 0 then
                        auraBotOv = auraBotOv - bOffY
                    end
                else
                    if bOffY > 0 then
                        auraTopOv = auraTopOv + bOffY
                    elseif bOffY < 0 then
                        auraBotOv = auraBotOv - bOffY
                    end
                end
            else
                for _, bf in ipairs(buffIcons) do
                    if bf:IsShown() then
                        bf:Hide()
                    end
                end
            end
        end

        -- Debuff icons -- reposition per anchor/growth/size/offset. Boss Simple
        -- Debuff Display forces Left anchor + frame-height-matched size; must
        -- match the live runtime override.
        local debuffExtra = 0
        if #debuffIcons > 0 and not noDebuffPreview then
            local dAnc = s.debuffAnchor or "bottomleft"
            local effectiveDebuffSize = s.debuffSize or 22
            local simpleMode = (unitKey == "boss") and mod.GetBossSimpleDebuffMode(s) or "none"
            local simpleOn = simpleMode ~= "none"
            if simpleOn then
                dAnc = simpleMode -- "left" or "right"
                local pvPowerPos = s.powerPosition or "below"
                local pvPowerIsAtt = (pvPowerPos == "below" or pvPowerPos == "above")
                local pvPowerH = pvPowerIsAtt and (s.powerHeight or 0) or 0
                effectiveDebuffSize = (s.healthHeight or 34) + pvPowerH
            end
            local maxDeb = s.maxDebuffs or 10
            local previewDebuffLimit = 5
            local visibleDebuffCount = math.min(#debuffIcons, maxDeb, previewDebuffLimit)
            -- Boss preview always shows exactly 3 debuffs regardless of Max Count.
            if unitKey == "boss" then
                visibleDebuffCount = math.min(#debuffIcons, 3)
            end
            if dAnc ~= "none" and visibleDebuffCount > 0 then
                local debuffSize = effectiveDebuffSize
                -- Crop never applies in simple boss mode (runtime passes nil crop
                -- and frame-height-matches those icons).
                local debuffCrop = (not simpleOn) and (as.debuffCropIcons or false) or false
                local debuffH = mod.GetAuraCropHeight(debuffCrop, debuffSize)
                -- Boss spacing from its slider (simple display has its own key);
                -- other units keep the 1px schematic gap.
                local debuffGapX = (unitKey == "boss") and mod.GetBossDebuffSpacing(s, simpleOn)
                    or (s.debuffSpacingX or 1)
                local debuffGapY = (unitKey == "boss") and mod.GetBossDebuffSpacing(s, simpleOn)
                    or (s.debuffSpacingY or 1)
                local dOffX = s.debuffOffsetX or 0
                -- Preview mirrors the real frame's Y offset; the header below
                -- reserves room so offset auras never overflow.
                local dOffY = s.debuffOffsetY or 0
                -- Simple mode has its own X/Y offsets (falling back to the regular
                -- debuff offsets) to match the live column.
                if simpleOn then
                    dOffX, dOffY = mod.GetBossSimpleDebuffOffset(s)
                end
                -- Cap the preview's Y offset so it can't over-expand the preview.
                dOffY = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, dOffY))
                local dg = s.debuffGrowth or "auto"

                local autoGrowth = {
                    topleft = "right",
                    topright = "left",
                    bottomleft = "right",
                    bottomright = "left",
                    left = "left",
                    right = "right",
                }
                local gDir = (dg == "auto") and (autoGrowth[dAnc] or "right") or dg

                local anchorMap = {
                    topleft = {
                        pt = "TOPLEFT",
                        ox = dOffX,
                        oy = debuffGapY + dOffY,
                    },
                    topright = {
                        pt = "TOPRIGHT",
                        ox = dOffX,
                        oy = debuffGapY + dOffY,
                    },
                    bottomleft = {
                        pt = "BOTTOMLEFT",
                        ox = dOffX,
                        oy = -(debuffH + debuffGapY) + dOffY,
                    },
                    bottomright = {
                        pt = "BOTTOMRIGHT",
                        ox = dOffX,
                        oy = -(debuffH + debuffGapY) + dOffY,
                    },
                    left = { pt = "LEFT", ox = -debuffGapX + dOffX, oy = dOffY },
                    right = { pt = "RIGHT", ox = debuffGapX + dOffX, oy = dOffY },
                }
                local am = anchorMap[dAnc] or anchorMap.bottomleft
                if blizzG then
                    popFrame._blizzInset(am, dAnc, blizzG, blizzMirror)
                end

                local dx, dy = 0, 0
                if gDir == "right" then
                    dx = debuffSize + debuffGapX
                elseif gDir == "left" then
                    dx = -(debuffSize + debuffGapX)
                elseif gDir == "up" then
                    dy = debuffH + debuffGapY
                elseif gDir == "down" then
                    dy = -(debuffH + debuffGapY)
                else
                    dx = debuffSize + debuffGapX
                end

                local justH = "BOTTOMLEFT"
                if dAnc == "topright" or dAnc == "bottomright" then
                    justH = "BOTTOMRIGHT"
                elseif dAnc == "left" then
                    justH = "RIGHT"
                elseif dAnc == "right" then
                    justH = "LEFT"
                end

                -- Boss Simple Debuff Display: anchor the stack to the health bar's
                -- top (not pf, which includes the cast bar) so icons align with the
                -- bar area, matching the runtime layout.
                local useSimpleBossAnchor = simpleOn
                local bossSimpleAnchorFrame = useSimpleBossAnchor and healthBar or popFrame
                -- Simple mode side: Left pins the column to the frame's left edge
                -- (icons grow left), Right pins to the right edge (icons grow right).
                local simpleIconPt = (simpleMode == "right") and "TOPLEFT" or "TOPRIGHT"
                local simpleParentPt = (simpleMode == "right") and "TOPRIGHT" or "TOPLEFT"
                local simpleEdgeSign = (simpleMode == "right") and 1 or -1
                local anchorKey = justH
                    .. am.pt
                    .. am.ox
                    .. am.oy
                    .. dx
                    .. dy
                    .. debuffSize
                    .. debuffH
                    .. (useSimpleBossAnchor and "S" or "N")
                    .. simpleMode
                    .. dOffX
                    .. "gx"
                    .. debuffGapX
                    .. "gy"
                    .. debuffGapY
                    .. "z"
                    .. (as.debuffIconZoom or 0.07)
                for idx, df in ipairs(debuffIcons) do
                    if idx <= visibleDebuffCount then
                        if df._anchorKey ~= anchorKey then
                            Pix.Size(df, debuffSize, debuffH)
                            if df._iconTex then
                                mod.SetAuraIconCrop(
                                    df._iconTex,
                                    debuffCrop,
                                    debuffSize,
                                    debuffH,
                                    as.debuffIconZoom or 0.07
                                )
                            end
                            df:ClearAllPoints()
                            if idx == 1 then
                                if useSimpleBossAnchor then
                                    Pix.Point(
                                        df,
                                        simpleIconPt,
                                        bossSimpleAnchorFrame,
                                        simpleParentPt,
                                        simpleEdgeSign * debuffGapX + dOffX,
                                        dOffY
                                    )
                                else
                                    -- Left/Right center on barArea only, not pf (which
                                    -- includes the cast bar), as on the real frames.
                                    Pix.Point(
                                        df,
                                        justH,
                                        (dAnc == "left" or dAnc == "right") and barArea or popFrame,
                                        am.pt,
                                        am.ox,
                                        am.oy
                                    )
                                end
                            else
                                if useSimpleBossAnchor then
                                    Pix.Point(
                                        df,
                                        simpleIconPt,
                                        debuffIcons[1],
                                        simpleIconPt,
                                        simpleEdgeSign * (idx - 1) * (debuffSize + debuffGapX),
                                        0
                                    )
                                else
                                    Pix.Point(
                                        df,
                                        justH,
                                        debuffIcons[1],
                                        justH,
                                        dx * (idx - 1),
                                        dy * (idx - 1)
                                    )
                                end
                            end
                            df._anchorKey = anchorKey
                        end
                        if not df:IsShown() then
                            df:Show()
                        end
                    else
                        if df:IsShown() then
                            df:Hide()
                        end
                    end
                end

                -- Reserve debuff height only for top/bottom anchors; Left/Right
                -- columns grow sideways and need no vertical room.
                local debuffGap2 = 1
                if
                    dAnc == "topleft"
                    or dAnc == "topright"
                    or dAnc == "bottomleft"
                    or dAnc == "bottomright"
                then
                    debuffExtra = debuffH + debuffGap2 + 2
                end
                -- The stack's lowest visible icon edge below the art (a
                -- downward column adds its rows), for the cast bar under it.
                if dAnc == "bottomleft" or dAnc == "bottomright" then
                    debuffDrop = debuffH + debuffGapY - dOffY
                    if gDir == "down" then
                        debuffDrop = debuffDrop + (visibleDebuffCount - 1) * (debuffH + debuffGapY)
                    end
                end
                -- Reserve Y-offset overflow beyond the footprint (see the buff block).
                if dAnc == "topleft" or dAnc == "topright" then
                    if dOffY > 0 then
                        auraTopOv = auraTopOv + dOffY
                    end
                elseif dAnc == "bottomleft" or dAnc == "bottomright" then
                    if dOffY < 0 then
                        auraBotOv = auraBotOv - dOffY
                    end
                else
                    if dOffY > 0 then
                        auraTopOv = auraTopOv + dOffY
                    elseif dOffY < 0 then
                        auraBotOv = auraBotOv - dOffY
                    end
                end
            else
                for _, df in ipairs(debuffIcons) do
                    if df:IsShown() then
                        df:Hide()
                    end
                end
            end
        end

        -- Fake static cooldown swipe + duration/stack text on the boss debuff
        -- preview icons (mirrors the live boss aura buttons); sizing and visibility
        -- follow the boss aura settings so those controls live-update here.
        do
            local showExtras = (unitKey == "boss") and not noDebuffPreview
            local showCDText, cdTextSize, cdTOffX, cdTOffY, stackTextSize, stackTextPosition, stackTOffX, stackTOffY, cdTextColor, stackTextColor
            if showExtras then
                if mod.GetBossSimpleDebuffMode(s) ~= "none" then
                    showCDText = s.simpleDebuffShowCooldownText
                    cdTextSize = s.simpleDebuffCooldownTextSize or 14
                    cdTOffX = s.simpleDebuffCooldownTextOffsetX or 0
                    cdTOffY = s.simpleDebuffCooldownTextOffsetY or 0
                else
                    showCDText = s.debuffShowCooldownText
                    cdTextSize = s.debuffCooldownTextSize or 10
                    cdTOffX = s.debuffCooldownTextOffsetX or 0
                    cdTOffY = s.debuffCooldownTextOffsetY or 0
                end
                stackTextSize = s.debuffStackTextSize or 14
                stackTextPosition = s.debuffStackTextPosition or "bottomright"
                stackTOffX = s.debuffStackTextOffsetX or 0
                stackTOffY = s.debuffStackTextOffsetY or 0
                cdTextColor = s.debuffCooldownTextColor or { r = 1, g = 1, b = 1 }
                stackTextColor = s.debuffStackTextColor or { r = 1, g = 1, b = 1 }
            end
            local fontP = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
            for idx = 1, #debuffIcons do
                local df = debuffIcons[idx]
                local cd, dt, st = df._previewCD, df._durText, df._stackText
                if showExtras and df:IsShown() then
                    if cd and not cd:IsShown() then
                        cd:Show()
                    end
                    if dt then
                        if showCDText then
                            CludesUI.ApplyIconTextFont(dt, fontP, cdTextSize, "unitFrames")
                            dt:ClearAllPoints()
                            dt:SetPoint("CENTER", df, "CENTER", cdTOffX, cdTOffY)
                            dt:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)
                            dt:Show()
                        else
                            dt:Hide()
                        end
                    end
                    -- Stack text on one icon only (most debuffs are unstacked);
                    -- icon 2 matches the in-game preview.
                    if st then
                        if idx == 2 then
                            CludesUI.ApplyIconTextFont(st, fontP, stackTextSize, "unitFrames")
                            st:SetText(3)
                            mod.ApplyStackAnchor(st, df, stackTextPosition, stackTOffX, stackTOffY)
                            st:SetTextColor(stackTextColor.r, stackTextColor.g, stackTextColor.b)
                            st:Show()
                        else
                            st:Hide()
                        end
                    end
                else
                    if cd then
                        cd:Hide()
                    end
                    if dt then
                        dt:Hide()
                    end
                    if st then
                        st:Hide()
                    end
                end
            end
        end

        local btbExtra = (btbFrame and s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
        local th = bh2 + btbExtra + (ch > 0 and ch or 0)
        -- Blizzard Style: the visible art (its transparent rows trimmed) plus
        -- the cast bar strip (no text bar) -- unless the bar hangs below the
        -- auras, when the strip is reserved under them instead (auraExtra).
        if blizzG then
            local pad = blizzG.pad
            th = blizzG.h - (pad and (pad.top + pad.bottom) or 0)
            if ch > 0 then
                cbStrip = ch
                -- The stock text box hangs 13px under the cast bar: reserve
                -- it so the content header below does not overlap it.
                local UFC = mod.UF_CAST_BLIZZ
                if
                    UFC
                    and not mod.UF_BLIZZ.cast
                    and mod.UF_BlizzAtlas(UFC.textbox)
                    and (s.castSpellNameSide or "left") ~= "none"
                then
                    cbStrip = cbStrip + 13
                end
                if not blizzBelow then
                    th = th + cbStrip
                end
            end
        end
        popFrame:SetSize(tw, th)

        -- Apply preview scale; shrink to fit when the frame is wider than the panel
        local baseScale = popFrame._previewScale or 1
        local fitScale = 1
        do
            local PAD = CludesUI.CONTENT_PAD or 10
            local availW = (popFrame:GetParent():GetWidth() - PAD * 2) / baseScale
            if tw > availW and tw > 0 and availW > 0 then
                fitScale = availW / tw
            end
        end
        local combinedScale = baseScale * fitScale
        popFrame:SetScale(combinedScale)

        -- Recalculate border sizes after scale change so they stay pixel-perfect
        if border then
            local bs2 = s.borderSizeOverride or bds.borderSize or 1
            local bTex2 = bds.borderTexture or "solid"
            CludesUI.ApplyBorderStyle(
                border,
                bs2,
                (bds.borderColor or { r = 0, g = 0, b = 0 }).r,
                (bds.borderColor or { r = 0, g = 0, b = 0 }).g,
                (bds.borderColor or { r = 0, g = 0, b = 0 }).b,
                bds.borderAlpha or 1,
                bTex2,
                bds.borderTextureOffset,
                bds.borderTextureOffsetY,
                bds.borderTextureShiftX,
                bds.borderTextureShiftY,
                "unitframes",
                bs2,
                nil,
                CludesUI.BorderPx((not s.borderSizeOverride) and bds.borderSizePx, bs2, bTex2)
            )
        end
        -- Rounded corners, as on the live frame: the border frame is the shape
        -- (health + power + attached portrait and text bar); the fill sits on
        -- pf, under the bars. The portrait joins with its own art only.
        do
            local radius = (not ResolveBlizzPreview(unitKey, s) and bds.cornerRadius) or 0
            local det = pvPpPos == "detached_top" or pvPpPos == "detached_bottom"
            local corners, pCorners = bds.cornerMask, bds.cornerMask
            if det and s.cornerJoinPower then
                local upper, lower = CludesUI.RoundedJoinCorners(corners)
                if pvPpPos == "detached_bottom" then
                    corners, pCorners = upper, lower
                else
                    corners, pCorners = lower, upper
                end
            end
            if radius > 0 then
                local port = sp and isAttached and portraitFrame and portraitFrame:IsShown() and portraitFrame
                    or nil
                CludesUI.RoundCorners(popFrame, radius, {
                    roots = {
                        healthBar,
                        (pvPpPos == "below" or pvPpPos == "above") and power or nil,
                        s.bottomTextBar and btbIsAtt and btbFrame or nil,
                    },
                    textures = { port and port._previewBg, port and port._previewTex },
                    border = border,
                    rect = border,
                    style = bds.borderTexture or "solid",
                    corners = corners,
                })
            else
                CludesUI.RoundCorners(popFrame, 0)
            end
            if power then
                if det and radius > 0 then
                    CludesUI.RoundCorners(power, radius, {
                        border = power._pbBorder,
                        style = s.powerBorderStyle or "solid",
                        corners = pCorners,
                    })
                else
                    CludesUI.RoundCorners(power, 0)
                end
            end
        end
        if castBar then
            if Pix.GetBorders(castBar) then
                Pix.SetBorderSize(castBar, 1)
            end
            if castFill then
                castFill:ClearAllPoints()
                Pix.Point(castFill, "TOPLEFT", castBar, "TOPLEFT", 1, 0)
                Pix.Point(castFill, "BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
            end
        end
        if castIconFrame then
            Pix.SetBorderSize(castIconFrame, 1)
            if castIconFrame._iconTex then
                castIconFrame._iconTex:ClearAllPoints()
                Pix.Point(castIconFrame._iconTex, "TOPLEFT", castIconFrame, "TOPLEFT", 1, -1)
                Pix.Point(castIconFrame._iconTex, "BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", -1, 1)
            end
            -- Show Icon on Portrait: the icon rides the preview portrait
            -- through the live helper (nil hands it back to the bar).
            mod.UF_CastIconPortraitLayout(
                castIconFrame,
                castIconFrame._iconTex,
                (portraitFrame and mod.UF_CastIconOnPortrait(unitKey, s)) and portraitFrame or nil,
                s
            )
        end
        -- Share border geometry, icon decoration and seam cleanup with live
        -- frames, after the scale and portrait placement have been applied
        -- (preview: its divider stays off the UI-scale re-layout list).
        if castBar then
            mod.UF_ApplyCastBorder(
                castBar,
                s,
                CludesUI.BlizzStyle.Get("unitframes"),
                unitKey,
                castIconFrame,
                true
            )
        end

        -- Re-apply PixelUtil sizing to every element so it stays pixel-perfect at
        -- the new scale, starting with the preview frame itself.
        Pix.Size(popFrame, tw, th)
        local snappedFrameW = popFrame:GetWidth()
        local snappedFrameH = popFrame:GetHeight()

        -- Re-snap portrait
        if portraitFrame and sp and isAttached then
            Pix.Size(portraitFrame, portraitDim, portraitDim)
            local snappedPortW = portraitFrame:GetWidth()
            local snappedPortH = portraitFrame:GetHeight()
            if snappedPortW + fw > snappedFrameW + 0.01 then
                portraitFrame:SetWidth(snappedFrameW - fw)
            end
            if snappedPortH > snappedFrameH + 0.01 then
                portraitFrame:SetHeight(snappedFrameH)
            end
        end

        -- Re-snap health bar
        if healthBar then
            Pix.Size(healthBar, fw, hh)
            local snappedHealthW = healthBar:GetWidth()
            local availW = snappedFrameW
            if portraitFrame and sp and isAttached then
                availW = snappedFrameW - portraitFrame:GetWidth()
            end
            if snappedHealthW > availW + 0.01 then
                healthBar:SetWidth(availW)
            end
        end

        -- Re-snap power bar
        if power and power:IsShown() then
            local pvPw2 = fw
            local pvPpIsDet2 = (pvPpPos == "detached_top" or pvPpPos == "detached_bottom")
            if pvPpIsDet2 and (s.powerWidth or 0) > 0 then
                pvPw2 = s.powerWidth
            end
            Pix.Size(power, pvPw2, ph)
            if pvPpIsAtt and healthBar then
                -- Height: ensure health + power don't exceed expected total
                local snappedHH = healthBar:GetHeight()
                local snappedPH = power:GetHeight()
                local expectedTotal = hh + ph
                if snappedHH + snappedPH > expectedTotal + 0.01 then
                    power:SetHeight(snappedPH - (snappedHH + snappedPH - expectedTotal))
                end
                -- Width: match health bar width exactly
                local snappedHealthW2 = healthBar:GetWidth()
                local snappedPowerW2 = power:GetWidth()
                if math.abs(snappedPowerW2 - snappedHealthW2) > 0.01 then
                    power:SetWidth(snappedHealthW2)
                end
            end
        end
        -- Power Bar Seam: the live helper on the preview bar (preview = true:
        -- this panel repaints itself on a scale change).
        if power then
            mod.UpdatePowerSeam(power, s, CludesUI.BlizzStyle.Get("unitframes"), true)
        end
        if s.portraitSeparator or popFrame._portraitSeparator then
            mod.UpdatePortraitSeparator(
                popFrame,
                portraitFrame,
                s,
                effectiveSide,
                sp and isAttached,
                CludesUI.BlizzStyle.Get("unitframes"),
                true,
                (unitKey == "targettarget" or unitKey == "boss") and bds or nil
            )
        end
        -- Color Custom Borders: while the Magic border copy shows, both
        -- separators are tinted Magic at full opacity in place, as the live
        -- copies draw them (the two passes above reset the border colour
        -- first), so the preview does not depend on copy-frame draw order
        -- inside the options panel.
        if popFrame._pvDispelBorder and popFrame._pvDispelBorder:IsShown() then
            local mc = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
            local pSeam, vSeam = power and power._pbSeam, popFrame._portraitSeparator
            if pSeam and pSeam:IsShown() then
                pSeam._tex:SetVertexColor(mc.r, mc.g, mc.b, 1)
            end
            if vSeam and vSeam:IsShown() then
                vSeam._tex:SetVertexColor(mc.r, mc.g, mc.b, 1)
            end
        end

        -- Re-snap BTB
        if btbFrame and s.bottomTextBar and btbIsAtt then
            Pix.Size(btbFrame, tw, s.bottomTextBarHeight or 16)
            local snappedBtbW = btbFrame:GetWidth()
            local snappedBtbH = btbFrame:GetHeight()
            -- Width: trim to frame width
            if snappedBtbW > snappedFrameW + 0.01 then
                btbFrame:SetWidth(snappedFrameW)
            end
            -- Height: ensure full stack fits within frame height
            local usedH = cpAboveH
            if healthBar then
                usedH = usedH + healthBar:GetHeight()
            end
            if power and pvPpIsAtt and power:IsShown() then
                usedH = usedH + power:GetHeight()
            end
            if usedH + snappedBtbH > snappedFrameH + 0.01 then
                btbFrame:SetHeight(snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
            end
        end

        -- Re-snap castbar width, but never trim boss custom widths (castbarWidth
        -- > 0): they are deliberately off-frame and already clamped at sizing
        -- time, so trimming would silently revert them to frame width.
        if castBar then
            local pvCbCustom = unitKey == "boss" and (s.castbarWidth or 0) > 0
            local cbW = castBar:GetWidth()
            if not pvCbCustom and cbW > snappedFrameW + 0.01 then
                castBar:SetWidth(snappedFrameW)
            end
        end

        -- Blizzard Style: the stock look over everything laid out above.
        -- The cast bar hangs under the lowest bottom-anchored stack (live:
        -- the aura block's bottom): merged buffs ride the debuff anchor, so
        -- that stack decides; else a bottom debuff stack wins over a bottom
        -- buff stack; nothing below = flush with the art.
        local stackDrop = 0
        if blizzBelow then
            local merged = s.debuffAnchorBuffs == true and (s.debuffAnchor or "none") ~= "none"
            if merged then
                if debuffDrop then
                    stackDrop = debuffDrop
                end
            elseif debuffDrop then
                stackDrop = debuffDrop
            elseif buffDrop then
                stackDrop = buffDrop
            end
        end
        if blizzG then
            popFrame._blizzApply(s, blizzG, blizzMirror, blizzExtras, ch, stackDrop)
        end
        -- Spell cost preview: a third of the fill as the stock styles left it.
        if popFrame._pvCostSeg and popFrame._pvCostSeg:IsShown() and popFrame._powerFill then
            popFrame._pvCostSeg:SetWidth(math.floor(popFrame._powerFill:GetWidth() / 3 + 0.5))
        end

        -- Determine how much extra space buffs/debuffs need above/below the frame
        local auraTopPad = 0 -- extra space above frame (push preview down)
        if buffExtra > 0 then
            local ba2 = s.buffAnchor or "topleft"
            if ba2 == "topleft" or ba2 == "topright" then
                auraTopPad = buffExtra
            end
        end
        if debuffExtra > 0 then
            local da2 = s.debuffAnchor or "bottomleft"
            if da2 == "topleft" or da2 == "topright" then
                auraTopPad = auraTopPad + debuffExtra
            end
        end
        -- Add upward Y-offset overflow so the preview slides down far enough to
        -- fit auras pushed above their footprint (any anchor).
        auraTopPad = auraTopPad + auraTopOv

        -- Extra space above frame for detached-top elements
        local detTopExtra = 0
        -- Detached top portrait (Blizzard Style seats it in the art instead)
        if
            sp
            and not isAttached
            and effectiveSide == "top"
            and not blizzG
            and portraitFrame
            and portraitFrame:IsShown()
        then
            detTopExtra = detTopExtra + portraitDim + 15 + pYOff
        end
        -- Detached top text bar (Blizzard Style has no text bar)
        if btbFrame and s.bottomTextBar and (s.btbPosition or "bottom") == "detached_top" and not blizzG then
            detTopExtra = detTopExtra + (s.bottomTextBarHeight or 16) + 15 + (s.btbY or 0)
        end
        -- Floating "top" class power pips
        if cpTopH > 0 then
            detTopExtra = detTopExtra + cpTopH
        end
        -- WoW Forever pet happiness icon centred above the frame
        if popFrame._happyInd and s.happinessEnabled ~= false and s.happinessAlign == "top" then
            detTopExtra = detTopExtra + math.max(0, (s.happinessSize or 20) + (s.happinessY or 0))
        end
        auraTopPad = auraTopPad + detTopExtra

        -- Reposition pf vertically based on aura padding
        local baseOY = popFrame._headerDropdownOY or 25
        local pfOY = -(baseOY + auraTopPad) / combinedScale
        if popFrame._lastOY ~= pfOY then
            popFrame:ClearAllPoints()
            Pix.Point(popFrame, "TOP", popFrame:GetParent(), "TOP", 0, pfOY)
            popFrame._lastOY = pfOY
        end

        -- Notify UpdateContentHeaderHeight of the height change; it compensates scroll
        -- position so the widget the user is interacting with stays put as the
        -- preview grows/shrinks. auraBotOv clears auras pushed below their footprint.
        local auraExtra = buffExtra + debuffExtra + auraBotOv
        -- Blizzard Style: the cast bar strip under the bottom stacks.
        if blizzBelow then
            auraExtra = auraExtra + cbStrip
        end
        popFrame._buffExtra = auraExtra
        popFrame._detTopExtra = detTopExtra
        local parentTH = th * combinedScale
        local cpBottomScaled = cpBottomH * combinedScale
        -- The preview hint belongs to the Main Frames header, which parents it to
        -- its own preview: only that preview's header makes room for it.
        local hintH = 0
        if
            optionState._ufPreviewHintFS_display
            and optionState._ufPreviewHintFS_display:IsShown()
            and optionState._ufPreviewHintFS_display:GetParent() == popFrame
        then
            hintH = 29
        end
        local fixedH = popFrame._headerFixedH or 0
        if fixedH > 0 then
            -- The preview slid down by auraTopOv, so the section must grow by it
            -- too or it overlaps the next section.
            CludesUI:UpdateContentHeaderHeight(
                fixedH + parentTH + auraExtra + auraTopOv + detTopExtra + cpBottomScaled + hintH
            )
        end
        -- Reposition segmented pill below the preview when height changes
        if popFrame._segFrame then
            local pillY = -(
                baseOY
                + parentTH
                + auraExtra
                + auraTopOv
                + detTopExtra
                + cpBottomScaled
                + (popFrame._segGap or 20)
            )
            Pix.Point(popFrame._segFrame, "TOP", popFrame:GetParent(), "TOP", 0, pillY)
        end

        -- Combat indicator preview
        if combatInd then
            if
                optionState.showCombatIndicatorPreview
                and s.combatIndicatorStyle
                and s.combatIndicatorStyle ~= "none"
            then
                local ciStyle = s.combatIndicatorStyle or "class"
                local ciColor = s.combatIndicatorColor or "custom"
                local ciSz = s.combatIndicatorSize or 22
                local ciOx = s.combatIndicatorX or 0
                local ciOy = s.combatIndicatorY or 0
                local ciPos = s.combatIndicatorPosition or "healthbar"
                combatInd:SetSize(ciSz, ciSz)
                combatInd:ClearAllPoints()
                -- "healthbar" is the stored value labeled "Center" in the dropdown;
                -- "center" is a render alias for it. Portrait follows the live
                -- rule (ns.UF_PortraitShown): a stock style (blizzG) always
                -- shows its portrait, whatever Portrait Mode says.
                if ciPos == "portrait" and portraitFrame and (sp or blizzG) then
                    combatInd:SetPoint("CENTER", portraitFrame, "CENTER", ciOx, ciOy)
                elseif ciPos == "textbar" then
                    combatInd:SetPoint("CENTER", btbFrame or popFrame, "CENTER", ciOx, ciOy)
                elseif ciPos == "healthbar" or ciPos == "center" then
                    combatInd:SetPoint("CENTER", healthBar, "CENTER", ciOx, ciOy)
                else
                    local anchorFrame = (ciPos == "topright" and "TOPRIGHT")
                        or (ciPos == "bottomleft" and "BOTTOMLEFT")
                        or (ciPos == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    combatInd:SetPoint(anchorFrame, healthBar, anchorFrame, ciOx, ciOy)
                end
                local _, classToken = UnitClass("player")
                -- Custom combat icons (combat0..5) render untinted; Standard/Class
                -- Theme are tinted by the colour mode below.
                if ciStyle:find("^combat%d") then
                    combatInd:SetTexture(COMBAT_MEDIA_P .. ciStyle .. ".tga")
                    combatInd:SetTexCoord(0, 1, 0, 1)
                    if combatInd.SetDesaturated then
                        combatInd:SetDesaturated(false)
                    end
                    combatInd:SetVertexColor(1, 1, 1, 1)
                else
                    if ciStyle == "class" then
                        combatInd:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-class-custom.png")
                        local crd = CLASS_FULL_COORDS[classToken]
                        if crd then
                            combatInd:SetTexCoord(crd[1], crd[2], crd[3], crd[4])
                        else
                            combatInd:SetTexCoord(0, 1, 0, 1)
                        end
                    else
                        combatInd:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-custom.png")
                        combatInd:SetTexCoord(0, 1, 0, 1)
                    end
                    if ciColor == "classcolor" then
                        local cc = RAID_CLASS_COLORS[classToken] or { r = 1, g = 1, b = 1 }
                        combatInd:SetVertexColor(cc.r, cc.g, cc.b, 1)
                    elseif ciColor == "custom" then
                        local cc = s.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                        combatInd:SetVertexColor(cc.r or 1, cc.g or 1, cc.b or 1, 1)
                    else
                        combatInd:SetVertexColor(1, 1, 1, 1)
                    end
                end
                combatInd:Show()
            else
                combatInd:Hide()
            end
        end
        -- Faction indicator preview, behind its row's eye toggle: your own faction
        -- on the player frame, the other faction on the target frame (what
        -- Opposite Faction shows).
        if factionInd then
            local fMode = s.factionIndicatorMode or "off"
            local fEye = mod._ufPvEyes and mod._ufPvEyes.faction
            if (unitKey == "player" or unitKey == "target") and fMode ~= "off" and fEye then
                local mine = UnitFactionGroup("player")
                local fac = mine
                if unitKey == "target" then
                    fac = (mine == "Horde") and "Alliance" or "Horde"
                end
                if fac ~= "Horde" and fac ~= "Alliance" then
                    fac = "Horde"
                end
                local fSz = s.factionIndicatorSize or 18
                local fPos = s.factionIndicatorPosition or "topright"
                local fOx, fOy = s.factionIndicatorX or 0, s.factionIndicatorY or 0
                local fStyle = s.factionIndicatorStyle or "pvp"
                -- The preview shows your own badge on both frames.
                CludesUI.SetFactionArt(factionInd, fStyle, fac, CludesUI.FactionBadgeFor(fStyle, "player"))
                factionInd:SetSize(fSz, fSz)
                factionInd:ClearAllPoints()
                if fPos == "portrait" and portraitFrame and (sp or blizzG) then
                    factionInd:SetPoint("CENTER", portraitFrame, "CENTER", fOx, fOy)
                else
                    local anchorFrame = (fPos == "topleft" and "TOPLEFT")
                        or (fPos == "bottomleft" and "BOTTOMLEFT")
                        or (fPos == "bottomright" and "BOTTOMRIGHT")
                        or "TOPRIGHT"
                    factionInd:SetPoint(anchorFrame, popFrame, anchorFrame, fOx, fOy)
                end
                factionInd:Show()
            else
                factionInd:Hide()
            end
        end
        -- Raid marker / leader / elite previews, shown by their rows' eye toggles
        -- (and only while the indicator itself is on). Placement mirrors the
        -- live frames: raid marker centred on a frame corner, the other two on
        -- a health-bar corner or the portrait.
        do
            local eyes = mod._ufPvEyes or {}
            local isPT = unitKey == "player" or unitKey == "target"
            local function PlaceCorner(texture, place, ox, oy)
                texture:ClearAllPoints()
                if place == "portrait" and portraitFrame and (sp or blizzG) then
                    texture:SetPoint("CENTER", portraitFrame, "CENTER", ox, oy)
                else
                    local anchorFrame = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    texture:SetPoint(anchorFrame, healthBar, anchorFrame, ox, oy)
                end
            end
            local rt = popFrame._pvRaid
            if rt then
                if isPT and eyes.raid and s.raidMarkerEnabled then
                    local idx = (eyes.raidIndex or 1) - 1
                    local column, rowFrame = idx % 4, math.floor(idx / 4)
                    rt:SetTexCoord(column / 4, (column + 1) / 4, rowFrame / 4, (rowFrame + 1) / 4)
                    local rmSize = s.raidMarkerSize or 28
                    local rmAlign = s.raidMarkerAlign or "right"
                    local anchorFrame = (rmAlign == "left") and "TOPLEFT"
                        or (rmAlign == "center") and "TOP"
                        or "TOPRIGHT"
                    rt:SetSize(rmSize, rmSize)
                    rt:ClearAllPoints()
                    rt:SetPoint("CENTER", popFrame, anchorFrame, s.raidMarkerX or 0, s.raidMarkerY or 0)
                    rt:Show()
                else
                    rt:Hide()
                end
            end
            local lt = popFrame._pvLeader
            if lt then
                if isPT and eyes.leader and s.leaderIndicatorEnabled ~= false then
                    local sz = s.leaderIndicatorSize or 16
                    lt:SetTexture(
                        (mod.UF_LEADER_ART[s.leaderIndicatorStyle] or mod.UF_LEADER_ART.blizzard).leader
                    )
                    lt:SetSize(sz, sz)
                    PlaceCorner(
                        lt,
                        s.leaderIndicatorPosition or "topleft",
                        s.leaderIndicatorX or 0,
                        s.leaderIndicatorY or 0
                    )
                    lt:Show()
                else
                    lt:Hide()
                end
            end
            local et = popFrame._pvElite
            if et then
                -- A "wingless" style reads as off: the Portrait Dragon draws that one.
                if
                    unitKey == "target"
                    and eyes.elite
                    and s.eliteIndicatorEnabled == true
                    and not mod.UF_DragonLegacy(s)
                then
                    if s.eliteIndicatorStyle == "pixelsDragon" and portraitFrame and sp and not blizzG then
                        -- Pixels Dragon (Elite sample) around the portrait, as live
                        -- (the stock styles draw the Badge).
                        local d = portraitFrame:GetHeight() * mod.UF_ELITE_DRAGON_SCALE
                        et:SetTexture(mod.UF_ELITE_DRAGON_ART.elite)
                        et:SetTexCoord(0, 1, 0, 1)
                        et:SetSize(d, d)
                        et:ClearAllPoints()
                        et:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
                    else
                        local sz = s.eliteIndicatorSize or 16
                        -- Clear a dragon style's sheet coords first (SetAtlas
                        -- can keep custom coords, reading them inside the atlas box).
                        et:SetTexCoord(0, 1, 0, 1)
                        et:SetAtlas("nameplates-icon-elite-gold")
                        et:SetSize(sz, sz)
                        PlaceCorner(
                            et,
                            s.eliteIndicatorPosition or "topleft",
                            s.eliteIndicatorX or 0,
                            s.eliteIndicatorY or 0
                        )
                    end
                    et:Show()
                else
                    et:Hide()
                end
            end
        end
        -- Click overlays follow their badges (see the hit-overlay setup).
        if popFrame._badgeOv then
            for texture, shade in pairs(popFrame._badgeOv) do
                shade:SetShown(texture:IsShown())
            end
        end
        -- WoW Forever pet happiness icon: outside the frame's left or right
        -- edge, or centred above it, moved by the offsets (as live).
        if popFrame._happyInd then
            local hInd = popFrame._happyInd
            if s.happinessEnabled ~= false then
                local hSz = s.happinessSize or 20
                local hX, hY = s.happinessX or 0, s.happinessY or 0
                local hAl = s.happinessAlign or "right"
                hInd:SetSize(hSz, hSz)
                hInd:ClearAllPoints()
                if hAl == "left" then
                    hInd:SetPoint("RIGHT", barArea, "LEFT", hX, hY)
                elseif hAl == "top" then
                    hInd:SetPoint("BOTTOM", barArea, "TOP", hX, hY)
                else
                    hInd:SetPoint("LEFT", barArea, "RIGHT", hX, hY)
                end
                hInd:Show()
            else
                hInd:Hide()
            end
        end
        -- Sync disabled overlay AFTER pf is fully sized/positioned
        if not isEnabled then
            SyncDisabledOverlay()
            disabledOverlay:Show()
        end
    end

    -- Store element references for hit overlay system
    popFrame._health = healthBar
    popFrame._power = power
    popFrame._castbar = castBar
    popFrame._castIconFrame = castIconFrame
    popFrame._castNameFS = castNameFS2
    popFrame._castTimeFS = castTimeFS
    popFrame._castTargetFS = castTargetFS
    popFrame._nameFS = leftFS
    popFrame._hpFS = rightFS
    popFrame._centerFS = centerFS
    popFrame._extraFS = extraFS
    popFrame._portraitFrame = portraitFrame
    popFrame._buffIcons = buffIcons
    popFrame._debuffIcons = debuffIcons
    popFrame._barArea = barArea
    popFrame._textOverlay = textOverlay
    popFrame._btbFrame = btbFrame
    popFrame._btbBg = btbBg
    popFrame._btbLeftFS = btbLeftFS
    popFrame._btbRightFS = btbRightFS
    popFrame._btbCenterFS = btbCenterFS
    popFrame._btbClassIcon = btbClassIconTex
    popFrame._ppFS = ppPreviewFS
    popFrame._border = border
    popFrame._cpPipContainer = cpPipContainer
    popFrame._cpPips = cpPips
    popFrame._combatIndicator = combatInd
    popFrame._dispelOverlayPreview = dispelOverlayPreview

    popFrame._disabledOverlay = disabledOverlay
    -- Clean up any orphaned preview for this unit key before storing the new one
    -- (a frame dressed again for another unit keeps its overlay for that unit)
    local oldPv = allPreviews[unitKey]
    if oldPv and oldPv ~= popFrame and oldPv._pvUnit == unitKey then
        if oldPv._disabledOverlay then
            oldPv._disabledOverlay:Hide()
        end
    end
    -- Also purge any orphaned previews (parent set to nil by ClearContentHeaderInner)
    -- and every entry whose frame was dressed again for another unit (this one included)
    for k, pv in pairs(allPreviews) do
        if pv and pv._pvUnit ~= k then
            allPreviews[k] = nil
        elseif pv and pv ~= popFrame and not pv:GetParent() then
            if pv._disabledOverlay then
                pv._disabledOverlay:Hide()
            end
            allPreviews[k] = nil
        end
    end
    allPreviews[unitKey] = popFrame
    return popFrame
end
