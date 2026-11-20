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

function mod.UFO_BuildUnitPreview(hostFrame, unitName, side)
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
    -- Paints one preview fill the way the live bars do: a flat tint, or with
    -- the gradient on, the bar colour fading into the gradient colour.
    local GRADIENT_FALLBACK = { r = 0.20, g = 0.20, b = 0.80 }
    local function PV_FillColor(texture, texPath, red, green, blue, useGradient, toColor, direction, alpha)
        if not texture then
            return
        end
        if not useGradient then
            if texPath then
                texture:SetTexture(texPath)
                texture:SetVertexColor(red, green, blue, 1)
            else
                texture:SetColorTexture(red, green, blue, 1)
            end
            return
        end
        local to = toColor or GRADIENT_FALLBACK
        if texPath then
            texture:SetTexture(texPath)
        else
            texture:SetColorTexture(1, 1, 1, 1)
        end
        texture:SetVertexColor(1, 1, 1, 1)
        -- A gradient replaces the region alpha, so Bar Opacity rides both
        -- of its endpoint colours instead.
        local endA = alpha or 1
        texture:SetGradient(
            direction or "HORIZONTAL",
            CreateColor(red, green, blue, endA),
            CreateColor(to.r, to.g, to.b, endA)
        )
    end

    -- The settings table this preview dresses from, read fresh on each call
    -- (a held table goes stale after a profile switch); a unit key this
    -- builder does not know shows the player's.
    local DRESSED_UNITS = {
        player = true,
        target = true,
        focus = true,
        pet = true,
        boss = true,
        targettarget = true,
        focustarget = true,
    }
    local function UnitPrefs()
        return saved.profile[DRESSED_UNITS[unitName] and unitName or "player"]
    end
    local prefs = UnitPrefs()

    side = side or "left"

    -- The live mini frames (ToT, FoT, pet) carry no cast bar, power bar or
    -- debuffs, so neither does their preview. Two exceptions: the pet keeps
    -- its opt-in auras (shown while a Location is picked) and, on WoW
    -- Forever, its power bar in the CludesUI look (a stock style paints its own).
    local isMiniPreview = (unitName == "targettarget" or unitName == "focustarget" or unitName == "pet")
    local petDrawsPower = unitName == "pet" and mod.UF_PetHasPower and not ResolveBlizzPreview(unitName, prefs)
    local noPowerPreview = isMiniPreview and not petDrawsPower
    local noDebuffPreview = isMiniPreview and unitName ~= "pet"
    local noCastbarPreview = isMiniPreview

    local portraitLook = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    local hasPortraitSupport = prefs.showPortrait ~= nil or prefs.portraitMode ~= nil
    local showPortrait = hasPortraitSupport and portraitLook ~= "none" and prefs.showPortrait ~= false
    local frameW, healthH = prefs.frameWidth or 181, prefs.healthHeight or 46
    local powerH, initPpPos = 0, "none"
    if not noPowerPreview then
        powerH, initPpPos = prefs.powerHeight or 6, mod.UF_PowerPos(prefs)
    end
    local initPpIsAtt = (initPpPos == "below" or initPpPos == "above")
    local initPpExtra = initPpIsAtt and powerH or 0
    -- Cast bar height: the player's follows Show Cast Bar (it is always
    -- pinned to the frame), target and focus follow theirs, and a cast bar
    -- the live layout moved out of the strip under the frame reserves no
    -- room there (the same call the live aura containers make).
    local castbarH = 0
    if not noCastbarPreview then
        if unitName ~= "player" then
            castbarH = (prefs.showCastbar ~= false) and (prefs.castbarHeight or 14) or 0
        elseif prefs.showPlayerCastbar then
            local ownH = prefs.playerCastbarHeight
            castbarH = (ownH and ownH > 0) and ownH or 14
        end
    end
    local inStrip = CludesUI.UF_CastbarBelowFrame
    if castbarH > 0 and inStrip and not inStrip(unitName) then
        castbarH = 0
    end
    local barH = healthH + initPpExtra
    local isAttachedInit = portraitLook == "attached"
    local portraitW = (showPortrait and isAttachedInit) and barH or 0
    local totalW = frameW + portraitW
    local totalH = barH

    -- Header room the first build keeps above (top pad) and below (extra)
    -- the frame for each aura row, the reserve pf:Update makes too, so the
    -- page is spaced right before any slider moves. A corner anchor adds a
    -- row; a Y offset past the frame adds its overflow on that side, and a
    -- side-anchored row (sideways true) may overflow either way.
    local initBuffExtra, initBuffTopPad = 0, 0
    local function ReserveAuraRoom(anchor, iconSize, offsetY, sideways)
        local atTop = anchor == "topleft" or anchor == "topright"
        local atBottom = anchor == "bottomleft" or anchor == "bottomright"
        if atTop or atBottom then
            local rowH = (iconSize or 22) + 3
            initBuffExtra = initBuffExtra + rowH
            if atTop then
                initBuffTopPad = initBuffTopPad + rowH
            end
        end
        local shift = math.max(-PREVIEW_Y_CAP, math.min(PREVIEW_Y_CAP, offsetY or 0))
        if shift > 0 and (atTop or (sideways and not atBottom)) then
            initBuffTopPad = initBuffTopPad + shift
        elseif shift < 0 and (atBottom or (sideways and not atTop)) then
            initBuffExtra = initBuffExtra - shift
        end
    end
    if prefs.showBuffs then
        ReserveAuraRoom(prefs.buffAnchor or "topleft", prefs.buffSize, prefs.buffOffsetY, true)
    end
    local firstDebuffAnchor = prefs.debuffAnchor or "none"
    ReserveAuraRoom(firstDebuffAnchor, prefs.debuffSize, prefs.debuffOffsetY, firstDebuffAnchor ~= "none")

    local popFrame = CreateFrame("Frame", nil, hostFrame)
    -- The unit this dress shows: a kept header root hands the same frame to the
    -- next unit, so an allPreviews entry whose frame now shows another unit is stale.
    popFrame._pvUnit = unitName
    -- Real frames render at UIParent's effective scale vs. the panel's smaller one;
    -- this ratio makes every pixel value match the real frames' physical size.
    local previewScale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    popFrame._previewBaseScale = previewScale
    -- Blizzard Style: Frame Scale rides the preview scale (the live frame is
    -- SetScale'd the same way), so anchors and the header math stay in step.
    if ResolveBlizzPreview(unitName, prefs) then
        previewScale = previewScale * BlizzPreviewScale(prefs)
    end
    popFrame:SetScale(previewScale)
    popFrame._buffExtra = initBuffExtra
    popFrame._buffTopPad = initBuffTopPad
    popFrame._previewScale = previewScale
    Pix.Point(popFrame, "TOP", hostFrame, "TOP", 0, -(25 + initBuffTopPad) / previewScale)

    -- barArea: child of pf sized to health+power only (excludes castbar).
    local barRegion = CreateFrame("Frame", nil, popFrame)
    Pix.Size(barRegion, totalW, barH)
    Pix.Point(barRegion, "TOPLEFT", popFrame, "TOPLEFT", 0, 0)

    -- Portrait: a clipped box over a dark backing, holding one texture (the
    -- 2D portrait or the class art) and, made on first need, a PlayerModel
    -- (3D, and the test for whether a 2D portrait may be mirrored).
    local portraitHolder
    if hasPortraitSupport then
        portraitHolder = CreateFrame("Frame", nil, popFrame)
        Pix.Size(portraitHolder, barH, barH)
        portraitHolder:SetClipsChildren(true)
        local backing = portraitHolder:CreateTexture(nil, "BACKGROUND")
        backing:SetAllPoints()
        backing:SetColorTexture(0.082, 0.082, 0.082, 1)
        portraitHolder._previewBg = backing
        local nearCorner = (side == "left") and "TOPLEFT" or "TOPRIGHT"
        Pix.Point(portraitHolder, nearCorner, barRegion, nearCorner, 0, 0)

        local function FillBox(region)
            region:SetPoint("TOPLEFT", portraitHolder, "TOPLEFT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", portraitHolder, "BOTTOMRIGHT", 0, 0)
        end
        local portraitTexture = portraitHolder:CreateTexture(nil, "ARTWORK")
        FillBox(portraitTexture)
        portraitTexture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

        local portraitModel
        local function EnsurePreviewModel()
            if not portraitModel then
                portraitModel = CreateFrame("PlayerModel", nil, portraitHolder)
                FillBox(portraitModel)
                portraitModel:SetUnit("player")
                portraitModel:SetCamera(0)
                portraitModel:Hide()
                portraitHolder._previewModel = portraitModel
            end
            return portraitModel
        end
        -- The texture pinned inside the box, `inset` px in from every edge.
        local function SeatPortraitTex(inset)
            portraitTexture:ClearAllPoints()
            Pix.Point(portraitTexture, "TOPLEFT", portraitHolder, "TOPLEFT", inset, -inset)
            Pix.Point(portraitTexture, "BOTTOMRIGHT", portraitHolder, "BOTTOMRIGHT", -inset, inset)
        end

        -- What the box last drew. An Update that changes none of mode, art
        -- style, zoom and mirror leaves the box alone: seating a PlayerModel
        -- again on every Update blinks and costs a great deal of GPU.
        local drawn = {}
        local function ApplyPortraitMode()
            local cur = UnitPrefs()
            local modeName = cur.portraitMode or "2d"
            -- A non-player frame that opted in shows its Class art fallback
            -- (a stock style keeps its own portrait). The resolved mode is
            -- what the memo compares, so the fallback's inputs ride it.
            if
                modeName == "class"
                and unitName ~= "player"
                and cur.portraitNonPlayerOn
                and not CludesUI.BlizzStyle.Get("unitframes")
            then
                modeName = mod.UF_ClassFallback(cur)
            end
            local style = cur.classThemeStyle or "modern"
            local zoom = (cur.portraitArtScale or 100) + (cur.portrait3dZoom or 100) * 1000
            -- Mirror Portrait turns 3D models too, and never under a stock style.
            local mirror = cur.portraitMirror and not CludesUI.BlizzStyle.Get("unitframes") and true or false
            if modeName == drawn.mode and style == drawn.style and zoom == drawn.zoom then
                if mirror == drawn.mirror then
                    return
                end
                if modeName == "3d" and portraitModel then
                    drawn.mirror = mirror
                    mod.UF_ApplyPortraitRotation(portraitModel, mirror)
                    return
                end
            end
            drawn.mode, drawn.style, drawn.zoom, drawn.mirror = modeName, style, zoom, mirror
            portraitHolder._previewMode = modeName
            -- Class art and the 2D portrait share the one texture, so a mask
            -- the class art left behind comes off for anything else.
            if modeName ~= "class" and portraitTexture._classZoomMasked then
                portraitTexture:RemoveMaskTexture(portraitTexture._classZoomMask)
                portraitTexture._classZoomMask:Hide()
                portraitTexture._classZoomMasked = nil
            end
            portraitHolder:Show()
            if modeName == "3d" then
                portraitTexture:Hide()
                local model = EnsurePreviewModel()
                model:SetUnit("player")
                model:SetCamera(0)
                model:SetPortraitZoom(1)
                model:SetPosition(0, 0, 0)
                model:SetCamDistanceScale((cur.portrait3dZoom or 100) / 100)
                model:Show()
                mod.UF_ApplyPortraitRotation(model, mirror)
                return
            end
            if portraitModel then
                portraitModel:Hide()
            end
            if modeName == "none" then
                -- The non-player "Nothing" fallback: just the empty backing.
                portraitTexture:Hide()
            elseif modeName == "class" then
                portraitTexture:Show()
                local _, classToken = UnitClass("player")
                ApplyClassIconTexture_Preview(portraitTexture, classToken or "WARRIOR", style, mirror)
                portraitTexture:SetAlpha(0.9)
                -- Inset from the box's height now, not the build-time barH.
                local boxH = portraitHolder:GetHeight()
                SeatPortraitTex(math.floor((boxH < 1 and barH or boxH) * 0.08))
            else
                portraitTexture:Show()
                SetPortraitTexture(portraitTexture, "player")
                mirror = mirror and mod.UF_CanMirrorPortrait2D(EnsurePreviewModel(), "player")
                local u0, u1 = 0.15, 0.85
                if mirror then
                    u0, u1 = u1, u0
                end
                portraitTexture:SetTexCoord(u0, u1, 0.15, 0.85)
                portraitTexture:SetAlpha(1)
                SeatPortraitTex(0)
            end
        end
        portraitHolder._applyMode = ApplyPortraitMode
        portraitHolder._isPreview = true
        portraitHolder._previewTex = portraitTexture
        portraitHolder._previewModel = portraitModel
        ApplyPortraitMode()
        if not showPortrait then
            portraitHolder:Hide()
        end
    end

    -- Health colours outside the dark theme, for a settings table (the
    -- build's and every Update's): the fill from the unit's own picks with
    -- Dynamic Health Color over every flat source as on the live bar (fed
    -- the preview's known fake percent, so the clean-number twin of the
    -- engine curve stands in for UnitHealthPercent), then the backing.
    local function LitHealthColors(cfg)
        local function PlayerClassRGB()
            local _, token = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[token]
            if classColor then
                return classColor.r, classColor.g, classColor.b
            end
            return 37 / 255, 193 / 255, 29 / 255
        end
        -- The boss preview stays hostile red: the live boss frame never class-colours.
        local red, green, blue
        local ownFill = cfg.customFillColor
        if cfg.healthClassColored and unitName ~= "boss" then
            red, green, blue = PlayerClassRGB()
        elseif ownFill then
            red, green, blue = ownFill.r, ownFill.g, ownFill.b
        elseif unitName == "player" then
            red, green, blue = PlayerClassRGB()
        elseif unitName == "pet" then
            red, green, blue = 37 / 255, 193 / 255, 29 / 255
        else
            red, green, blue = 0.8, 0.2, 0.2
        end
        local dynR, dynG, dynB = mod.UF_PreviewDynamicColor(cfg, optionState._previewHealthPct or 0.70)
        if dynR then
            red, green, blue = dynR, dynG, dynB
        end
        -- Backing: the player's class colour (the designer shows your class)
        -- while Class Colored Background is on, else the custom pick.
        local classBack
        if cfg.bgClassColored then
            local _, token = UnitClass("player")
            classBack = token and CludesUI.GetClassColor(token)
        end
        local backPick = classBack or cfg.customBgColor
        if backPick then
            return red, green, blue, backPick.r, backPick.g, backPick.b
        end
        return red, green, blue, 17 / 255, 17 / 255, 17 / 255
    end
    local hR, hG, hB, hA, bgR, bgG, bgB, bgA
    local isDarkTheme = mod.UF_DarkThemeOn(prefs)
    if isDarkTheme then
        hR, hG, hB, hA = CludesUI.GetDarkModeFill()
        bgR, bgG, bgB, bgA = CludesUI.GetDarkModeBg()
    else
        hA = (prefs.healthBarOpacity or 90) / 100
        hR, hG, hB, bgR, bgG, bgB = LitHealthColors(prefs)
        bgA = (prefs.customBgAlpha or 100) / 100
    end

    -- Health bar. The backing colour covers only the missing-health part, so
    -- a fill below full opacity shows the dark base through it rather than
    -- the backing colour; Update re-anchors it for reverse fill, as live.
    local fillW = math.floor(frameW * (optionState._previewHealthPct or 0.70) + 0.5)
    local healthBar = CreateFrame("Frame", nil, popFrame)
    Pix.Size(healthBar, frameW, healthH)
    local healthBgColor = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", fillW, 0)
    healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    healthBgColor:SetColorTexture(bgR, bgG, bgB, 1)
    healthBgColor:SetAlpha(bgA)
    -- A power bar above the health bar pushes the health bar down by its height.
    local dropForPower = (initPpPos == "above") and powerH or 0
    if not (showPortrait and portraitHolder) then
        Pix.Point(healthBar, "TOPLEFT", barRegion, "TOPLEFT", 0, -dropForPower)
    elseif side == "left" then
        Pix.Point(healthBar, "TOPLEFT", portraitHolder, "TOPRIGHT", 0, -dropForPower)
    else
        Pix.Point(healthBar, "TOPRIGHT", portraitHolder, "TOPLEFT", 0, -dropForPower)
    end

    local healthBg = healthBar:CreateTexture(nil, "BACKGROUND", nil, -1)
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(0.1, 0.1, 0.1, 0.75)

    local healthFill = healthBar:CreateTexture(nil, "ARTWORK")
    healthFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    healthFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    healthFill:SetWidth(fillW)
    local healthGradient = (not isDarkTheme) and prefs.gradientEnabled
    PV_FillColor(healthFill, nil, hR, hG, hB, healthGradient, prefs.gradientColor, prefs.gradientDir, hA)
    healthFill:SetAlpha(hA)
    popFrame._healthFill = healthFill
    popFrame._hR, popFrame._hG, popFrame._hB, popFrame._hA = hR, hG, hB, hA

    local dispelPreview
    if unitName == "player" then
        dispelPreview = healthBar:CreateTexture(nil, "ARTWORK", nil, 3)
        dispelPreview:SetTexture("Interface\\Buttons\\WHITE8X8")
        dispelPreview:Hide()
    end

    -- Text layer over the health bar, above the absorb bars and the border.
    local textOverlay = CreateFrame("Frame", nil, popFrame)
    textOverlay:SetAllPoints(healthBar)
    textOverlay:SetFrameStrata(popFrame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(popFrame:GetFrameLevel() + 20, healthBar:GetFrameLevel() + 12))

    -- The four health bar text slots, white and unwrapped until Update
    -- places and colours them. Extra Text is never width-limited (the
    -- live frames never cut it short either).
    local function TextSlot(sizeKey)
        local fs = textOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(fs, PREVIEW_FONT, prefs[sizeKey] or prefs.textSize or 12)
        fs:SetTextColor(1, 1, 1)
        fs:SetWordWrap(false)
        return fs
    end
    local leftFS = TextSlot("leftTextSize")
    local rightFS = TextSlot("rightTextSize")
    local centerFS = TextSlot("centerTextSize")
    local extraFS = TextSlot("extraTextSize")

    -- The sample a text content key shows, built from the preview's fake
    -- health and power percents. prefixText is the slot's settings prefix
    -- ("leftText", "btbRight" ...), which carries its Name Format, Target
    -- separator, Target prefix and custom format.
    local function PreviewTextForContent(contentFrame, cfg, prefixText)
        -- Numbers as the live tags print them: the Show Decimal on Text
        -- function when that is on (WoW Forever: nothing under 10,000
        -- abbreviates), else the Number Format for the value type (a boss
        -- frame's health reads as "bossHealth").
        local function Abbr(val, valueType)
            local decimalCfg = _G._CUI_AbbrevDecimalCfg
            if decimalCfg then
                return mod.AbbreviateNumbers(val, decimalCfg)
            end
            if valueType ~= "absorb" and unitName:match("^boss") then
                valueType = "bossHealth"
            end
            return mod.AbbreviateValue(val, valueType)
        end
        local function Pct(share)
            if not _G._CUI_TextDecimals then
                return tostring(math.floor(share * 100))
            end
            local trim = _G._CUI_PctTrim
            if trim then
                return AbbreviateNumbers(trim.curve:Evaluate(share), trim.cfg)
            end
            return string.format("%.1f", share * 100)
        end
        -- The name the live frame would show (the player's with its WoW
        -- Forever surname), cut to the slot's Name Format.
        local function NameText()
            local shown
            if unitName == "player" then
                shown = CludesUI.WithSurname(UnitName("player")) or "Player"
            else
                shown = _previewCreatureNames[unitName] or unitName
            end
            if prefixText and cfg then
                shown = CludesUI.ShortName(shown, cfg[prefixText .. "NameFormat"])
            end
            return shown
        end
        local function Tint(text, red, green, blue)
            return string.format("%s%s|r", CludesUI.HexColor(red, green, blue), text)
        end
        -- " > Target", mirroring the live [cui-tgtsep(...)] tag: the slot's
        -- separator padded with spaces, in the class colour (the preview's
        -- target is of the player's class) or its own colour (white by
        -- default). literal replaces the padded separator ("" = none), as the
        -- Target content's prefix does; plain leaves the name uncoloured.
        local function TargetText(literal, plain)
            local _, token = UnitClass("player")
            local classColor = token and CludesUI.GetClassColor(token)
            local word = "Target"
            if classColor and not plain then
                word = Tint(word, classColor.r, classColor.g, classColor.b)
            end
            local sep = literal
            if not sep then
                local picked = prefixText and cfg[prefixText .. "TargetSep"]
                if type(picked) ~= "string" or picked == "" then
                    picked = ">"
                end
                sep = " " .. picked .. " "
            end
            if sep == "" then
                return word
            end
            if prefixText and cfg[prefixText .. "TargetSepClassColor"] then
                if classColor then
                    sep = Tint(sep, classColor.r, classColor.g, classColor.b)
                end
                return sep .. word
            end
            local own = prefixText and cfg[prefixText .. "TargetSepColor"]
            if type(own) ~= "table" then
                own = {}
            end
            return Tint(sep, own.r or 1, own.g or 1, own.b or 1) .. word
        end
        local maxHP = UnitHealthMax("player") or 1
        local hpShare = optionState._previewHealthPct or 0.70
        local curHP = math.floor(maxHP * hpShare)
        local maxPP = UnitPowerMax("player") or 100
        local ppShare = optionState._previewPowerPct or 0.85
        local curPP = math.floor(maxPP * ppShare)
        local function LevelText()
            local levelText = UnitLevel("player")
            levelText = (type(levelText) == "number" and levelText > 0) and tostring(levelText) or "80"
            -- Level Difficulty Color: tinted as an attackable unit of your level.
            if cfg and cfg.levelDifficultyColor then
                levelText = CludesUI.ColorText(levelText, CludesUI.GetLevelDifficultyColor(tonumber(levelText), true))
            end
            return levelText
        end
        -- A shield or heal absorb sized at share of max health.
        local function AbsorbText(share, short)
            local amount = math.floor(maxHP * share)
            if short then
                return Abbr(amount, "absorb")
            end
            return string.format("%d", amount)
        end
        local hpAbbr = function()
            return Abbr(curHP, "health")
        end
        local ppWhole = function()
            return math.floor(ppShare * 100)
        end
        -- Content keys and tag keys to the sample each shows. Live frames cut
        -- names to a Width % per slot; the preview leaves that to the
        -- FontString's own width.
        local SAMPLE = {
            name = NameText,
            nametotarget = function()
                return NameText() .. TargetText()
            end,
            -- The live Target content (ns.ContentToZone): prefix nil = "T:",
            -- "" = none, the name class coloured only while the slot is.
            targetname = function()
                local pre = prefixText and cfg[prefixText .. "TargetPrefix"]
                if type(pre) ~= "string" then
                    pre = "T:"
                end
                return TargetText(
                    pre ~= "" and (pre .. " ") or "",
                    not (prefixText and cfg[prefixText .. "ClassColor"])
                )
            end,
            level = LevelText,
            levelname = function()
                return LevelText() .. " | " .. NameText()
            end,
            namelevel = function()
                return NameText() .. " | " .. LevelText()
            end,
            both = function()
                return hpAbbr() .. " | " .. Pct(hpShare) .. "%"
            end,
            bothdash = function()
                return hpAbbr() .. " - " .. Pct(hpShare) .. "%"
            end,
            curhpshort = hpAbbr,
            healthshort = function()
                return mod.AbbreviateShortHealth(curHP)
            end,
            curmaxhp = function()
                return hpAbbr() .. " / " .. Abbr(maxHP, "maxHealth")
            end,
            perhp = function()
                return Pct(hpShare) .. "%"
            end,
            perhpnosign = function()
                return Pct(hpShare)
            end,
            perhpnum = function()
                return Pct(hpShare) .. "% | " .. hpAbbr()
            end,
            perhpnumdash = function()
                return Pct(hpShare) .. "% - " .. hpAbbr()
            end,
            perpp = function()
                return ppWhole() .. "%"
            end,
            curpp = function()
                return mod.AbbreviateNumbers(curPP)
            end,
            curmaxpp = function()
                return mod.AbbreviateNumbers(curPP) .. " / " .. mod.AbbreviateNumbers(maxPP)
            end,
            curhp_curpp = function()
                return hpAbbr() .. " | " .. mod.AbbreviateNumbers(curPP)
            end,
            perhp_perpp = function()
                return Pct(hpShare) .. "% | " .. ppWhole() .. "%"
            end,
            absorb = function()
                return AbsorbText(0.14)
            end,
            absorbshort = function()
                return AbsorbText(0.14, true)
            end,
            healabsorb = function()
                return AbsorbText(0.08)
            end,
            healabsorbshort = function()
                return AbsorbText(0.08, true)
            end,
            group = function()
                return "3"
            end,
        }
        -- Custom: the live parse of the slot's format (ns.ContentToZone's
        -- custom branch), filled with one sample per tag; an unknown tag
        -- reads as the short heal absorb.
        SAMPLE.custom = function()
            local parsed =
                CludesUI.TextTags.Parse(mod.UF_TextTags, prefixText and cfg and cfg[prefixText .. "CustomFormat"])
            if not parsed then
                return ""
            end
            local TAG = {
                name = NameText,
                target = function()
                    return "Target"
                end,
                group = SAMPLE.group,
                level = LevelText,
                hp = function()
                    return tostring(curHP)
                end,
                ["hp:abr"] = hpAbbr,
                ["hp:max"] = function()
                    return tostring(maxHP)
                end,
                ["hp:max:abr"] = function()
                    return Abbr(maxHP, "maxHealth")
                end,
                ["hp:pct"] = function()
                    return Pct(hpShare)
                end,
                pp = function()
                    return tostring(curPP)
                end,
                ["pp:abr"] = SAMPLE.curpp,
                ["pp:max"] = function()
                    return tostring(maxPP)
                end,
                ["pp:max:abr"] = function()
                    return mod.AbbreviateNumbers(maxPP)
                end,
                ["pp:pct"] = function()
                    return tostring(ppWhole())
                end,
                absorb = SAMPLE.absorb,
                ["absorb:abr"] = SAMPLE.absorbshort,
                healabsorb = SAMPLE.healabsorb,
            }
            local tagKeys, filled = parsed.keys, {}
            for i = 1, #tagKeys do
                filled[i] = (TAG[tagKeys[i]] or SAMPLE.healabsorbshort)()
            end
            return string.format(parsed.fmt, unpack(filled, 1, #tagKeys))
        end
        local make = SAMPLE[contentFrame]
        return make and make() or ""
    end

    -- A slot's colour: the class colour while the slot asks for it (the
    -- player's class on the player preview, a hostile red on any other),
    -- else its own pick, white by default.
    local function PreviewClassColor(fontStr, useCC, customR, customG, customB)
        if not fontStr then
            return
        end
        if useCC and unitName ~= "player" then
            fontStr:SetTextColor(0.9, 0.3, 0.3)
            return
        end
        local classColor
        if useCC then
            local _, token = UnitClass("player")
            classColor = token and CludesUI.GetClassColor(token)
        end
        if classColor then
            fontStr:SetTextColor(classColor.r, classColor.g, classColor.b)
        else
            fontStr:SetTextColor(customR or 1, customG or 1, customB or 1)
        end
    end

    -- Power Color on a slot showing power content: the player's power
    -- colour, over any class colour.
    local function PreviewPowerColor(fontStr, contentKey, usePowerColor, customFmt)
        if not (fontStr and usePowerColor and mod.UF_IsPowerContent(contentKey, customFmt)) then
            return
        end
        local red, green, blue = CludesUI.ResolveUnitPowerColor("player")
        if red then
            fontStr:SetTextColor(red, green, blue)
        else
            fontStr:SetTextColor(1, 1, 1)
        end
    end

    -- Where each health bar slot sits for its alignment: the point, and the
    -- inset from that edge before the slot's own X offset.
    local SLOT_EDGE = { left = { "LEFT", 5 }, right = { "RIGHT", -5 }, center = { "CENTER", 0 } }
    -- Room the right slot's content takes, which the left slot's width
    -- gives up so the two never overlap (the live frames truncate the same way).
    local RIGHT_TEXT_ROOM = {
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
    -- Sets a slot's font from the unit's OWN size (as the live frames do:
    -- slot size, else Text Size, else 12) and places it; false (and hidden)
    -- for the "none" content.
    local function PlaceSlot(fs, cfg, prefix, content, edge)
        SetPVFont(fs, PREVIEW_FONT, cfg[prefix .. "Size"] or cfg.textSize or 12)
        fs:ClearAllPoints()
        if prefix == "extraText" then
            fs:SetWidth(0)
        end
        if content == "none" then
            fs:Hide()
            return false
        end
        local spot = SLOT_EDGE[edge]
        fs:SetJustifyH(spot[1])
        Pix.Point(fs, spot[1], textOverlay, spot[1], spot[2] + (cfg[prefix .. "X"] or 0), cfg[prefix .. "Y"] or 0)
        return true
    end
    local function FillSlot(fs, cfg, prefix, content)
        fs:SetText(PreviewTextForContent(content, cfg, prefix))
        fs:Show()
        PreviewClassColor(
            fs,
            cfg[prefix .. "ClassColor"],
            cfg[prefix .. "ColorR"],
            cfg[prefix .. "ColorG"],
            cfg[prefix .. "ColorB"]
        )
    end
    -- Every slot draws on its own: a Center text hides neither Left nor Right.
    local function ApplyPreviewTextPositions(cfg)
        local leftKey = cfg.leftTextContent or "name"
        local rightKey = cfg.rightTextContent or (unitName == "focus" and "perhp" or "both")
        local centerKey = cfg.centerTextContent or "none"
        local extraKey = cfg.extraTextContent or "none"
        if
            PlaceSlot(
                extraFS,
                cfg,
                "extraText",
                extraKey,
                SLOT_EDGE[cfg.extraTextAlign] and cfg.extraTextAlign or "left"
            )
        then
            FillSlot(extraFS, cfg, "extraText", extraKey)
        end
        if PlaceSlot(centerFS, cfg, "centerText", centerKey, "center") then
            FillSlot(centerFS, cfg, "centerText", centerKey)
        end
        if PlaceSlot(leftFS, cfg, "leftText", leftKey, "left") then
            if rightKey == "none" then
                leftFS:SetWidth(0)
            else
                local taken = (RIGHT_TEXT_ROOM[rightKey] or 0) + 10
                if rightKey == "custom" then
                    taken = mod.UF_EstimateTextWidth(rightKey, cfg.rightTextCustomFormat, true)
                end
                Pix.Width(leftFS, math.max((cfg.frameWidth or 181) - taken - 10, 20))
            end
            FillSlot(leftFS, cfg, "leftText", leftKey)
        end
        if PlaceSlot(rightFS, cfg, "rightText", rightKey, "right") then
            FillSlot(rightFS, cfg, "rightText", rightKey)
        end
    end
    ApplyPreviewTextPositions(prefs)

    -- The power fill colour: the power type's colour (the class colour with
    -- Class Colored) while Power Color is on, else the custom fill, else blue.
    local function PowerFillRGB(cfg)
        cfg = cfg or prefs
        local byPower = cfg.powerPercentPowerColor ~= false
        if byPower and cfg.powerClassColored then
            local _, token = UnitClass("player")
            local classColor = CludesUI.GetClassColor(token)
            return classColor.r, classColor.g, classColor.b
        elseif byPower then
            local _, kind = UnitPowerType("player")
            local typeColor = CludesUI.GetPowerColor(kind or "MANA")
            return typeColor.r, typeColor.g, typeColor.b
        end
        local own = cfg.customPowerFillColor
        if own then
            return own.r, own.g, own.b
        end
        return 0, 0, 1
    end
    local function PaintPowerFill(fill, texPath, red, green, blue)
        local opacity = (prefs.powerBarOpacity or 100) / 100
        PV_FillColor(
            fill,
            texPath,
            red,
            green,
            blue,
            prefs.powerGradientEnabled,
            prefs.powerGradientColor,
            prefs.powerGradientDir,
            opacity
        )
        return opacity
    end

    -- Power bar: made for every unit that can show one, even at height 0, so
    -- a 0 height bar still carries its text and grows back when raised.
    local powerBar
    local ppPreviewFS
    if not noPowerPreview then
        powerBar = CreateFrame("Frame", nil, popFrame)
        Pix.Size(powerBar, frameW, powerH)
        local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
        powerBg:SetAllPoints()
        popFrame._powerBg = powerBg
        local powerFill = powerBar:CreateTexture(nil, "ARTWORK")
        powerFill:SetPoint("TOPLEFT", powerBar, "TOPLEFT", 0, 0)
        powerFill:SetPoint("BOTTOMLEFT", powerBar, "BOTTOMLEFT", 0, 0)
        powerFill:SetWidth(math.floor(frameW * (optionState._previewPowerPct or 0.85) + 0.5))
        popFrame._powerFill = powerFill

        local fillR, fillG, fillB = PowerFillRGB()
        -- Backing: the power colour darkened (Power Colored Background), else
        -- the custom pick, else near black.
        local backR, backG, backB = 17 / 255, 17 / 255, 17 / 255
        local ownBack = prefs.customPowerBgColor
        if prefs.powerBgPowerColored then
            local _, kind = UnitPowerType("player")
            local typeColor = CludesUI.GetPowerColor(kind or "MANA")
            local dim = CludesUI.GetPowerBgDarkenFactor()
            backR, backG, backB = typeColor.r * dim, typeColor.g * dim, typeColor.b * dim
        elseif ownBack then
            backR, backG, backB = ownBack.r, ownBack.g, ownBack.b
        end
        powerBg:SetColorTexture(backR, backG, backB, 1)
        powerBg:SetAlpha((prefs.customPowerBgAlpha or 100) / 100)
        local fillOpacity = PaintPowerFill(powerFill, nil, fillR, fillG, fillB)
        powerFill:SetAlpha(fillOpacity)
        -- Below full Fill Opacity the backing covers only the empty part, so
        -- the world shows through the fill as it does live.
        if fillOpacity < 1 then
            popFrame._powerBgOpAnchored = true
            powerBg:ClearAllPoints()
            local reversed = prefs.powerReverseFill
            powerBg:SetPoint(
                "TOPLEFT",
                reversed and powerBar or powerFill,
                reversed and "TOPLEFT" or "TOPRIGHT",
                0,
                0
            )
            powerBg:SetPoint(
                "BOTTOMRIGHT",
                reversed and powerFill or powerBar,
                reversed and "BOTTOMLEFT" or "BOTTOMRIGHT",
                0,
                0
            )
        end
        -- First placement for the Bar Position (Update places it again).
        if initPpPos == "none" then
            powerBar:Hide()
        elseif initPpPos == "detached_top" or initPpPos == "detached_bottom" then
            local onTop = initPpPos == "detached_top"
            local lift = (onTop and 15 or -15) + (prefs.powerY or 0)
            powerBar:SetPoint(
                onTop and "BOTTOM" or "TOP",
                healthBar,
                onTop and "TOP" or "BOTTOM",
                prefs.powerX or 0,
                lift
            )
        else
            local ownEdge, healthEdge = "TOP", "BOTTOM"
            if initPpPos == "above" then
                ownEdge, healthEdge = "BOTTOM", "TOP"
            end
            Pix.Point(powerBar, ownEdge .. "LEFT", healthBar, healthEdge .. "LEFT", 0, 0)
            Pix.Point(powerBar, ownEdge .. "RIGHT", healthBar, healthEdge .. "RIGHT", 0, 0)
        end

        -- The power text's own layer on pf, over the border.
        local ppOvr = CreateFrame("Frame", nil, popFrame)
        ppOvr:SetAllPoints(powerBar)
        ppOvr:SetFrameLevel(barRegion:GetFrameLevel() + 8)
        ppPreviewFS = ppOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(ppPreviewFS, PREVIEW_FONT, 9)
        ppPreviewFS:Hide()
    end

    -- Bar texture, laid straight onto the fill textures (the preview's bars
    -- are plain Frames, not StatusBars).
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
                healthGradient,
                prefs.gradientColor,
                prefs.gradientDir,
                hA
            )
        end
        if popFrame._powerFill and powerH > 0 then
            local red, green, blue = PowerFillRGB()
            popFrame._pR, popFrame._pG, popFrame._pB = red, green, blue
            PaintPowerFill(popFrame._powerFill, texPath, red, green, blue)
        end
    end

    -- Cast bar: always made for the player (Update shows or hides it), for
    -- the others only while it has a height.
    local castBar, castFill, castNameText, castIconHolder
    local castTimeFS, castTargetFS
    if unitName == "player" or castbarH > 0 then
        local isPlayer = unitName == "player"
        local initCH = castbarH
        if isPlayer and castbarH <= 0 then
            initCH = 14
        end
        -- Icon as part of the bar: the bar (backing, border and fill) narrows
        -- and the icon takes the freed room with the outer edge fixed, as on
        -- the live cast bar; off, the icon hangs outside a full-width bar.
        -- The module's own rule decides it (a stock style forces it for a
        -- shown icon), so the preview lays it out exactly as live.
        local iconW = initCH
        local iconInBar = mod.UF_CastIconInWidth(unitName, prefs)
        local iconOnRight = prefs[isPlayer and "playerCastbarIconRight" or "castbarIconRight"] == true
        local offsetKey = isPlayer and "playerCastIconOffset" or "castIconOffset"
        local iconDX, iconDY = prefs[offsetKey .. "X"] or 0, prefs[offsetKey .. "Y"] or 0
        -- Boss: a Cast Bar Width above 0 replaces the frame width (0 = match),
        -- held to frame width + 120 here so an extreme value cannot spill over
        -- the options panel (pf does not clip); live frames take it in full.
        local fullW = totalW
        if unitName == "boss" and (prefs.castbarWidth or 0) > 0 then
            fullW = math.min(math.max(prefs.castbarWidth, 30), totalW + 120)
        end
        local barW = iconInBar and math.max(1, fullW - iconW) or fullW
        castBar = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castBar, barW, initCH)
        local cbAnchor = powerBar or healthBar
        local cbOffset = 0
        if showPortrait then
            if side == "right" then
                cbOffset = portraitW / 2
            elseif side == "left" then
                cbOffset = -(portraitW / 2)
            end
        end
        castBar._cbAnchor = cbAnchor
        castBar._cbOffset = cbOffset
        -- A narrowed bar moves half the icon width toward the side without
        -- the icon, so bar and icon fill the full bar's footprint.
        local iconShift = 0
        if iconInBar then
            iconShift = iconOnRight and -(iconW / 2) or (iconW / 2)
        end
        Pix.Point(castBar, "TOP", cbAnchor, "BOTTOM", cbOffset + iconShift, 0)
        if castbarH > 0 then
            totalH = totalH + castbarH
        end

        -- Half-black backing and a 1px black border, as the live cast bar.
        local cbBg = castBar:CreateTexture(nil, "BACKGROUND")
        cbBg:SetAllPoints(castBar)
        cbBg:SetColorTexture(0, 0, 0, 0.5)
        castBar._previewBgTex = cbBg
        Pix.CreateBorder(castBar, 0, 0, 0, 1, 1, "OVERLAY", 0)

        -- The fill spans the (maybe narrowed) bar; Update gives it its real
        -- colour and texture, this teal is only the first paint.
        castFill = castBar:CreateTexture(nil, "ARTWORK")
        Pix.Point(castFill, "TOPLEFT", castBar, "TOPLEFT", 1, 0)
        Pix.Point(castFill, "BOTTOMLEFT", castBar, "BOTTOMLEFT", 1, 1)
        Pix.Width(castFill, math.max(0, barW - 2) * (optionState._previewCastFill or 0.6))
        castFill:SetColorTexture(0.114, 0.655, 0.514, 1)

        -- The player casts one of its class spells; anyone else a generic
        -- spell under the Shadow Bolt icon.
        local sample = isPlayer and optionState._previewCastSpell or nil
        local castSpellName = sample and sample.name or "Spell Name"
        local castSpellIcon = sample and sample.icon or 136197

        -- Text layer over the cast bar's border and the frame border.
        local cbTextOvr = CreateFrame("Frame", nil, castBar)
        cbTextOvr:SetAllPoints(castBar)
        cbTextOvr:SetFrameLevel(popFrame:GetFrameLevel() + 11)
        -- Name, time and target: one line each, cut short rather than wrapped.
        local function CastText(size, justify)
            local fs = cbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(fs, PREVIEW_FONT, size)
            fs:SetJustifyH(justify)
            fs:SetWordWrap(false)
            fs:SetMaxLines(1)
            return fs
        end
        castNameText = CastText(11, "LEFT")
        castNameText:SetTextColor(1, 1, 1)
        castNameText:SetText(castSpellName)
        castTimeFS = CastText(11, "RIGHT")
        castTimeFS:SetTextColor(1, 1, 1)
        local fullCast = (optionState._previewCastSpell and optionState._previewCastSpell.castTime) or 3.0
        castTimeFS:SetText(string.format("%.1f", fullCast * (1 - (optionState._previewCastFill or 0.6))))
        if not isPlayer then
            castTargetFS = CastText(10, "RIGHT")
            castTargetFS:SetText(UnitName("player") or "Player")
            local _, token = UnitClass("player")
            local classColor = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            if classColor then
                castTargetFS:SetTextColor(classColor.r, classColor.g, classColor.b)
            else
                castTargetFS:SetTextColor(1, 1, 1)
            end
        end

        -- First layout of the three: name at the left, time at the right,
        -- target just inside the time.
        local shownW = castBar:GetWidth() or totalW
        local timeW = 11 * 2.2
        castNameText:SetWidth(shownW * 0.42)
        castNameText:SetPoint("LEFT", castBar, "LEFT", 5, 1)
        castTimeFS:SetWidth(timeW)
        castTimeFS:SetPoint("RIGHT", castBar, "RIGHT", -3, 0)
        if castTargetFS then
            castTargetFS:SetWidth(shownW * 0.42)
            castTargetFS:SetPoint("RIGHT", castBar, "RIGHT", -3 - timeW, 0)
        end

        -- Spell icon off the bar's left end (right with Show Icon on Right);
        -- with the icon as part of the bar it lands inside the footprint.
        -- A plain frame and edge textures, not BackdropTemplate, for exact pixels.
        castIconHolder = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castIconHolder, initCH, initCH)
        if iconOnRight then
            Pix.Point(castIconHolder, "TOPLEFT", castBar, "TOPRIGHT", iconDX, iconDY)
        else
            Pix.Point(castIconHolder, "TOPRIGHT", castBar, "TOPLEFT", iconDX, iconDY)
        end
        local iconBg = castIconHolder:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints()
        iconBg:SetColorTexture(0, 0, 0, 1)
        castIconHolder._bg = iconBg
        Pix.CreateBorder(castIconHolder, 0, 0, 0, 1)
        local castIconTex = castIconHolder:CreateTexture(nil, "ARTWORK")
        Pix.Point(castIconTex, "TOPLEFT", castIconHolder, "TOPLEFT", 1, -1)
        Pix.Point(castIconTex, "BOTTOMRIGHT", castIconHolder, "BOTTOMRIGHT", -1, 1)
        castIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castIconTex:SetTexture(castSpellIcon)
        castIconHolder._iconTex = castIconTex

        -- The player's bar starts hidden while its cast bar is off.
        if isPlayer and castbarH <= 0 then
            castBar:Hide()
            castIconHolder:Hide()
        end
    end

    -- Text Bar: the live bottom text bar's twin (CreateBottomTextBar). It has
    -- no border of its own; the main frame's border takes it in.
    local btbFrame, btbBg, btbLeftFS, btbRightFS, btbCenterFS, btbClassIconTex
    local ApplyBTBPreviewTexts
    do
        local btbH = prefs.bottomTextBarHeight or 16
        local barPos = prefs.btbPosition or "bottom"
        local detached = (barPos == "detached_top" or barPos == "detached_bottom")
        local attached = (barPos == "top" or barPos == "bottom")
        local ownW = detached and (prefs.btbWidth or 0) or 0
        btbFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(btbFrame, ownW > 0 and ownW or totalW, btbH)
        local underFrame = (initPpIsAtt and powerBar) and powerBar or healthBar
        -- An attached bar centres under the bars and portrait together.
        local slide = 0
        if attached and showPortrait and isAttachedInit then
            if side == "right" then
                slide = portraitW / 2
            elseif side == "left" then
                slide = -(portraitW / 2)
            end
        end
        local dx, dy = prefs.btbX or 0, prefs.btbY or 0
        if barPos == "top" then
            Pix.Point(btbFrame, "BOTTOM", healthBar, "TOP", slide, 0)
        elseif barPos == "detached_top" then
            btbFrame:SetPoint("BOTTOM", healthBar, "TOP", dx, 15 + dy)
        elseif barPos == "detached_bottom" then
            btbFrame:SetPoint("TOP", underFrame, "BOTTOM", dx, -15 + dy)
        else
            Pix.Point(btbFrame, "TOP", underFrame, "BOTTOM", slide, 0)
        end

        local fillColor = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
        btbBg = btbFrame:CreateTexture(nil, "BACKGROUND")
        btbBg:SetAllPoints()
        btbBg:SetColorTexture(fillColor.r, fillColor.g, fillColor.b, prefs.btbBgOpacity or 1.0)

        -- Text layer over the border (which sits at barArea + 5).
        local btbTextOvr = CreateFrame("Frame", nil, btbFrame)
        btbTextOvr:SetAllPoints()
        btbTextOvr:SetFrameLevel(barRegion:GetFrameLevel() + 10)
        local function BarText(prefix)
            local fs = btbTextOvr:CreateFontString(nil, "OVERLAY")
            SetPVFont(fs, PREVIEW_FONT, prefs[prefix .. "Size"] or 11)
            fs:SetTextColor(1, 1, 1)
            fs:SetWordWrap(false)
            return fs
        end
        btbLeftFS = BarText("btbLeft")
        btbRightFS = BarText("btbRight")
        btbCenterFS = BarText("btbCenter")

        -- The class icon rides its own higher frame so it draws over the border.
        local iconLayer = CreateFrame("Frame", nil, btbFrame)
        iconLayer:SetAllPoints(btbTextOvr)
        iconLayer:SetFrameLevel(barRegion:GetFrameLevel() + 12)
        btbClassIconTex = iconLayer:CreateTexture(nil, "ARTWORK")
        btbClassIconTex:SetTexCoord(0, 1, 0, 1)
        btbClassIconTex:Hide()

        -- Each slot: its point and edge inset, before its own X offset.
        local BAR_SLOTS = {
            { btbLeftFS, "btbLeft", "LEFT", 5 },
            { btbRightFS, "btbRight", "RIGHT", -5 },
            { btbCenterFS, "btbCenter", "CENTER", 0 },
        }
        local ICON_SPOT = { center = { "CENTER", 0 }, right = { "RIGHT", -3 }, left = { "LEFT", 3 } }
        local function IconOverlayShown(on)
            local hit = popFrame._btbClassIconOv
            if not hit then
                return
            end
            if on then
                hit:Show()
            else
                hit:Hide()
            end
        end
        ApplyBTBPreviewTexts = function(cfg)
            for _, slot in ipairs(BAR_SLOTS) do
                local fs, prefix, point, inset = slot[1], slot[2], slot[3], slot[4]
                local content = cfg[prefix .. "Content"] or "none"
                SetPVFont(fs, PREVIEW_FONT, cfg[prefix .. "Size"] or 11)
                fs:ClearAllPoints()
                if content == "none" then
                    fs:Hide()
                else
                    fs:SetJustifyH(point)
                    Pix.Point(
                        fs,
                        point,
                        btbTextOvr,
                        point,
                        inset + (cfg[prefix .. "X"] or 0),
                        cfg[prefix .. "Y"] or 0
                    )
                    fs:SetText(PreviewTextForContent(content, cfg, prefix))
                    fs:Show()
                    local red, green, blue = cfg[prefix .. "ColorR"], cfg[prefix .. "ColorG"], cfg[prefix .. "ColorB"]
                    PreviewClassColor(fs, cfg[prefix .. "ClassColor"], red, green, blue)
                    PreviewPowerColor(fs, content, cfg[prefix .. "PowerColor"], cfg[prefix .. "CustomFormat"])
                end
            end

            -- The class icon, in the picked art style at its Location.
            local iconStyle = cfg.btbClassIcon or "none"
            local _, classToken
            if iconStyle ~= "none" then
                _, classToken = UnitClass("player")
            end
            if not (classToken and ApplyClassIconTexture_Preview(btbClassIconTex, classToken, iconStyle)) then
                btbClassIconTex:Hide()
                IconOverlayShown(false)
                return
            end
            local iconSize = cfg.btbClassIconSize or 14
            Pix.Size(btbClassIconTex, iconSize, iconSize)
            btbClassIconTex:ClearAllPoints()
            local spot = ICON_SPOT[cfg.btbClassIconLocation] or ICON_SPOT.left
            local iconX = spot[2] + (cfg.btbClassIconX or 0)
            Pix.Point(btbClassIconTex, spot[1], btbTextOvr, spot[1], iconX, cfg.btbClassIconY or 0)
            btbClassIconTex:Show()
            IconOverlayShown(true)
        end
        ApplyBTBPreviewTexts(prefs)

        if not prefs.bottomTextBar then
            btbFrame:Hide()
        elseif attached then
            totalH = totalH + btbH
        end
    end

    -- Class power pips (player preview only), in the nameplate pip look:
    -- three of the class's pips lit, the rest empty.
    local comboPipHolder, cpPips
    if unitName == "player" then
        -- Pip count per class; a class whose count depends on spec lists it by spec id.
        local PIPS_BY_CLASS = {
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
        local counts = PIPS_BY_CLASS[playerClass]
        local cpMax = counts and counts[1] or 0
        if counts and not counts[1] then
            local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
            local specID = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
            cpMax = specID and counts[specID] or 0
        end
        -- Lit colour: the suite's resource colour for the class (its class
        -- colour where that lookup is missing), gold by default.
        local litRGB = { 1.00, 0.84, 0.30 }
        local colorOf = CludesUI.GetResourceColor or CludesUI.GetClassColor
        local found = colorOf and colorOf(playerClass)
        if found then
            litRGB = { found.r, found.g, found.b }
        end

        if cpMax > 0 then
            comboPipHolder = CreateFrame("Frame", nil, popFrame)
            comboPipHolder:SetFrameLevel(popFrame:GetFrameLevel() + 4)
            local cpBgTex = comboPipHolder:CreateTexture(nil, "BACKGROUND")
            cpBgTex:SetAllPoints()
            local backing = prefs.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
            cpBgTex:SetColorTexture(backing.r, backing.g, backing.b, backing.a)
            comboPipHolder._bgTex = cpBgTex
            cpPips = {}
            local lit = math.min(3, cpMax)
            for pipIndex = 1, cpMax do
                local pip = comboPipHolder:CreateTexture(nil, "OVERLAY", nil, 3)
                pip:SetColorTexture(1, 1, 1, 1)
                Pix.Size(pip, 8, 3)
                if pipIndex <= lit then
                    pip:SetColorTexture(litRGB[1], litRGB[2], litRGB[3], 1)
                end
                cpPips[pipIndex] = pip
            end
            -- Update shows the row unless the style is "none".
            comboPipHolder:Hide()

            -- A 1px line in the frame border colour along the bottom, for the
            -- "above" position only; sublevel 7 keeps it over the pips (3).
            local cpBottomBdr = comboPipHolder:CreateTexture(nil, "OVERLAY", nil, 7)
            cpBottomBdr:SetHeight(1)
            Pix.Point(cpBottomBdr, "BOTTOMLEFT", comboPipHolder, "BOTTOMLEFT", 0, 0)
            Pix.Point(cpBottomBdr, "BOTTOMRIGHT", comboPipHolder, "BOTTOMRIGHT", 0, 0)
            local edgeColor = prefs.borderColor or { r = 0, g = 0, b = 0 }
            cpBottomBdr:SetColorTexture(edgeColor.r, edgeColor.g, edgeColor.b, 1)
            cpBottomBdr:Hide()
            comboPipHolder._bottomBdr = cpBottomBdr
        end
    end

    -- Border: a plain frame on barArea with four edge textures sized through
    -- PixelUtil. Never BackdropTemplate: its edgeSize clipping drops sides on
    -- small frames and its snapping cannot be turned off. It wraps the health
    -- and power bars and an attached Text Bar.
    local bdrSize = prefs.borderSize or 1
    local bdrColor = prefs.borderColor or { r = 0, g = 0, b = 0 }
    local bdrTexKey = prefs.borderTexture or "solid"
    local edgeFrame = CreateFrame("Frame", nil, popFrame)
    edgeFrame:SetPoint("TOPLEFT", barRegion, "TOPLEFT", 0, 0)
    edgeFrame:SetPoint("TOPRIGHT", barRegion, "TOPRIGHT", 0, 0)
    local barPosNow = prefs.btbPosition or "bottom"
    local wrapsTextBar = prefs.bottomTextBar and (barPosNow == "top" or barPosNow == "bottom")
    edgeFrame:SetHeight(
        prefs.healthHeight + initPpExtra + (wrapsTextBar and (prefs.bottomTextBarHeight or 16) or 0)
    )
    edgeFrame:SetFrameLevel(barRegion:GetFrameLevel() + 5)
    local edgePx = CludesUI.BorderPx(prefs.borderSizePx, bdrSize, bdrTexKey)
    CludesUI.ApplyBorderStyle(
        edgeFrame,
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
        edgePx
    )
    if bdrSize == 0 and bdrTexKey == "solid" then
        edgeFrame:Hide()
    end

    -- Places an absorb StatusBar for its edge mode, as the live
    -- UpdateAbsorbBarReverseFill (CUI_UnitFrames_Absorb.lua) does. "right" /
    -- "left" pin it to that end of the health bar, filling inward whatever
    -- the reverse fill; the overlay reverse modes fill into the health fill
    -- from its leading edge (the clip trims the rest, and the preview shield
    -- never outgrows health, so Full looks the same); plain overlay fills the
    -- missing health from the current-health edge. Vertical fill swaps the
    -- axis but keeps the key names: "right" is the top, "left" the bottom.
    local function PositionPreviewAbsorb(barFrame, modeName, isRev, isVert)
        if not barFrame then
            return
        end
        barFrame:ClearAllPoints()
        barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        mod.ApplyFillRotation(barFrame)
        local near, far, sideA, sideB = "LEFT", "RIGHT", "TOP", "BOTTOM"
        if isVert then
            near, far, sideA, sideB = "BOTTOM", "TOP", "LEFT", "RIGHT"
        end
        -- own: the bar's end that is pinned; onto: the target end it pins to.
        local target, own, onto = healthFill, nil, nil
        if modeName == "right" or modeName == "left" then
            target = healthBar
            own = (modeName == "right") and far or near
            onto = own
        elseif modeName == "overlayReverse" or modeName == "overlayReverseFull" then
            own = isRev and near or far
            onto = own
        else
            own = isRev and far or near
            onto = isRev and near or far
        end
        barFrame:SetReverseFill(own == far)
        local function Corner(axisEnd, crossSide)
            return isVert and (axisEnd .. crossSide) or (crossSide .. axisEnd)
        end
        barFrame:SetPoint(Corner(own, sideA), target, Corner(onto, sideA), 0, 0)
        barFrame:SetPoint(Corner(own, sideB), target, Corner(onto, sideB), 0, 0)
    end

    -- Absorb bars (player, target and focus), drawn in the chosen styles:
    -- the shield absorb underneath and the heal absorb one sublevel above
    -- it. On the preview the two take turns: the heal absorb shows only
    -- while its Heal Absorb Style eye is on, which hides the shield.
    local absorbFill, healAbsorbFill, absorbTopBar, healAbsorbTopBar
    local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
    local STRIPED_TEX = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga"
    -- Paints an absorb StatusBar: texture from the style (SharedMedia names
    -- go through the bar texture lookup), tiled where the style tiles, at the
    -- given draw sublevel and colour, placed for its edge mode. Shared with
    -- pf:Update (reached through pf: Update is at the upvalue cap).
    local function PaintAbsorb(barFrame, cfg, style, fallbackTex, sublevel, red, green, blue, a, edgeMode)
        barFrame:SetStatusBarTexture(mod.ResolveAbsorbStyleTex(style, fallbackTex))
        local fill = barFrame:GetStatusBarTexture()
        if fill then
            fill:SetDrawLayer("ARTWORK", sublevel)
            local tiled = (mod.ABSORB_TILED_STYLES[style] == true)
            fill:SetHorizTile(tiled)
            fill:SetVertTile(tiled)
        end
        barFrame:SetStatusBarColor(red, green, blue, a)
        PositionPreviewAbsorb(barFrame, edgeMode or "overlay", cfg.healthReverseFill, cfg.healthVerticalFill)
    end
    -- The shield absorb's look. Its opacity follows the live GetAbsorbOpacity
    -- (CUI_UnitFrames_Absorb.lua): the set opacity, else the style's own.
    local function PaintShield(barFrame, cfg)
        local style = cfg.showPlayerAbsorb
        local STYLE_ALPHA = {
            striped = 0.8,
            stripedReversed = 0.8,
            clean = (cfg.absorbCleanAlpha or 30) / 100,
            blizzard = 0.8,
        }
        local a = cfg.absorbOpacity and (cfg.absorbOpacity / 100) or STYLE_ALPHA[style] or 0.8
        local color = cfg.absorbColor or { r = 1, g = 1, b = 1 }
        PaintAbsorb(barFrame, cfg, style, STRIPED_TEX, 1, color.r, color.g, color.b, a, cfg.absorbEdgeMode)
        return style
    end
    -- The heal absorb's look: red by default; the outlined stripe styles
    -- carry their own colour, so those draw untinted.
    local function PaintHealAbsorb(barFrame, cfg, style)
        local color = cfg.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
        if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then
            color = { r = 1, g = 1, b = 1 }
        end
        local a = (cfg.healAbsorbOpacity or 65) / 100
        PaintAbsorb(
            barFrame,
            cfg,
            style,
            WHITE_TEX,
            2,
            color.r or 0.8,
            color.g or 0.15,
            color.b or 0.15,
            a,
            cfg.healAbsorbEdgeMode
        )
    end
    popFrame._paintShield = PaintShield
    popFrame._paintHealAbsorb = PaintHealAbsorb
    if unitName == "player" or unitName == "target" or unitName == "focus" then
        -- The fills hang off the health fill's current-health edge at full
        -- frame width, so a high preview fill would run past the bar; the
        -- live frames clamp, and this clip to the health bar does the same.
        local absClip = CreateFrame("Frame", nil, healthBar)
        absClip:SetAllPoints(healthBar)
        absClip:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        absClip:SetClipsChildren(true)

        local function SizeAbsorbBar(barFrame)
            Pix.Width(barFrame, frameW)
            Pix.Height(barFrame, healthH)
            barFrame:SetMinMaxValues(0, 1)
            barFrame:SetValue(0.14)
            barFrame:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        end
        absorbFill = CreateFrame("StatusBar", nil, absClip)
        local absStyle = PaintShield(absorbFill, prefs)
        SizeAbsorbBar(absorbFill)
        if not absStyle or absStyle == "none" then
            absorbFill:Hide()
        end
        healAbsorbFill = CreateFrame("StatusBar", nil, absClip)
        PaintHealAbsorb(healAbsorbFill, prefs, prefs.healAbsorbStyle or "clean")
        SizeAbsorbBar(healAbsorbFill)
        healAbsorbFill:Hide()
        -- A black backing (Heal Absorb Background Opacity) one sublevel under
        -- the heal absorb fill, following its rect.
        local healBack = healAbsorbFill:CreateTexture(nil, "ARTWORK", nil, 1)
        healBack:SetColorTexture(0, 0, 0, (prefs.healAbsorbBgOpacity or 15) / 100)
        healBack:SetAllPoints(healAbsorbFill:GetStatusBarTexture())
        healAbsorbFill._bg = healBack

        -- Max Health Style (its eye): a fixed reduced maximum on the bar's far
        -- end, styled by the live frames' own function; pf:Update drives it.
        local maxHp = CreateFrame("StatusBar", nil, healthBar)
        maxHp:SetAllPoints(healthBar)
        maxHp:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        maxHp:SetMinMaxValues(0, 1)
        maxHp:SetValue(0.2)
        maxHp._bg = maxHp:CreateTexture(nil, "ARTWORK", nil, 2)
        maxHp:Hide()
        popFrame._pvMaxHp = maxHp

        -- Heal Prediction (its eye): other players' heals at the whole incoming
        -- total underneath, yours over them, both from the health edge. Their
        -- holder clips at the bar's end unless Overheal lets them run on.
        -- Kept on pf (this builder is long); pf:Update drives them.
        local predHolder = CreateFrame("Frame", nil, healthBar)
        predHolder:SetAllPoints(healthBar)
        predHolder:SetFrameLevel(healthBar:GetFrameLevel() + 1)
        popFrame._pvPredHolder = predHolder
        for layer, key in ipairs({ "_pvPredOther", "_pvPredMy" }) do
            local barFrame = CreateFrame("StatusBar", nil, predHolder)
            barFrame:SetStatusBarTexture(WHITE_TEX)
            barFrame:SetMinMaxValues(0, 1)
            barFrame:SetFrameLevel(healthBar:GetFrameLevel() + layer)
            barFrame:Hide()
            popFrame[key] = barFrame
        end

        -- The Absorb and Heal Absorb strips, on pf so an "above" strip can sit
        -- outside the health bar; placed further down.
        local function StripBar()
            local barFrame = CreateFrame("StatusBar", nil, popFrame)
            barFrame:SetStatusBarTexture(WHITE_TEX)
            barFrame:SetMinMaxValues(0, 1)
            barFrame:SetValue(0.45)
            barFrame:Hide()
            return barFrame
        end
        absorbTopBar = StripBar()
        healAbsorbTopBar = StripBar()
    end
    popFrame._absorbBar = absorbFill
    popFrame._healAbsorbBar = healAbsorbFill
    popFrame._absorbTopBar = absorbTopBar
    popFrame._healAbsorbTopBar = healAbsorbTopBar

    -- A sample aura icon: black edge (the backdrop showing round the icon's
    -- 1px inset, like the live black border), raised past the border frame
    -- (barArea + 5) and its pixel border holder (barArea + 6).
    local function SampleAuraIcon(size, iconID)
        local iconTex = CreateFrame("Frame", nil, popFrame, "BackdropTemplate")
        Pix.Size(iconTex, size, size)
        iconTex:SetBackdrop(SOLID_BACKDROP)
        iconTex:SetBackdropColor(0, 0, 0, 1)
        iconTex:SetFrameLevel(barRegion:GetFrameLevel() + 7)
        local art = iconTex:CreateTexture(nil, "ARTWORK")
        Pix.Point(art, "TOPLEFT", iconTex, "TOPLEFT", 1, -1)
        Pix.Point(art, "BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", -1, 1)
        art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        art:SetTexture(iconID)
        iconTex._iconTex = art
        return iconTex
    end

    -- Two sample buffs on every unit, shown while Show Buffs is on with an anchor.
    local buffIcons = {}
    do
        local size = prefs.buffSize or 22
        local buffsShown = prefs.showBuffs and (prefs.buffAnchor or "topleft") ~= "none"
        for slot = 1, 2 do
            local iconTex = SampleAuraIcon(size, _previewBuffIcons[slot] or 135932)
            Pix.Point(iconTex, "BOTTOMLEFT", popFrame, "TOPLEFT", (slot - 1) * (size + 1), 1)
            buffIcons[slot] = iconTex
            if not buffsShown then
                iconTex:Hide()
            end
        end
    end

    -- Twenty sample debuffs on every unit with debuffs, shown while the
    -- debuff anchor is set. Each carries a still cooldown swipe (an hour
    -- long, parked at a fixed share so the wedge never moves) and still
    -- duration and stack numbers, which only the boss preview shows (pf:Update
    -- sizes them from the boss aura settings).
    local debuffIcons = {}
    do
        local size = prefs.debuffSize or 22
        local ICON_IDS = {}
        local idList = "136116 132099 136182 136214 132155 136201 136148 136175 136130 136160"
            .. " 136195 136133 136222 136168 136205 136186 136124 136151 136210 136143"
        for id in idList:gmatch("%d+") do
            ICON_IDS[#ICON_IDS + 1] = tonumber(id)
        end
        local auraFont = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        local debuffsHidden = noDebuffPreview or (prefs.debuffAnchor or "bottomleft") == "none"
        for slot = 1, 20 do
            local iconTex = SampleAuraIcon(size, ICON_IDS[slot] or 136116)
            Pix.Point(iconTex, "TOPLEFT", popFrame, "BOTTOMLEFT", (slot - 1) * (size + 1), -1)
            local step = (slot - 1) % 5
            local swipe = CreateFrame("Cooldown", nil, iconTex, "CooldownFrameTemplate")
            swipe:SetPoint("TOPLEFT", iconTex, "TOPLEFT", 1, -1)
            swipe:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", -1, 1)
            swipe:SetFrameLevel(iconTex:GetFrameLevel() + 1)
            swipe:SetDrawEdge(false)
            swipe:SetDrawBling(false)
            swipe:SetReverse(false)
            swipe:SetDrawSwipe(true)
            swipe:SetSwipeColor(0, 0, 0, 0.6)
            swipe:SetHideCountdownNumbers(true)
            swipe:SetCooldown(GetTime() - 3600 * (1 - (0.25 + step * 0.15)), 3600)
            swipe:Hide()
            iconTex._previewCD = swipe
            local numbers = CreateFrame("Frame", nil, iconTex)
            numbers:SetAllPoints(iconTex)
            numbers:SetFrameLevel(swipe:GetFrameLevel() + 1)
            local durText = numbers:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(durText, auraFont, 10, "unitFrames")
            durText:SetPoint("CENTER", iconTex, "CENTER", 0, 0)
            durText:SetText(4 + step * 5)
            durText:Hide()
            iconTex._durText = durText
            local stackText = numbers:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(stackText, auraFont, 14, "unitFrames")
            stackText:SetText(2 + step)
            stackText:Hide()
            iconTex._stackText = stackText
            debuffIcons[slot] = iconTex
            if debuffsHidden then
                iconTex:Hide()
            end
        end
    end

    -- Disabled overlay: on UIParent (pf's strata would cap it) so it covers
    -- every child of the preview. pf owns it, so the next dress of the same
    -- preview frame gets the same overlay back (hidden when pf is reset).
    local disabledOverlay = PoolOwned(popFrame, "disabled", "Frame", UIParent, "BackdropTemplate")
    disabledOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    disabledOverlay:SetBackdrop(SOLID_BACKDROP)
    disabledOverlay:SetBackdropColor(0, 0, 0, 0.6)
    disabledOverlay:Hide()
    local disabledText = disabledOverlay:CreateFontString(nil, "OVERLAY")
    SetPVFont(disabledText, PREVIEW_FONT, 11)
    disabledText:SetTextColor(1, 1, 1)
    disabledText:SetText(CludesUI.L("Disabled"))
    -- Lays the overlay over pf at pf's scale, its label centred (run on
    -- every Update and whenever the preview shows).
    local function SyncDisabledOverlay()
        disabledOverlay:ClearAllPoints()
        disabledOverlay:SetScale(popFrame:GetScale())
        disabledOverlay:SetPoint("TOPLEFT", popFrame, "TOPLEFT", 0, 0)
        disabledOverlay:SetPoint("BOTTOMRIGHT", popFrame, "BOTTOMRIGHT", 0, 0)
        disabledText:ClearAllPoints()
        disabledText:SetPoint("CENTER", disabledOverlay, "CENTER", 0, 0)
    end
    SyncDisabledOverlay()
    -- The overlay lives on UIParent, so it hides with the preview (tab or
    -- module switch, page cache stash, the panel folding to its mini
    -- window) and comes back when the preview shows again without an
    -- Update (unfolding the panel runs no OnShow callback).
    popFrame:HookScript("OnHide", function()
        disabledOverlay:Hide()
    end)
    popFrame:HookScript("OnShow", function()
        local sourceKey = unitName:match("^boss") and "boss" or unitName
        if mod.GetUnitFrameSource(sourceKey) == "cui" then
            return
        end
        SyncDisabledOverlay()
        disabledOverlay:Show()
    end)

    -- Indicator samples on one holder above everything else: the combat
    -- icon (centred on the portrait, else the health bar), the faction
    -- icon (player and target), and the raid marker, leader and elite
    -- icons, each behind its row's eye. Kept on pf (this builder is long).
    local COMBAT_MEDIA_P = "Interface\\AddOns\\CludesUI\\media\\combat\\"
    local combatIndHolder = CreateFrame("Frame", nil, popFrame)
    combatIndHolder:SetAllPoints(popFrame)
    combatIndHolder:SetFrameLevel(popFrame:GetFrameLevel() + 20)
    local function IndicatorTex(sublevel)
        local texture = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, sublevel)
        texture:Hide()
        return texture
    end
    local combatIcon = IndicatorTex(7)
    combatIcon:SetSize(24, 24)
    combatIcon:SetPoint("CENTER", portraitHolder or healthBar, "CENTER", 0, 0)
    popFrame._combatIndicator = combatIcon
    local factionInd = IndicatorTex(6)
    popFrame._factionIndicator = factionInd
    popFrame._pvRaid = IndicatorTex(6)
    popFrame._pvRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    popFrame._pvLeader = IndicatorTex(6)
    popFrame._pvLeader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    popFrame._pvElite = IndicatorTex(6)
    popFrame._pvElite:SetAtlas("nameplates-icon-elite-gold")
    -- WoW Forever: the pet's happiness icon (the happy face as the sample),
    -- placed beside the frame on each Update as the live one is. Its own
    -- frame lets the page's click overlay show and hide with it.
    if unitName == "pet" and CludesUI.IS_FOREVER == true then
        local happyInd = CreateFrame("Frame", nil, popFrame)
        happyInd:SetFrameLevel(popFrame:GetFrameLevel() + 20)
        local face = happyInd:CreateTexture(nil, "OVERLAY")
        face:SetAllPoints()
        face:SetAtlas("UI-PetHappiness")
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
    local function ApplyBlizzPreview(cfg, G, mirror, extras, ch, drop)
        local levelText = popFrame:GetFrameLevel()
        local pct = optionState._previewHealthPct or 0.70
        local ppct = optionState._previewPowerPct or 0.85
        local isMini = G.small and true or false
        -- Hide Power Bar: a main frame's health bar takes the power track too,
        -- as live (with the cut art where the art draws over the bars).
        local merged = not isMini
            and G.power ~= nil
            and mod.UF_IsMainSettings(cfg)
            and mod.UF_StockHidesPower(cfg)
        local HB = merged and mod.UF_MergedHealth(G) or G.health
        barRegion._blizzMerged = merged or nil
        barRegion._blizzMergeCut = (merged and G.merge) or nil

        -- Art box: the stock box, hung so its transparent top rows sit above
        -- pf (pf spans only the visible art, plus the cast bar strip below).
        local padTop = G.pad and G.pad.top or 0
        local padBottom = G.pad and G.pad.bottom or 0
        barRegion:ClearAllPoints()
        barRegion:SetPoint("TOPLEFT", popFrame, "TOPLEFT", 0, padTop)
        barRegion:SetSize(G.w, G.h)

        -- Art: one texture on its own child frame, centred on the art box
        -- (the module painter reads the mirror stamp and the texture host
        -- off the box frame it is handed).
        local artFrame = popFrame._blizzArtFrame
        if not artFrame then
            artFrame = CreateFrame("Frame", nil, popFrame)
            artFrame:SetAllPoints(barRegion)
            artFrame:EnableMouse(false)
            popFrame._blizzArtFrame = artFrame
        end
        -- Art over or under the bars as the kit layers it (the classic
        -- target and pet arts draw over their transparent bar windows).
        artFrame:SetFrameLevel(G.artAbove and (levelText + 5) or (levelText + 2))
        barRegion._blizzArtFrame = artFrame
        barRegion._blizzMirror = mirror
        -- The boss preview wears the classic kit's whole-frame boss art.
        local artEntry = (extras and unitName == "boss" and G.artByClass and G.artByClass.boss) or G.art
        -- Hide Power Bar repaints it too: the stock atlas art's cut has no kit spec.
        local cut, mergedArt = barRegion._blizzMergeCut, merged or nil
        if
            artFrame._artAtlas ~= artEntry
            or artFrame._artMirror ~= mirror
            or artFrame._artCutSpec ~= cut
            or artFrame._artMerged ~= mergedArt
        then
            artFrame._artAtlas, artFrame._artMirror, artFrame._artCutSpec, artFrame._artMerged = artEntry, mirror, cut, mergedArt
            mod.UF_PaintBlizzArt(barRegion, artEntry)
        end
        -- The dark plaque behind the name and bars (classic kit), under the art.
        if G.back then
            local bk = popFrame._blizzBack
            if not bk then
                bk = barRegion:CreateTexture(nil, "BACKGROUND", nil, -2)
                bk:SetColorTexture(0, 0, 0, 0.5)
                popFrame._blizzBack = bk
            end
            bk:ClearAllPoints()
            mod.UF_BlizzPoint(bk, "TOPLEFT", barRegion, "TOPLEFT", G.back.x, -G.back.y, mirror)
            bk:SetSize(G.back.w, G.back.h)
            bk:Show()
        elseif popFrame._blizzBack then
            popFrame._blizzBack:Hide()
        end
        -- Type strip (the preview's target is hostile: the stock strip over
        -- the art, or the classic name plaque under it) and the boss dragon.
        local repArt = extras and G.rep and (G.rep.art or G.rep.atlas)
        if repArt and mod.UF_ArtOK(repArt) and mod.UF_BlizzHeaderOn(cfg) then
            local rep = artFrame._rep
            if not rep then
                rep = artFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
                artFrame._rep = rep
            end
            mod.UF_SetArt(rep, repArt, true)
            rep:SetDrawLayer("BACKGROUND", G.rep.below and -1 or 1)
            rep:ClearAllPoints()
            local rp = G.rep.point or "TOPRIGHT"
            rep:SetPoint(rp, barRegion, rp, G.rep.x, G.rep.y)
            rep:SetVertexColor(1, 0, 0)
            rep:Show()
        elseif artFrame._rep then
            artFrame._rep:Hide()
        end
        local dragon = extras and unitName == "boss" and G.boss and G.boss.winged
        if dragon and mod.UF_AtlasOK(dragon) then
            local d = artFrame._dragon
            if not d then
                d = artFrame:CreateTexture(nil, "BACKGROUND", nil, 2)
                artFrame._dragon = d
            end
            mod.UF_StockAtlas(d, dragon, true)
            d:ClearAllPoints()
            -- The kit's own spot where it has one (WoW Forever).
            local dp = G.boss.pos and G.boss.pos.winged
            d:SetPoint("TOPRIGHT", barRegion, "TOPRIGHT", dp and dp[1] or 8, dp and dp[2] or -8)
            d:Show()
        elseif artFrame._dragon then
            artFrame._dragon:Hide()
        end
        -- The level number in the art's level circle (your own level as the
        -- sample), following Show Level and the level's size and offsets. The
        -- string exists whenever the art has a circle (hidden while off), so
        -- the page builds its click overlay once and it follows the toggle.
        local Lv, B = G.level, G.badge
        local lf, lb = artFrame._level, artFrame._levelBadge
        if Lv and not lf then
            lf = artFrame:CreateFontString(nil, "OVERLAY")
            lf:SetFontObject(GameNormalNumberFont)
            artFrame._level = lf
            popFrame._levelFS = lf
        end
        -- WoW Forever: the round level badge behind the number.
        if B and not lb then
            lb = artFrame:CreateTexture(nil, "OVERLAY", nil, -1)
            mod.UF_SetArt(lb, B.atlas)
            artFrame._levelBadge = lb
        end
        local lvOn = Lv and cfg.blizzShowLevel ~= false
        if lb then
            lb:SetShown((lvOn and B) and true or false)
        end
        if not lvOn then
            if lf then
                lf:Hide()
            end
        else
            -- The name's font object (its shadow) and face, as live; a name on
            -- a font family lends its roman member's face. (Called plainly:
            -- `nf and nf:GetFont()` would keep only the face.)
            local nf = popFrame._nameFS
            if nf then
                local fo = nf:GetFontObject()
                local family = fo and CludesUI._fontFamilySet[fo]
                local source = (family and fo:GetFontObjectForAlphabet("roman")) or nf
                local face, size, flags = source:GetFont()
                if face then
                    if fo then
                        lf:SetFontObject(fo)
                    end
                    lf:SetFont(face, cfg.blizzLevelSize or size, flags)
                end
            end
            lf:ClearAllPoints()
            lf:SetJustifyH(Lv.justify or "CENTER")
            -- With a badge the badge takes the offsets and the number centres on it.
            local onto, dx, dy = barRegion, cfg.blizzLevelX or 0, cfg.blizzLevelY or 0
            if B then
                lb:SetSize(B.size, B.size)
                lb:ClearAllPoints()
                mod.UF_BlizzPoint(lb, B.point, barRegion, B.point, B.x + dx, B.y + dy, mirror)
                onto, dx, dy = lb, 0, 0
            end
            mod.UF_BlizzPoint(lf, Lv.point, onto, Lv.relPoint or Lv.point, Lv.x + dx, Lv.y + dy, mirror)
            -- WoW Forever paints the player's own level white; else stock gold.
            local white = B and unitName == "player"
            lf:SetTextColor(1, white and 1 or 0.82, white and 1 or 0)
            lf:SetText(UnitLevel("player"))
            lf:Show()
        end
        if popFrame._levelOv then
            popFrame._levelOv:SetShown(lvOn and true or false)
        end

        -- Health bar at the stock spot, filling sideways (the stock track has
        -- no upright variant), in the colours, texture, gradient and opacity set.
        healthBar:ClearAllPoints()
        mod.UF_BlizzPoint(healthBar, "TOPLEFT", barRegion, "TOPLEFT", HB.x, -HB.y, mirror)
        healthBar:SetSize(HB.w, HB.h)
        healthBar:SetFrameLevel(levelText + 3)
        -- The absorb pieces sit one level over the bars.
        local absClip = absorbFill and absorbFill:GetParent()
        if absClip and absClip ~= healthBar then
            absClip:SetFrameLevel(levelText + 4)
        end
        for _, piece in ipairs({
            absorbFill or false,
            healAbsorbFill or false,
            absorbTopBar or false,
            healAbsorbTopBar or false,
        }) do
            if piece then
                piece:SetFrameLevel(levelText + 4)
            end
        end
        local hpW = math.floor(HB.w * pct + 0.5)
        healthFill:ClearAllPoints()
        healthBgColor:ClearAllPoints()
        local fromRight = cfg.healthReverseFill
        local fillEdge = fromRight and "RIGHT" or "LEFT"
        healthFill:SetPoint("TOP" .. fillEdge, healthBar, "TOP" .. fillEdge, 0, 0)
        healthFill:SetPoint("BOTTOM" .. fillEdge, healthBar, "BOTTOM" .. fillEdge, 0, 0)
        healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", fromRight and 0 or hpW, 0)
        healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", fromRight and -hpW or 0, 0)
        healthFill:SetWidth(hpW)
        for _, barFrame in ipairs({ absorbFill or false, healAbsorbFill or false }) do
            if barFrame then
                barFrame:SetSize(HB.w, HB.h)
            end
        end
        -- The stock rounded mask goes on everything in the track (a mirrored
        -- small frame runs unmasked: masks cannot flip), then the bar's bevel.
        local hm = healthBar._blizzMask
        local hMaskOK = not mirror and mod.UF_AtlasOK(G.health.mask)
        -- Everything drawn in the track, in one reused list refilled each pass
        -- (a style change can swap the absorb fills).
        local hTex = popFrame._blizzTrackTex
        if not hTex then
            hTex = {}
            popFrame._blizzTrackTex = hTex
        end
        table.wipe(hTex)
        local function Track(region)
            if region then
                hTex[#hTex + 1] = region
            end
        end
        Track(healthFill)
        Track(healthBg)
        Track(healthBgColor)
        Track(healthBar._cuiBgTex) -- the Textured Background layer
        Track(dispelPreview)
        Track(absorbFill and absorbFill:GetStatusBarTexture())
        if healAbsorbFill then
            Track(healAbsorbFill:GetStatusBarTexture())
            Track(healAbsorbFill._bg)
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

        -- Power: the small frames carry the stock bar (the mock has none, so a
        -- plain one is made here once); a main frame's attached bar moves into
        -- the track, and a detached one keeps its own spot.
        local powerW = powerBar
        if isMini then
            powerW = popFrame._blizzPower
            if not powerW then
                powerW = CreateFrame("Frame", nil, popFrame)
                local back = powerW:CreateTexture(nil, "BACKGROUND")
                back:SetAllPoints()
                back:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
                local barFrame = powerW:CreateTexture(nil, "ARTWORK")
                barFrame:SetPoint("TOPLEFT", powerW, "TOPLEFT", 0, 0)
                barFrame:SetPoint("BOTTOMLEFT", powerW, "BOTTOMLEFT", 0, 0)
                powerW._bg, powerW._fill = back, barFrame
                popFrame._blizzPower = powerW
            end
            -- The small frames' bar wears the donor's texture, as live, with
            -- the Textured Background under it.
            local donor = mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitName)
                or saved.profile.player
            local texKey = mod.ResolveHealthBarTextureKey(cfg, donor)
            local _, kind = UnitPowerType("player")
            local tint = CludesUI.GetPowerColor(kind or "MANA")
            PV_FillColor(
                powerW._fill,
                (mod.healthBarTextures or {})[texKey],
                tint.r,
                tint.g,
                tint.b,
                nil,
                nil,
                nil,
                1
            )
            local _, backTex = mod.UF_TexBgPaths(unitName, cfg, texKey)
            mod.UF_TexBgPaint(powerW._bg, backTex, 17 / 255, 17 / 255, 17 / 255, 1)
        end
        local pPos = mod.UF_PowerPos(cfg)
        local inTrack = powerW and (isMini or pPos == "below" or pPos == "above")
        if inTrack then
            -- A mirrored small frame's bar runs unmasked, so it ends where the
            -- health bar does (as live, UF_ApplyBlizzardLayout).
            local px, pwid = G.power.x, G.power.w
            if isMini and mirror and px < HB.x then
                pwid = pwid - (HB.x - px)
                px = HB.x
            end
            powerW:ClearAllPoints()
            mod.UF_BlizzPoint(powerW, "TOPLEFT", barRegion, "TOPLEFT", px, -G.power.y, mirror)
            powerW:SetSize(pwid, G.power.h)
            powerW:SetFrameLevel(levelText + 3)
            local fill = powerW._fill or popFrame._powerFill
            local backdrop = powerW._bg or popFrame._powerBg
            if fill then
                fill:ClearAllPoints()
                local fillEdge = (not isMini and cfg.powerReverseFill) and "RIGHT" or "LEFT"
                fill:SetPoint("TOP" .. fillEdge, powerW, "TOP" .. fillEdge, 0, 0)
                fill:SetPoint("BOTTOM" .. fillEdge, powerW, "BOTTOM" .. fillEdge, 0, 0)
                fill:SetWidth(math.floor(pwid * ppct + 0.5))
            end
            local pm = powerW._blizzMask
            local pMaskOK = not mirror and mod.UF_AtlasOK(G.power.mask)
            if pMaskOK then
                if not pm then
                    pm = powerW:CreateMaskTexture()
                    powerW._blizzMask = pm
                end
                mod.UF_SeatBarMask(pm, powerW, G.power)
                mod.UF_SetMask(fill, pm)
                mod.UF_SetMask(backdrop, pm)
                mod.UF_SetMask(popFrame._pvCostSeg, pm)
            elseif pm then
                if fill then
                    pcall(fill.RemoveMaskTexture, fill, pm)
                end
                if backdrop then
                    pcall(backdrop.RemoveMaskTexture, backdrop, pm)
                end
                local cs = popFrame._pvCostSeg
                if cs then
                    pcall(cs.RemoveMaskTexture, cs, pm)
                end
            end
            mod.UF_BlizzBarShadow(powerW, pMaskOK and pm or nil, G.power.h)
            if isMini or (cfg.powerHeight or 6) > 0 then
                powerW:Show()
            end
        elseif powerW and powerW._blizzMask then
            -- Detached now: the track pieces come off.
            local fill = popFrame._powerFill
            if fill then
                pcall(fill.RemoveMaskTexture, fill, powerW._blizzMask)
            end
            if popFrame._powerBg then
                pcall(popFrame._powerBg.RemoveMaskTexture, popFrame._powerBg, powerW._blizzMask)
            end
            if powerW._blizzShadow then
                for idx = 1, 4 do
                    powerW._blizzShadow[idx]:Hide()
                end
            end
        end
        -- Hide Power Bar keeps the bar down, and its text with it (the text's
        -- own frame, which carries its click overlay).
        if merged and powerW then
            powerW:Hide()
        end
        local ppOv = ppPreviewFS and ppPreviewFS:GetParent()
        if ppOv then
            ppOv:SetShown(not merged)
        end

        -- Portrait: always shown, at the stock spot and size under the art,
        -- in the stock mask. 3D cannot be masked, so 2D art stands in for it
        -- as on the live frame, and every CludesUI portrait extra steps aside.
        if portraitHolder then
            local P = G.portrait
            portraitHolder:Show()
            portraitHolder:ClearAllPoints()
            mod.UF_BlizzPoint(portraitHolder, P.point, barRegion, P.point, P.x, P.y, mirror)
            portraitHolder:SetSize(P.size, P.size)
            portraitHolder:SetFrameLevel(levelText + 1)
            portraitHolder:SetClipsChildren(false)
            local function HideIf(region)
                if region then
                    region:Hide()
                end
            end
            HideIf(portraitHolder._previewBg)
            HideIf(portraitHolder._shapeBorderTex)
            for _, edge in ipairs(portraitHolder._sqBorderTexs or {}) do
                edge:Hide()
            end
            mod.UF_PortraitExtras(portraitHolder, nil)
            mod.UF_PortraitDragon(portraitHolder, nil)
            local texture = portraitHolder._previewTex
            local shapeMask = portraitHolder._shapeMask
            if shapeMask then
                if texture then
                    pcall(texture.RemoveMaskTexture, texture, shapeMask)
                end
                shapeMask:Hide()
            end
            local model = portraitHolder._previewModel
            if model and model:IsShown() then
                model:Hide()
            end
            if texture then
                texture:Show()
                if (cfg.portraitMode or "2d") ~= "class" then
                    -- The third argument turns the client's own round crop off
                    -- where the stock mask is not a circle (the player frame).
                    SetPortraitTexture(texture, "player", P.rawArt)
                    texture:SetTexCoord(0, 1, 0, 1)
                    texture:SetAlpha(1)
                    texture:ClearAllPoints()
                    texture:SetPoint("TOPLEFT", portraitHolder, "TOPLEFT", 0, 0)
                    texture:SetPoint("BOTTOMRIGHT", portraitHolder, "BOTTOMRIGHT", 0, 0)
                end
                if mod.UF_AtlasOK(P.mask) then
                    local m = portraitHolder._blizzMask
                    if not m then
                        m = portraitHolder:CreateMaskTexture()
                        m:SetAllPoints(portraitHolder)
                        portraitHolder._blizzMask = m
                    end
                    mod.UF_StockMask(m, P.mask)
                    m:Show()
                    mod.UF_SetMask(texture, m)
                end
            end
        end

        -- The left text moves onto the name strip; the other slots stay on the bar.
        local nameSpot = G.name
        if nameSpot and leftFS:IsShown() then
            leftFS:ClearAllPoints()
            leftFS:SetJustifyH(nameSpot.justify or "LEFT")
            local dx, dy = cfg.leftTextX or 0, cfg.leftTextY or 0
            -- UF_BlizzPoint mirrors x, so the user's X offset is flipped first
            -- to stay screen-relative.
            local x = nameSpot.x + (mirror and -dx or dx)
            mod.UF_BlizzPoint(leftFS, nameSpot.point, barRegion, nameSpot.point, x, nameSpot.y + dy, mirror)
            leftFS:SetWidth(nameSpot.w)
        end

        -- No CludesUI chrome: the border and the Text Bar make way for the art.
        edgeFrame:Hide()
        if btbFrame then
            btbFrame:Hide()
        end

        -- Cast bar: under the art box (no Text Bar between them now), or on
        -- the frames whose bar hangs off the aura block, under the lowest
        -- bottom aura stack (`drop`, from Update); in the stock background,
        -- fill art, frame and text box.
        if castBar and castBar:IsShown() and ch > 0 then
            local inW = mod.UF_CastIconInWidth(unitName, cfg)
            local onRight = cfg[unitName == "player" and "playerCastbarIconRight" or "castbarIconRight"] == true
            local UFC = mod.UF_CAST_BLIZZ
            -- The classic kit's own cast chrome (nil on the stock kit): the
            -- vanilla frame round the user's own fill, and no stock
            -- background, fill art or text box.
            local CK = mod.UF_BLIZZ.cast
            local function StockAtlas(key)
                return (not CK) and UFC and mod.UF_BlizzAtlas(UFC[key])
            end
            -- The stock text box (while the spell name shows) hangs 13px under
            -- the bar and the icon spans bar and box, as live; an icon that
            -- is part of the bar moves the bar half that width to centre the pair.
            local tbAtlas = StockAtlas("textbox")
            local nameSide = cfg.castSpellNameSide or "left"
            local tbOn = tbAtlas and castNameText and nameSide ~= "none"
            local icoW = ch + (tbOn and 13 or 0)
            local shift = 0
            if inW then
                shift = onRight and -(icoW / 2) or (icoW / 2)
            end
            castBar:ClearAllPoints()
            castBar:SetPoint("TOP", barRegion, "BOTTOM", shift, padBottom - (drop or 0))
            if castIconHolder then
                castIconHolder:SetSize(icoW, icoW)
            end
            -- The retail background, under WoW Forever too, as live.
            local bgAtlas = StockAtlas("bg")
            local backTex = castBar._previewBgTex
            if bgAtlas and backTex then
                CludesUI.StockAtlas(backTex, bgAtlas)
                backTex:ClearAllPoints()
                backTex:SetPoint("TOPLEFT", castBar, "TOPLEFT", -1, 1)
                backTex:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 1, -1)
            end
            local fillAtlas = StockAtlas("cast")
            if fillAtlas and castFill then
                castFill:SetAtlas(fillAtlas)
                castFill:SetVertexColor(1, 1, 1, 1)
            end
            Pix.HideBorder(castBar)
            if castIconHolder then
                -- Bare art as live: no plate, border or 1px inset (Update
                -- re-seats the inset each pass; this runs after it).
                Pix.HideBorder(castIconHolder)
                if castIconHolder._bg then
                    castIconHolder._bg:Hide()
                end
                local art = castIconHolder._iconTex
                if art then
                    art:ClearAllPoints()
                    art:SetAllPoints(castIconHolder)
                    art:SetTexCoord(0, 1, 0, 1)
                end
            end
            local frAtlas = StockAtlas("frame")
            if CK then
                -- The vanilla frame round the footprint (bar and icon while the
                -- icon is part of the bar, which live sits inside the frame's
                -- window), on an art frame over both so the rim overlaps the
                -- icon's edges too.
                local rim = castBar._classicArt
                if not rim then
                    rim = CreateFrame("Frame", nil, popFrame)
                    rim:EnableMouse(false)
                    rim:SetFrameLevel(popFrame:GetFrameLevel() + 3)
                    castBar._classicArt = rim
                    castBar._blizzFrame = rim:CreateTexture(nil, "OVERLAY", nil, 2)
                end
                rim:ClearAllPoints()
                if not (inW and castIconHolder and castIconHolder:IsShown()) then
                    rim:SetAllPoints(castBar)
                elseif onRight then
                    rim:SetPoint("TOPLEFT", castBar, "TOPLEFT", 0, 0)
                    rim:SetPoint("BOTTOMRIGHT", castIconHolder, "BOTTOMRIGHT", 0, 0)
                else
                    rim:SetPoint("TOPLEFT", castIconHolder, "TOPLEFT", 0, 0)
                    rim:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT", 0, 0)
                end
                mod.UF_SeatClassicCastFrame(castBar._blizzFrame, rim, ch, cfg[mod.UF_CastClassicKey(unitName)])
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
                local ox, oy = cfg.castSpellNameX or 0, cfg.castSpellNameY or 0
                castNameText:ClearAllPoints()
                if nameSide == "right" then
                    castNameText:SetJustifyH("RIGHT")
                    castNameText:SetPoint("RIGHT", tb, "RIGHT", -8 + ox, oy)
                elseif nameSide == "center" then
                    castNameText:SetJustifyH("CENTER")
                    castNameText:SetPoint("CENTER", tb, "CENTER", ox, oy)
                else
                    castNameText:SetJustifyH("LEFT")
                    castNameText:SetPoint("LEFT", tb, "LEFT", 8 + ox, oy)
                end
                local wid = castBar:GetWidth() or 0
                if wid > 20 then
                    castNameText:SetWidth(wid - 16)
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
    local function BlizzInsetAnchor(am, anchor, G, mirror)
        local val = G.vis
        if not val then
            return
        end
        local pad = G.pad
        local vl, vr = val.l, val.r
        if mirror then
            vl, vr = vr, vl
        end
        if anchor == "topleft" or anchor == "bottomleft" or anchor == "left" then
            am.ox = am.ox + vl
        elseif anchor == "topright" or anchor == "bottomright" or anchor == "right" then
            am.ox = am.ox - vr
        end
        if anchor == "topleft" or anchor == "topright" then
            am.oy = am.oy - (val.t - (pad and pad.top or 0))
        elseif anchor == "bottomleft" or anchor == "bottomright" then
            am.oy = am.oy + (val.b - (pad and pad.bottom or 0))
        end
    end

    -- Update is at Lua's 60-upvalue cap: it reaches the style helpers
    -- through pf instead of capturing them.
    popFrame._blizzResolve = ResolveBlizzPreview
    popFrame._blizzScale = BlizzPreviewScale
    popFrame._blizzApply = ApplyBlizzPreview
    popFrame._blizzInset = BlizzInsetAnchor
    popFrame._unitPrefs = UnitPrefs
    popFrame._litHealth = LitHealthColors
    popFrame._powerRGB = PowerFillRGB

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
        local s = popFrame._unitPrefs()

        -- Blizzard Style: stock geometry (nil = CUI look); Frame Scale rides
        -- the preview scale so every anchor and the header math follow it.
        local stockGroup, blizzMirror, blizzExtras = popFrame._blizzResolve(unitName, s)
        popFrame._previewScale = (popFrame._previewBaseScale or popFrame._previewScale or 1)
            * (stockGroup and popFrame._blizzScale(s) or 1)

        -- The aura settings the live containers read: the pet's through its
        -- Copy Auras From view (its own size, crop and placement, the source
        -- frame's look), every other unit's own table.
        local as = s
        if unitName == "pet" then
            as = mod.UF_AuraSettings("pet") or s
        end

        -- Aura preview: mirror the live shared aura border style.
        if
            unitName == "player"
            or unitName == "target"
            or unitName == "focus"
            or unitName == "boss"
            or unitName == "pet"
        then
            -- Blizzard Style: the live frames draw no custom aura border, so
            -- the preview keeps the plain 1px edge and hides it too.
            local blizzAura = stockGroup ~= nil
            local function ApplyPreviewAuraBorder(iconTex)
                if iconTex._iconTex then
                    iconTex._iconTex:ClearAllPoints()
                    local inset = (blizzAura or (as.auraBorderSize or 1) > 0) and 1 or 0
                    Pix.Point(iconTex._iconTex, "TOPLEFT", iconTex, "TOPLEFT", inset, -inset)
                    Pix.Point(iconTex._iconTex, "BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", -inset, inset)
                end
                local edgeFrame = iconTex._cuiAuraBorder
                if blizzAura then
                    if edgeFrame then
                        edgeFrame:Hide()
                    end
                    return
                end
                if not edgeFrame then
                    edgeFrame = CreateFrame("Frame", nil, iconTex)
                    edgeFrame:SetAllPoints(iconTex)
                    edgeFrame:EnableMouse(false)
                    iconTex._cuiAuraBorder = edgeFrame
                end
                local aboveEffects = unitName == "boss" and mod.UF_BossAuraBorderAboveEffects(s)
                if as.auraBorderBehindUnitFrame then
                    edgeFrame:SetFrameLevel(0)
                elseif aboveEffects then
                    edgeFrame:SetFrameLevel(iconTex:GetFrameLevel() + 20)
                else
                    edgeFrame:SetFrameLevel(
                        as.auraBorderBehind and math.max(0, iconTex:GetFrameLevel() - 1)
                            or (iconTex:GetFrameLevel() + 1)
                    )
                end
                if iconTex._durText and (aboveEffects or iconTex._borderAboveEffects) then
                    iconTex._durText:GetParent():SetFrameLevel(iconTex:GetFrameLevel() + (aboveEffects and 25 or 2))
                    iconTex._borderAboveEffects = aboveEffects or nil
                end
                CludesUI.ApplyBorderStyle(
                    edgeFrame,
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
            unitName == "pet"
            or unitName == "boss"
            or unitName == "targettarget"
            or unitName == "focustarget"
        )
        local ds = s
        if isMini then
            ds = mod.GetMiniDonorSettings and mod.GetMiniDonorSettings(unitName) or saved.profile.player
        end
        -- The frame border's settings: the donor's for the minis; the boss
        -- frames' own once the boss Border Style leaves Inherit (the live
        -- frames' ns.UF_BossBorderSettings).
        local bds = (unitName == "boss") and mod.UF_BossBorderSettings() or ds

        -- The preview mocks the CUI frame, so it counts as "enabled" only when the
        -- unit's source is the CUI frame.
        local unitKey2 = unitName:match("^boss") and "boss" or unitName
        local isEnabled = mod.GetUnitFrameSource(unitKey2) == "cui"
        if isEnabled then
            disabledOverlay:Hide()
            popFrame:SetAlpha(1)
        else
            popFrame:SetAlpha(0.5)
        end

        -- Reposition name and health text based on settings
        side = s.portraitSide or unitSide[unitName] or "left"
        local pvPStyle = s.portraitStyle or saved.profile.portraitStyle or "attached"
        local sp = hasPortraitSupport and pvPStyle ~= "none" and s.showPortrait ~= false
        local isAttached = pvPStyle == "attached"
        local fw = s.frameWidth or 181
        local hh = s.healthHeight or 46
        local ph = noPowerPreview and 0 or (s.powerHeight or 6)
        local powerPlace = noPowerPreview and "none" or mod.UF_PowerPos(s)
        local pvPpIsAtt = (powerPlace == "below" or powerPlace == "above")
        local pvPpExtra = pvPpIsAtt and ph or 0
        local ch = (unitName == "player")
                and (s.showPlayerCastbar and (s.playerCastbarHeight and s.playerCastbarHeight > 0 and s.playerCastbarHeight or 14) or 0)
            or ((s.showCastbar ~= false) and (s.castbarHeight or 14) or 0)
        -- Mirrors the live reserve decision (see the build path above).
        if ch > 0 and CludesUI.UF_CastbarBelowFrame and not CludesUI.UF_CastbarBelowFrame(unitName) then
            ch = 0
        end
        -- Blizzard Style: on the frames with a movable cast bar the bar
        -- hangs below the bottom aura stacks, off the frame's aura block
        -- (live: AnchorContainer plus the unlock follow provider), and
        -- those stacks reserve nothing for it. Only with the engine's
        -- layout aspect; a client without it keeps the bar on the art's
        -- bottom with the stacks under it, as the boss frames always do.
        local blizzBelow = stockGroup ~= nil
            and ch > 0
            and (unitName == "player" or unitName == "target" or unitName == "focus")
            and mod.UF_LayoutAspectOK ~= nil
            and mod.UF_LayoutAspectOK() == true
        -- The strip the bar takes under the art (plus the stock text box).
        local cbStrip = 0
        local bh = hh + pvPpExtra
        -- Class power "above" position adds height above health bar ("top" floats outside)
        local cpStyle = (unitName == "player") and (s.classPowerStyle or "none") or "none"
        -- The style that builds (WoW Forever reads a saved "blizzard" as modern,
        -- and a rogue's own style); only the player frame has a class resource.
        if unitName == "player" and mod.UF_ForeverCPStyle then
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
        local pvIsInside = (side == "insideleft" or side == "insideright" or side == "insidecenter")
        if not isAttached and not pvIsInside then
            pSizeAdj = pSizeAdj + 10
            pYOff = pYOff + 5
        end
        local portraitDim = bh2 + pSizeAdj -- portrait width & height
        if portraitDim < 8 then
            portraitDim = 8
        end
        -- For attached, "top" and "inside*" fall back to default side
        local effectiveSide = side
        if isAttached and (side == "top" or pvIsInside) then
            effectiveSide = unitSide[unitName] or "left"
            pvIsInside = false
        end
        local powerW = (sp and isAttached and effectiveSide ~= "top") and portraitDim or 0
        local tw = fw + powerW
        -- Blizzard Style: the stock footprint (cast bar width, pf size, fit).
        if stockGroup then
            tw = stockGroup.w
        end

        Pix.Size(healthBar, fw, hh)

        -- Re-anchor portrait + health every update (no caching) to avoid circular
        -- dependency errors on style switches: clear BOTH first, then anchor in
        -- dependency order.
        if portraitHolder then
            portraitHolder:ClearAllPoints()
        end
        healthBar:ClearAllPoints()
        local btbTopOff = (s.bottomTextBar and (s.btbPosition or "bottom") == "top")
                and (s.bottomTextBarHeight or 16)
            or 0
        local pvPwAbove = (powerPlace == "above") and ph or 0

        if portraitHolder and sp then
            if pvIsInside then
                Pix.Size(portraitHolder, portraitDim, bh2)
            else
                Pix.Size(portraitHolder, portraitDim, portraitDim)
            end
            if pvIsInside then
                -- Inside: portrait overlays the health bar
                Pix.Point(healthBar, "TOPLEFT", barRegion, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                portraitHolder:SetClipsChildren(true)
                if portraitHolder._previewBg then
                    portraitHolder._previewBg:Hide()
                end
                if effectiveSide == "insideleft" then
                    portraitHolder:SetPoint("TOPLEFT", healthBar, "TOPLEFT", pXOff, pYOff)
                elseif effectiveSide == "insideright" then
                    portraitHolder:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", pXOff, pYOff)
                else -- insidecenter
                    portraitHolder:SetPoint("TOP", healthBar, "TOP", pXOff, pYOff)
                end
            elseif isAttached then
                -- Attached: portrait to barArea, then health to portrait
                portraitHolder:SetClipsChildren(true)
                if portraitHolder._previewBg then
                    portraitHolder._previewBg:Show()
                end
                if effectiveSide == "left" then
                    portraitHolder:SetPoint("TOPLEFT", barRegion, "TOPLEFT", 0, 0)
                    Pix.Point(
                        healthBar,
                        "TOPLEFT",
                        portraitHolder,
                        "TOPRIGHT",
                        0,
                        -cpAboveH - btbTopOff - pvPwAbove
                    )
                else
                    portraitHolder:SetPoint("TOPRIGHT", barRegion, "TOPRIGHT", 0, 0)
                    Pix.Point(
                        healthBar,
                        "TOPRIGHT",
                        portraitHolder,
                        "TOPLEFT",
                        0,
                        -cpAboveH - btbTopOff - pvPwAbove
                    )
                end
            else
                -- Detached: health to barArea, then portrait floats. Clip back
                -- on; ApplyPreviewPortraitShape (later this Update) turns it off
                -- again for Pixels Circle or a shown Outer Ring.
                portraitHolder:SetClipsChildren(true)
                if portraitHolder._previewBg then
                    portraitHolder._previewBg:Show()
                end
                Pix.Point(healthBar, "TOPLEFT", barRegion, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                if effectiveSide == "top" then
                    -- Top: portrait centered above health bar
                    portraitHolder:SetPoint("BOTTOM", healthBar, "TOP", pXOff, 15 + pYOff)
                elseif effectiveSide == "left" then
                    portraitHolder:SetPoint("TOPRIGHT", healthBar, "TOPLEFT", -15 + pXOff, pYOff)
                else
                    portraitHolder:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", 15 + pXOff, pYOff)
                end
            end
            portraitHolder._anchored = true
            portraitHolder._anchoredAttached = isAttached
            -- Raise detached portrait above the border, capped so it can't overlap
            -- dropdown menus and other UI controls.
            if isAttached then
                portraitHolder:SetFrameLevel(popFrame:GetFrameLevel() + 1)
            else
                portraitHolder:SetFrameLevel(popFrame:GetFrameLevel() + 3)
            end
        else
            Pix.Point(healthBar, "TOPLEFT", barRegion, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
            if portraitHolder then
                portraitHolder._anchored = false
            end
        end
        healthFill:ClearAllPoints()
        -- Vertical Fill turns the fill axis upright (growing up from the
        -- bottom, or down from the top with Reverse Fill). The anchors pin the
        -- cross axis; the filled length is set explicitly below.
        local vertFill, revFill = s.healthVerticalFill, s.healthReverseFill
        local hpShare = optionState._previewHealthPct or 0.70
        local filledLen = math.floor((vertFill and hh or fw) * hpShare + 0.5)
        local pinA, pinB = "TOPLEFT", "BOTTOMLEFT"
        if vertFill then
            pinA, pinB = "BOTTOMLEFT", "BOTTOMRIGHT"
            if revFill then
                pinA, pinB = "TOPLEFT", "TOPRIGHT"
            end
        elseif revFill then
            pinA, pinB = "TOPRIGHT", "BOTTOMRIGHT"
        end
        healthFill:SetPoint(pinA, healthBar, pinA, 0, 0)
        healthFill:SetPoint(pinB, healthBar, pinB, 0, 0)
        if vertFill then
            Pix.Height(healthFill, filledLen)
        else
            Pix.Width(healthFill, filledLen)
        end

        -- Health colours again, live (the dark theme's pair or the unit's picks).
        do
            local isDark = mod.UF_DarkThemeOn(s)
            local uHR, uHG, uHB, uBgR, uBgG, uBgB
            if isDark then
                uHR, uHG, uHB = CludesUI.GetDarkModeFill()
                uBgR, uBgG, uBgB = CludesUI.GetDarkModeBg()
            else
                uHR, uHG, uHB, uBgR, uBgG, uBgB = popFrame._litHealth(s)
            end
            healthFill:SetColorTexture(uHR, uHG, uHB, 1)
            -- The backing covers only the empty part, so a fill below full
            -- opacity shows the dark base, not the backing (the live edge anchor).
            healthBgColor:ClearAllPoints()
            local leftIn, topIn, rightIn, bottomIn = 0, 0, 0, 0
            if vertFill then
                if revFill then
                    topIn = -filledLen
                else
                    bottomIn = filledLen
                end
            elseif revFill then
                rightIn = -filledLen
            else
                leftIn = filledLen
            end
            healthBgColor:SetPoint("TOPLEFT", healthBar, "TOPLEFT", leftIn, topIn)
            healthBgColor:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", rightIn, bottomIn)
            healthBgColor:SetColorTexture(uBgR, uBgG, uBgB, 1)
            -- The bar texture on both fills; a mini frame takes its donor's
            -- texture unless it picked one of its own.
            local texKeyNow = mod.ResolveHealthBarTextureKey(s, isMini and ds or nil)
            local texNow = (mod.healthBarTextures or {})[texKeyNow]
            if healthFill then
                local fillA = s.healthBarOpacity or 90
                if fillA > 1.0 then
                    fillA = fillA / 100
                end
                local withGradient = (not isDark) and s.gradientEnabled
                PV_FillColor(
                    healthFill,
                    texNow,
                    uHR,
                    uHG,
                    uHB,
                    withGradient,
                    s.gradientColor,
                    s.gradientDir,
                    fillA
                )
            end
            local pFill = popFrame._powerFill
            if pFill then
                local pr, pg, pb = popFrame._powerRGB(s)
                popFrame._pR, popFrame._pG, popFrame._pB = pr, pg, pb
                if texNow then
                    pFill:SetTexture(texNow)
                    pFill:SetVertexColor(pr, pg, pb, 1)
                else
                    pFill:SetVertexColor(1, 1, 1, 1)
                    pFill:SetColorTexture(pr, pg, pb, 1)
                end
            end

            -- Fill and backing alpha from the one opacity setting (fixed under
            -- the dark theme).
            local hFillA, hBgA = 0.90, 1
            if not isDark then
                hFillA = (s.healthBarOpacity or 90) / 100
                hBgA = (s.customBgAlpha or 100) / 100
            end
            if healthFill then
                healthFill:SetAlpha(hFillA)
            end
            if healthBgColor then
                healthBgColor:SetAlpha(hBgA)
            end
            -- Textured Background, as live: a fixed full-size layer while the
            -- fill is opaque.
            local tbPath = mod.UF_TexBgPaths(unitName, s, texKeyNow)
            if tbPath then
                local tb = mod.UF_TexBgLayer(healthBar, tbPath, s.healthVerticalFill and not stockGroup)
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
        Pix.Size(barRegion, tw, bh2 + btbTopOff)

        if powerBar then
            local pvPw = fw
            local pvPpIsDet = (powerPlace == "detached_top" or powerPlace == "detached_bottom")
            if pvPpIsDet and (s.powerWidth or 0) > 0 then
                pvPw = s.powerWidth
            end
            Pix.Size(powerBar, pvPw, ph)
            if pvPpIsDet and saved.profile.enableCustomBarStratas then
                powerBar:SetFrameLevel(popFrame:GetFrameLevel() + 40)
            elseif pvPpIsDet then
                powerBar:SetFrameLevel(popFrame:GetFrameLevel() + 3)
            end
            powerBar:ClearAllPoints()
            if powerPlace == "none" then
                powerBar:Hide()
            elseif powerPlace == "above" then
                Pix.Point(powerBar, "BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
                Pix.Point(powerBar, "BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
                if ph > 0 then
                    powerBar:Show()
                else
                    powerBar:Hide()
                end
            elseif powerPlace == "detached_top" then
                powerBar:SetPoint("BOTTOM", healthBar, "TOP", s.powerX or 0, 15 + (s.powerY or 0))
                if ph > 0 then
                    powerBar:Show()
                else
                    powerBar:Hide()
                end
            elseif powerPlace == "detached_bottom" then
                powerBar:SetPoint("TOP", healthBar, "BOTTOM", s.powerX or 0, -15 + (s.powerY or 0))
                if ph > 0 then
                    powerBar:Show()
                else
                    powerBar:Hide()
                end
            else -- "below"
                Pix.Point(powerBar, "TOPLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                Pix.Point(powerBar, "TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
                if ph > 0 then
                    powerBar:Show()
                else
                    powerBar:Hide()
                end
            end
            -- Live-frame rule: attached bars get only the Solid seam facing health;
            -- detached bars keep their selected full style.
            if mod.UpdatePowerBorder then
                mod.UpdatePowerBorder(powerBar, s)
            end
            if popFrame._powerFill then
                popFrame._powerFill:ClearAllPoints()
                if s.powerReverseFill then
                    popFrame._powerFill:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT", 0, 0)
                    popFrame._powerFill:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT", 0, 0)
                else
                    popFrame._powerFill:SetPoint("TOPLEFT", powerBar, "TOPLEFT", 0, 0)
                    popFrame._powerFill:SetPoint("BOTTOMLEFT", powerBar, "BOTTOMLEFT", 0, 0)
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
                        popFrame._powerBg:SetPoint("TOPLEFT", powerBar, "TOPLEFT", 0, 0)
                        popFrame._powerBg:SetPoint("BOTTOMRIGHT", popFrame._powerFill, "BOTTOMLEFT", 0, 0)
                    else
                        popFrame._powerBg:SetPoint("TOPLEFT", popFrame._powerFill, "TOPRIGHT", 0, 0)
                        popFrame._powerBg:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT", 0, 0)
                    end
                elseif popFrame._powerBgOpAnchored then
                    popFrame._powerBgOpAnchored = nil
                    popFrame._powerBg:ClearAllPoints()
                    popFrame._powerBg:SetAllPoints(powerBar)
                end
            end

            local pvPfR, pvPfG, pvPfB
            local pvUsePowerColor = s.powerPercentPowerColor ~= false
            if pvUsePowerColor and s.powerClassColored then
                local _, classTok = UnitClass("player")
                local classColor = CludesUI.GetClassColor(classTok)
                pvPfR, pvPfG, pvPfB = classColor.r, classColor.g, classColor.b
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
                    unitName,
                    s,
                    s.healthBarTexture or saved.profile.healthBarTexture or "none"
                )
                mod.UF_TexBgPaint(popFrame._powerBg, tp, pvPbR, pvPbG, pvPbB, 1)
            end
            -- Spell Cost Prediction eyeball (player, WoW Forever): the last
            -- third of the fill in the prediction color, as during a cast.
            -- Mana only, as live.
            if
                unitName == "player"
                and CludesUI.SpellCostPrediction
                and popFrame._powerFill
                and mod._ufShowPowerCostPreview
                and s.powerCostPrediction == true
                and UnitPowerType("player") == Enum.PowerType.Mana
            then
                local seg = popFrame._pvCostSeg
                if not seg then
                    seg = powerBar:CreateTexture(nil, "ARTWORK", nil, 2)
                    popFrame._pvCostSeg = seg
                end
                local red, green, blue = mod.UF_PowerCostColor(s)
                local curTP = (mod.healthBarTextures or {})[s.healthBarTexture or saved.profile.healthBarTexture or "none"]
                if curTP then
                    seg:SetTexture(curTP)
                    seg:SetVertexColor(red, green, blue, 1)
                else
                    seg:SetColorTexture(red, green, blue, 1)
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

        -- Power text, at its Text Position in its format, as the live bar shows it.
        if ppPreviewFS then
            local ppPos = s.powerPercentText or "none"
            local ppFmt = CludesUI.PowerTextFormat(s.powerTextFormat or "perpp")
            if ppPos == "none" or ppFmt == "none" or not powerBar then
                ppPreviewFS:Hide()
            else
                SetPVFont(ppPreviewFS, PREVIEW_FONT, s.powerPercentSize or 9)
                ppPreviewFS:ClearAllPoints()
                local justify, inset, lane = "CENTER", 0, ""
                if ppPos == "left" then
                    justify, inset, lane = "LEFT", 2, "LEFT"
                elseif ppPos == "right" then
                    justify, inset, lane = "RIGHT", -2, "RIGHT"
                end
                ppPreviewFS:SetJustifyH(justify)
                -- At Power Bar Height 0 the bar's rect never resolves, so the
                -- text meets the health bar's edge in the power row instead,
                -- as on the live frame.
                local target, ownEdge, targetEdge = powerBar, "", ""
                if ph <= 0 then
                    local above = (powerPlace == "above" or powerPlace == "detached_top")
                    target = healthBar
                    ownEdge, targetEdge = above and "BOTTOM" or "TOP", above and "TOP" or "BOTTOM"
                end
                local ownPoint = ownEdge .. lane
                local targetPoint = targetEdge .. lane
                Pix.Point(
                    ppPreviewFS,
                    ownPoint ~= "" and ownPoint or "CENTER",
                    target,
                    targetPoint ~= "" and targetPoint or "CENTER",
                    inset + (s.powerPercentX or 0),
                    s.powerPercentY or 0
                )
                local pctPart = math.floor((optionState._previewPowerPct or 0.85) * 100)
                    .. ((s.powerShowPercent == false) and "" or "%")
                local curPart = mod.AbbreviateNumbers(18200)
                local shown
                if ppFmt == "custom" then
                    shown = PreviewTextForContent("custom", s, "powerText")
                elseif ppFmt == "curpp" then
                    shown = curPart
                elseif ppFmt == "curmaxpp" then
                    shown = curPart .. " / " .. mod.AbbreviateNumbers(22000)
                elseif ppFmt == "both" then
                    shown = curPart .. " | " .. pctPart
                else
                    -- Percent, and Smart (the preview always shows its percent).
                    shown = pctPart
                end
                ppPreviewFS:SetText(shown)
                -- Power Color: the player's current power colour, as the swatch
                -- and the live frame use; else the text colour, white by default.
                local tint = s.powerTextColor
                if s.powerPercentTextPowerColor then
                    local _, kind = UnitPowerType("player")
                    tint = CludesUI.GetPowerColor(kind or "MANA")
                end
                if tint then
                    ppPreviewFS:SetTextColor(tint.r, tint.g, tint.b)
                else
                    ppPreviewFS:SetTextColor(1, 1, 1)
                end
                ppPreviewFS:Show()
            end
        end

        if portraitHolder then
            if sp then
                if not portraitHolder:IsShown() then
                    portraitHolder:Show()
                end
                if portraitHolder._applyMode then
                    portraitHolder._applyMode()
                end
                ApplyPreviewPortraitShape(portraitHolder, s)
                -- Portrait Dragon (player, target, focus; any shape, attached
                -- or detached, never a stock style): the live helper at the
                -- preview's strata, the enemy frames showing the gold sample.
                -- It reaches past the frame, so the preview stops clipping.
                local pvDragon = not stockGroup
                    and (unitName == "player" or unitName == "target" or unitName == "focus")
                    and mod.UF_DragonSettings(unitName, s)
                if pvDragon and pvDragon.on then
                    local dt =
                        mod.UF_PortraitDragon(portraitHolder, pvDragon, (unitName == "player") ~= pvDragon.flip)
                    if dt then
                        dt:Show()
                        portraitHolder:SetClipsChildren(false)
                    end
                else
                    mod.UF_PortraitDragon(portraitHolder, nil)
                end
            else
                if portraitHolder:IsShown() then
                    portraitHolder:Hide()
                    portraitHolder._anchored = false
                end
            end
        end

        -- Text Bar, placed before the cast bar (which may hang off it). An
        -- attached bar centres under the bars and an attached portrait.
        local cbOff = 0
        if sp and isAttached then
            if side == "right" then
                cbOff = powerW / 2
            elseif side == "left" then
                cbOff = -(powerW / 2)
            end
        end
        local btbPos = s.btbPosition or "bottom"
        local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
        if btbFrame and not s.bottomTextBar then
            if btbFrame:IsShown() then
                btbFrame:Hide()
            end
        elseif btbFrame then
            local floating = not btbIsAtt
            local ownW = floating and (s.btbWidth or 0) or 0
            Pix.Size(btbFrame, ownW > 0 and ownW or tw, s.bottomTextBarHeight or 16)
            -- A floating bar rides over the frame (far over it with custom bar stratas).
            if floating then
                local raise = saved.profile.enableCustomBarStratas and 50 or 3
                btbFrame:SetFrameLevel(popFrame:GetFrameLevel() + raise)
            end
            btbFrame:ClearAllPoints()
            local under = (pvPpIsAtt and powerBar and powerBar:IsShown()) and powerBar or healthBar
            local dx, dy = s.btbX or 0, s.btbY or 0
            if btbPos == "top" then
                Pix.Point(btbFrame, "BOTTOM", healthBar, "TOP", cbOff, 0)
            elseif btbPos == "detached_top" then
                btbFrame:SetPoint("BOTTOM", popFrame, "TOP", dx, 15 + dy)
            elseif btbPos == "detached_bottom" then
                btbFrame:SetPoint("TOP", popFrame, "BOTTOM", dx, -15 + dy)
            else
                Pix.Point(btbFrame, "TOP", under, "BOTTOM", cbOff, 0)
            end
            local fillColor = s.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
            btbBg:SetColorTexture(fillColor.r, fillColor.g, fillColor.b, s.btbBgOpacity or 1.0)
            ApplyBTBPreviewTexts(s)
            if not btbFrame:IsShown() then
                btbFrame:Show()
            end
        end

        -- Cast bar, laid out live: its width (narrowed when the icon is part of
        -- the bar), backing, fill, icon and the three text zones, then its
        -- one authoritative anchor (under the Text Bar or the bars, shifted
        -- for the icon).
        if castBar and ch <= 0 then
            castBar:Hide()
            if castIconHolder then
                castIconHolder:Hide()
            end
        elseif castBar then
            local isPlayer = unitName == "player"
            local iconInBar = mod.UF_CastIconInWidth(unitName, s)
            local iconOnRight = s[isPlayer and "playerCastbarIconRight" or "castbarIconRight"] == true
            local offsetKey = isPlayer and "playerCastIconOffset" or "castIconOffset"
            local iconDX, iconDY = s[offsetKey .. "X"] or 0, s[offsetKey .. "Y"] or 0
            -- Boss: a Cast Bar Width above 0 replaces the frame width, held to
            -- tw + 120 (see the note in the build).
            local fullW = tw
            if unitName == "boss" and (s.castbarWidth or 0) > 0 then
                fullW = math.min(math.max(s.castbarWidth, 30), tw + 120)
            end
            local barW = iconInBar and math.max(1, fullW - ch) or fullW
            castBar:SetSize(barW, ch)
            castBar:Show()
            -- Backing colour and opacity, with the Textured Background as live
            -- (never over the stock cast art).
            local backTex = castBar._previewBgTex
            if backTex then
                local backC = s.castBgColor
                local unitTexKey = s.healthBarTexture or saved.profile.healthBarTexture or "none"
                local stockArt = CludesUI.BlizzStyle.Active("unitframes") == "blizzard"
                local backPath = mod.UF_TexBgCastPath(s, unitTexKey, stockArt)
                local br, bgc, bb = backC and backC.r or 0, backC and backC.g or 0, backC and backC.b or 0
                mod.UF_TexBgPaint(backTex, backPath, br, bgc, bb, s.castBgAlpha or 0.5)
            end
            if castFill then
                castFill:ClearAllPoints()
                local fillEnd, endInset = "LEFT", 1
                if s.castReverseFill then
                    fillEnd, endInset = "RIGHT", -1
                end
                Pix.Point(castFill, "TOP" .. fillEnd, castBar, "TOP" .. fillEnd, endInset, 0)
                Pix.Point(castFill, "BOTTOM" .. fillEnd, castBar, "BOTTOM" .. fillEnd, endInset, 1)
                castFill:SetWidth(
                    math.floor(math.max(0, barW - 2) * (optionState._previewCastFill or 0.6) + 0.5)
                )
                -- Fill colour: the class colour on the player with Class Colored,
                -- else the unit's pick, else the profile's cast colour, else teal.
                local classFill
                if isPlayer and s.castbarClassColored then
                    local _, token = UnitClass("player")
                    classFill = token and RAID_CLASS_COLORS[token]
                end
                local fc = classFill
                    or s.castbarFillColor
                    or saved.profile.castbarColor
                    or { r = 0.114, g = 0.655, b = 0.514 }
                -- The unit's bar texture unless the cast bars carry their own (as
                -- live); WHITE8X8 as the fallback so the tint is always set fresh.
                local ownTex = saved.profile.castBarTexture
                local fillKey = s.healthBarTexture or saved.profile.healthBarTexture or "none"
                if ownTex and ownTex ~= "inherit" then
                    fillKey = ownTex
                end
                local fillPath = (mod.healthBarTextures or {})[fillKey] or "Interface\\Buttons\\WHITE8X8"
                PV_FillColor(castFill, fillPath, fc.r, fc.g, fc.b, nil, nil, nil, 1)
                -- "Blizzard" is the vanilla cast bar's own fill art, tinted.
                if fillKey == "blizzard" then
                    castFill:SetAtlas("UI-CastingBar-Fill", true)
                end
            end
            local sample = isPlayer and optionState._previewCastSpell or nil
            if castIconHolder then
                castIconHolder:SetSize(ch, ch)
                castIconHolder:ClearAllPoints()
                if iconOnRight then
                    Pix.Point(castIconHolder, "TOPLEFT", castBar, "TOPRIGHT", iconDX, iconDY)
                else
                    Pix.Point(castIconHolder, "TOPRIGHT", castBar, "TOPLEFT", iconDX, iconDY)
                end
                if s[isPlayer and "showPlayerCastIcon" or "showCastIcon"] ~= false then
                    castIconHolder:Show()
                else
                    castIconHolder:Hide()
                end
                if castIconHolder._iconTex then
                    castIconHolder._iconTex:SetTexture(sample and sample.icon or 136197)
                end
            end
            -- The three zones, side-aware as on the live cast bar: name and
            -- duration on every unit, the target zone on all but the player.
            local nameSide = s.castSpellNameSide or "left"
            local targetSide = s.castSpellTargetSide or "right"
            local timeSide = s.castDurationSide or "right"
            local showDur = s.showCastDuration ~= false
            local shownW = castBar:GetWidth()
            local hasW = shownW and shownW > 0
            local timeW = (s.castDurationSize or 10) * 2.2
            local zoneW = hasW and (shownW * 0.42) or 0
            local function Tint(fs, color)
                color = color or { r = 1, g = 1, b = 1 }
                fs:SetTextColor(color.r, color.g, color.b)
            end
            local function PlaceZone(fs, zoneSide, isTime, width, x, y)
                local pt, xb, jh = mod.GetCastTextAnchor(
                    zoneSide,
                    not isTime and showDur and timeSide == zoneSide,
                    timeW,
                    isTime
                )
                fs:SetWidth(width)
                fs:SetJustifyH(jh)
                fs:ClearAllPoints()
                fs:SetPoint(pt, castBar, pt, xb + x, y)
            end
            if castNameText then
                castNameText:SetText(sample and sample.name or "Spell Name")
                SetPVFont(castNameText, PREVIEW_FONT, s.castSpellNameSize or 11)
                Tint(castNameText, s.castSpellNameColor)
                castNameText:ClearAllPoints()
                if nameSide == "none" then
                    castNameText:Hide()
                elseif hasW then
                    PlaceZone(
                        castNameText,
                        nameSide,
                        false,
                        zoneW,
                        s.castSpellNameX or 0,
                        1 + (s.castSpellNameY or 0)
                    )
                    castNameText:Show()
                end
            end
            if castTimeFS then
                local fullCast = (optionState._previewCastSpell and optionState._previewCastSpell.castTime)
                    or 3.0
                castTimeFS:SetText(
                    string.format("%.1f", fullCast * (1 - (optionState._previewCastFill or 0.6)))
                )
                SetPVFont(castTimeFS, PREVIEW_FONT, s.castDurationSize or 10)
                Tint(castTimeFS, s.castDurationColor)
                castTimeFS:SetShown(showDur)
                if hasW then
                    PlaceZone(castTimeFS, timeSide, true, timeW, s.castDurationX or 0, (s.castDurationY or 0))
                end
            end
            if castTargetFS then
                SetPVFont(castTargetFS, PREVIEW_FONT, s.castSpellTargetSize or 11)
                Tint(castTargetFS, s.castSpellTargetColor)
                castTargetFS:SetShown(s.showCastTarget ~= false)
                if hasW then
                    PlaceZone(
                        castTargetFS,
                        targetSide,
                        false,
                        zoneW,
                        s.castSpellTargetX or 0,
                        (s.castSpellTargetY or 0)
                    )
                end
            end
            -- Flow the text again so a live justify change shows on text already drawn.
            for _, fs in ipairs({ castNameText, castTimeFS, castTargetFS }) do
                mod.ReflowFontString(fs)
            end
            castBar:ClearAllPoints()
            local onTextBar = btbFrame and s.bottomTextBar and btbPos == "bottom"
            local hangFrom = onTextBar and btbFrame
                or ((pvPpIsAtt and powerBar and powerBar:IsShown()) and powerBar or healthBar)
            -- An icon that is part of the bar moves the narrowed bar half an icon
            -- toward the icon-free side, so the pair sits flush under the frame.
            local iconShift = 0
            if iconInBar then
                iconShift = iconOnRight and -(ch / 2) or (ch / 2)
            end
            Pix.Point(castBar, "TOP", hangFrom, "BOTTOM", (onTextBar and 0 or cbOff) + iconShift, 0)
        end

        -- Border round the health and power bars, an attached Text Bar and
        -- pips above; a mini frame's Border Size override replaces the
        -- donor's size, as live.
        local bs = s.borderSizeOverride or bds.borderSize or 1
        local bc = bds.borderColor or { r = 0, g = 0, b = 0 }
        local bTexKey = bds.borderTexture or "solid"
        edgeFrame:ClearAllPoints()
        edgeFrame:SetPoint("TOPLEFT", barRegion, "TOPLEFT", 0, 0)
        edgeFrame:SetPoint("TOPRIGHT", barRegion, "TOPRIGHT", 0, 0)
        edgeFrame:SetHeight(bh2 + (s.bottomTextBar and btbIsAtt and (s.bottomTextBarHeight or 16) or 0))
        local borderPx = CludesUI.BorderPx((not s.borderSizeOverride) and bds.borderSizePx, bs, bTexKey)
        CludesUI.ApplyBorderStyle(
            edgeFrame,
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
            borderPx
        )

        -- Class pips (player only), in the Modern style; any other style
        -- hides the row.
        if comboPipHolder and cpPips and cpStyle ~= "modern" then
            comboPipHolder:Hide()
            for _, pip in ipairs(cpPips) do
                pip:Hide()
            end
            if popFrame._cpPipOv then
                popFrame._cpPipOv:Hide()
            end
        elseif comboPipHolder and cpPips then
            local cpPos = s.classPowerPosition or "top"
            local cpMax = #cpPips
            local pipSize, pipGap = s.classPowerSize or 8, s.classPowerSpacing or 2
            local pipH = math.max(3, math.floor(pipSize * 0.375))
            local backC = s.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
            if comboPipHolder._bgTex then
                comboPipHolder._bgTex:SetColorTexture(backC.r, backC.g, backC.b, backC.a)
            end
            comboPipHolder:ClearAllPoints()
            -- Every edge rounds to a physical pixel, so the gaps all match.
            local efs = comboPipHolder:GetEffectiveScale()
            if efs <= 0 then
                efs = 1
            end
            local function Snap(val)
                return math.floor(val * efs + 0.5) / efs
            end
            if cpPos == "above" then
                -- Flush with the health bar's edges: the width shared out as
                -- cpMax pips with snapped gaps, each pip's edges snapped.
                local gapPx = Snap(pipGap)
                local eachW = (math.floor(fw) - (cpMax - 1) * gapPx) / cpMax
                comboPipHolder:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
                comboPipHolder:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
                comboPipHolder:SetHeight(pipH)
                for idx, pip in ipairs(cpPips) do
                    local leftEdge = Snap((idx - 1) * (eachW + gapPx))
                    local rightEdge = Snap((idx - 1) * (eachW + gapPx) + eachW)
                    pip:ClearAllPoints()
                    pip:SetSize(rightEdge - leftEdge, pipH)
                    pip:SetPoint("TOPLEFT", comboPipHolder, "TOPLEFT", leftEdge, 0)
                    pip:Show()
                end
            else
                -- Floating over ("top") or under the frame, at pixel-exact sizes.
                local eachW, eachH, gapPx = Snap(pipSize), Snap(pipH), Snap(pipGap)
                Pix.Size(comboPipHolder, cpMax * eachW + (cpMax - 1) * gapPx, eachH)
                local dx, dy = s.classPowerBarX or 0, s.classPowerBarY or 0
                if cpPos == "top" then
                    Pix.Point(comboPipHolder, "BOTTOM", healthBar, "TOP", dx, dy)
                else
                    -- Under a shown cast bar unless moved; Blizzard Style
                    -- measures from the stock box's bottom (barArea here), as
                    -- live, whatever hangs under the art.
                    local baseY = -1
                    if dy == 0 and castBar and ch > 0 and s.showPlayerCastbar then
                        baseY = -1 - ch
                    end
                    Pix.Point(comboPipHolder, "TOP", stockGroup and barRegion or popFrame, "BOTTOM", dx, baseY + dy)
                end
                local x = 0
                for _, pip in ipairs(cpPips) do
                    pip:ClearAllPoints()
                    pip:SetSize(eachW, eachH)
                    pip:SetPoint("TOPLEFT", comboPipHolder, "TOPLEFT", Snap(x), 0)
                    pip:Show()
                    x = x + eachW + gapPx
                end
            end
            -- The 1px border-coloured line under the row, for "above" only.
            local underline = comboPipHolder._bottomBdr
            if underline and cpPos == "above" then
                underline:SetColorTexture(bc.r, bc.g, bc.b, 1)
                underline:Show()
            elseif underline then
                underline:Hide()
            end
            -- Three pips lit: the resource colour (or class colour, else gold)
            -- with Class Color on, else the custom pick; the rest empty.
            local _, cpClass = UnitClass("player")
            local lit
            if s.classPowerClassColor == false then
                lit = s.classPowerCustomColor or { r = 1, g = 0.82, b = 0 }
            else
                lit = CludesUI.GetResourceColor(cpClass)
                    or CludesUI.GetClassColor(cpClass)
                    or { r = 1, g = 0.84, b = 0.30 }
            end
            local empty = s.classPowerEmptyColor or { r = 0.2, g = 0.2, b = 0.2, a = 1.0 }
            local litCount = math.min(3, cpMax)
            for idx, pip in ipairs(cpPips) do
                if idx <= litCount then
                    pip:SetColorTexture(lit.r, lit.g, lit.b, 1)
                else
                    pip:SetColorTexture(empty.r, empty.g, empty.b, empty.a)
                end
                pip:SetAlpha(1)
            end
            comboPipHolder:Show()
            if popFrame._cpPipOv then
                popFrame._cpPipOv:Show()
            end
        end

        -- Absorb bars (player/target/focus): the Heal Absorb Style eyeball
        -- replaces the shield absorb with the heal absorb. Both honor their
        -- placement cog (absorbEdgeMode / healAbsorbEdgeMode).
        local _healPrev = optionState.showHealAbsorbPreview
        -- Only replace when there IS a heal absorb to show; with style "none"
        -- keep the shield preview instead of blanking the absorb area.
        local _healWillShow = _healPrev and (s.healAbsorbStyle or "clean") ~= "none"
        if absorbFill then
            local absS = s.showPlayerAbsorb
            if (not _healWillShow) and absS and absS ~= "none" then
                popFrame._paintShield(absorbFill, s)
                absorbFill:SetWidth(fw)
                absorbFill:SetHeight(hh)
                absorbFill:Show()
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
                        pvGl = absorbFill:CreateTexture(nil, "OVERLAY")
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
                        absorbFill:GetStatusBarTexture(),
                        glRev and "RIGHT" or "LEFT",
                        glRev and 1 or -1,
                        0
                    )
                    pvGl:Show()
                elseif pvGl then
                    pvGl:Hide()
                end
            else
                absorbFill:Hide()
            end
        end
        if healAbsorbFill then
            local haS = s.healAbsorbStyle or "clean"
            if _healPrev and haS ~= "none" then
                popFrame._paintHealAbsorb(healAbsorbFill, s, haS)
                healAbsorbFill:SetWidth(fw)
                healAbsorbFill:SetHeight(hh)
                healAbsorbFill:Show()
                if healAbsorbFill._bg then
                    healAbsorbFill._bg:SetColorTexture(0, 0, 0, (s.healAbsorbBgOpacity or 15) / 100)
                    healAbsorbFill._bg:SetAllPoints(healAbsorbFill:GetStatusBarTexture())
                    healAbsorbFill._bg:Show()
                end
            else
                healAbsorbFill:Hide()
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
                if absorbFill then
                    absorbFill:Hide()
                end
            else
                popFrame._pvPredOther:Hide()
                popFrame._pvPredMy:Hide()
            end
        end

        -- Absorb / Heal Absorb strips: independent of the overlay styles,
        -- anchored to the preview health bar.
        local _absStripHp = absorbFill and absorbFill:GetParent()
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

        if dispelPreview then
            local modeName = saved.profile.dispelOverlay or "none"
            if optionState.showDispelOverlayPreview and modeName ~= "none" then
                local color = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                local alpha = (saved.profile.dispelOverlayOpacity or 100) / 100
                dispelPreview:ClearAllPoints()
                dispelPreview:SetVertexColor(1, 1, 1, 1)
                dispelPreview:SetTexCoord(0, 1, 0, 1)
                if modeName == "full" then
                    dispelPreview:SetAllPoints(healthBar)
                    dispelPreview:SetColorTexture(color.r, color.g, color.b, alpha)
                elseif modeName == "gradient" or modeName == "gradient_sharp" or modeName == "gradient_reverse" then
                    dispelPreview:SetAllPoints(healthBar)
                    dispelPreview:SetTexture(
                        modeName == "gradient" and "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
                            or "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"
                    )
                    if modeName == "gradient_reverse" then
                        dispelPreview:SetTexCoord(0, 1, 1, 0)
                    end
                    dispelPreview:SetVertexColor(color.r, color.g, color.b, alpha)
                else
                    dispelPreview:SetAllPoints(healthFill)
                    dispelPreview:SetColorTexture(color.r, color.g, color.b, alpha)
                end
                dispelPreview:Show()
            else
                dispelPreview:Hide()
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
                    cbPv:SetAllPoints(edgeFrame)
                    popFrame._pvDispelBorder = cbPv
                end
                local mc = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                local cbs, cbt = s.borderSize or 1, s.borderTexture
                cbPv:SetFrameLevel(edgeFrame:GetFrameLevel() + 1)
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
                local size = dp.dispelIconSize or 16
                local corner = (dp.dispelIconPosition or "right"):upper()
                tiPv:SetFrameLevel(edgeFrame:GetFrameLevel() + 2)
                tiPv:SetSize(size, size)
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
                local size = dp.dispelIconSize or 16
                local step = size + CludesUI.PP.FromPixels(1)
                local dx = (grow == "left" and -step) or (grow == "right" and step) or 0
                local dy = (grow == "down" and -step) or (grow == "up" and step) or 0
                for idx = 1, #extra do
                    local f = extra[idx]
                    if growOn then
                        f:SetFrameLevel(tiPv:GetFrameLevel())
                        f:SetSize(size, size)
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
            local simpleBuffMode = (unitName == "boss") and mod.GetBossSimpleBuffMode(s) or "none"
            local simpleBuffOn = simpleBuffMode ~= "none"
            local maxBuf = s.maxBuffs or 4
            local visibleBuffCount = math.min(2, maxBuf)
            -- Boss preview always shows exactly 2 buffs regardless of Max Count.
            if unitName == "boss" then
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
                local buffGapX = (unitName == "boss") and mod.GetBossBuffSpacing(s, simpleBuffOn)
                    or (s.buffSpacingX or 1)
                local buffGapY = (unitName == "boss") and mod.GetBossBuffSpacing(s, simpleBuffOn)
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
                local barAnchor = simpleBuffOn and simpleBuffMode or (s.buffAnchor or "topleft")
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
                local gDir = (backdrop == "auto") and (autoGrowth[barAnchor] or "right") or backdrop

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
                local am = anchorMap[barAnchor] or anchorMap.topleft
                if stockGroup then
                    popFrame._blizzInset(am, barAnchor, stockGroup, blizzMirror)
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
                if barAnchor == "topright" or barAnchor == "bottomright" then
                    justH = "BOTTOMRIGHT"
                elseif barAnchor == "left" then
                    justH = "RIGHT"
                elseif barAnchor == "right" then
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
                                        (barAnchor == "left" or barAnchor == "right") and barRegion or popFrame,
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
                            mod.UFOpt_PreviewPurgeGlow(bf, unitName, s, buffSize, buffH)
                        end
                    else
                        if bf:IsShown() then
                            bf:Hide()
                        end
                    end
                end

                -- Reserve buff height only for top/bottom anchors; Left/Right
                -- columns grow sideways and need no vertical room.
                if barAnchor == "topleft" or barAnchor == "topright" or barAnchor == "bottomleft" or barAnchor == "bottomright" then
                    buffExtra = buffH + buffGapY + 2
                end
                -- The stack's lowest visible icon edge below the art (a
                -- downward column adds its rows), for the cast bar under it.
                if barAnchor == "bottomleft" or barAnchor == "bottomright" then
                    buffDrop = buffH + buffGapY - bOffY
                    if gDir == "down" then
                        buffDrop = buffDrop + (visibleBuffCount - 1) * (buffH + buffGapY)
                    end
                end
                -- Reserve Y-offset overflow beyond that footprint: top anchors push
                -- up, bottom push down; side anchors have none, so all of it counts.
                if barAnchor == "topleft" or barAnchor == "topright" then
                    if bOffY > 0 then
                        auraTopOv = auraTopOv + bOffY
                    end
                elseif barAnchor == "bottomleft" or barAnchor == "bottomright" then
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
            local detailAnchor = s.debuffAnchor or "bottomleft"
            local effectiveDebuffSize = s.debuffSize or 22
            local simpleMode = (unitName == "boss") and mod.GetBossSimpleDebuffMode(s) or "none"
            local simpleOn = simpleMode ~= "none"
            if simpleOn then
                detailAnchor = simpleMode -- "left" or "right"
                local pvPowerPos = s.powerPosition or "below"
                local pvPowerIsAtt = (pvPowerPos == "below" or pvPowerPos == "above")
                local pvPowerH = pvPowerIsAtt and (s.powerHeight or 0) or 0
                effectiveDebuffSize = (s.healthHeight or 34) + pvPowerH
            end
            local maxDeb = s.maxDebuffs or 10
            local previewDebuffLimit = 5
            local visibleDebuffCount = math.min(#debuffIcons, maxDeb, previewDebuffLimit)
            -- Boss preview always shows exactly 3 debuffs regardless of Max Count.
            if unitName == "boss" then
                visibleDebuffCount = math.min(#debuffIcons, 3)
            end
            if detailAnchor ~= "none" and visibleDebuffCount > 0 then
                local debuffSize = effectiveDebuffSize
                -- Crop never applies in simple boss mode (runtime passes nil crop
                -- and frame-height-matches those icons).
                local debuffCrop = (not simpleOn) and (as.debuffCropIcons or false) or false
                local debuffH = mod.GetAuraCropHeight(debuffCrop, debuffSize)
                -- Boss spacing from its slider (simple display has its own key);
                -- other units keep the 1px schematic gap.
                local debuffGapX = (unitName == "boss") and mod.GetBossDebuffSpacing(s, simpleOn)
                    or (s.debuffSpacingX or 1)
                local debuffGapY = (unitName == "boss") and mod.GetBossDebuffSpacing(s, simpleOn)
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
                local gDir = (dg == "auto") and (autoGrowth[detailAnchor] or "right") or dg

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
                local am = anchorMap[detailAnchor] or anchorMap.bottomleft
                if stockGroup then
                    popFrame._blizzInset(am, detailAnchor, stockGroup, blizzMirror)
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
                if detailAnchor == "topright" or detailAnchor == "bottomright" then
                    justH = "BOTTOMRIGHT"
                elseif detailAnchor == "left" then
                    justH = "RIGHT"
                elseif detailAnchor == "right" then
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
                                        (detailAnchor == "left" or detailAnchor == "right") and barRegion or popFrame,
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
                    detailAnchor == "topleft"
                    or detailAnchor == "topright"
                    or detailAnchor == "bottomleft"
                    or detailAnchor == "bottomright"
                then
                    debuffExtra = debuffH + debuffGap2 + 2
                end
                -- The stack's lowest visible icon edge below the art (a
                -- downward column adds its rows), for the cast bar under it.
                if detailAnchor == "bottomleft" or detailAnchor == "bottomright" then
                    debuffDrop = debuffH + debuffGapY - dOffY
                    if gDir == "down" then
                        debuffDrop = debuffDrop + (visibleDebuffCount - 1) * (debuffH + debuffGapY)
                    end
                end
                -- Reserve Y-offset overflow beyond the footprint (see the buff block).
                if detailAnchor == "topleft" or detailAnchor == "topright" then
                    if dOffY > 0 then
                        auraTopOv = auraTopOv + dOffY
                    end
                elseif detailAnchor == "bottomleft" or detailAnchor == "bottomright" then
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

        -- Boss debuff samples carry the still cooldown swipe, a duration and
        -- one stack number, as the live boss aura buttons do. Their look
        -- follows the boss aura settings (the Simple Debuffs set while that
        -- mode is on), so those controls update here live.
        do
            local showExtras = (unitName == "boss") and not noDebuffPreview
            local cdOn, cdSize, cdX, cdY, cdColor, stSize, stPos, stX, stY, stColor
            if showExtras then
                local cdKey, cdDefault, cdShowKey = "debuffCooldownText", 10, "debuffShowCooldownText"
                if mod.GetBossSimpleDebuffMode(s) ~= "none" then
                    cdKey, cdDefault, cdShowKey =
                        "simpleDebuffCooldownText", 14, "simpleDebuffShowCooldownText"
                end
                cdOn = s[cdShowKey]
                cdSize = s[cdKey .. "Size"] or cdDefault
                cdX, cdY = s[cdKey .. "OffsetX"] or 0, s[cdKey .. "OffsetY"] or 0
                stSize = s.debuffStackTextSize or 14
                stPos = s.debuffStackTextPosition or "bottomright"
                stX, stY = s.debuffStackTextOffsetX or 0, s.debuffStackTextOffsetY or 0
                cdColor = s.debuffCooldownTextColor or { r = 1, g = 1, b = 1 }
                stColor = s.debuffStackTextColor or { r = 1, g = 1, b = 1 }
            end
            local fontP = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
            for idx, df in ipairs(debuffIcons) do
                local cd, dt, st = df._previewCD, df._durText, df._stackText
                local dressed = showExtras and df:IsShown()
                if cd and not dressed then
                    cd:Hide()
                elseif cd and not cd:IsShown() then
                    cd:Show()
                end
                if dt then
                    if dressed and cdOn then
                        CludesUI.ApplyIconTextFont(dt, fontP, cdSize, "unitFrames")
                        dt:ClearAllPoints()
                        dt:SetPoint("CENTER", df, "CENTER", cdX, cdY)
                        dt:SetTextColor(cdColor.r, cdColor.g, cdColor.b)
                        dt:Show()
                    else
                        dt:Hide()
                    end
                end
                -- A stack number on the second icon only (most debuffs do not
                -- stack), matching the in-game preview.
                if st then
                    if dressed and idx == 2 then
                        CludesUI.ApplyIconTextFont(st, fontP, stSize, "unitFrames")
                        st:SetText(3)
                        mod.ApplyStackAnchor(st, df, stPos, stX, stY)
                        st:SetTextColor(stColor.r, stColor.g, stColor.b)
                        st:Show()
                    else
                        st:Hide()
                    end
                end
            end
        end

        -- Frame height: the bars, an attached Text Bar and the cast bar strip.
        -- Under Blizzard Style it is the visible art (its transparent rows
        -- trimmed) plus the cast bar strip, unless the cast bar hangs below
        -- the auras, when that strip is kept under them instead (auraExtra).
        local textBarH = (btbFrame and s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
        local th = bh2 + textBarH + (ch > 0 and ch or 0)
        if stockGroup then
            local pad = stockGroup.pad
            th = stockGroup.h - (pad and (pad.top + pad.bottom) or 0)
            if ch > 0 then
                cbStrip = ch
                -- The stock text box hangs 13px under the cast bar; it is kept
                -- clear so the content header below does not run into it.
                local UFC = mod.UF_CAST_BLIZZ
                local nameShown = (s.castSpellNameSide or "left") ~= "none"
                if UFC and not mod.UF_BLIZZ.cast and mod.UF_BlizzAtlas(UFC.textbox) and nameShown then
                    cbStrip = cbStrip + 13
                end
                if not blizzBelow then
                    th = th + cbStrip
                end
            end
        end
        popFrame:SetSize(tw, th)

        -- The preview scale, shrunk to fit when the frame is wider than the panel.
        local baseScale = popFrame._previewScale or 1
        local roomW = (popFrame:GetParent():GetWidth() - (CludesUI.CONTENT_PAD or 10) * 2) / baseScale
        local fitScale = 1
        if tw > roomW and tw > 0 and roomW > 0 then
            fitScale = roomW / tw
        end
        local combinedScale = baseScale * fitScale
        popFrame:SetScale(combinedScale)

        -- The border again at the new scale, so it stays pixel exact.
        if edgeFrame then
            local edge = s.borderSizeOverride or bds.borderSize or 1
            local edgeTex = bds.borderTexture or "solid"
            local edgeC = bds.borderColor or { r = 0, g = 0, b = 0 }
            local edgePx = CludesUI.BorderPx((not s.borderSizeOverride) and bds.borderSizePx, edge, edgeTex)
            CludesUI.ApplyBorderStyle(
                edgeFrame,
                edge,
                edgeC.r,
                edgeC.g,
                edgeC.b,
                bds.borderAlpha or 1,
                edgeTex,
                bds.borderTextureOffset,
                bds.borderTextureOffsetY,
                bds.borderTextureShiftX,
                bds.borderTextureShiftY,
                "unitframes",
                edge,
                nil,
                edgePx
            )
        end
        -- Rounded corners, as on the live frame: the border frame is the shape
        -- (health + power + attached portrait and text bar); the fill sits on
        -- pf, under the bars. The portrait joins with its own art only.
        do
            local radius = (not ResolveBlizzPreview(unitName, s) and bds.cornerRadius) or 0
            local det = powerPlace == "detached_top" or powerPlace == "detached_bottom"
            local corners, pCorners = bds.cornerMask, bds.cornerMask
            if det and s.cornerJoinPower then
                local max, lower = CludesUI.RoundedJoinCorners(corners)
                if powerPlace == "detached_bottom" then
                    corners, pCorners = max, lower
                else
                    corners, pCorners = lower, max
                end
            end
            if radius > 0 then
                local port = sp and isAttached and portraitHolder and portraitHolder:IsShown() and portraitHolder
                    or nil
                CludesUI.RoundCorners(popFrame, radius, {
                    roots = {
                        healthBar,
                        (powerPlace == "below" or powerPlace == "above") and powerBar or nil,
                        s.bottomTextBar and btbIsAtt and btbFrame or nil,
                    },
                    textures = { port and port._previewBg, port and port._previewTex },
                    border = edgeFrame,
                    rect = edgeFrame,
                    style = bds.borderTexture or "solid",
                    corners = corners,
                })
            else
                CludesUI.RoundCorners(popFrame, 0)
            end
            if powerBar then
                if det and radius > 0 then
                    CludesUI.RoundCorners(powerBar, radius, {
                        border = powerBar._pbBorder,
                        style = s.powerBorderStyle or "solid",
                        corners = pCorners,
                    })
                else
                    CludesUI.RoundCorners(powerBar, 0)
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
        if castIconHolder then
            Pix.SetBorderSize(castIconHolder, 1)
            if castIconHolder._iconTex then
                castIconHolder._iconTex:ClearAllPoints()
                Pix.Point(castIconHolder._iconTex, "TOPLEFT", castIconHolder, "TOPLEFT", 1, -1)
                Pix.Point(castIconHolder._iconTex, "BOTTOMRIGHT", castIconHolder, "BOTTOMRIGHT", -1, 1)
            end
            -- Show Icon on Portrait: the icon rides the preview portrait
            -- through the live helper (nil hands it back to the bar).
            mod.UF_CastIconPortraitLayout(
                castIconHolder,
                castIconHolder._iconTex,
                (portraitHolder and mod.UF_CastIconOnPortrait(unitName, s)) and portraitHolder or nil,
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
                unitName,
                castIconHolder,
                true
            )
        end

        -- Re-apply PixelUtil sizing to every element so it stays pixel-perfect at
        -- the new scale, starting with the preview frame itself.
        Pix.Size(popFrame, tw, th)
        local snappedFrameW = popFrame:GetWidth()
        local snappedFrameH = popFrame:GetHeight()

        -- Re-snap portrait
        if portraitHolder and sp and isAttached then
            Pix.Size(portraitHolder, portraitDim, portraitDim)
            local snappedPortW = portraitHolder:GetWidth()
            local snappedPortH = portraitHolder:GetHeight()
            if snappedPortW + fw > snappedFrameW + 0.01 then
                portraitHolder:SetWidth(snappedFrameW - fw)
            end
            if snappedPortH > snappedFrameH + 0.01 then
                portraitHolder:SetHeight(snappedFrameH)
            end
        end

        -- Re-snap health bar
        if healthBar then
            Pix.Size(healthBar, fw, hh)
            local snappedHealthW = healthBar:GetWidth()
            local availW = snappedFrameW
            if portraitHolder and sp and isAttached then
                availW = snappedFrameW - portraitHolder:GetWidth()
            end
            if snappedHealthW > availW + 0.01 then
                healthBar:SetWidth(availW)
            end
        end

        -- Re-snap power bar
        if powerBar and powerBar:IsShown() then
            local pvPw2 = fw
            local pvPpIsDet2 = (powerPlace == "detached_top" or powerPlace == "detached_bottom")
            if pvPpIsDet2 and (s.powerWidth or 0) > 0 then
                pvPw2 = s.powerWidth
            end
            Pix.Size(powerBar, pvPw2, ph)
            if pvPpIsAtt and healthBar then
                -- Height: ensure health + power don't exceed expected total
                local snappedHH = healthBar:GetHeight()
                local snappedPH = powerBar:GetHeight()
                local expectedTotal = hh + ph
                if snappedHH + snappedPH > expectedTotal + 0.01 then
                    powerBar:SetHeight(snappedPH - (snappedHH + snappedPH - expectedTotal))
                end
                -- Width: match health bar width exactly
                local snappedHealthW2 = healthBar:GetWidth()
                local snappedPowerW2 = powerBar:GetWidth()
                if math.abs(snappedPowerW2 - snappedHealthW2) > 0.01 then
                    powerBar:SetWidth(snappedHealthW2)
                end
            end
        end
        -- Power Bar Seam: the live helper on the preview bar (preview = true:
        -- this panel repaints itself on a scale change).
        if powerBar then
            mod.UpdatePowerSeam(powerBar, s, CludesUI.BlizzStyle.Get("unitframes"), true)
        end
        if s.portraitSeparator or popFrame._portraitSeparator then
            mod.UpdatePortraitSeparator(
                popFrame,
                portraitHolder,
                s,
                effectiveSide,
                sp and isAttached,
                CludesUI.BlizzStyle.Get("unitframes"),
                true,
                (unitName == "targettarget" or unitName == "boss") and bds or nil
            )
        end
        -- Color Custom Borders: while the Magic border copy shows, both
        -- separators are tinted Magic at full opacity in place, as the live
        -- copies draw them (the two passes above reset the border colour
        -- first), so the preview does not depend on copy-frame draw order
        -- inside the options panel.
        if popFrame._pvDispelBorder and popFrame._pvDispelBorder:IsShown() then
            local mc = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
            local pSeam, vSeam = powerBar and powerBar._pbSeam, popFrame._portraitSeparator
            if pSeam and pSeam:IsShown() then
                pSeam._tex:SetVertexColor(mc.r, mc.g, mc.b, 1)
            end
            if vSeam and vSeam:IsShown() then
                vSeam._tex:SetVertexColor(mc.r, mc.g, mc.b, 1)
            end
        end

        -- An attached Text Bar snapped again: no wider than the frame, and
        -- no taller than the room the class pips, health and power leave.
        if btbFrame and s.bottomTextBar and btbIsAtt then
            Pix.Size(btbFrame, tw, s.bottomTextBarHeight or 16)
            local barW, barH = btbFrame:GetWidth(), btbFrame:GetHeight()
            if barW > snappedFrameW + 0.01 then
                btbFrame:SetWidth(snappedFrameW)
            end
            local stackH = cpAboveH + (healthBar and healthBar:GetHeight() or 0)
            if powerBar and pvPpIsAtt and powerBar:IsShown() then
                stackH = stackH + powerBar:GetHeight()
            end
            if stackH + barH > snappedFrameH + 0.01 then
                btbFrame:SetHeight(barH - (stackH + barH - snappedFrameH))
            end
        end

        -- The cast bar trimmed to the frame width too, except a boss bar with
        -- its own Cast Bar Width: that one is meant to run past the frame and
        -- was already held in at sizing time, so trimming it would quietly
        -- put it back to frame width.
        if castBar then
            local ownWidth = unitName == "boss" and (s.castbarWidth or 0) > 0
            if not ownWidth and castBar:GetWidth() > snappedFrameW + 0.01 then
                castBar:SetWidth(snappedFrameW)
            end
        end

        -- Blizzard Style: the stock look over everything laid out above. The
        -- cast bar hangs under the lowest bottom-anchored stack (live: the
        -- aura block's bottom). Merged buffs ride the debuff anchor, so that
        -- stack decides; else a bottom debuff stack beats a bottom buff stack;
        -- with nothing below it sits flush with the art.
        local stackDrop = 0
        if blizzBelow then
            local merged = s.debuffAnchorBuffs == true and (s.debuffAnchor or "none") ~= "none"
            stackDrop = debuffDrop or (not merged and buffDrop) or 0
        end
        if stockGroup then
            popFrame._blizzApply(s, stockGroup, blizzMirror, blizzExtras, ch, stackDrop)
        end
        -- Spell cost preview: a third of the fill, as the stock styles left it.
        local costSeg = popFrame._pvCostSeg
        if costSeg and costSeg:IsShown() and popFrame._powerFill then
            costSeg:SetWidth(math.floor(popFrame._powerFill:GetWidth() / 3 + 0.5))
        end

        -- Room the auras need above the frame (the preview moves down by it):
        -- a top-anchored buff or debuff row, then whatever a Y offset pushes
        -- past the footprint on any anchor.
        local function TopAnchored(anchor)
            return anchor == "topleft" or anchor == "topright"
        end
        local auraTopPad = 0
        if buffExtra > 0 and TopAnchored(s.buffAnchor or "topleft") then
            auraTopPad = buffExtra
        end
        if debuffExtra > 0 and TopAnchored(s.debuffAnchor or "bottomleft") then
            auraTopPad = auraTopPad + debuffExtra
        end
        auraTopPad = auraTopPad + auraTopOv

        -- And room for what floats above the frame: a detached top portrait
        -- (Blizzard Style seats it in the art), a detached top Text Bar (none
        -- under Blizzard Style), floating top class pips and the WoW Forever
        -- pet happiness icon centred over the frame.
        local detTopExtra = 0
        local portraitUp = sp and not isAttached and effectiveSide == "top" and not stockGroup
        if portraitUp and portraitHolder and portraitHolder:IsShown() then
            detTopExtra = detTopExtra + portraitDim + 15 + pYOff
        end
        if btbFrame and s.bottomTextBar and (s.btbPosition or "bottom") == "detached_top" and not stockGroup then
            detTopExtra = detTopExtra + (s.bottomTextBarHeight or 16) + 15 + (s.btbY or 0)
        end
        if cpTopH > 0 then
            detTopExtra = detTopExtra + cpTopH
        end
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

        -- The corner a stored indicator place names; anything else takes the
        -- indicator's own default corner.
        local CORNER = {
            topleft = "TOPLEFT",
            topright = "TOPRIGHT",
            bottomleft = "BOTTOMLEFT",
            bottomright = "BOTTOMRIGHT",
        }
        local WHITE_RGB = { r = 1, g = 1, b = 1 }
        -- Combat indicator, behind its eye toggle.
        local combatOn = optionState.showCombatIndicatorPreview
            and s.combatIndicatorStyle
            and s.combatIndicatorStyle ~= "none"
        if combatIcon and not combatOn then
            combatIcon:Hide()
        elseif combatIcon then
            local ciStyle = s.combatIndicatorStyle or "class"
            local ciColor = s.combatIndicatorColor or "custom"
            local ciSz = s.combatIndicatorSize or 22
            local ciOx, ciOy = s.combatIndicatorX or 0, s.combatIndicatorY or 0
            local ciPos = s.combatIndicatorPosition or "healthbar"
            combatIcon:SetSize(ciSz, ciSz)
            combatIcon:ClearAllPoints()
            -- "healthbar" is the stored value the dropdown calls Center, and
            -- "center" draws the same. Portrait follows the live rule
            -- (ns.UF_PortraitShown): a stock style (blizzG) always shows its
            -- portrait, whatever Portrait Mode says.
            if ciPos == "portrait" and portraitHolder and (sp or stockGroup) then
                combatIcon:SetPoint("CENTER", portraitHolder, "CENTER", ciOx, ciOy)
            elseif ciPos == "textbar" then
                combatIcon:SetPoint("CENTER", btbFrame or popFrame, "CENTER", ciOx, ciOy)
            elseif ciPos == "healthbar" or ciPos == "center" then
                combatIcon:SetPoint("CENTER", healthBar, "CENTER", ciOx, ciOy)
            else
                local corner = CORNER[ciPos] or "TOPLEFT"
                combatIcon:SetPoint(corner, healthBar, corner, ciOx, ciOy)
            end
            local _, classToken = UnitClass("player")
            if ciStyle:find("^combat%d") then
                -- The custom combat icons (combat0..5) draw untinted.
                combatIcon:SetTexture(COMBAT_MEDIA_P .. ciStyle .. ".tga")
                combatIcon:SetTexCoord(0, 1, 0, 1)
                if combatIcon.SetDesaturated then
                    combatIcon:SetDesaturated(false)
                end
                combatIcon:SetVertexColor(1, 1, 1, 1)
            else
                -- Standard and Class Theme take the colour mode's tint.
                local coords
                if ciStyle == "class" then
                    combatIcon:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-class-custom.png")
                    coords = CLASS_FULL_COORDS[classToken]
                else
                    combatIcon:SetTexture(COMBAT_MEDIA_P .. "combat-indicator-custom.png")
                end
                if coords then
                    combatIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                else
                    combatIcon:SetTexCoord(0, 1, 0, 1)
                end
                local tint = WHITE_RGB
                if ciColor == "classcolor" then
                    tint = RAID_CLASS_COLORS[classToken] or WHITE_RGB
                elseif ciColor == "custom" then
                    tint = s.combatIndicatorCustomColor or WHITE_RGB
                end
                combatIcon:SetVertexColor(tint.r or 1, tint.g or 1, tint.b or 1, 1)
            end
            combatIcon:Show()
        end
        -- Faction indicator, behind its eye toggle: your own faction on the
        -- player frame, the other one on the target frame (what Opposite
        -- Faction shows), with your own badge on both.
        if factionInd then
            local eyeOn = mod._ufPvEyes and mod._ufPvEyes.faction
            local wanted = (s.factionIndicatorMode or "off") ~= "off"
            if not ((unitName == "player" or unitName == "target") and wanted and eyeOn) then
                factionInd:Hide()
            else
                local mine = UnitFactionGroup("player")
                local fac = mine
                if unitName == "target" then
                    fac = (mine == "Horde") and "Alliance" or "Horde"
                end
                if fac ~= "Horde" and fac ~= "Alliance" then
                    fac = "Horde"
                end
                local fSz = s.factionIndicatorSize or 18
                local fPos = s.factionIndicatorPosition or "topright"
                local fOx, fOy = s.factionIndicatorX or 0, s.factionIndicatorY or 0
                local fStyle = s.factionIndicatorStyle or "pvp"
                CludesUI.SetFactionArt(factionInd, fStyle, fac, CludesUI.FactionBadgeFor(fStyle, "player"))
                factionInd:SetSize(fSz, fSz)
                factionInd:ClearAllPoints()
                if fPos == "portrait" and portraitHolder and (sp or stockGroup) then
                    factionInd:SetPoint("CENTER", portraitHolder, "CENTER", fOx, fOy)
                else
                    local corner = CORNER[fPos] or "TOPRIGHT"
                    factionInd:SetPoint(corner, popFrame, corner, fOx, fOy)
                end
                factionInd:Show()
            end
        end
        -- Raid marker / leader / elite previews, shown by their rows' eye toggles
        -- (and only while the indicator itself is on). Placement mirrors the
        -- live frames: raid marker centred on a frame corner, the other two on
        -- a health-bar corner or the portrait.
        do
            local eyes = mod._ufPvEyes or {}
            local isPT = unitName == "player" or unitName == "target"
            local function PlaceCorner(texture, place, ox, oy)
                texture:ClearAllPoints()
                if place == "portrait" and portraitHolder and (sp or stockGroup) then
                    texture:SetPoint("CENTER", portraitHolder, "CENTER", ox, oy)
                else
                    local anchor = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    texture:SetPoint(anchor, healthBar, anchor, ox, oy)
                end
            end
            local rt = popFrame._pvRaid
            if rt then
                if isPT and eyes.raid and s.raidMarkerEnabled then
                    local idx = (eyes.raidIndex or 1) - 1
                    local col, row = idx % 4, math.floor(idx / 4)
                    rt:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
                    local rmSize = s.raidMarkerSize or 28
                    local rmAlign = s.raidMarkerAlign or "right"
                    local anchor = (rmAlign == "left") and "TOPLEFT"
                        or (rmAlign == "center") and "TOP"
                        or "TOPRIGHT"
                    rt:SetSize(rmSize, rmSize)
                    rt:ClearAllPoints()
                    rt:SetPoint("CENTER", popFrame, anchor, s.raidMarkerX or 0, s.raidMarkerY or 0)
                    rt:Show()
                else
                    rt:Hide()
                end
            end
            local lt = popFrame._pvLeader
            if lt then
                if isPT and eyes.leader and s.leaderIndicatorEnabled ~= false then
                    local size = s.leaderIndicatorSize or 16
                    lt:SetTexture(
                        (mod.UF_LEADER_ART[s.leaderIndicatorStyle] or mod.UF_LEADER_ART.blizzard).leader
                    )
                    lt:SetSize(size, size)
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
                    unitName == "target"
                    and eyes.elite
                    and s.eliteIndicatorEnabled == true
                    and not mod.UF_DragonLegacy(s)
                then
                    if s.eliteIndicatorStyle == "pixelsDragon" and portraitHolder and sp and not stockGroup then
                        -- Pixels Dragon (Elite sample) around the portrait, as live
                        -- (the stock styles draw the Badge).
                        local d = portraitHolder:GetHeight() * mod.UF_ELITE_DRAGON_SCALE
                        et:SetTexture(mod.UF_ELITE_DRAGON_ART.elite)
                        et:SetTexCoord(0, 1, 0, 1)
                        et:SetSize(d, d)
                        et:ClearAllPoints()
                        et:SetPoint("CENTER", portraitHolder, "CENTER", 0, 0)
                    else
                        local size = s.eliteIndicatorSize or 16
                        -- Clear a dragon style's sheet coords first (SetAtlas
                        -- can keep custom coords, reading them inside the atlas box).
                        et:SetTexCoord(0, 1, 0, 1)
                        et:SetAtlas("nameplates-icon-elite-gold")
                        et:SetSize(size, size)
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
                    hInd:SetPoint("RIGHT", barRegion, "LEFT", hX, hY)
                elseif hAl == "top" then
                    hInd:SetPoint("BOTTOM", barRegion, "TOP", hX, hY)
                else
                    hInd:SetPoint("LEFT", barRegion, "RIGHT", hX, hY)
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
    popFrame._power = powerBar
    popFrame._castbar = castBar
    popFrame._castIconFrame = castIconHolder
    popFrame._castNameFS = castNameText
    popFrame._castTimeFS = castTimeFS
    popFrame._castTargetFS = castTargetFS
    popFrame._nameFS = leftFS
    popFrame._hpFS = rightFS
    popFrame._centerFS = centerFS
    popFrame._extraFS = extraFS
    popFrame._portraitFrame = portraitHolder
    popFrame._buffIcons = buffIcons
    popFrame._debuffIcons = debuffIcons
    popFrame._barArea = barRegion
    popFrame._textOverlay = textOverlay
    popFrame._btbFrame = btbFrame
    popFrame._btbBg = btbBg
    popFrame._btbLeftFS = btbLeftFS
    popFrame._btbRightFS = btbRightFS
    popFrame._btbCenterFS = btbCenterFS
    popFrame._btbClassIcon = btbClassIconTex
    popFrame._ppFS = ppPreviewFS
    popFrame._border = edgeFrame
    popFrame._cpPipContainer = comboPipHolder
    popFrame._cpPips = cpPips
    popFrame._combatIndicator = combatIcon
    popFrame._dispelOverlayPreview = dispelPreview

    popFrame._disabledOverlay = disabledOverlay
    -- Clean up any orphaned preview for this unit key before storing the new one
    -- (a frame dressed again for another unit keeps its overlay for that unit)
    local oldPv = allPreviews[unitName]
    if oldPv and oldPv ~= popFrame and oldPv._pvUnit == unitName then
        if oldPv._disabledOverlay then
            oldPv._disabledOverlay:Hide()
        end
    end
    -- Also purge any orphaned previews (parent set to nil by ClearContentHeaderInner)
    -- and every entry whose frame was dressed again for another unit (this one included)
    for keyName, preview in pairs(allPreviews) do
        if preview and preview._pvUnit ~= keyName then
            allPreviews[keyName] = nil
        elseif preview and preview ~= popFrame and not preview:GetParent() then
            if preview._disabledOverlay then
                preview._disabledOverlay:Hide()
            end
            allPreviews[keyName] = nil
        end
    end
    allPreviews[unitName] = popFrame
    return popFrame
end
