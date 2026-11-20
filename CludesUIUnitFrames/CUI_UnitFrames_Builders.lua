if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Builders.lua
--
--  The unified frame border with its hover handlers, the aura crop helpers
--  and the four style functions that build a spawned unit frame, published
--  as I.Style*Frame (CUI_UnitFrames_Init.lua). Reads earlier files through
--  ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local math_floor = math.floor
local Pix = CludesUI.PP
local GetMiniDonorSettings = mod.GetMiniDonorSettings

local Inner = mod._internals
local GetSettingsForUnit, UnitToSettingsKey, SetFSFont =
    Inner.GetSettingsForUnit, Inner.UnitToSettingsKey, Inner.SetFSFont
local ApplyDarkTheme, ApplyClassColor, SpecHasClassPower =
    Inner.ApplyDarkTheme, Inner.ApplyClassColor, Inner.SpecHasClassPower
local ApplyHealthBarTexture, ApplyHealthBarAlpha = Inner.ApplyHealthBarTexture, Inner.ApplyHealthBarAlpha
local CreateHealthBar, CreateAbsorbBar, CreatePowerBar, CreatePortrait =
    Inner.CreateHealthBar, Inner.CreateAbsorbBar, Inner.CreatePowerBar, Inner.CreatePortrait
local CreateCastBar, SetupShowOnCastBar, CreateBottomTextBar =
    Inner.CreateCastBar, Inner.SetupShowOnCastBar, Inner.CreateBottomTextBar
