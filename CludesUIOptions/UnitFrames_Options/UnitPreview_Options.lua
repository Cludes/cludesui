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

function mod.UFO_BuildUnitPreview(hostFrame, unitKey, side)
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
    local function PV_FillColor(texture, texPath, r, g, b, useGradient, toColor, direction, alpha)
        if not texture then
            return
        end
        if not useGradient then
            if texPath then
                texture:SetTexture(texPath)
                texture:SetVertexColor(r, g, b, 1)
            else
                texture:SetColorTexture(r, g, b, 1)
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
            CreateColor(r, g, b, endA),
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
        return saved.profile[DRESSED_UNITS[unitKey] and unitKey or "player"]
    end
    local prefs = UnitPrefs()

    side = side or "left"

    -- The live mini frames (ToT, FoT, pet) carry no cast bar, power bar or
    -- debuffs, so neither does their preview. Two exceptions: the pet keeps
    -- its opt-in auras (shown while a Location is picked) and, on WoW
    -- Forever, its power bar in the CludesUI look (a stock style paints its own).
    local isMiniPreview = (unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "pet")
    local petDrawsPower = unitKey == "pet" and mod.UF_PetHasPower and not ResolveBlizzPreview(unitKey, prefs)
    local noPowerPreview = isMiniPreview and not petDrawsPower
    local noDebuffPreview = isMiniPreview and unitKey ~= "pet"
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
        if unitKey ~= "player" then
            castbarH = (prefs.showCastbar ~= false) and (prefs.castbarHeight or 14) or 0
        elseif prefs.showPlayerCastbar then
            local ownH = prefs.playerCastbarHeight
            castbarH = (ownH and ownH > 0) and ownH or 14
        end
    end
    local inStrip = CludesUI.UF_CastbarBelowFrame
    if castbarH > 0 and inStrip and not inStrip(unitKey) then
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

    -- Portrait: a clipped box over a dark backing, holding one texture (the
    -- 2D portrait or the class art) and, made on first need, a PlayerModel
    -- (3D, and the test for whether a 2D portrait may be mirrored).
    local portraitFrame
    if hasPortraitSupport then
        portraitFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(portraitFrame, barH, barH)
        portraitFrame:SetClipsChildren(true)
        local backing = portraitFrame:CreateTexture(nil, "BACKGROUND")
        backing:SetAllPoints()
        backing:SetColorTexture(0.082, 0.082, 0.082, 1)
        portraitFrame._previewBg = backing
        local nearCorner = (side == "left") and "TOPLEFT" or "TOPRIGHT"
        Pix.Point(portraitFrame, nearCorner, barArea, nearCorner, 0, 0)

        local function FillBox(region)
            region:SetPoint("TOPLEFT", portraitFrame, "TOPLEFT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", 0, 0)
        end
        local portraitTex = portraitFrame:CreateTexture(nil, "ARTWORK")
        FillBox(portraitTex)
        portraitTex:SetTexCoord(0.15, 0.85, 0.15, 0.85)

        local portraitModel
        local function EnsurePreviewModel()
            if not portraitModel then
                portraitModel = CreateFrame("PlayerModel", nil, portraitFrame)
                FillBox(portraitModel)
                portraitModel:SetUnit("player")
                portraitModel:SetCamera(0)
                portraitModel:Hide()
                portraitFrame._previewModel = portraitModel
            end
            return portraitModel
        end
        -- The texture pinned inside the box, `inset` px in from every edge.
        local function SeatPortraitTex(inset)
            portraitTex:ClearAllPoints()
            Pix.Point(portraitTex, "TOPLEFT", portraitFrame, "TOPLEFT", inset, -inset)
            Pix.Point(portraitTex, "BOTTOMRIGHT", portraitFrame, "BOTTOMRIGHT", -inset, inset)
        end

        -- What the box last drew. An Update that changes none of mode, art
        -- style, zoom and mirror leaves the box alone: seating a PlayerModel
        -- again on every Update blinks and costs a great deal of GPU.
        local drawn = {}
        local function ApplyPortraitMode()
            local cur = UnitPrefs()
            local mode = cur.portraitMode or "2d"
            -- A non-player frame that opted in shows its Class art fallback
            -- (a stock style keeps its own portrait). The resolved mode is
            -- what the memo compares, so the fallback's inputs ride it.
            if
                mode == "class"
                and unitKey ~= "player"
                and cur.portraitNonPlayerOn
                and not CludesUI.BlizzStyle.Get("unitframes")
            then
                mode = mod.UF_ClassFallback(cur)
            end
            local style = cur.classThemeStyle or "modern"
            local zoom = (cur.portraitArtScale or 100) + (cur.portrait3dZoom or 100) * 1000
            -- Mirror Portrait turns 3D models too, and never under a stock style.
            local mirror = cur.portraitMirror and not CludesUI.BlizzStyle.Get("unitframes") and true or false
            if mode == drawn.mode and style == drawn.style and zoom == drawn.zoom then
                if mirror == drawn.mirror then
                    return
                end
                if mode == "3d" and portraitModel then
                    drawn.mirror = mirror
                    mod.UF_ApplyPortraitRotation(portraitModel, mirror)
                    return
                end
            end
            drawn.mode, drawn.style, drawn.zoom, drawn.mirror = mode, style, zoom, mirror
            portraitFrame._previewMode = mode
            -- Class art and the 2D portrait share the one texture, so a mask
            -- the class art left behind comes off for anything else.
            if mode ~= "class" and portraitTex._classZoomMasked then
                portraitTex:RemoveMaskTexture(portraitTex._classZoomMask)
                portraitTex._classZoomMask:Hide()
                portraitTex._classZoomMasked = nil
            end
            portraitFrame:Show()
            if mode == "3d" then
                portraitTex:Hide()
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
            if mode == "none" then
                -- The non-player "Nothing" fallback: just the empty backing.
                portraitTex:Hide()
            elseif mode == "class" then
                portraitTex:Show()
                local _, classToken = UnitClass("player")
                ApplyClassIconTexture_Preview(portraitTex, classToken or "WARRIOR", style, mirror)
                portraitTex:SetAlpha(0.9)
                -- Inset from the box's height now, not the build-time barH.
                local boxH = portraitFrame:GetHeight()
                SeatPortraitTex(math.floor((boxH < 1 and barH or boxH) * 0.08))
            else
                portraitTex:Show()
                SetPortraitTexture(portraitTex, "player")
                mirror = mirror and mod.UF_CanMirrorPortrait2D(EnsurePreviewModel(), "player")
                local u0, u1 = 0.15, 0.85
                if mirror then
                    u0, u1 = u1, u0
                end
                portraitTex:SetTexCoord(u0, u1, 0.15, 0.85)
                portraitTex:SetAlpha(1)
                SeatPortraitTex(0)
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

    -- Health colours outside the dark theme, for a settings table (the
    -- build's and every Update's): the fill from the unit's own picks with
    -- Dynamic Health Color over every flat source as on the live bar (fed
    -- the preview's known fake percent, so the clean-number twin of the
    -- engine curve stands in for UnitHealthPercent), then the backing.
    local function LitHealthColors(s)
        local function PlayerClassRGB()
            local _, token = UnitClass("player")
            local classColor = RAID_CLASS_COLORS[token]
            if classColor then
                return classColor.r, classColor.g, classColor.b
            end
            return 37 / 255, 193 / 255, 29 / 255
        end
        -- The boss preview stays hostile red: the live boss frame never class-colours.
        local r, g, b
        local ownFill = s.customFillColor
        if s.healthClassColored and unitKey ~= "boss" then
            r, g, b = PlayerClassRGB()
        elseif ownFill then
            r, g, b = ownFill.r, ownFill.g, ownFill.b
        elseif unitKey == "player" then
            r, g, b = PlayerClassRGB()
        elseif unitKey == "pet" then
            r, g, b = 37 / 255, 193 / 255, 29 / 255
        else
            r, g, b = 0.8, 0.2, 0.2
        end
        local dynR, dynG, dynB = mod.UF_PreviewDynamicColor(s, optionState._previewHealthPct or 0.70)
        if dynR then
            r, g, b = dynR, dynG, dynB
        end
        -- Backing: the player's class colour (the designer shows your class)
        -- while Class Colored Background is on, else the custom pick.
        local classBack
        if s.bgClassColored then
            local _, token = UnitClass("player")
            classBack = token and CludesUI.GetClassColor(token)
        end
        local backPick = classBack or s.customBgColor
        if backPick then
            return r, g, b, backPick.r, backPick.g, backPick.b
        end
        return r, g, b, 17 / 255, 17 / 255, 17 / 255
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
    local health = CreateFrame("Frame", nil, popFrame)
    Pix.Size(health, frameW, healthH)
    local healthBgColor = health:CreateTexture(nil, "BACKGROUND")
    healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", fillW, 0)
    healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    healthBgColor:SetColorTexture(bgR, bgG, bgB, 1)
    healthBgColor:SetAlpha(bgA)
    -- A power bar above the health bar pushes the health bar down by its height.
    local dropForPower = (initPpPos == "above") and powerH or 0
    if not (showPortrait and portraitFrame) then
        Pix.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -dropForPower)
    elseif side == "left" then
        Pix.Point(health, "TOPLEFT", portraitFrame, "TOPRIGHT", 0, -dropForPower)
    else
        Pix.Point(health, "TOPRIGHT", portraitFrame, "TOPLEFT", 0, -dropForPower)
    end

    local healthBg = health:CreateTexture(nil, "BACKGROUND", nil, -1)
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(0.1, 0.1, 0.1, 0.75)

    local healthFill = health:CreateTexture(nil, "ARTWORK")
    healthFill:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    healthFill:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    healthFill:SetWidth(fillW)
    local healthGradient = (not isDarkTheme) and prefs.gradientEnabled
    PV_FillColor(healthFill, nil, hR, hG, hB, healthGradient, prefs.gradientColor, prefs.gradientDir, hA)
    healthFill:SetAlpha(hA)
    popFrame._healthFill = healthFill
    popFrame._hR, popFrame._hG, popFrame._hB, popFrame._hA = hR, hG, hB, hA

    local dispelOverlayPreview
    if unitKey == "player" then
        dispelOverlayPreview = health:CreateTexture(nil, "ARTWORK", nil, 3)
        dispelOverlayPreview:SetTexture("Interface\\Buttons\\WHITE8X8")
        dispelOverlayPreview:Hide()
    end

    -- Text layer over the health bar, above the absorb bars and the border.
    local textOverlay = CreateFrame("Frame", nil, popFrame)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameStrata(popFrame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(popFrame:GetFrameLevel() + 20, health:GetFrameLevel() + 12))

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
    local function PreviewTextForContent(contentFrame, s, prefixText)
        -- Numbers as the live tags print them: the Show Decimal on Text
        -- function when that is on (WoW Forever: nothing under 10,000
        -- abbreviates), else the Number Format for the value type (a boss
        -- frame's health reads as "bossHealth").
        local function Abbr(val, valueType)
            local decimalCfg = _G._CUI_AbbrevDecimalCfg
            if decimalCfg then
                return mod.AbbreviateNumbers(val, decimalCfg)
            end
            if valueType ~= "absorb" and unitKey:match("^boss") then
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
            if unitKey == "player" then
                shown = CludesUI.WithSurname(UnitName("player")) or "Player"
            else
                shown = _previewCreatureNames[unitKey] or unitKey
            end
            if prefixText and s then
                shown = CludesUI.ShortName(shown, s[prefixText .. "NameFormat"])
            end
            return shown
        end
        local function Tint(text, r, g, b)
            return string.format("%s%s|r", CludesUI.HexColor(r, g, b), text)
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
                local picked = prefixText and s[prefixText .. "TargetSep"]
                if type(picked) ~= "string" or picked == "" then
                    picked = ">"
                end
                sep = " " .. picked .. " "
            end
            if sep == "" then
                return word
            end
            if prefixText and s[prefixText .. "TargetSepClassColor"] then
                if classColor then
                    sep = Tint(sep, classColor.r, classColor.g, classColor.b)
                end
                return sep .. word
            end
            local own = prefixText and s[prefixText .. "TargetSepColor"]
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
            local lvl = UnitLevel("player")
            lvl = (type(lvl) == "number" and lvl > 0) and tostring(lvl) or "80"
            -- Level Difficulty Color: tinted as an attackable unit of your level.
            if s and s.levelDifficultyColor then
                lvl = CludesUI.ColorText(lvl, CludesUI.GetLevelDifficultyColor(tonumber(lvl), true))
            end
            return lvl
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
                local pre = prefixText and s[prefixText .. "TargetPrefix"]
                if type(pre) ~= "string" then
                    pre = "T:"
                end
                return TargetText(
                    pre ~= "" and (pre .. " ") or "",
                    not (prefixText and s[prefixText .. "ClassColor"])
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
                CludesUI.TextTags.Parse(mod.UF_TextTags, prefixText and s and s[prefixText .. "CustomFormat"])
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
        if useCC and unitKey ~= "player" then
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
        local r, g, b = CludesUI.ResolveUnitPowerColor("player")
        if r then
            fontStr:SetTextColor(r, g, b)
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
    local function PlaceSlot(fs, s, prefix, content, edge)
        SetPVFont(fs, PREVIEW_FONT, s[prefix .. "Size"] or s.textSize or 12)
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
        Pix.Point(fs, spot[1], textOverlay, spot[1], spot[2] + (s[prefix .. "X"] or 0), s[prefix .. "Y"] or 0)
        return true
    end
    local function FillSlot(fs, s, prefix, content)
        fs:SetText(PreviewTextForContent(content, s, prefix))
        fs:Show()
        PreviewClassColor(
            fs,
            s[prefix .. "ClassColor"],
            s[prefix .. "ColorR"],
            s[prefix .. "ColorG"],
            s[prefix .. "ColorB"]
        )
    end
    -- Every slot draws on its own: a Center text hides neither Left nor Right.
    local function ApplyPreviewTextPositions(s)
        local leftKey = s.leftTextContent or "name"
        local rightKey = s.rightTextContent or (unitKey == "focus" and "perhp" or "both")
        local centerKey = s.centerTextContent or "none"
        local extraKey = s.extraTextContent or "none"
        if
            PlaceSlot(
                extraFS,
                s,
                "extraText",
                extraKey,
                SLOT_EDGE[s.extraTextAlign] and s.extraTextAlign or "left"
            )
        then
            FillSlot(extraFS, s, "extraText", extraKey)
        end
        if PlaceSlot(centerFS, s, "centerText", centerKey, "center") then
            FillSlot(centerFS, s, "centerText", centerKey)
        end
        if PlaceSlot(leftFS, s, "leftText", leftKey, "left") then
            if rightKey == "none" then
                leftFS:SetWidth(0)
            else
                local taken = (RIGHT_TEXT_ROOM[rightKey] or 0) + 10
                if rightKey == "custom" then
                    taken = mod.UF_EstimateTextWidth(rightKey, s.rightTextCustomFormat, true)
                end
                Pix.Width(leftFS, math.max((s.frameWidth or 181) - taken - 10, 20))
            end
            FillSlot(leftFS, s, "leftText", leftKey)
        end
        if PlaceSlot(rightFS, s, "rightText", rightKey, "right") then
            FillSlot(rightFS, s, "rightText", rightKey)
        end
    end
    ApplyPreviewTextPositions(prefs)

    -- The power fill colour: the power type's colour (the class colour with
    -- Class Colored) while Power Color is on, else the custom fill, else blue.
    local function PowerFillRGB(s)
        s = s or prefs
        local byPower = s.powerPercentPowerColor ~= false
        if byPower and s.powerClassColored then
            local _, token = UnitClass("player")
            local classColor = CludesUI.GetClassColor(token)
            return classColor.r, classColor.g, classColor.b
        elseif byPower then
            local _, kind = UnitPowerType("player")
            local typeColor = CludesUI.GetPowerColor(kind or "MANA")
            return typeColor.r, typeColor.g, typeColor.b
        end
        local own = s.customPowerFillColor
        if own then
            return own.r, own.g, own.b
        end
        return 0, 0, 1
    end
    local function PaintPowerFill(fill, texPath, r, g, b)
        local opacity = (prefs.powerBarOpacity or 100) / 100
        PV_FillColor(
            fill,
            texPath,
            r,
            g,
            b,
            prefs.powerGradientEnabled,
            prefs.powerGradientColor,
            prefs.powerGradientDir,
            opacity
        )
        return opacity
    end

    -- Power bar: made for every unit that can show one, even at height 0, so
    -- a 0 height bar still carries its text and grows back when raised.
    local power
    local ppPreviewFS
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
                reversed and power or powerFill,
                reversed and "TOPLEFT" or "TOPRIGHT",
                0,
                0
            )
            powerBg:SetPoint(
                "BOTTOMRIGHT",
                reversed and powerFill or power,
                reversed and "BOTTOMLEFT" or "BOTTOMRIGHT",
                0,
                0
            )
        end
        -- First placement for the Bar Position (Update places it again).
        if initPpPos == "none" then
            power:Hide()
        elseif initPpPos == "detached_top" or initPpPos == "detached_bottom" then
            local onTop = initPpPos == "detached_top"
            local lift = (onTop and 15 or -15) + (prefs.powerY or 0)
            power:SetPoint(
                onTop and "BOTTOM" or "TOP",
                health,
                onTop and "TOP" or "BOTTOM",
                prefs.powerX or 0,
                lift
            )
        else
            local ownEdge, healthEdge = "TOP", "BOTTOM"
            if initPpPos == "above" then
                ownEdge, healthEdge = "BOTTOM", "TOP"
            end
            Pix.Point(power, ownEdge .. "LEFT", health, healthEdge .. "LEFT", 0, 0)
            Pix.Point(power, ownEdge .. "RIGHT", health, healthEdge .. "RIGHT", 0, 0)
        end

        -- The power text's own layer on pf, over the border.
        local ppOvr = CreateFrame("Frame", nil, popFrame)
        ppOvr:SetAllPoints(power)
        ppOvr:SetFrameLevel(barArea:GetFrameLevel() + 8)
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
            local r, g, b = PowerFillRGB()
            popFrame._pR, popFrame._pG, popFrame._pB = r, g, b
            PaintPowerFill(popFrame._powerFill, texPath, r, g, b)
        end
    end

    -- Cast bar: always made for the player (Update shows or hides it), for
    -- the others only while it has a height.
    local castBar, castFill, castNameFS2, castIconFrame
    local castTimeFS, castTargetFS
    if unitKey == "player" or castbarH > 0 then
        local isPlayer = unitKey == "player"
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
        local iconInBar = mod.UF_CastIconInWidth(unitKey, prefs)
        local iconOnRight = prefs[isPlayer and "playerCastbarIconRight" or "castbarIconRight"] == true
        local offsetKey = isPlayer and "playerCastIconOffset" or "castIconOffset"
        local iconDX, iconDY = prefs[offsetKey .. "X"] or 0, prefs[offsetKey .. "Y"] or 0
        -- Boss: a Cast Bar Width above 0 replaces the frame width (0 = match),
        -- held to frame width + 120 here so an extreme value cannot spill over
        -- the options panel (pf does not clip); live frames take it in full.
        local fullW = totalW
        if unitKey == "boss" and (prefs.castbarWidth or 0) > 0 then
            fullW = math.min(math.max(prefs.castbarWidth, 30), totalW + 120)
        end
        local barW = iconInBar and math.max(1, fullW - iconW) or fullW
        castBar = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castBar, barW, initCH)
        local cbAnchor = power or health
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
        castNameFS2 = CastText(11, "LEFT")
        castNameFS2:SetTextColor(1, 1, 1)
        castNameFS2:SetText(castSpellName)
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
        castNameFS2:SetWidth(shownW * 0.42)
        castNameFS2:SetPoint("LEFT", castBar, "LEFT", 5, 1)
        castTimeFS:SetWidth(timeW)
        castTimeFS:SetPoint("RIGHT", castBar, "RIGHT", -3, 0)
        if castTargetFS then
            castTargetFS:SetWidth(shownW * 0.42)
            castTargetFS:SetPoint("RIGHT", castBar, "RIGHT", -3 - timeW, 0)
        end

        -- Spell icon off the bar's left end (right with Show Icon on Right);
        -- with the icon as part of the bar it lands inside the footprint.
        -- A plain frame and edge textures, not BackdropTemplate, for exact pixels.
        castIconFrame = CreateFrame("Frame", nil, popFrame)
        Pix.Size(castIconFrame, initCH, initCH)
        if iconOnRight then
            Pix.Point(castIconFrame, "TOPLEFT", castBar, "TOPRIGHT", iconDX, iconDY)
        else
            Pix.Point(castIconFrame, "TOPRIGHT", castBar, "TOPLEFT", iconDX, iconDY)
        end
        local iconBg = castIconFrame:CreateTexture(nil, "BACKGROUND")
        iconBg:SetAllPoints()
        iconBg:SetColorTexture(0, 0, 0, 1)
        castIconFrame._bg = iconBg
        Pix.CreateBorder(castIconFrame, 0, 0, 0, 1)
        local castIconTex = castIconFrame:CreateTexture(nil, "ARTWORK")
        Pix.Point(castIconTex, "TOPLEFT", castIconFrame, "TOPLEFT", 1, -1)
        Pix.Point(castIconTex, "BOTTOMRIGHT", castIconFrame, "BOTTOMRIGHT", -1, 1)
        castIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castIconTex:SetTexture(castSpellIcon)
        castIconFrame._iconTex = castIconTex

        -- The player's bar starts hidden while its cast bar is off.
        if isPlayer and castbarH <= 0 then
            castBar:Hide()
            castIconFrame:Hide()
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
        local underFrame = (initPpIsAtt and power) and power or health
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
            Pix.Point(btbFrame, "BOTTOM", health, "TOP", slide, 0)
        elseif barPos == "detached_top" then
            btbFrame:SetPoint("BOTTOM", health, "TOP", dx, 15 + dy)
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
        btbTextOvr:SetFrameLevel(barArea:GetFrameLevel() + 10)
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
        iconLayer:SetFrameLevel(barArea:GetFrameLevel() + 12)
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
        ApplyBTBPreviewTexts = function(s)
            for _, slot in ipairs(BAR_SLOTS) do
                local fs, prefix, point, inset = slot[1], slot[2], slot[3], slot[4]
                local content = s[prefix .. "Content"] or "none"
                SetPVFont(fs, PREVIEW_FONT, s[prefix .. "Size"] or 11)
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
                        inset + (s[prefix .. "X"] or 0),
                        s[prefix .. "Y"] or 0
                    )
                    fs:SetText(PreviewTextForContent(content, s, prefix))
                    fs:Show()
                    local r, g, b = s[prefix .. "ColorR"], s[prefix .. "ColorG"], s[prefix .. "ColorB"]
                    PreviewClassColor(fs, s[prefix .. "ClassColor"], r, g, b)
                    PreviewPowerColor(fs, content, s[prefix .. "PowerColor"], s[prefix .. "CustomFormat"])
                end
            end

            -- The class icon, in the picked art style at its Location.
            local iconStyle = s.btbClassIcon or "none"
            local _, classToken
            if iconStyle ~= "none" then
                _, classToken = UnitClass("player")
            end
            if not (classToken and ApplyClassIconTexture_Preview(btbClassIconTex, classToken, iconStyle)) then
                btbClassIconTex:Hide()
                IconOverlayShown(false)
                return
            end
            local iconSize = s.btbClassIconSize or 14
            Pix.Size(btbClassIconTex, iconSize, iconSize)
            btbClassIconTex:ClearAllPoints()
            local spot = ICON_SPOT[s.btbClassIconLocation] or ICON_SPOT.left
            local iconX = spot[2] + (s.btbClassIconX or 0)
            Pix.Point(btbClassIconTex, spot[1], btbTextOvr, spot[1], iconX, s.btbClassIconY or 0)
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
    local cpPipContainer, cpPips
    if unitKey == "player" then
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
            cpPipContainer = CreateFrame("Frame", nil, popFrame)
            cpPipContainer:SetFrameLevel(popFrame:GetFrameLevel() + 4)
            local cpBgTex = cpPipContainer:CreateTexture(nil, "BACKGROUND")
            cpBgTex:SetAllPoints()
            local backing = prefs.classPowerBgColor or { r = 0.082, g = 0.082, b = 0.082, a = 1.0 }
            cpBgTex:SetColorTexture(backing.r, backing.g, backing.b, backing.a)
            cpPipContainer._bgTex = cpBgTex
            cpPips = {}
            local lit = math.min(3, cpMax)
            for pipIndex = 1, cpMax do
                local pip = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 3)
                pip:SetColorTexture(1, 1, 1, 1)
                Pix.Size(pip, 8, 3)
                if pipIndex <= lit then
                    pip:SetColorTexture(litRGB[1], litRGB[2], litRGB[3], 1)
                end
                cpPips[pipIndex] = pip
            end
            -- Update shows the row unless the style is "none".
            cpPipContainer:Hide()

            -- A 1px line in the frame border colour along the bottom, for the
            -- "above" position only; sublevel 7 keeps it over the pips (3).
            local cpBottomBdr = cpPipContainer:CreateTexture(nil, "OVERLAY", nil, 7)
            cpBottomBdr:SetHeight(1)
            Pix.Point(cpBottomBdr, "BOTTOMLEFT", cpPipContainer, "BOTTOMLEFT", 0, 0)
            Pix.Point(cpBottomBdr, "BOTTOMRIGHT", cpPipContainer, "BOTTOMRIGHT", 0, 0)
            local edgeColor = prefs.borderColor or { r = 0, g = 0, b = 0 }
            cpBottomBdr:SetColorTexture(edgeColor.r, edgeColor.g, edgeColor.b, 1)
            cpBottomBdr:Hide()
            cpPipContainer._bottomBdr = cpBottomBdr
        end
    end

    -- Border: a plain frame on barArea with four edge textures sized through
    -- PixelUtil. Never BackdropTemplate: its edgeSize clipping drops sides on
    -- small frames and its snapping cannot be turned off. It wraps the health
    -- and power bars and an attached Text Bar.
    local bdrSize = prefs.borderSize or 1
    local bdrColor = prefs.borderColor or { r = 0, g = 0, b = 0 }
    local bdrTexKey = prefs.borderTexture or "solid"
    local border = CreateFrame("Frame", nil, popFrame)
    border:SetPoint("TOPLEFT", barArea, "TOPLEFT", 0, 0)
    border:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
    local barPosNow = prefs.btbPosition or "bottom"
    local wrapsTextBar = prefs.bottomTextBar and (barPosNow == "top" or barPosNow == "bottom")
    border:SetHeight(
        prefs.healthHeight + initPpExtra + (wrapsTextBar and (prefs.bottomTextBarHeight or 16) or 0)
    )
    border:SetFrameLevel(barArea:GetFrameLevel() + 5)
    local edgePx = CludesUI.BorderPx(prefs.borderSizePx, bdrSize, bdrTexKey)
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
        edgePx
    )
    if bdrSize == 0 and bdrTexKey == "solid" then
        border:Hide()
    end

    -- Places an absorb StatusBar for its edge mode, as the live
    -- UpdateAbsorbBarReverseFill (CUI_UnitFrames_Absorb.lua) does. "right" /
    -- "left" pin it to that end of the health bar, filling inward whatever
    -- the reverse fill; the overlay reverse modes fill into the health fill
    -- from its leading edge (the clip trims the rest, and the preview shield
    -- never outgrows health, so Full looks the same); plain overlay fills the
    -- missing health from the current-health edge. Vertical fill swaps the
    -- axis but keeps the key names: "right" is the top, "left" the bottom.
    local function PositionPreviewAbsorb(bar, mode, isRev, isVert)
        if not bar then
            return
        end
        bar:ClearAllPoints()
        bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        mod.ApplyFillRotation(bar)
        local near, far, sideA, sideB = "LEFT", "RIGHT", "TOP", "BOTTOM"
        if isVert then
            near, far, sideA, sideB = "BOTTOM", "TOP", "LEFT", "RIGHT"
        end
        -- own: the bar's end that is pinned; onto: the target end it pins to.
        local target, own, onto = healthFill, nil, nil
        if mode == "right" or mode == "left" then
            target = health
            own = (mode == "right") and far or near
            onto = own
        elseif mode == "overlayReverse" or mode == "overlayReverseFull" then
            own = isRev and near or far
            onto = own
        else
            own = isRev and far or near
            onto = isRev and near or far
        end
        bar:SetReverseFill(own == far)
        local function Corner(axisEnd, crossSide)
            return isVert and (axisEnd .. crossSide) or (crossSide .. axisEnd)
        end
        bar:SetPoint(Corner(own, sideA), target, Corner(onto, sideA), 0, 0)
        bar:SetPoint(Corner(own, sideB), target, Corner(onto, sideB), 0, 0)
    end

    -- Absorb bars (player, target and focus), drawn in the chosen styles:
    -- the shield absorb underneath and the heal absorb one sublevel above
    -- it. On the preview the two take turns: the heal absorb shows only
    -- while its Heal Absorb Style eye is on, which hides the shield.
    local absorbBar, healAbsorbBar, absorbTopBar, healAbsorbTopBar
    local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
    if unitKey == "player" or unitKey == "target" or unitKey == "focus" then
        -- The fills hang off the health fill's current-health edge at full
        -- frame width, so a high preview fill would run past the bar; the
        -- live frames clamp, and this clip to the health bar does the same.
        local absClip = CreateFrame("Frame", nil, health)
        absClip:SetAllPoints(health)
        absClip:SetFrameLevel(health:GetFrameLevel() + 1)
        absClip:SetClipsChildren(true)

        -- One absorb StatusBar: texture from the style (SharedMedia names go
        -- through the bar texture lookup), tiled where the style tiles, at
        -- the given draw sublevel, colour and edge mode.
        local function MakeAbsorbBar(style, fallbackTex, sublevel, r, g, b, a, edgeMode)
            local bar = CreateFrame("StatusBar", nil, absClip)
            bar:SetStatusBarTexture(mod.ResolveAbsorbStyleTex(style, fallbackTex))
            local fill = bar:GetStatusBarTexture()
            if fill then
                fill:SetDrawLayer("ARTWORK", sublevel)
                local tiled = (mod.ABSORB_TILED_STYLES[style] == true)
                fill:SetHorizTile(tiled)
                fill:SetVertTile(tiled)
            end
            bar:SetStatusBarColor(r, g, b, a)
            PositionPreviewAbsorb(
                bar,
                edgeMode or "overlay",
                prefs.healthReverseFill,
                prefs.healthVerticalFill
            )
            Pix.Width(bar, frameW)
            Pix.Height(bar, healthH)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.14)
            bar:SetFrameLevel(health:GetFrameLevel() + 1)
            return bar
        end

        -- Shield absorb. Its opacity follows the live GetAbsorbOpacity
        -- (CUI_UnitFrames_Absorb.lua): the set opacity, else the style's own.
        local absStyle = prefs.showPlayerAbsorb
        local STYLE_ALPHA = {
            striped = 0.8,
            stripedReversed = 0.8,
            clean = (prefs.absorbCleanAlpha or 30) / 100,
            blizzard = 0.8,
        }
        local shieldA = prefs.absorbOpacity and (prefs.absorbOpacity / 100) or STYLE_ALPHA[absStyle] or 0.8
        local shieldC = prefs.absorbColor or { r = 1, g = 1, b = 1 }
        local STRIPED_TEX = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped3.tga"
        absorbBar = MakeAbsorbBar(
            absStyle,
            STRIPED_TEX,
            1,
            shieldC.r,
            shieldC.g,
            shieldC.b,
            shieldA,
            prefs.absorbEdgeMode
        )
        if not absStyle or absStyle == "none" then
            absorbBar:Hide()
        end

        -- Heal absorb: red by default; the outlined stripe styles carry their
        -- own colour, so those draw untinted.
        local healStyle = prefs.healAbsorbStyle or "clean"
        local healC = prefs.healAbsorbColor or { r = 0.8, g = 0.15, b = 0.15 }
        if healStyle == "largeOutlinedStripes" or healStyle == "largeOutlinedStripesR" then
            healC = { r = 1, g = 1, b = 1 }
        end
        healAbsorbBar = MakeAbsorbBar(
            healStyle,
            WHITE_TEX,
            2,
            healC.r or 0.8,
            healC.g or 0.15,
            healC.b or 0.15,
            (prefs.healAbsorbOpacity or 65) / 100,
            prefs.healAbsorbEdgeMode
        )
        healAbsorbBar:Hide()
        -- A black backing (Heal Absorb Background Opacity) one sublevel under
        -- the heal absorb fill, following its rect.
        local healBack = healAbsorbBar:CreateTexture(nil, "ARTWORK", nil, 1)
        healBack:SetColorTexture(0, 0, 0, (prefs.healAbsorbBgOpacity or 15) / 100)
        healBack:SetAllPoints(healAbsorbBar:GetStatusBarTexture())
        healAbsorbBar._bg = healBack

        -- Max Health Style (its eye): a fixed reduced maximum on the bar's far
        -- end, styled by the live frames' own function; pf:Update drives it.
        local maxHp = CreateFrame("StatusBar", nil, health)
        maxHp:SetAllPoints(health)
        maxHp:SetFrameLevel(health:GetFrameLevel() + 2)
        maxHp:SetMinMaxValues(0, 1)
        maxHp:SetValue(0.2)
        maxHp._bg = maxHp:CreateTexture(nil, "ARTWORK", nil, 2)
        maxHp:Hide()
        popFrame._pvMaxHp = maxHp

        -- Heal Prediction (its eye): other players' heals at the whole incoming
        -- total underneath, yours over them, both from the health edge. Their
        -- holder clips at the bar's end unless Overheal lets them run on.
        -- Kept on pf (this builder is long); pf:Update drives them.
        local predHolder = CreateFrame("Frame", nil, health)
        predHolder:SetAllPoints(health)
        predHolder:SetFrameLevel(health:GetFrameLevel() + 1)
        popFrame._pvPredHolder = predHolder
        for layer, key in ipairs({ "_pvPredOther", "_pvPredMy" }) do
            local bar = CreateFrame("StatusBar", nil, predHolder)
            bar:SetStatusBarTexture(WHITE_TEX)
            bar:SetMinMaxValues(0, 1)
            bar:SetFrameLevel(health:GetFrameLevel() + layer)
            bar:Hide()
            popFrame[key] = bar
        end

        -- The Absorb and Heal Absorb strips, on pf so an "above" strip can sit
        -- outside the health bar; placed further down.
        local function StripBar()
            local bar = CreateFrame("StatusBar", nil, popFrame)
            bar:SetStatusBarTexture(WHITE_TEX)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.45)
            bar:Hide()
            return bar
        end
        absorbTopBar = StripBar()
        healAbsorbTopBar = StripBar()
    end
    popFrame._absorbBar = absorbBar
    popFrame._healAbsorbBar = healAbsorbBar
    popFrame._absorbTopBar = absorbTopBar
    popFrame._healAbsorbTopBar = healAbsorbTopBar

    -- A sample aura icon: black edge (the backdrop showing round the icon's
    -- 1px inset, like the live black border), raised past the border frame
    -- (barArea + 5) and its pixel border holder (barArea + 6).
    local function SampleAuraIcon(size, iconID)
        local icon = CreateFrame("Frame", nil, popFrame, "BackdropTemplate")
        Pix.Size(icon, size, size)
        icon:SetBackdrop(SOLID_BACKDROP)
        icon:SetBackdropColor(0, 0, 0, 1)
        icon:SetFrameLevel(barArea:GetFrameLevel() + 7)
        local art = icon:CreateTexture(nil, "ARTWORK")
        Pix.Point(art, "TOPLEFT", icon, "TOPLEFT", 1, -1)
        Pix.Point(art, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
        art:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        art:SetTexture(iconID)
        icon._iconTex = art
        return icon
    end

    -- Two sample buffs on every unit, shown while Show Buffs is on with an anchor.
    local buffIcons = {}
    do
        local size = prefs.buffSize or 22
        local buffsShown = prefs.showBuffs and (prefs.buffAnchor or "topleft") ~= "none"
        for slot = 1, 2 do
            local icon = SampleAuraIcon(size, _previewBuffIcons[slot] or 135932)
            Pix.Point(icon, "BOTTOMLEFT", popFrame, "TOPLEFT", (slot - 1) * (size + 1), 1)
            buffIcons[slot] = icon
            if not buffsShown then
                icon:Hide()
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
            local icon = SampleAuraIcon(size, ICON_IDS[slot] or 136116)
            Pix.Point(icon, "TOPLEFT", popFrame, "BOTTOMLEFT", (slot - 1) * (size + 1), -1)
            local step = (slot - 1) % 5
            local swipe = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            swipe:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
            swipe:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
            swipe:SetFrameLevel(icon:GetFrameLevel() + 1)
            swipe:SetDrawEdge(false)
            swipe:SetDrawBling(false)
            swipe:SetReverse(false)
            swipe:SetDrawSwipe(true)
            swipe:SetSwipeColor(0, 0, 0, 0.6)
            swipe:SetHideCountdownNumbers(true)
            swipe:SetCooldown(GetTime() - 3600 * (1 - (0.25 + step * 0.15)), 3600)
            swipe:Hide()
            icon._previewCD = swipe
            local numbers = CreateFrame("Frame", nil, icon)
            numbers:SetAllPoints(icon)
            numbers:SetFrameLevel(swipe:GetFrameLevel() + 1)
            local durText = numbers:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(durText, auraFont, 10, "unitFrames")
            durText:SetPoint("CENTER", icon, "CENTER", 0, 0)
            durText:SetText(4 + step * 5)
            durText:Hide()
            icon._durText = durText
            local stackText = numbers:CreateFontString(nil, "OVERLAY", nil, 7)
            CludesUI.ApplyIconTextFont(stackText, auraFont, 14, "unitFrames")
            stackText:SetText(2 + step)
            stackText:Hide()
            icon._stackText = stackText
            debuffIcons[slot] = icon
            if debuffsHidden then
                icon:Hide()
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
        local sourceKey = unitKey:match("^boss") and "boss" or unitKey
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
        local tex = combatIndHolder:CreateTexture(nil, "OVERLAY", nil, sublevel)
        tex:Hide()
        return tex
    end
    local combatInd = IndicatorTex(7)
    combatInd:SetSize(24, 24)
    combatInd:SetPoint("CENTER", portraitFrame or health, "CENTER", 0, 0)
    popFrame._combatIndicator = combatInd
    popFrame._factionIndicator = IndicatorTex(6)
    popFrame._pvRaid = IndicatorTex(6)
    popFrame._pvRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    popFrame._pvLeader = IndicatorTex(6)
    popFrame._pvLeader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    popFrame._pvElite = IndicatorTex(6)
    popFrame._pvElite:SetAtlas("nameplates-icon-elite-gold")
    -- WoW Forever: the pet's happiness icon (the happy face as the sample),
    -- placed beside the frame on each Update as the live one is. Its own
    -- frame lets the page's click overlay show and hide with it.
    if unitKey == "pet" and CludesUI.IS_FOREVER == true then
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
                local face, size, flags = source:GetFont()
                if face then
                    if fo then
                        lf:SetFontObject(fo)
                    end
                    lf:SetFont(face, s.blizzLevelSize or size, flags)
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
        health:ClearAllPoints()
        mod.UF_BlizzPoint(health, "TOPLEFT", barArea, "TOPLEFT", HB.x, -HB.y, mirror)
        health:SetSize(HB.w, HB.h)
        health:SetFrameLevel(lvl + 3)
        local absClip = absorbBar and absorbBar:GetParent()
        if absClip and absClip ~= health then
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
            healthFill:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
            healthFill:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
            healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", -hpW, 0)
        else
            healthFill:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
            healthFill:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
            healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", hpW, 0)
            healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
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
        local hm = health._blizzMask
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
        if health._cuiBgTex then
            hTex[#hTex + 1] = health._cuiBgTex
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
                hm = health:CreateMaskTexture()
                health._blizzMask = hm
            end
            mod.UF_SeatBarMask(hm, health, HB)
            for idx = 1, #hTex do
                mod.UF_SetMask(hTex[idx], hm)
            end
        elseif hm then
            for idx = 1, #hTex do
                pcall(hTex[idx].RemoveMaskTexture, hTex[idx], hm)
            end
        end
        mod.UF_BlizzBarShadow(health, hMaskOK and hm or nil, HB.h)

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
                local fill = pw:CreateTexture(nil, "ARTWORK")
                fill:SetPoint("TOPLEFT", pw, "TOPLEFT", 0, 0)
                fill:SetPoint("BOTTOMLEFT", pw, "BOTTOMLEFT", 0, 0)
                pw._bg, pw._fill = backdrop, fill
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
            local fill = pw._fill or popFrame._powerFill
            local backdrop = pw._bg or popFrame._powerBg
            if fill then
                fill:ClearAllPoints()
                if not isMini and s.powerReverseFill then
                    fill:SetPoint("TOPRIGHT", pw, "TOPRIGHT", 0, 0)
                    fill:SetPoint("BOTTOMRIGHT", pw, "BOTTOMRIGHT", 0, 0)
                else
                    fill:SetPoint("TOPLEFT", pw, "TOPLEFT", 0, 0)
                    fill:SetPoint("BOTTOMLEFT", pw, "BOTTOMLEFT", 0, 0)
                end
                fill:SetWidth(math.floor(pwid * ppct + 0.5))
            end
            local pm = pw._blizzMask
            local pMaskOK = not mirror and mod.UF_AtlasOK(G.power.mask)
            if pMaskOK then
                if not pm then
                    pm = pw:CreateMaskTexture()
                    pw._blizzMask = pm
                end
                mod.UF_SeatBarMask(pm, pw, G.power)
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
            mod.UF_BlizzBarShadow(pw, pMaskOK and pm or nil, G.power.h)
            if isMini or (s.powerHeight or 6) > 0 then
                pw:Show()
            end
        elseif pw and pw._blizzMask then
            -- Detached now: the track pieces come off.
            local fill = popFrame._powerFill
            if fill then
                pcall(fill.RemoveMaskTexture, fill, pw._blizzMask)
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
            local function ApplyPreviewAuraBorder(icon)
                if icon._iconTex then
                    icon._iconTex:ClearAllPoints()
                    local inset = (blizzAura or (as.auraBorderSize or 1) > 0) and 1 or 0
                    Pix.Point(icon._iconTex, "TOPLEFT", icon, "TOPLEFT", inset, -inset)
                    Pix.Point(icon._iconTex, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -inset, inset)
                end
                local border = icon._cuiAuraBorder
                if blizzAura then
                    if border then
                        border:Hide()
                    end
                    return
                end
                if not border then
                    border = CreateFrame("Frame", nil, icon)
                    border:SetAllPoints(icon)
                    border:EnableMouse(false)
                    icon._cuiAuraBorder = border
                end
                local aboveEffects = unitKey == "boss" and mod.UF_BossAuraBorderAboveEffects(s)
                if as.auraBorderBehindUnitFrame then
                    border:SetFrameLevel(0)
                elseif aboveEffects then
                    border:SetFrameLevel(icon:GetFrameLevel() + 20)
                else
                    border:SetFrameLevel(
                        as.auraBorderBehind and math.max(0, icon:GetFrameLevel() - 1)
                            or (icon:GetFrameLevel() + 1)
                    )
                end
                if icon._durText and (aboveEffects or icon._borderAboveEffects) then
                    icon._durText:GetParent():SetFrameLevel(icon:GetFrameLevel() + (aboveEffects and 25 or 2))
                    icon._borderAboveEffects = aboveEffects or nil
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
        side = s.portraitSide or unitSide[unitKey] or "left"
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
            effectiveSide = unitSide[unitKey] or "left"
            pvIsInside = false
        end
        local pw = (sp and isAttached and effectiveSide ~= "top") and portraitDim or 0
        local tw = fw + pw
        -- Blizzard Style: the stock footprint (cast bar width, pf size, fit).
        if blizzG then
            tw = blizzG.w
        end

        Pix.Size(health, fw, hh)

        -- Re-anchor portrait + health every update (no caching) to avoid circular
        -- dependency errors on style switches: clear BOTH first, then anchor in
        -- dependency order.
        if portraitFrame then
            portraitFrame:ClearAllPoints()
        end
        health:ClearAllPoints()
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
                Pix.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                portraitFrame:SetClipsChildren(true)
                if portraitFrame._previewBg then
                    portraitFrame._previewBg:Hide()
                end
                if effectiveSide == "insideleft" then
                    portraitFrame:SetPoint("TOPLEFT", health, "TOPLEFT", pXOff, pYOff)
                elseif effectiveSide == "insideright" then
                    portraitFrame:SetPoint("TOPRIGHT", health, "TOPRIGHT", pXOff, pYOff)
                else -- insidecenter
                    portraitFrame:SetPoint("TOP", health, "TOP", pXOff, pYOff)
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
                        health,
                        "TOPLEFT",
                        portraitFrame,
                        "TOPRIGHT",
                        0,
                        -cpAboveH - btbTopOff - pvPwAbove
                    )
                else
                    portraitFrame:SetPoint("TOPRIGHT", barArea, "TOPRIGHT", 0, 0)
                    Pix.Point(
                        health,
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
                Pix.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
                if effectiveSide == "top" then
                    -- Top: portrait centered above health bar
                    portraitFrame:SetPoint("BOTTOM", health, "TOP", pXOff, 15 + pYOff)
                elseif effectiveSide == "left" then
                    portraitFrame:SetPoint("TOPRIGHT", health, "TOPLEFT", -15 + pXOff, pYOff)
                else
                    portraitFrame:SetPoint("TOPLEFT", health, "TOPRIGHT", 15 + pXOff, pYOff)
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
            Pix.Point(health, "TOPLEFT", barArea, "TOPLEFT", 0, -cpAboveH - btbTopOff - pvPwAbove)
            if portraitFrame then
                portraitFrame._anchored = false
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
        healthFill:SetPoint(pinA, health, pinA, 0, 0)
        healthFill:SetPoint(pinB, health, pinB, 0, 0)
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
            healthBgColor:SetPoint("TOPLEFT", health, "TOPLEFT", leftIn, topIn)
            healthBgColor:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", rightIn, bottomIn)
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
            local tbPath = mod.UF_TexBgPaths(unitKey, s, texKeyNow)
            if tbPath then
                local tb = mod.UF_TexBgLayer(health, tbPath, s.healthVerticalFill and not blizzG)
                tb:SetVertexColor(uBgR, uBgG, uBgB, 1)
                tb:SetAlpha(hBgA)
            elseif health._cuiBgTex then
                health._cuiBgTex:Hide()
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
                Pix.Point(power, "BOTTOMLEFT", health, "TOPLEFT", 0, 0)
                Pix.Point(power, "BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            elseif pvPpPos == "detached_top" then
                power:SetPoint("BOTTOM", health, "TOP", s.powerX or 0, 15 + (s.powerY or 0))
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            elseif pvPpPos == "detached_bottom" then
                power:SetPoint("TOP", health, "BOTTOM", s.powerX or 0, -15 + (s.powerY or 0))
                if ph > 0 then
                    power:Show()
                else
                    power:Hide()
                end
            else -- "below"
                Pix.Point(power, "TOPLEFT", health, "BOTTOMLEFT", 0, 0)
                Pix.Point(power, "TOPRIGHT", health, "BOTTOMRIGHT", 0, 0)
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

        -- Power text, at its Text Position in its format, as the live bar shows it.
        if ppPreviewFS then
            local ppPos = s.powerPercentText or "none"
            local ppFmt = CludesUI.PowerTextFormat(s.powerTextFormat or "perpp")
            if ppPos == "none" or ppFmt == "none" or not power then
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
                local target, ownEdge, targetEdge = power, "", ""
                if ph <= 0 then
                    local above = (pvPpPos == "above" or pvPpPos == "detached_top")
                    target = health
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

        -- Text Bar, placed before the cast bar (which may hang off it). An
        -- attached bar centres under the bars and an attached portrait.
        local cbOff = 0
        if sp and isAttached then
            if side == "right" then
                cbOff = pw / 2
            elseif side == "left" then
                cbOff = -(pw / 2)
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
            local under = (pvPpIsAtt and power and power:IsShown()) and power or health
            local dx, dy = s.btbX or 0, s.btbY or 0
            if btbPos == "top" then
                Pix.Point(btbFrame, "BOTTOM", health, "TOP", cbOff, 0)
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
            if castIconFrame then
                castIconFrame:Hide()
            end
        elseif castBar then
            local isPlayer = unitKey == "player"
            local iconInBar = mod.UF_CastIconInWidth(unitKey, s)
            local iconOnRight = s[isPlayer and "playerCastbarIconRight" or "castbarIconRight"] == true
            local offsetKey = isPlayer and "playerCastIconOffset" or "castIconOffset"
            local iconDX, iconDY = s[offsetKey .. "X"] or 0, s[offsetKey .. "Y"] or 0
            -- Boss: a Cast Bar Width above 0 replaces the frame width, held to
            -- tw + 120 (see the note in the build).
            local fullW = tw
            if unitKey == "boss" and (s.castbarWidth or 0) > 0 then
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
            if castIconFrame then
                castIconFrame:SetSize(ch, ch)
                castIconFrame:ClearAllPoints()
                if iconOnRight then
                    Pix.Point(castIconFrame, "TOPLEFT", castBar, "TOPRIGHT", iconDX, iconDY)
                else
                    Pix.Point(castIconFrame, "TOPRIGHT", castBar, "TOPLEFT", iconDX, iconDY)
                end
                if s[isPlayer and "showPlayerCastIcon" or "showCastIcon"] ~= false then
                    castIconFrame:Show()
                else
                    castIconFrame:Hide()
                end
                if castIconFrame._iconTex then
                    castIconFrame._iconTex:SetTexture(sample and sample.icon or 136197)
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
            local function Tint(fs, c)
                c = c or { r = 1, g = 1, b = 1 }
                fs:SetTextColor(c.r, c.g, c.b)
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
            if castNameFS2 then
                castNameFS2:SetText(sample and sample.name or "Spell Name")
                SetPVFont(castNameFS2, PREVIEW_FONT, s.castSpellNameSize or 11)
                Tint(castNameFS2, s.castSpellNameColor)
                castNameFS2:ClearAllPoints()
                if nameSide == "none" then
                    castNameFS2:Hide()
                elseif hasW then
                    PlaceZone(
                        castNameFS2,
                        nameSide,
                        false,
                        zoneW,
                        s.castSpellNameX or 0,
                        1 + (s.castSpellNameY or 0)
                    )
                    castNameFS2:Show()
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
            for _, fs in ipairs({ castNameFS2, castTimeFS, castTargetFS }) do
                mod.ReflowFontString(fs)
            end
            castBar:ClearAllPoints()
            local onTextBar = btbFrame and s.bottomTextBar and btbPos == "bottom"
            local hangFrom = onTextBar and btbFrame
                or ((pvPpIsAtt and power and power:IsShown()) and power or health)
            -- An icon that is part of the bar moves the narrowed bar half an icon
            -- toward the icon-free side, so the pair sits flush under the frame.
            local iconShift = 0
            if iconInBar then
                iconShift = iconOnRight and -(ch / 2) or (ch / 2)
            end
            Pix.Point(castBar, "TOP", hangFrom, "BOTTOM", (onTextBar and 0 or cbOff) + iconShift, 0)
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
                    cpPipContainer:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 0)
                    cpPipContainer:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
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
                        Pix.Point(cpPipContainer, "BOTTOM", health, "TOP", cpXOff, cpYOff)
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
                    local bar, c, val = e[1], e[2], e[3]
                    bar:SetStatusBarTexture(texPath)
                    bar:SetStatusBarColor(c.r, c.g, c.b, alpha)
                    PositionPreviewAbsorb(bar, "forward", s.healthReverseFill, s.healthVerticalFill)
                    bar:SetWidth(fw)
                    bar:SetHeight(hh)
                    bar:SetValue(val)
                    bar:Show()
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
            local mode = saved.profile.dispelOverlay or "none"
            if optionState.showDispelOverlayPreview and mode ~= "none" then
                local c = saved.profile.dispelColorMagic or { r = 0.349, g = 0.475, b = 1.0 }
                local alpha = (saved.profile.dispelOverlayOpacity or 100) / 100
                dispelOverlayPreview:ClearAllPoints()
                dispelOverlayPreview:SetVertexColor(1, 1, 1, 1)
                dispelOverlayPreview:SetTexCoord(0, 1, 0, 1)
                if mode == "full" then
                    dispelOverlayPreview:SetAllPoints(health)
                    dispelOverlayPreview:SetColorTexture(c.r, c.g, c.b, alpha)
                elseif mode == "gradient" or mode == "gradient_sharp" or mode == "gradient_reverse" then
                    dispelOverlayPreview:SetAllPoints(health)
                    dispelOverlayPreview:SetTexture(
                        mode == "gradient" and "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
                            or "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"
                    )
                    if mode == "gradient_reverse" then
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
                tiPv:SetPoint(corner, health, corner, dp.dispelIconOffsetX or 0, dp.dispelIconOffsetY or 0)
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
                local bossSimpleAnchorFrame = useSimpleBossAnchor and health or popFrame
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
                local bossSimpleAnchorFrame = useSimpleBossAnchor and health or popFrame
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
                local max, lower = CludesUI.RoundedJoinCorners(corners)
                if pvPpPos == "detached_bottom" then
                    corners, pCorners = max, lower
                else
                    corners, pCorners = lower, max
                end
            end
            if radius > 0 then
                local port = sp and isAttached and portraitFrame and portraitFrame:IsShown() and portraitFrame
                    or nil
                CludesUI.RoundCorners(popFrame, radius, {
                    roots = {
                        health,
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
        if health then
            Pix.Size(health, fw, hh)
            local snappedHealthW = health:GetWidth()
            local availW = snappedFrameW
            if portraitFrame and sp and isAttached then
                availW = snappedFrameW - portraitFrame:GetWidth()
            end
            if snappedHealthW > availW + 0.01 then
                health:SetWidth(availW)
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
            if pvPpIsAtt and health then
                -- Height: ensure health + power don't exceed expected total
                local snappedHH = health:GetHeight()
                local snappedPH = power:GetHeight()
                local expectedTotal = hh + ph
                if snappedHH + snappedPH > expectedTotal + 0.01 then
                    power:SetHeight(snappedPH - (snappedHH + snappedPH - expectedTotal))
                end
                -- Width: match health bar width exactly
                local snappedHealthW2 = health:GetWidth()
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
            if health then
                usedH = usedH + health:GetHeight()
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
                    combatInd:SetPoint("CENTER", health, "CENTER", ciOx, ciOy)
                else
                    local anchor = (ciPos == "topright" and "TOPRIGHT")
                        or (ciPos == "bottomleft" and "BOTTOMLEFT")
                        or (ciPos == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    combatInd:SetPoint(anchor, health, anchor, ciOx, ciOy)
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
                    local anchor = (fPos == "topleft" and "TOPLEFT")
                        or (fPos == "bottomleft" and "BOTTOMLEFT")
                        or (fPos == "bottomright" and "BOTTOMRIGHT")
                        or "TOPRIGHT"
                    factionInd:SetPoint(anchor, popFrame, anchor, fOx, fOy)
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
                    local anchor = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    texture:SetPoint(anchor, health, anchor, ox, oy)
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
    popFrame._health = health
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