local ReparentBarsToClip, UpdateBordersForScale = Inner.ReparentBarsToClip, Inner.UpdateBordersForScale
local SlotWidthMul, EstimateUFTextWidth = Inner.SlotWidthMul, Inner.EstimateUFTextWidth
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- Boss frames have an independent Hover / Target border recolor (mirrors Raid Frames
-- "Hover Borders"); both default OFF. Priority: hover (moused over) > target (current
-- target) > the frame's normal border color. Recolors the existing unified border in
-- place. _hovered is maintained by OnEnter/OnLeave hooks; _isTarget by the boss target
-- updater. On ns to avoid the Lua 200-local cap.
mod.ApplyBossBorderState = function(self)
    if not self.unifiedBorder then
        return
    end
    local s = saved.profile.boss
    if not s then
        return
    end
    local red, green, blue, a
    if self._hovered and s.bossHoverBorderEnabled then
        local color = s.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
        red, green, blue, a = color.r, color.g, color.b, s.bossHoverBorderAlpha or 1
    elseif self._isTarget and s.bossTargetBorderEnabled then
        local color = s.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
        red, green, blue, a = color.r, color.g, color.b, s.bossTargetBorderAlpha or 1
    else
        -- The normal colour the reload sweep painted: the same settings table
        -- (the donor's while inheriting, never the unused boss copy).
        local bsrc = mod.UF_BossBorderSettings()
        local color = bsrc.borderColor or { r = 0, g = 0, b = 0 }
        red, green, blue, a = color.r, color.g, color.b, bsrc.borderAlpha or 1
    end
    CludesUI.SetBorderStyleColor(self.unifiedBorder, red, green, blue, a)
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then
        seam._tex:SetVertexColor(red, green, blue, a)
    end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then
        portraitSeam._tex:SetVertexColor(red, green, blue, a)
    end
end

local function FrameBorderEnter(self)
    if not self.unifiedBorder then
        return
    end
    if self._blizzArtFrame then
        return
    end -- Blizzard Style: no CUI border to recolor
    local unitToken = self._cuiUnit or "player"
    if unitToken:match("^boss%d$") then
        self._hovered = true
        mod.ApplyBossBorderState(self)
        return
    end
    local isMini = (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget")
    local prefs = isMini and GetMiniDonorSettings(unitToken) or GetSettingsForUnit(unitToken)
    -- Highlight defaults ON (nil == enabled); only an explicit false disables it.
    if prefs.highlightEnabled == false then
        return
    end
    -- Per-mini-frame opt-out: with "Show Highlight Border" off, a mini frame never
    -- recolors on hover even when the donor (main frame) highlight is enabled. (When the
    -- donor highlight is off we already returned above, so this has no effect then.)
    if isMini and GetSettingsForUnit(unitToken).showHighlightBorder == false then
        return
    end
    local hc = prefs.highlightColor or { r = 1, g = 1, b = 1 }
    local ha = prefs.highlightAlpha or 1
    CludesUI.SetBorderStyleColor(self.unifiedBorder, hc.r, hc.g, hc.b, ha)
    -- The portrait's Outer Ring wears the frame border tint (only once built).
    local pt = self.Portrait
    local ring = pt and pt.backdrop and pt.backdrop._outerRing
    if ring and ring:IsShown() then
        ring:SetVertexColor(hc.r, hc.g, hc.b, ha)
    end
    -- So does the Power Bar Seam (only once built).
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then
        seam._tex:SetVertexColor(hc.r, hc.g, hc.b, ha)
    end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then
        portraitSeam._tex:SetVertexColor(hc.r, hc.g, hc.b, ha)
    end
end
local function FrameBorderLeave(self)
    if not self.unifiedBorder then
        return
    end
    if self._blizzArtFrame then
        return
    end -- Blizzard Style: no CUI border to recolor
    local unitToken = self._cuiUnit or "player"
    if unitToken:match("^boss%d$") then
        self._hovered = false
        mod.ApplyBossBorderState(self)
        return
    end
    local isMini = (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget")
    local prefs = isMini and GetMiniDonorSettings(unitToken) or GetSettingsForUnit(unitToken)
    local bc = prefs.borderColor or { r = 0, g = 0, b = 0 }
    local ba = prefs.borderAlpha or 1
    CludesUI.SetBorderStyleColor(self.unifiedBorder, bc.r, bc.g, bc.b, ba)
    local pt = self.Portrait
    local ring = pt and pt.backdrop and pt.backdrop._outerRing
    if ring and ring:IsShown() then
        ring:SetVertexColor(bc.r, bc.g, bc.b, ba)
    end
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then
        seam._tex:SetVertexColor(bc.r, bc.g, bc.b, ba)
    end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then
        portraitSeam._tex:SetVertexColor(bc.r, bc.g, bc.b, ba)
    end
end
-- The detached portrait's click overlay replays these on hover (Portrait.lua).
Inner.FrameBorderEnter, Inner.FrameBorderLeave = FrameBorderEnter, FrameBorderLeave

-- Unified border for unit frames using the PP border system
local function CreateUnifiedBorder(widget, unitToken)
    local prefs = GetSettingsForUnit(unitToken or "player")
    local size = prefs.borderSize or 1
    local bc = prefs.borderColor or { r = 0, g = 0, b = 0 }
    local textureKey = prefs.borderTexture or "solid"

    local border = CreateFrame("Frame", nil, widget)
    Pix.Point(border, "TOPLEFT", widget, "TOPLEFT", 0, 0)
    Pix.Point(border, "BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 0)
    local borderBehind = prefs.borderBehind
    border:SetFrameLevel(
        borderBehind and math.max(0, widget:GetFrameLevel() - 1) or (widget:GetFrameLevel() + 10)
    )

    CludesUI.ApplyBorderStyle(
        border,
        size,
        bc.r,
        bc.g,
        bc.b,
        prefs.borderAlpha or 1,
        textureKey,
        prefs.borderTextureOffset,
        prefs.borderTextureOffsetY,
        prefs.borderTextureShiftX,
        prefs.borderTextureShiftY,
        "unitframes",
        size,
        nil,
        CludesUI.BorderPx(prefs.borderSizePx, size, textureKey)
    )

    widget.unifiedBorder = border

    if size == 0 then
        border:Hide()
    end

    widget:HookScript("OnEnter", FrameBorderEnter)
    widget:HookScript("OnLeave", FrameBorderLeave)

    return border
end

-- Cropped aura icons: the button becomes a rectangle (height = 80% of width) and the
-- texture is trimmed top/bottom so the visible art keeps its aspect ratio (no vertical
-- squish), matching the action bar "cropped" shape. Horizontal keeps the normal 0.07
-- zoom (span 0.86); vertical span derives from the button's ACTUAL width/height
-- (height = uSpan * h/w, centered) so texture width:height always equals the frame's
-- exactly, even after height rounds to whole pixels.
local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function SetAuraIconCrop(iconTex, cropped, wid, hgt, zoom)
    if not iconTex then
        return
    end
    local z = zoom or AURA_ZOOM
    if cropped and wid and hgt and wid > 0 then
        local uSpan = 1 - 2 * z
        local vSpan = uSpan * (hgt / wid)
        local v0 = 0.5 - vSpan / 2
        iconTex:SetTexCoord(z, 1 - z, v0, 1 - v0)
    else
        iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
    end
end
-- Exposed so the options live preview can apply the exact same crop math
-- (rectangular height = 80% of width + aspect-preserving texcoord trim).
mod.SetAuraIconCrop = SetAuraIconCrop
function mod.GetAuraCropHeight(cropped, wid)
    if cropped then
        return math_floor(wid * AURA_CROP_HEIGHT + 0.5)
    end
    return wid
end

-- Anchor a stack-count FontString per the "Position" setting. Default anchor is the
-- classic aura-button corner (BOTTOMRIGHT -1,0); corner anchors tuck the number inside
-- the icon edge, center sits dead-center. User X/Y offset adds on top. On ns for the
-- 200-local cap.
function mod.ApplyStackAnchor(fontStr, hostFrame, place, offX, offY)
    if not fontStr or not hostFrame then
        return
    end
    local anchorPoint, baseX = "BOTTOMRIGHT", -1
    if place == "bottomleft" then
        anchorPoint, baseX = "BOTTOMLEFT", 1
    elseif place == "topright" then
        anchorPoint, baseX = "TOPRIGHT", -1
    elseif place == "topleft" then
        anchorPoint, baseX = "TOPLEFT", 1
    elseif place == "center" then
        anchorPoint, baseX = "CENTER", 0
    end
    fontStr:ClearAllPoints()
    fontStr:SetPoint(anchorPoint, hostFrame, anchorPoint, baseX + (offX or 0), offY or 0)
end

-- 12.1 aura containers own every unit frame's buff/debuff rows
-- (CUI_UnitFrames_AuraContainers.lua): hand the container file its
-- always-fresh settings access and build the unit's containers.
local function CreateTargetAuras(widget, unitToken)
    mod.UF_GetSettings = GetSettingsForUnit
    mod.UF_GetProfile = mod.UF_GetProfile or function()
        return saved and saved.profile
    end
    return mod.UF_CreateAuraContainers(widget, unitToken or "target")
end

-- Pet frame buffs and debuffs are opt-in: the containers are built once one of
-- the two is on -- at spawn, and on every reload pass (CUI_UnitFrames_OptionsSetup.lua),
-- where the options setters, profile switches and Spec and Conditional
-- Overrides land. Same settings view and on/off test as the container runtime.
function mod.UF_EnsurePetAuras(widget)
    widget = widget or (mod.frames and mod.frames.pet)
    if not widget or mod.GetUnitFrameSource("pet") ~= "cui" then
        return
    end
    local s = mod.UF_AuraSettings("pet")
    if not s then
        return
    end
    if mod.UF_AuraSideOn("pet", "HELPFUL", s) or mod.UF_AuraSideOn("pet", "HARMFUL", s) then
        CreateTargetAuras(widget, "pet")
    end
end

-- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw absorb clips
-- the abbreviated text away at zero shield, secret-safely (absorb only feeds SetValue,
-- never compared). The zone FontString is reparented into a clip frame that tracks the
-- gate fill; the HealthPrediction Override drives it. Lazy: _absGate/_absClip stay nil
-- until a zone uses Absorb Short. content "absorbshort" gates shield absorbs,
-- "healabsorbshort" heal absorbs (g._cuiHealGate); anything else tears the gate down.
local function ApplyAbsorbGate(widget, unitToken, textOverlay, zone, fontStr, contentFrame)
    local isHeal = (contentFrame == "healabsorbshort")
    local wantGate = (contentFrame == "absorbshort" or isHeal)
    local g = widget._absGate and widget._absGate[zone]
    if wantGate then
        if not g then
            widget._absGate = widget._absGate or {}
            widget._absClip = widget._absClip or {}
            g = CreateFrame("StatusBar", nil, textOverlay)
            g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            g:SetStatusBarColor(1, 1, 1, 0) -- geometry only; never drawn
            g:SetMinMaxValues(0, 1)
            g:SetValue(0)
            local clip = CreateFrame("Frame", nil, textOverlay)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
            clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            widget._absGate[zone] = g
            widget._absClip[zone] = clip
        end
        local clip = widget._absClip[zone]
        g._cuiHealGate = isHeal
        g:ClearAllPoints()
        g:SetAllPoints(fontStr) -- gate spans the zone's text allocation (live)
        if fontStr:GetParent() ~= clip then
            fontStr:SetParent(clip)
        end
        g:Show()
        clip:Show()
        local amt
        if isHeal then
            amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unitToken)) or 0
        else
            amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unitToken)) or 0
        end
        g:SetValue(amt)
    elseif g then
        local clip = widget._absClip[zone]
        if fontStr:GetParent() == clip then
            fontStr:SetParent(textOverlay)
        end
        g:Hide()
        if clip then
            clip:Hide()
        end
    end
end

-- Text zones shared by every Style*Frame builder. Simple frames have no ExtraText.
-- Extra Text is tagged like the other zones; only its positioning differs. The
-- builders' wrappers pass the unit's settings as they are at the call: a profile
-- switch or import replaces the unit's table between frame reloads.
local function ApplyFrameTextTags(widget, unitToken, prefs, lc, rc, cc, ec)
    local textOverlay, extraText = widget._textOverlay, widget.ExtraText
    mod.SetTextZone(widget, widget.LeftText, lc, "leftText", prefs)
    mod.SetTextZone(widget, widget.RightText, rc, "rightText", prefs)
    mod.SetTextZone(widget, widget.CenterText, cc, "centerText", prefs)
    -- ReloadFrames passes 3 args; ec falls back to the stored content.
    if extraText then
        ec = ec or (prefs.extraTextContent or "none")
        mod.SetTextZone(widget, extraText, ec, "extraText", prefs)
    end
    ApplyAbsorbGate(widget, unitToken, textOverlay, "left", widget.LeftText, lc)
    ApplyAbsorbGate(widget, unitToken, textOverlay, "right", widget.RightText, rc)
    ApplyAbsorbGate(widget, unitToken, textOverlay, "center", widget.CenterText, cc)
    if extraText then
        ApplyAbsorbGate(widget, unitToken, textOverlay, "extra", extraText, ec)
    end
    mod.UF_PaintText(widget, widget._cuiUnit or unitToken)
end

-- Position and show/hide based on content + offsets
local function ApplyFrameTextPositions(widget, unitToken, cfg, rcDefault, barWDefault)
    local textOverlay = widget._textOverlay
    local leftText, rightText, centerText, extraText =
        widget.LeftText, widget.RightText, widget.CenterText, widget.ExtraText
    local lc = cfg.leftTextContent or "name"
    local rc = cfg.rightTextContent or rcDefault
    local cc = cfg.centerTextContent or "none"
    local lsz = cfg.leftTextSize or cfg.textSize or 12
    local rsz = cfg.rightTextSize or cfg.textSize or 12
    local csz = cfg.centerTextSize or cfg.textSize or 12
    local lxo = cfg.leftTextX or 0
    local lyo = cfg.leftTextY or 0
    local rxo = cfg.rightTextX or 0
    local ryo = cfg.rightTextY or 0
    local cxo = cfg.centerTextX or 0
    local cyo = cfg.centerTextY or 0
    local barW = cfg.frameWidth or barWDefault

    -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
    -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below).
    if extraText then
        local ec = cfg.extraTextContent or "none"
        SetFSFont(extraText, cfg.extraTextSize or cfg.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = cfg.extraTextX or 0
            local eyo = cfg.extraTextY or 0
            local ealign = cfg.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                Pix.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                Pix.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                Pix.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            Pix.Width(extraText, barW * 0.95 * SlotWidthMul(cfg, "extraText"))
            extraText:Show()
            ApplyClassColor(
                extraText,
                unitToken,
                cfg.extraTextClassColor,
                cfg.extraTextColorR,
                cfg.extraTextColorG,
                cfg.extraTextColorB
            )
        else
            extraText:Hide()
        end
    end

    -- Each text position renders independently.
    SetFSFont(centerText, csz)
    centerText:ClearAllPoints()
    if cc ~= "none" then
        centerText:SetJustifyH("CENTER")
        Pix.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
        Pix.Width(centerText, barW * 0.9 * SlotWidthMul(cfg, "centerText"))
        centerText:Show()
        ApplyClassColor(
            centerText,
            unitToken,
            cfg.centerTextClassColor,
            cfg.centerTextColorR,
            cfg.centerTextColorG,
            cfg.centerTextColorB
        )
    else
        centerText:Hide()
    end

    SetFSFont(leftText, lsz)
    leftText:ClearAllPoints()
    if lc ~= "none" then
        leftText:SetJustifyH("LEFT")
        Pix.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
        -- Constrain width when opposing right text exists
        if rc ~= "none" then
            local rightUsed = EstimateUFTextWidth(rc, cfg.rightTextCustomFormat, true)
            Pix.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(cfg, "leftText"))
        else
            Pix.Width(leftText, barW * 0.9 * SlotWidthMul(cfg, "leftText"))
        end
        leftText:Show()
        ApplyClassColor(
            leftText,
            unitToken,
            cfg.leftTextClassColor,
            cfg.leftTextColorR,
            cfg.leftTextColorG,
            cfg.leftTextColorB
        )
    else
        leftText:Hide()
    end

    SetFSFont(rightText, rsz)
    rightText:ClearAllPoints()
    if rc ~= "none" then
        rightText:SetJustifyH("RIGHT")
        Pix.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
        -- Constrain width when opposing left text exists
        if lc ~= "none" then
            local leftUsed = EstimateUFTextWidth(lc, cfg.leftTextCustomFormat)
            Pix.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(cfg, "rightText"))
        else
            Pix.Width(rightText, barW * 0.9 * SlotWidthMul(cfg, "rightText"))
        end
        rightText:Show()
        ApplyClassColor(
            rightText,
            unitToken,
            cfg.rightTextClassColor,
            cfg.rightTextColorR,
            cfg.rightTextColorG,
            cfg.rightTextColorB
        )
    else
        rightText:Hide()
    end
end

local function StyleFullFrame(widget, unitToken)
    local prefs = GetSettingsForUnit(unitToken)
    local powerPos = prefs.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and prefs.powerHeight or 0
    local playerTargetHeight = prefs.healthHeight + powerExtra
    local btbPos = prefs.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (prefs.bottomTextBar and btbIsAttached) and (prefs.bottomTextBarHeight or 16) or 0
    local targetFrameHeight = playerTargetHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = playerTargetHeight
    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    local isAttached = pStyle == "attached"

    if unitToken == "player" then
        local pSide = prefs.portraitSide or "left"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then
            effectiveSide = "left"
        end
        -- Class power "above" adds height above health bar ("top" floats outside)
        local cpAboveH = 0
        if SpecHasClassPower() then
            local cpSt = prefs.classPowerStyle or "none"
            if mod.UF_ForeverCPStyle then
                cpSt = mod.UF_ForeverCPStyle(cpSt)
            end
            local cpPo = (cpSt == "modern") and (prefs.classPowerPosition or "top") or "none"
            if cpSt == "modern" and cpPo == "above" then
                local cpSizeAdj = prefs.classPowerSize or 8
                local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                cpAboveH = cpPipH
            end
        end
        local playerHeightWithCp = playerTargetHeight + cpAboveH
        -- Apply portrait size adjustment
        local pSizeAdj = prefs.portraitSize or 0
        local adjPortraitH = playerHeightWithCp + pSizeAdj
        if adjPortraitH < 8 then
            adjPortraitH = 8
        end
        if not isAttached then
            pSizeAdj = pSizeAdj + 10
        end
        if not showPortrait then
            totalWidth = prefs.frameWidth
            portraitHeight = 0
        elseif isAttached then
            totalWidth = adjPortraitH + prefs.frameWidth
        else
            -- Detached: portrait doesn't contribute to frame width
            totalWidth = prefs.frameWidth
            portraitHeight = 0
        end
        -- Health bar xOffset: only offset when portrait is attached on the left
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH
            or 0
        Pix.Size(widget, totalWidth, playerHeightWithCp + btbExtra)
        widget.Health =
            CreateHealthBar(widget, unitToken, prefs.healthHeight, healthXOffset, prefs, healthRightInset)
        widget.Power = CreatePowerBar(widget, unitToken, prefs)
        -- Always create absorb bar; oUF element disabled later if not wanted
        CreateAbsorbBar(widget, unitToken, prefs)
        -- Always create portrait; hide backdrop when disabled
        widget.Portrait = CreatePortrait(widget, pSide, playerHeightWithCp, unitToken)
        CludesUI._ufPortraitSide[widget] = pSide
        if widget.Portrait and not showPortrait then
            widget.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if widget.Portrait and widget.Portrait.backdrop and showPortrait and isAttached and widget.Health then
            local snappedPortW = widget.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and prefs.powerHeight or 0
            local topOff = cpAboveH + powerAboveOff
            widget.Health:ClearAllPoints()
            Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", newXOff, -topOff)
            Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -newRI, 0)
            Pix.Height(widget.Health, prefs.healthHeight)
            widget.Health._xOffset = newXOff
            widget.Health._rightInset = newRI
            widget.Health._topOffset = topOff
        end

        -- Always create castbar; oUF element disabled later if not wanted
        widget.Castbar = CreateCastBar(widget, unitToken, prefs)
        SetupShowOnCastBar(widget, "player")

        -- Create player buffs and debuffs using shared aura setup
        CreateTargetAuras(widget, unitToken)
    elseif unitToken == "target" then
        local pSide = prefs.portraitSide or "right"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then
            effectiveSide = "right"
        end
        local pSizeAdj = prefs.portraitSize or 0
        local adjPortraitH = playerTargetHeight + pSizeAdj
        if not isAttached then
            pSizeAdj = pSizeAdj + 10
        end
        if adjPortraitH < 8 then
            adjPortraitH = 8
        end
        if not showPortrait then
            totalWidth = prefs.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + prefs.frameWidth
        else
            totalWidth = prefs.frameWidth
        end
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH
            or 0
        Pix.Size(widget, totalWidth, targetFrameHeight)
        widget.Health =
            CreateHealthBar(widget, unitToken, prefs.healthHeight, healthXOffset, prefs, healthRightInset)
        widget.Power = CreatePowerBar(widget, unitToken, prefs)
        CreateAbsorbBar(widget, unitToken, prefs)
        widget.Castbar = CreateCastBar(widget, unitToken, prefs)
        SetupShowOnCastBar(widget, unitToken)
        widget.Portrait = CreatePortrait(widget, pSide, playerTargetHeight, unitToken)
        CludesUI._ufPortraitSide[widget] = pSide
        if widget.Portrait and not showPortrait then
            widget.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if widget.Portrait and widget.Portrait.backdrop and showPortrait and isAttached and widget.Health then
            local snappedPortW = widget.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and prefs.powerHeight or 0
            widget.Health:ClearAllPoints()
            Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", newXOff, -powerAboveOff)
            Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -newRI, 0)
            Pix.Height(widget.Health, prefs.healthHeight)
            widget.Health._xOffset = newXOff
            widget.Health._rightInset = newRI
            widget.Health._topOffset = powerAboveOff
        end

        CreateTargetAuras(widget, unitToken)
    end

    CreateUnifiedBorder(widget, unitToken)
    UpdateBordersForScale(widget, unitToken)
    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)

    -- Raid target marker icon -- oUF's RaidTargetIndicator element manages
    -- visibility via RAID_TARGET_UPDATE. We only assign the element when
    -- enabled so oUF registers/unregisters the event accordingly.
    do
        local raidIconHolder = CreateFrame("Frame", nil, widget)
        raidIconHolder:SetAllPoints(widget)
        raidIconHolder:SetFrameLevel(widget:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize = prefs.raidMarkerSize or 28
        local rmAlign = prefs.raidMarkerAlign or "right"
        local rmX = prefs.raidMarkerX or 0
        local rmY = prefs.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT" or (rmAlign == "center") and "TOP" or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", widget, rmAnchor, rmX, rmY)
        widget._raidMarkerIcon = raidIcon
        widget._raidMarkerHolder = raidIconHolder
        if prefs.raidMarkerEnabled then
            widget.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints(widget.Health)
    textOverlay:SetFrameStrata(widget:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(widget:GetFrameLevel() + 20, widget.Health:GetFrameLevel() + 12))
    widget._textOverlay = textOverlay

    local leftContent = prefs.leftTextContent or "name"
    local rightContent = prefs.rightTextContent or "both"
    local centerContent = prefs.centerTextContent or "none"
    local extraContent = prefs.extraTextContent or "none"
    local lts = prefs.leftTextSize or prefs.textSize or 12
    local rts = prefs.rightTextSize or prefs.textSize or 12
    local cts = prefs.centerTextSize or prefs.textSize or 12
    local ets = prefs.extraTextSize or prefs.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    widget.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    widget.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    widget.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    widget.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    widget.NameText = leftText
    widget.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc, ec)
        ApplyFrameTextTags(widget, unitToken, GetSettingsForUnit(unitToken), lc, rc, cc, ec)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    widget._applyTextTags = ApplyTextTags
    local function ApplyTextPositions(s)
        ApplyFrameTextPositions(widget, unitToken, s, "both", 181)
    end
    ApplyTextPositions(prefs)
    widget._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if prefs.bottomTextBar then
        local anchor = (powerIsAtt and widget.Power) or widget.Health
        local btbPos = prefs.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached then
            local pSide = prefs.portraitSide or (unitToken == "player" and "left" or "right")
            local eSide = pSide
            if pSide == "top" then
                eSide = (unitToken == "player") and "left" or "right"
            end
            if eSide == "left" then
                local ppPos2 = prefs.powerPosition or "below"
                local ppIsAtt2 = (ppPos2 == "below" or ppPos2 == "above")
                local barH = prefs.healthHeight + (ppIsAtt2 and (prefs.powerHeight or 6) or 0)
                local adj = barH + (prefs.portraitSize or 0)
                if adj < 8 then
                    adj = 8
                end
                btbXOff = -adj
            end
        end
        widget.BottomTextBar = CreateBottomTextBar(widget, unitToken, prefs, anchor, btbXOff, totalWidth)
        widget._btb = widget.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end

local function StyleFocusFrame(widget, unitToken)
    local prefs = GetSettingsForUnit(unitToken)
    local fPpPos = prefs.powerPosition or "below"
    local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
    local powerHeight = fPpIsAtt and (prefs.powerHeight or 6) or 0
    local focusBarHeight = prefs.healthHeight + powerHeight
    local btbPos = prefs.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (prefs.bottomTextBar and btbIsAttached) and (prefs.bottomTextBarHeight or 16) or 0
    local focusFrameHeight = focusBarHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSide = prefs.portraitSide or "right"
    -- For attached, "top" falls back to default side
    local effectiveSide = pSide
    if isAttached and pSide == "top" then
        effectiveSide = "right"
    end
    local pSizeAdj = prefs.portraitSize or 0
    if not isAttached then
        pSizeAdj = pSizeAdj + 10
    end
    local adjPortraitH = focusBarHeight + pSizeAdj
    if adjPortraitH < 8 then
        adjPortraitH = 8
    end

    if not showPortrait then
        totalWidth = prefs.frameWidth
    elseif isAttached then
        totalWidth = adjPortraitH + prefs.frameWidth
    else
        totalWidth = prefs.frameWidth
    end

    Pix.Size(widget, totalWidth, focusFrameHeight)
    local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
    local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
    widget.Health =
        CreateHealthBar(widget, unitToken, prefs.healthHeight, healthXOffset, prefs, healthRightInset)
    widget.Power = CreatePowerBar(widget, unitToken, prefs)
    CreateAbsorbBar(widget, unitToken, prefs)
    widget.Castbar = CreateCastBar(widget, unitToken, prefs)
    -- Always create portrait; hide backdrop when disabled
    widget.Portrait = CreatePortrait(widget, pSide, focusBarHeight, unitToken)
    CludesUI._ufPortraitSide[widget] = pSide
    if widget.Portrait and not showPortrait then
        widget.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if widget.Portrait and widget.Portrait.backdrop and showPortrait and isAttached and widget.Health then
        local snappedPortW = widget.Portrait.backdrop:GetWidth()
        local newXOff = (effectiveSide == "left") and snappedPortW or 0
        local newRI = (effectiveSide == "right") and snappedPortW or 0
        local powerAboveOff = (fPpPos == "above") and (prefs.powerHeight or 6) or 0
        widget.Health:ClearAllPoints()
        Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", newXOff, -powerAboveOff)
        Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -newRI, 0)
        Pix.Height(widget.Health, prefs.healthHeight)
        widget.Health._xOffset = newXOff
        widget.Health._rightInset = newRI
        widget.Health._topOffset = powerAboveOff
    end

    Pix.Size(widget, totalWidth, focusBarHeight)

    SetupShowOnCastBar(widget, "focus")

    CreateTargetAuras(widget, unitToken)

    CreateUnifiedBorder(widget, unitToken)
    UpdateBordersForScale(widget, unitToken)
    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)

    -- Raid target marker icon
    do
        local raidIconHolder = CreateFrame("Frame", nil, widget)
        raidIconHolder:SetAllPoints(widget)
        raidIconHolder:SetFrameLevel(widget:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize = prefs.raidMarkerSize or 28
        local rmAlign = prefs.raidMarkerAlign or "right"
        local rmX = prefs.raidMarkerX or 0
        local rmY = prefs.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT" or (rmAlign == "center") and "TOP" or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", widget, rmAnchor, rmX, rmY)
        widget._raidMarkerIcon = raidIcon
        widget._raidMarkerHolder = raidIconHolder
        if prefs.raidMarkerEnabled then
            widget.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar and unified border.
    -- Parented to frame (not Health) so text is not clipped by the health bar.
    local textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints(widget.Health)
    textOverlay:SetFrameStrata(widget:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(widget:GetFrameLevel() + 20, widget.Health:GetFrameLevel() + 12))
    widget._textOverlay = textOverlay

    local leftContent = prefs.leftTextContent or "name"
    local rightContent = prefs.rightTextContent or "perhp"
    local centerContent = prefs.centerTextContent or "none"
    local extraContent = prefs.extraTextContent or "none"
    local lts = prefs.leftTextSize or prefs.textSize or 12
    local rts = prefs.rightTextSize or prefs.textSize or 12
    local cts = prefs.centerTextSize or prefs.textSize or 12
    local ets = prefs.extraTextSize or prefs.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    widget.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    widget.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    widget.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    widget.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    widget.NameText = leftText
    widget.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc, ec)
        ApplyFrameTextTags(widget, unitToken, GetSettingsForUnit(unitToken), lc, rc, cc, ec)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    widget._applyTextTags = ApplyTextTags
    local function ApplyTextPositions(s)
        ApplyFrameTextPositions(widget, unitToken, s, "perhp", 181)
    end
    ApplyTextPositions(prefs)
    widget._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if prefs.bottomTextBar then
        local anchor = (fPpIsAtt and widget.Power) or widget.Health
        local btbPos = prefs.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached and effectiveSide == "left" then
            btbXOff = -adjPortraitH
        end
        widget.BottomTextBar = CreateBottomTextBar(widget, unitToken, prefs, anchor, btbXOff, totalWidth)
        widget._btb = widget.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end

-- WoW Forever pets have power (hunter pet focus, warlock pet mana), so there the
-- pet frame carries a power bar driven by the pet's own power settings, laid out
-- like the boss frames'. A plain boolean, fixed per session.
mod.UF_PetHasPower = (CludesUI.IS_FOREVER == true)

local function StyleSimpleFrame(widget, unitToken)
    local prefs = GetSettingsForUnit(unitToken)
    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    if pStyle == "detached" then
        pStyle = "attached"
    end
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    local pSide = prefs.portraitSide or "left"
    -- WoW Forever pet power bar (Blizzard Style keeps its stock one instead): an
    -- attached bar adds its height to the stack and the portrait squares off the
    -- whole stack, as on the boss frames. Zero for every other mini frame.
    local petPower = unitToken == "pet" and mod.UF_PetHasPower and not mod.UF_Blizz()
    local ppPos = petPower and (prefs.powerPosition or "below") or "none"
    local powerH = (ppPos == "below" or ppPos == "above") and (prefs.powerHeight or 6) or 0
    local aboveOff = (ppPos == "above") and powerH or 0
    local barH = prefs.healthHeight + powerH
    local totalWidth = prefs.frameWidth
    local portraitOffset = 0 -- applied to Health TOPLEFT when portrait on left
    local healthRightInset = 0 -- applied to Health RIGHT when portrait on right
    if showPortrait then
        totalWidth = barH + prefs.frameWidth
        if pSide == "right" then
            healthRightInset = barH
        else
            portraitOffset = barH
        end
    end

    Pix.Size(widget, totalWidth, barH)

    local health = CreateFrame("StatusBar", nil, widget)
    Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", portraitOffset, -aboveOff)
    Pix.Point(health, "RIGHT", widget, "RIGHT", -healthRightInset, 0)
    Pix.Height(health, prefs.healthHeight)
    health._topOffset = aboveOff -- SnapLayout re-anchoring
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bgTex = health:CreateTexture(nil, "BACKGROUND")
    Pix.Point(bgTex, "TOPLEFT", health, "TOPLEFT", 0, 0)
    Pix.Point(bgTex, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bgTex:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bgTex

    if unitToken ~= "pet" then
        health.colorClass = true
    end
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._cuiUnitKey = UnitToSettingsKey(unitToken)

    -- Inherit health bar texture from the donor frame (Copy Look From),
    -- unless this frame set its own override.
    local unitKey = UnitToSettingsKey(unitToken)
    local donor = GetMiniDonorSettings(unitKey)
    ApplyHealthBarTexture(health, unitKey, mod.ResolveHealthBarTextureKey(prefs, donor))
    ApplyHealthBarAlpha(health, unitKey)
    health:SetReverseFill(prefs.healthReverseFill and true or false)
    mod.ApplyHealthOrientation(health, prefs)
    ApplyDarkTheme(health, unitToken)

    widget.Health = health
    -- Blizzard Style: the stock small-frame power bar. Otherwise only a WoW Forever
    -- pet has one, built even at "none" so its position changes live (the painter
    -- is parked while it is hidden); ToT and FoT carry none.
    if petPower then
        widget.Power = CreatePowerBar(widget, unitToken, prefs)
        if ppPos == "none" then
            widget:DisableElement("Power")
        end
    else
        widget.Power = mod.UF_BlizzMiniPower(widget, unitToken, prefs)
    end
    -- A pet is never an attackable NPC, so the melee-mob gray-out pass (a pcall
    -- per paint) can never act on a WoW Forever pet's bar, stock or not (the pet
    -- defaults to an attached bar there, so it would run): drop it.
    if unitToken == "pet" and mod.UF_PetHasPower and widget.Power then
        widget.Power.PostUpdate = nil
    end

    -- Always create portrait; hide backdrop when disabled.
    widget.Portrait = CreatePortrait(widget, pSide, barH, unitToken)
    CludesUI._ufPortraitSide[widget] = pSide
    if widget.Portrait and not showPortrait then
        widget.Portrait.backdrop:Hide()
    end
    if widget.Portrait and widget.Portrait.backdrop and showPortrait then
        local portW = math.max(barH, 1)
        health:ClearAllPoints()
        if pSide == "right" then
            Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", 0, -aboveOff)
            Pix.Point(health, "RIGHT", widget, "RIGHT", -portW, 0)
            health._xOffset = 0
            health._rightInset = portW
        else
            Pix.Point(health, "TOPLEFT", widget, "TOPLEFT", portW, -aboveOff)
            Pix.Point(health, "RIGHT", widget, "RIGHT", 0, 0)
            health._xOffset = portW
            health._rightInset = 0
        end
        Pix.Height(health, prefs.healthHeight)
        health._topOffset = aboveOff
    end

    CreateUnifiedBorder(widget, unitToken)
    UpdateBordersForScale(widget, unitToken)
    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 12)
    widget._textOverlay = textOverlay

    local leftContent = prefs.leftTextContent or "name"
    local rightContent = prefs.rightTextContent or "none"
    local centerContent = prefs.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, prefs.leftTextSize or prefs.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    widget.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, prefs.rightTextSize or prefs.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    widget.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, prefs.centerTextSize or prefs.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    widget.CenterText = centerText

    -- Shorthand aliases for font/tag application code
    widget.NameText = leftText
    widget.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        ApplyFrameTextTags(widget, unitToken, GetSettingsForUnit(unitToken), lc, rc, cc)
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    widget._applyTextTags = ApplyTextTags
    local function ApplyTextPositions(s)
        ApplyFrameTextPositions(widget, unitToken, s, "none", 100)
    end
    ApplyTextPositions(prefs)
    widget._applyTextPositions = ApplyTextPositions
    if unitToken == "pet" then
        mod.UF_EnsurePetAuras(widget)
    end
    -- Pet cast bar: built only while on, so it costs nothing otherwise.
    if unitToken == "pet" and prefs.showCastbar == true then
        widget.Castbar = CreateCastBar(widget, unitToken, prefs)
        SetupShowOnCastBar(widget, unitToken)
    end
end

local function StyleBossFrame(widget, unitToken)
    local prefs = GetSettingsForUnit(unitToken)
    local bPpPos = prefs.powerPosition or "below"
    local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
    local powerHeight = bPpIsAtt and (prefs.powerHeight or 6) or 0
    local bossBarHeight = prefs.healthHeight + powerHeight
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    if pStyle == "detached" then
        pStyle = "attached"
    end
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    if not showPortrait then
        totalWidth = prefs.frameWidth
    else
        totalWidth = bossBarHeight + prefs.frameWidth
    end

    Pix.Size(widget, totalWidth, bossBarHeight)
    local pSide = prefs.portraitSide or "right"
    local healthRightInset = (showPortrait and pSide == "right") and bossBarHeight or 0
    widget.Health =
        CreateHealthBar(widget, unitToken, prefs.healthHeight, portraitHeight, prefs, healthRightInset)
    widget.Power = CreatePowerBar(widget, unitToken, prefs)
    -- Always create the absorb bar (visibility gated at render time). Boss frames
    -- carry no absorb settings of their own: they render with the TARGET frame's
    -- styling (donor convention, like textures) behind "Show on Boss Frames" in the
    -- absorb cog. Geometry (reverse fill) still comes from the boss block via `settings`.
    CreateAbsorbBar(widget, unitToken, prefs)
    -- Always create portrait; hide backdrop when disabled
    widget.Portrait = CreatePortrait(widget, pSide, bossBarHeight, unitToken)
    CludesUI._ufPortraitSide[widget] = pSide
    if widget.Portrait and not showPortrait then
        widget.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if widget.Portrait and widget.Portrait.backdrop and showPortrait and widget.Health then
        local snappedPortW = widget.Portrait.backdrop:GetWidth()
        local powerAboveOff = (bPpPos == "above") and (prefs.powerHeight or 6) or 0
        widget.Health:ClearAllPoints()
        if pSide == "left" then
            Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", snappedPortW, -powerAboveOff)
            Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", 0, 0)
            widget.Health._xOffset = snappedPortW
            widget.Health._rightInset = 0
        else
            Pix.Point(widget.Health, "TOPLEFT", widget, "TOPLEFT", 0, -powerAboveOff)
            Pix.Point(widget.Health, "RIGHT", widget, "RIGHT", -snappedPortW, 0)
            widget.Health._xOffset = 0
            widget.Health._rightInset = snappedPortW
        end
        Pix.Height(widget.Health, prefs.healthHeight)
        widget.Health._topOffset = powerAboveOff
    end

    Pix.Size(widget, totalWidth, bossBarHeight)

    widget.Castbar = CreateCastBar(widget, unitToken, prefs)
    SetupShowOnCastBar(widget, unitToken)

    CreateTargetAuras(widget, unitToken)

    CreateUnifiedBorder(widget, unitToken)
    UpdateBordersForScale(widget, unitToken)
    ReparentBarsToClip(widget, mod.UF_PowerPos(prefs), prefs)

    -- Raid target marker icon (boss frames) -- anchored outside the LEFT edge
    do
        local raidIconHolder = CreateFrame("Frame", nil, widget)
        raidIconHolder:SetAllPoints(widget)
        raidIconHolder:SetFrameLevel(widget:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize = prefs.raidMarkerSize or 28
        local rmAlign = prefs.raidMarkerAlign or "left"
        local rmX = prefs.raidMarkerX or 0
        local rmY = prefs.raidMarkerY or 0
        raidIcon:SetSize(rmSize, rmSize)
        if rmAlign == "left" then
            raidIcon:SetPoint("RIGHT", widget, "LEFT", rmX, rmY)
        elseif rmAlign == "center" then
            raidIcon:SetPoint("CENTER", widget, "CENTER", rmX, rmY)
        else
            raidIcon:SetPoint("LEFT", widget, "RIGHT", rmX, rmY)
        end
        widget._raidMarkerIcon = raidIcon
        widget._raidMarkerHolder = raidIconHolder
        if prefs.raidMarkerEnabled then
            widget.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints(widget.Health)
    textOverlay:SetFrameLevel(widget.Health:GetFrameLevel() + 12)
    widget._textOverlay = textOverlay

    local leftContent = prefs.leftTextContent or "name"
    local rightContent = prefs.rightTextContent or "perhp"
    local centerContent = prefs.centerTextContent or "none"
    local extraContent = prefs.extraTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, prefs.leftTextSize or prefs.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    widget.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, prefs.rightTextSize or prefs.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    widget.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, prefs.centerTextSize or prefs.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    widget.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb
    -- gate); it only anchors per extraTextAlign and is capped at 95% of the bar
    -- width (ellipsis truncation). Mirrors the Main Frames implementation.
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, prefs.extraTextSize or prefs.textSize or 12)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    widget.ExtraText = extraText

    widget.NameText = leftText
    widget.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc, ec)
        ApplyFrameTextTags(widget, unitToken, GetSettingsForUnit(unitToken), lc, rc, cc, ec)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    widget._applyTextTags = ApplyTextTags
    local function ApplyTextPositions(s)
        ApplyFrameTextPositions(widget, unitToken, s, "perhp", 100)
    end
    ApplyTextPositions(prefs)
    widget._applyTextPositions = ApplyTextPositions
end

-- (Styles are no longer registered anywhere: the spawn sites call
-- StyleFullFrame/StyleFocusFrame/StyleSimpleFrame/StyleBossFrame
-- directly, and the engine's portrait painter always routes through the shared
-- gated PortraitOverride.)

Inner.StyleFullFrame, Inner.StyleFocusFrame = StyleFullFrame, StyleFocusFrame
Inner.StyleSimpleFrame, Inner.StyleBossFrame = StyleSimpleFrame, StyleBossFrame
