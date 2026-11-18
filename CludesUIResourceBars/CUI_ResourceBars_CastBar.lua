if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_CastBar.lua
--
--  The cast bar: build, channel ticks, timer text, update, latency overlay
--  and the cast, channel and empower handlers.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local Pix = CludesUI.PP
local floor, min, max = math.floor, math.min, math.max
local format = string.format
local IsPlayerSpell, GetInventoryItemID = IsPlayerSpell, GetInventoryItemID

local CHANNEL_TICK_DATA, CLASS_COLORS, ERB = Inner.CHANNEL_TICK_DATA, Inner.CLASS_COLORS, Inner.ERB
local GetRBFont, SetRBFont, SnapXY = Inner.GetRBFont, Inner.SetRBFont, Inner.SnapXY
local empowerColorA, empowerColorB = Inner.empowerColorA, Inner.empowerColorB
local GetCurrentEmpowerStage = Inner.GetCurrentEmpowerStage
local GetEmpowerStageColor, SmoothBarAnimate = Inner.GetEmpowerStageColor, Inner.SmoothBarAnimate
local CAST_BAR_TEXTURES, SPARK_TEX = Inner.CAST_BAR_TEXTURES, Inner.SPARK_TEX
local SetCastBarFrame, SetUpdateCastBar = Inner.SetCastBarFrame, Inner.SetUpdateCastBar
local SetStageThresholds = Inner.SetStageThresholds

local castBarFrame
Inner.castBarFrameSetters[#Inner.castBarFrameSetters + 1] = function(val)
    castBarFrame = val
end
local cachedClass
Inner.cachedClassSetters[#Inner.cachedClassSetters + 1] = function(val)
    cachedClass = val
end
local cachedStageThresholds
Inner.stageThresholdsSetters[#Inner.stageThresholdsSetters + 1] = function(val)
    cachedStageThresholds = val
end

-- Forward declarations
local BuildCastBar
local OnCastStart, OnChannelStart, OnChannelUpdate, OnCastStop, OnEmpowerStart, OnEmpowerUpdate
local ShowChannelTicks, HideChannelTicks

BuildCastBar = function()
    local callback = ERB.db.profile.castBar
    -- Embed in Player Portrait: Unit Frames calls back after each frame reload, which
    -- can move, reshape or remove the portrait the icon sits on.
    local uf = CludesUI._ModuleNS["CludesUIUnitFrames"]
    if uf and uf.UF_WatchPlayerPortrait then
        uf.UF_WatchPlayerPortrait(
            "ResourceBars",
            (callback.enabled and callback.iconOnPortrait) and mod.ERB_RefreshCastPortrait or nil
        )
    end
    -- blizz = a stock style dictates the geometry (both stock styles);
    -- blizzKit = the 12.1 kit (atlas fill, background, pip and text box);
    -- classic keeps the user's fill under the vanilla frame and spark.
    local blizz = mod.ERB_CastBlizz()
    local classic = mod.ERB_CastClassic()
    local blizzKit = blizz and not classic

    -- ResourceBars only claims Blizzard's player cast bar while its own
    -- replacement bar is active. The shared helper arbitrates ownership
    -- across CUI modules and releases control cleanly for other addons.
    mod.RB_SyncBlizzCastSuppress()
    mod.ERB_SyncUninterruptWatch(callback.enabled and callback.uninterruptibleOverride and not blizzKit)
    mod.ERB_LatencySendWatch(callback.enabled and callback.latencyEnabled)

    if not callback.enabled then
        if castBarFrame then
            CludesUI.SetElementVisibility(castBarFrame, false)
        end
        return
    end

    if not castBarFrame then
        SetCastBarFrame(CreateFrame("Frame", "ERB_CastBarFrame", UIParent))
        castBarFrame:SetFrameStrata(callback.frameStrata or "MEDIUM")
        castBarFrame:SetFrameLevel(15)

        local backdrop = castBarFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        castBarFrame._bg = backdrop

        -- Border frame: child that covers the full cast bar (bar + icon)
        local bdrFrame = CreateFrame("Frame", nil, castBarFrame)
        bdrFrame:SetAllPoints(castBarFrame)
        bdrFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 5)
        castBarFrame._border = bdrFrame
        local Pix = CludesUI and CludesUI.PP
        if Pix then
            Pix.CreateBorder(bdrFrame, 0, 0, 0, 1, 1)
        end

        -- Clip frame to prevent bar fill from bleeding past the border
        local clipFrame = CreateFrame("Frame", nil, castBarFrame)
        clipFrame:SetClipsChildren(true)
        castBarFrame._barClip = clipFrame

        -- Status bar (inside clip frame)
        local barFrame = CreateFrame("StatusBar", "ERB_CastBar", clipFrame)
        barFrame:SetMinMaxValues(0, 1)
        barFrame:SetValue(0)
        castBarFrame._bar = barFrame
        -- NO native interpolation on this fill: the value is recomputed from
        -- GetTime() every frame and is already smooth. Easing toward a per-frame
        -- moving target makes the fill trail real progress (worst on short casts),
        -- so the bar hides on cast stop before it ever looks complete.

        -- Spark (in its own child frame inside clip so it gets clipped)
        local sparkFrame = CreateFrame("Frame", nil, clipFrame)
        sparkFrame:SetAllPoints(barFrame)
        sparkFrame:SetFrameLevel(barFrame:GetFrameLevel() + 2)
        local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        castBarFrame._spark = spark

        -- Latency overlay (on clipFrame: below the bar's fill, so a cast's
        -- completing fill sweeps over the end-side zone)
        local latOverlay = clipFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        latOverlay:Hide()
        castBarFrame._latencyOverlay = latOverlay

        -- Channel twin on the bar frame: a channel starts FULL, so the
        -- drain-side zone spends the whole channel under the fill unless it
        -- draws above it (OVERLAY 0: over the fill, under ticks and spark).
        local latOverlayFront = barFrame:CreateTexture(nil, "OVERLAY", nil, 0)
        latOverlayFront:Hide()
        castBarFrame._latencyOverlayFront = latOverlayFront

        -- Spell icon
        local iconFrame = CreateFrame("Frame", nil, castBarFrame)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castBarFrame._iconFrame = iconFrame
        castBarFrame._icon = iconTex

        -- Optional 1px divider at the icon/bar seam (opt-in: "Show Icon Divider").
        -- That seam is otherwise interior with no border by design (see the clip-inset
        -- comment below). Parented to the border frame (pl+5), not castBarFrame itself
        -- (pl+15): a texture drawn directly on castBarFrame renders at castBarFrame's
        -- own frame level, which sits BELOW the icon and bar/clip child frames -- it
        -- would be invisible under them regardless of draw layer, since draw layer only
        -- orders content within the SAME frame, not across frames.
        local iconDivider = castBarFrame._border:CreateTexture(nil, "OVERLAY", nil, 7)
        iconDivider:Hide()
        if iconDivider.SetSnapToPixelGrid then
            iconDivider:SetSnapToPixelGrid(false)
            iconDivider:SetTexelSnappingBias(0)
        end
        castBarFrame._iconDivider = iconDivider

        -- Text overlay frame (above all bar borders)
        local textFrame = CreateFrame("Frame", nil, castBarFrame)
        textFrame:SetAllPoints(barFrame)
        textFrame:SetFrameLevel(25)
        castBarFrame._textFrame = textFrame

        -- Spell name text
        local nameText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(nameText, GetRBFont(), 11)
        nameText:SetPoint("LEFT", barFrame, "LEFT", 4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        castBarFrame._nameText = nameText

        -- Timer text
        local timerText = textFrame:CreateFontString(nil, "OVERLAY")
        SetRBFont(timerText, GetRBFont(), 11)
        timerText:SetPoint("RIGHT", barFrame, "RIGHT", -4, 0)
        timerText:SetJustifyH("RIGHT")
        timerText:SetWordWrap(false)
        timerText:SetNonSpaceWrap(false)
        castBarFrame._timerText = timerText

        castBarFrame._casting = false
        castBarFrame._channeling = false
        castBarFrame._empowering = false
        castBarFrame._castID = nil
        castBarFrame._startTime = 0
        castBarFrame._endTime = 0
        castBarFrame._spellName = ""
        castBarFrame._pips = {}
        castBarFrame._numStages = 0
        castBarFrame._ticks = {}
        castBarFrame._numTicks = 0
    end
    -- Read by the per-cast fill swap (ns.ERB_SetBlizzCastFill): one field, no
    -- profile lookup. Blizzard Style only: the classic fill is the user's.
    castBarFrame._blizzFill = blizzKit or nil

    local wid, hgt = callback.width, callback.height
    local hasIcon = callback.showIcon ~= false
    -- Total frame width includes the icon only when it is shown (a square of
    -- the bar height; under the style it also spans the text box, so the
    -- bar keeps its configured width beside it).
    local iconW = mod.ERB_CastIconW(callback)
    local totalW = wid + iconW
    if CludesUI._TryOverrideAnchor and CludesUI._TryOverrideAnchor("ERB_CastBar", castBarFrame) then
        -- Override anchor owns position; just set size directly
        castBarFrame:SetSize(totalW, hgt)
    elseif callback.unlockPos and callback.unlockPos.point then
        -- Position managed by unlock mode -- only animate size changes.
        -- Skip reposition during unlock mode so resize does not snap the bar.
        local rp = callback.unlockPos.relPoint or callback.unlockPos.point
        local px, py = callback.unlockPos.x or 0, callback.unlockPos.y or 0
        local anchored = CludesUI.IsUnlockAnchored("ERB_CastBar")
        if CludesUI._unlockActive then
            castBarFrame:SetSize(totalW, hgt)
        elseif anchored and castBarFrame:GetLeft() then
            -- Anchor system owns position; just set size directly
            castBarFrame:SetSize(totalW, hgt)
        else
            local function ApplyCastUnlockTransform()
                local aw = castBarFrame["_barAnim_w"] or totalW
                local ah = castBarFrame["_barAnim_h"] or hgt
                castBarFrame:SetSize(aw, ah)
                castBarFrame:ClearAllPoints()
                -- Snap the stored CENTER/CENTER position to the pixel grid, dimension-
                -- aware (SnapXY -> SnapCenterForDim): an odd-pixel-height frame needs a
                -- +0.5px center offset for BOTH top and bottom edges to land on whole
                -- pixels. The unlock-mode drag path (castApply, near ERB_CastBar's MK()
                -- registration above) already does this; this normal-build path never
                -- did, so a raw stored position landed the center off-grid, and the
                -- border rendered thicker on one edge and missing on the opposite one.
                local sx, sy = SnapXY(px, py, castBarFrame, callback.unlockPos)
                castBarFrame:SetPoint(callback.unlockPos.point, UIParent, rp, sx, sy)
            end
            SmoothBarAnimate(castBarFrame, "w", totalW, function()
                ApplyCastUnlockTransform()
            end)
            SmoothBarAnimate(castBarFrame, "h", hgt, function()
                ApplyCastUnlockTransform()
            end)
        end
    else
        castBarFrame:SetSize(totalW, hgt)
        if not CludesUI._unlockActive then
            castBarFrame:ClearAllPoints()
            castBarFrame:SetPoint("CENTER", UIParent, "CENTER", callback.anchorX, callback.anchorY)
        end
    end

    -- Border: update the dedicated child border frame (PP or textured)
    if castBarFrame._border then
        -- Blizzard Style: no CUI border; the stock frame art draws on this child instead.
        local bs = blizz and 0 or (callback.borderSize or 0)
        local texKey = callback.borderTexture or "solid"
        -- "Show Behind": +5 in front of the bar, level-1 behind it.
        local pl = castBarFrame:GetFrameLevel()
        castBarFrame._border:SetFrameLevel(
            (callback.borderBehind and not blizz) and math.max(0, pl - 1) or (pl + 5)
        )
        -- Same lost-rect recovery as MakePixelBorder:ApplyStyle -- re-anchoring the bar
        -- stops this child's rect from resolving and the border silently vanishes.
        -- Extend Top / Extend Bottom seat it past the bar; none under a stock
        -- style, whose frame art rides this child.
        mod.ERB_AnchorBorderHost(
            castBarFrame._border,
            castBarFrame,
            mod.ERB_BorderExtents((not blizz) and callback or nil)
        )
        -- Exact size only for the bar's own step: the forced 0 under the style is a substitute.
        local bpx = (not blizz) and CludesUI.BorderPx(callback.borderSizePx, bs, texKey) or nil
        CludesUI.ApplyBorderStyle(
            castBarFrame._border,
            bs,
            callback.borderR or 0,
            callback.borderG or 0,
            callback.borderB or 0,
            callback.borderA or 1,
            texKey,
            callback.borderTextureOffset,
            callback.borderTextureOffsetY,
            callback.borderTextureShiftX,
            callback.borderTextureShiftY,
            "resourcebars",
            bs,
            nil,
            bpx
        )
    end
    -- Bottom Separator: across the whole bar (icon included), above its border;
    -- none under a stock style or a Solid border (inert unless it was ever on).
    if callback.edgeSep or castBarFrame._erbSep then
        mod.ERB_Separators(
            castBarFrame,
            callback,
            (callback.edgeSep and not blizz and mod.ERB_Textured(callback)) and true or false,
            castBarFrame:GetFrameLevel() + 7
        )
    end

    -- Icon: left or right side (iconOnRight), full height, no inset
    local iconFrame = castBarFrame._iconFrame
    local portrait, portraitSettings = mod.ERB_CastIconPortrait(callback)
    if uf and (portrait or iconFrame._pbd) then
        uf.UF_CastIconPortraitLayout(iconFrame, castBarFrame._icon, portrait, portraitSettings)
        if not portrait then
            castBarFrame._icon:ClearAllPoints()
            castBarFrame._icon:SetAllPoints(iconFrame)
        end
    end
    local iconOnRight = hasIcon and callback.iconOnRight
    local iconFree = mod.ERB_CastIconFree(callback)
    mod.ERB_LayoutFreeCastIcon(iconFrame, castBarFrame, callback, iconFree)
    if portrait or iconFree then
        iconFrame:Show()
    elseif hasIcon then
        -- A square of the bar height; under the style it also spans the stock
        -- text box under the bar (see ns.ERB_CastIconW), hung from the same
        -- top corner, as the unit frame cast bars do.
        iconFrame:SetSize(iconW, iconW)
        iconFrame:ClearAllPoints()
        if iconOnRight then
            iconFrame:SetPoint("TOPRIGHT", castBarFrame, "TOPRIGHT", 0, 0)
        else
            iconFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", 0, 0)
        end
        -- Blizzard Style shows the full spell art, as the stock bar does.
        if blizz then
            castBarFrame._icon:SetTexCoord(0, 1, 0, 1)
        end
        -- Classic WoW UI seats the icon inside the frame's window beside the
        -- fill, under the art child (+5) like the fill, so the frame's rim
        -- overlaps its edges as it does the bar's.
        if classic then
            iconFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 1)
        end
        iconFrame:Show()
    else
        iconFrame:Hide()
    end

    -- Optional icon/bar seam divider (opt-in "Show Icon Divider"). Same
    -- onePixel math as the perimeter border (SnapBorderTextures) so it reads
    -- as the same thickness. Anchored to iconFrame's inner edge and given
    -- only a width (both vertical anchor points already match iconFrame's
    -- own top/bottom, so it inherits the full bar height automatically).
    local iconDivider = castBarFrame._iconDivider
    -- Border Art Divider: the border style's vertical companion art in place of
    -- the solid line below (ns.ERB_CastDividerArt; inert unless it was ever on).
    local showDivider = hasIcon and not portrait and not iconFree and callback.showIconDivider
    if mod.ERB_CastDividerArt(iconDivider, showDivider, iconFrame, iconOnRight, callback, blizz) then
        iconDivider:Show()
    elseif showDivider then
        local des = castBarFrame:GetEffectiveScale()
        local onePixel = des > 0 and (Pix.perfect / des) or Pix.mult
        local dbs = callback.borderSize or 1
        -- An exact SOLID size drives the divider too; a textured one keeps the step.
        local dtex = callback.borderTexture
        if not blizz and (not dtex or dtex == "" or dtex == "solid") then
            dbs = CludesUI.BorderPx(callback.borderSizePx, callback.borderSize or 0, dtex) or dbs
        end
        iconDivider:ClearAllPoints()
        iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
        if iconOnRight then
            iconDivider:SetPoint("TOPRIGHT", iconFrame, "TOPLEFT", 0, 0)
            iconDivider:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMLEFT", 0, 0)
        else
            iconDivider:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 0, 0)
            iconDivider:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 0, 0)
        end
        iconDivider:SetColorTexture(callback.borderR or 0, callback.borderG or 0, callback.borderB or 0, callback.borderA or 1)
        iconDivider:Show()
    else
        iconDivider:Hide()
    end

    -- Clip frame + bar: beside the icon (or full width), full height
    local clipFrame = castBarFrame._barClip
    local barFrame = castBarFrame._bar
    -- No border, no inset: the bg spans the frame, so an inset with no border
    -- over it reads as a 1px background ring around the fill.
    local bdrInset = (not blizz and (callback.borderSize or 0) > 0 and Pix and Pix.mult) or 0
    clipFrame:ClearAllPoints()
    -- The icon-adjacent side sits FLUSH against the icon (no inset): that seam is
    -- interior with no border, and insetting it exposes a 1px background column
    -- next to the icon. Outer edges keep the inset so the fill never bleeds out.
    local clipLeft = (iconW > 0 and not iconOnRight) and iconW or bdrInset
    local clipRight = (iconW > 0 and iconOnRight) and iconW or bdrInset
    clipFrame:SetPoint("TOPLEFT", castBarFrame, "TOPLEFT", clipLeft, -bdrInset)
    clipFrame:SetPoint("BOTTOMRIGHT", castBarFrame, "BOTTOMRIGHT", -clipRight, bdrInset)
    clipFrame:SetFrameLevel(castBarFrame:GetFrameLevel() + 1)
    barFrame:ClearAllPoints()
    barFrame:SetAllPoints(clipFrame)

    local texKey = callback.texture
    local isBlizzard = (texKey == "blizzard")
    -- Textured Background: back to the plain background before a branch repaints it.
    if castBarFrame._bg._erbBgTex then
        mod.ERB_BgTexture(castBarFrame._bg, nil)
    end
    if blizzKit then
        -- Blizzard Style: the stock fill art follows the cast kind
        -- (ns.ERB_SetBlizzCastFill) and the background hugs the bar the way
        -- the stock frame anchors it.
        barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        castBarFrame._blizzFillKind = nil
        mod.ERB_SetBlizzCastFill(castBarFrame._channeling and "channel" or "cast")
        -- A bar texture, not frame chrome: the retail background under
        -- Blizzard Style, WoW Forever included.
        local bgAtlas = mod.ERB_BlizzAtlas("bg")
        if bgAtlas then
            CludesUI.StockAtlas(castBarFrame._bg, bgAtlas)
        else
            castBarFrame._bg:SetTexture(nil)
            castBarFrame._bg:SetColorTexture(0, 0, 0, 0.7)
        end
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetPoint("TOPLEFT", clipFrame, "TOPLEFT", -1, 1)
        castBarFrame._bg:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", 1, -1)
    elseif isBlizzard then
        barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        barFrame:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        -- Classic WoW UI's seeded fill: the retail background on WoW Forever
        -- too (the CludesUI look keeps the client's).
        if classic then
            mod.ERB_StockAtlas(castBarFrame._bg, "UI-CastingBar-Background", true)
        else
            castBarFrame._bg:SetAtlas("UI-CastingBar-Background", true)
        end
        castBarFrame._bg:ClearAllPoints()
        castBarFrame._bg:SetAllPoints(castBarFrame)
    else
        local texPath = CludesUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, "Interface\\Buttons\\WHITE8x8")
        barFrame:SetStatusBarTexture(texPath)
        castBarFrame._bg:SetTexture(nil)
        castBarFrame._bg:SetColorTexture(callback.bgR, callback.bgG, callback.bgB, callback.bgA)
        -- Textured Background: flat while Fill Color is below 100.
        if callback.textureBg and (callback.fillOpacity or 100) >= 100 then
            mod.ERB_BgTexture(
                castBarFrame._bg,
                CludesUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, nil),
                callback.bgR,
                callback.bgG,
                callback.bgB,
                callback.bgA
            )
        end
        mod.ApplyCastBgAnchor()
    end

    -- Bar color / gradient. Fill Opacity multiplies into the fill alpha (solid
    -- color and both gradient endpoints), so the fill turns translucent without
    -- double-dimming through a separate region alpha.
    local fillTex = barFrame:GetStatusBarTexture()
    local fillOp = (callback.fillOpacity or 100) / 100

    if blizzKit then
        -- Blizzard Style: the fill atlas carries its own colour; only Fill Opacity applies.
        fillTex:SetVertexColor(1, 1, 1, fillOp)
        if castBarFrame._gradClip then
            castBarFrame._gradClip:Hide()
        end
        castBarFrame._gradientFullBar = nil
        castBarFrame._nameText:SetParent(castBarFrame._textFrame)
        castBarFrame._timerText:SetParent(castBarFrame._textFrame)
    elseif callback.gradientEnabled then
        local direction = callback.gradientDir or "HORIZONTAL"

        local fR, fG, fB, fA = callback.fillR, callback.fillG, callback.fillB, 1
        if callback.classColored then
            local cc = CLASS_COLORS[cachedClass]
            if cc then
                fR, fG, fB = cc[1], cc[2], cc[3]
            end
        end
        fillTex:SetVertexColor(1, 1, 1, 1)
        fillTex:SetGradient(
            direction,
            CreateColor(fR, fG, fB, fA * fillOp),
            CreateColor(callback.gradientR, callback.gradientG, callback.gradientB, callback.gradientA * fillOp)
        )

        -- Hide the old clip-frame gradient if it exists from a prior session
        if castBarFrame._gradClip then
            castBarFrame._gradClip:Hide()
        end
        castBarFrame._gradientFullBar = nil

        castBarFrame._nameText:SetParent(castBarFrame._textFrame)
        castBarFrame._timerText:SetParent(castBarFrame._textFrame)
    else
        if castBarFrame._gradClip then
            castBarFrame._gradClip:Hide()
        end
        castBarFrame._gradientFullBar = nil

        castBarFrame._nameText:SetParent(castBarFrame._textFrame)
        castBarFrame._timerText:SetParent(castBarFrame._textFrame)

        do
            local fR, fG, fB, fA = callback.fillR, callback.fillG, callback.fillB, 1
            if callback.classColored then
                local cc = CLASS_COLORS[cachedClass]
                if cc then
                    fR, fG, fB = cc[1], cc[2], cc[3]
                end
            end
            fillTex:SetVertexColor(fR, fG, fB, fA * fillOp)
        end
    end
    -- The fill was just repainted from the settings: a live cast re-resolves its
    -- cached settings on the next tick and re-reads the Out of Range Gray, and a
    -- live uninterruptible cast or channel takes its override colour back (or
    -- keeps the configured paint with the option now off).
    castBarFrame._rangeOut = nil
    castBarFrame._cstKey = nil
    castBarFrame._uninterrupt = nil
    castBarFrame._channelPaint = nil
    mod.ERB_CastOverrideApply()

    local spark = castBarFrame._spark
    -- Blizzard Style: the stock pip replaces the spark art (once; the swap is
    -- reload-gated so it never needs undoing).
    if blizzKit and not castBarFrame._blizzSpark then
        local pip = mod.ERB_BlizzAtlas("spark")
        if pip then
            castBarFrame._blizzSpark = true
            spark:SetAtlas(pip)
            -- The stock pip is drawn plain (the CUI spark art is additive).
            spark:SetBlendMode("BLEND")
        end
    end
    -- Classic WoW UI: the vanilla spark file (additive, like the CUI art) once.
    -- It stands taller than the bar and draws over the frame art, so its
    -- host leaves the clip frame for the bar frame itself (anchors kept).
    if classic and not castBarFrame._classicSpark then
        castBarFrame._classicSpark = true
        spark:SetTexture(mod.ERB_CLASSIC.spark)
        local scrollFrame = spark:GetParent()
        scrollFrame:SetParent(castBarFrame)
        scrollFrame:ClearAllPoints()
        scrollFrame:SetAllPoints(barFrame)
    end
    -- Above the frame art (+5) and the icon (+6), under the texts (25);
    -- re-asserted like the art frame's level.
    if classic then
        spark:GetParent():SetFrameLevel(castBarFrame:GetFrameLevel() + 7)
    end
    if callback.showSpark then
        -- The vanilla spark is a square scaled with the bar, its centre a
        -- little above the bar's centre line.
        local sparkY = 0
        if classic then
            local C = mod.ERB_CLASSIC
            local ss = C.sparkSize * hgt / C.barH
            spark:SetSize(ss, ss)
            sparkY = C.sparkY * hgt / C.barH
        else
            spark:SetSize(8, hgt)
        end
        spark:ClearAllPoints()

        if callback.gradientEnabled and castBarFrame._gradClip then
            spark:SetPoint("CENTER", castBarFrame._gradClip, "RIGHT", 0, sparkY)
        else
            spark:SetPoint("CENTER", fillTex, "RIGHT", 0, sparkY)
        end

        spark:Show()
    else
        spark:Hide()
    end

    -- Latency overlay style. Width is computed per cast from that cast's own
    -- request-to-start time (ShowLatencyOverlay).
    if callback.latencyEnabled then
        local lR, lG, lB, lA =
            callback.latencyR or 0.835, callback.latencyG or 0.290, callback.latencyB or 0.290, callback.latencyA or 1
        local texKey = callback.texture
        local texPath
        if texKey and texKey ~= "none" and texKey ~= "blizzard" then
            texPath = CludesUI.ResolveTexturePath(CAST_BAR_TEXTURES, texKey, nil)
        end
        -- Style both overlays; ShowLatencyOverlay picks one per cast kind
        -- (channels use the front twin so the zone survives the full fill).
        for index = 1, 2 do
            local lo = (index == 1) and castBarFrame._latencyOverlay or castBarFrame._latencyOverlayFront
            if lo then
                if texPath then
                    lo:SetTexture(texPath)
                    lo:SetVertexColor(lR, lG, lB, lA)
                else
                    lo:SetColorTexture(lR, lG, lB, lA)
                end
            end
        end
    else
        if castBarFrame._latencyOverlay then
            castBarFrame._latencyOverlay:Hide()
        end
        if castBarFrame._latencyOverlayFront then
            castBarFrame._latencyOverlayFront:Hide()
        end
        castBarFrame._latencySuffix = nil
    end
    -- Text width cap from the bar's RENDERED width, so width-matching and border
    -- insets are accounted for. Falls back to cb.width before first layout.
    local barW = barFrame:GetWidth()
    if not barW or barW < 10 then
        barW = callback.width
    end

    -- Cast text side-aware layout (mirrors nameplates / unit frames): the duration
    -- reserves a slot on its side and pushes the spell text inward when they share
    -- one; center is never pushed. Visibility stays governed by showTimer /
    -- showSpellText (the dropdown "None" sets those flags false).
    local timerW = (callback.timerSize or 11) * 2.2
    local durSide = callback.timerSide or "right"
    local spellSide = callback.spellTextSide or "left"

    -- Timer / duration text (auto-sized, anchored to its side)
    local timerText = castBarFrame._timerText
    if callback.showTimer then
        SetRBFont(timerText, GetRBFont(), callback.timerSize or 11)
        local pt, xb, jh = mod.GetCastTextAnchor(durSide, false, timerW)
        timerText:ClearAllPoints()
        timerText:SetJustifyH(jh)
        timerText:SetPoint(pt, barFrame, pt, xb + (callback.timerX or 0), callback.timerY or 0)
        timerText:Show()
        mod.ERB_CastTextColor(timerText, callback.timerR, callback.timerG, callback.timerB, callback.timerA)
    else
        timerText:Hide()
    end

    -- Spell name text
    local nameText = castBarFrame._nameText
    if callback.showSpellText then
        SetRBFont(nameText, GetRBFont(), callback.spellTextSize or 11)
        local pt, xb, jh = mod.GetCastTextAnchor(spellSide, callback.showTimer and durSide == spellSide, timerW)
        nameText:ClearAllPoints()
        nameText:SetJustifyH(jh)
        nameText:SetPoint(pt, barFrame, pt, xb + (callback.spellTextX or 0), callback.spellTextY or 0)
        if spellSide == "center" then
            nameText:SetWidth(barW - 8 - (callback.showTimer and 2 * timerW or 0))
        else
            nameText:SetWidth(barW - 8 - (callback.showTimer and timerW or 0))
        end
        nameText:Show()
        mod.ERB_CastTextColor(nameText, callback.spellTextR, callback.spellTextG, callback.spellTextB, callback.spellTextA)
    else
        nameText:Hide()
    end
    -- Re-flow so a live JustifyH change takes effect on already-rendered text.
    mod.ReflowFontString(timerText)
    mod.ReflowFontString(nameText)
    -- Blizzard Style chrome: frame art + text box (moves the spell name under the bar).
    if blizz then
        mod.ERB_ApplyBlizzCastChrome(callback, barW)
    end
    -- Show Full Spell Name: the font above reset the name to its configured
    -- size; re-fit a cast in flight to the width it now has.
    if callback.fitSpellName then
        mod.ERB_FitCastName(callback)
    end

    -- Hide pips (build reset), then RE-LAY them for an in-flight empower:
    -- same wipe-sticks class as the channel ticks below (field: Evokers
    -- randomly losing all stage marks for one empowered cast whenever a
    -- width-match/anchor re-apply landed mid-cast). Geometry is final here,
    -- so the pips re-anchor against the rebuilt bar.
    if castBarFrame._pips then
        for index = 1, #castBarFrame._pips do
            castBarFrame._pips[index]:Hide()
        end
    end
    if castBarFrame._empowering and castBarFrame._empStages then
        mod.ERB_LayoutEmpowerPips(castBarFrame._empStages)
    end

    -- Hide channel ticks (build reset), then RE-SHOW them for an in-flight
    -- channel: ApplyAll can run mid-channel (unlock rebuilds, width-match and
    -- anchor-link re-applies, options edits, spec-override/profile refreshes --
    -- field: Arcane Missiles marks vanishing when a Bloodlust buff arrived
    -- mid-channel), and without the re-show the wipe sticks until the NEXT
    -- channel starts: a channel whose reported window never changes gets no
    -- further CHANNEL_UPDATE to redraw them. Geometry is final here, so the
    -- marks re-anchor against the rebuilt bar.
    HideChannelTicks()
    if castBarFrame._channeling and castBarFrame._tickSpellID then
        ShowChannelTicks(castBarFrame._tickSpellID)
    end

    -- Idle when not casting (empty bar with "Always Show", else hidden). Runs LAST
    -- on purpose: the idle state re-suppresses the spark and icon the style pass
    -- above just re-showed.
    if not castBarFrame._casting and not castBarFrame._channeling and not castBarFrame._empowering then
        mod.ShowIdleCastBar()
    else
        mod.ActivateCastBar()
    end
end

function mod.ERB_RefreshCastPortrait()
    BuildCastBar()
    CludesUI.NotifyElementResized("ERB_CastBar")
end

-- Some set bonuses never register via IsPlayerSpell or a player aura.
-- Count equipped items whose set-bonus data lists this spellID; two or
-- more equipped means the 2pc bonus is up.
local function IsSetBonusSpellActive(spellId)
    if not (C_Item and C_Item.GetSetBonusesForSpecializationByItemID) then
        return false
    end
    local specID = _G._CURB_ResolveSpecIDCached and _G._CURB_ResolveSpecIDCached()
    if not specID then
        return false
    end
    local matches = 0
    for slot = 1, 19 do
        local itemId = GetInventoryItemID and GetInventoryItemID("player", slot)
        if itemId then
            local success, bonusSpellIDs =
                pcall(C_Item.GetSetBonusesForSpecializationByItemID, specID, itemId)
            if success and type(bonusSpellIDs) == "table" then
                for _, ident in ipairs(bonusSpellIDs) do
                    if ident == spellId then
                        matches = matches + 1
                        break
                    end
                end
            end
        end
    end
    return matches >= 2
end

-- Channel tick marks: vertical marks on the cast bar for channeled spells
-- listed in CHANNEL_TICK_DATA. The penultimate tick (last safe chain/clip
-- point) draws slightly wider in gold. Layout mirrors the empower pip code above.
ShowChannelTicks = function(spellId)
    if not castBarFrame then
        return
    end
    -- Stashed so a mid-channel bar rebuild can re-show this channel's marks
    -- (see the BuildCastBar tail). Stale values are inert: the re-show gates
    -- on _channeling, and every channel start restores the stash.
    castBarFrame._tickSpellID = spellId
    local callback = ERB.db.profile.castBar
    if not callback.showChannelTicks then
        return
    end

    local tickData = CHANNEL_TICK_DATA[spellId]
    local wantTicks = tickData and (callback.showTickMarks or callback.showLastTick)

    -- Nothing to draw: hide stale marks and bail
    if not wantTicks then
        for index = 1, #castBarFrame._ticks do
            castBarFrame._ticks[index]:Hide()
        end
        castBarFrame._numTicks = 0
        if castBarFrame._gcdMark then
            castBarFrame._gcdMark:Hide()
        end
        return
    end

    local barFrame = castBarFrame._bar
    local barWidth = barFrame:GetWidth()
    local barHeight = barFrame:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    -- Physical-pixel helpers (same approach as empower pips): PP.perfect /
    -- effectiveScale is one PHYSICAL pixel in the bar's local units, so mark
    -- widths are exact physical pixel counts at every UI scale. The old
    -- effectiveScale rounding treated the target as UI units and drifted
    -- between 1 and 3 physical pixels depending on scale.
    local effectiveScale = barFrame:GetEffectiveScale()
    local PPc = CludesUI and CludesUI.PP
    local onePx = ((PPc and PPc.perfect) or 1) / effectiveScale
    local tickWidth = 2 * onePx
    local highlightWidth = 3 * onePx
    local snappedHeight = (PPc and PPc.SnapForES) and PPc.SnapForES(barHeight, effectiveScale) or barHeight

    -- Tick marks
    if wantTicks then
        -- Interior mark positions as fractions of elapsed channel time
        -- (ascending; the LAST entry is the gold last-safe-clip mark).
        -- Three cadence models:
        --   ticks = N         : N evenly spaced damage events ending at the
        --                       channel end -> marks at i/N
        --   tickInterval = s  : fixed short cadence -> floor(duration/s) segments
        --   intervalCount = N : damage lands AT channel start, then once every
        --                       duration/N. Marks sit on each later event, and
        --                       a recast begun BEFORE the old channel ended
        --                       (proc-driven chaining) inherits the outgoing
        --                       cast's rhythm: its first mark lands where the
        --                       old cadence's next tick was due, and the
        --                       channel runs carry + N intervals, so the
        --                       interval is the window AFTER the carry over N
        --                       (dividing the whole window stretches every
        --                       later mark late by carry/N). Haste and
        --                       whole-cast talents are absorbed by working in
        --                       fractions of the ACTUAL duration; only
        --                       interval-only modifiers change N.
        local positions
        if tickData.intervalCount then
            local dur = castBarFrame._endTime - castBarFrame._startTime
            if dur > 0 then
                local N = tickData.intervalCount
                if tickData.modSpell and IsPlayerSpell(tickData.modSpell) then
                    N = tickData.modIntervalCount or N
                end
                local startT = castBarFrame._startTime
                -- Chain carry is computed ONCE per cast and cached: duration
                -- updates re-enter here for the same cast, and re-starts
                -- within 0.5s are duplicate events for the SAME channel
                -- (hover-style refires), never a chain.
                local tracked = castBarFrame._cadStart
                if not tracked or (startT - tracked) >= 0.5 then
                    local carry = 0
                    local pEnd = castBarFrame._cadPrevEnd
                    local pInt = castBarFrame._cadPrevInterval
                    if pEnd and pInt and pInt > 0 and startT < pEnd - 0.01 then
                        carry = math.fmod(pEnd - startT, pInt)
                        if carry < 0.01 then
                            carry = 0
                        end
                    end
                    castBarFrame._cadCarry = carry
                    castBarFrame._cadStart = startT
                end
                local carry = castBarFrame._cadCarry or 0
                local interval = (dur - carry) / N
                if interval <= 0.01 then
                    carry = 0
                    interval = dur / N
                end
                -- Bank this cast's TRUE cadence for a possible chain into the
                -- next: a chained cast's whole window over N is not its
                -- interval, and banking it would misplace a chain of chains.
                castBarFrame._cadPrevEnd = castBarFrame._endTime
                castBarFrame._cadPrevInterval = interval
                positions = {}
                local t = carry
                if t < 0.01 then
                    t = interval
                end
                while t < dur - interval * 0.05 and #positions < 12 do
                    positions[#positions + 1] = t / dur
                    t = t + interval
                end
            end
        elseif tickData.missiles then
            -- Fencepost cadence: the first missile fires AT channel start and
            -- the last AT channel end, so M missiles span M-1 intervals and
            -- interior marks sit at i/(M-1). A recast begun while the
            -- previous channel of the SAME spell was still running fires one
            -- missile immediately (at the bar start, no mark) and then keeps
            -- the OUTGOING cast's schedule: its first mark lands where the
            -- old cadence's next missile was due, and the channel runs that
            -- much longer -- one more interior mark than a fresh cast.
            local M = tickData.missiles
            if tickData.addMissiles then
                for ident, extra in pairs(tickData.addMissiles) do
                    -- Talent, player aura, or item set bonus -- any counts.
                    if
                        IsPlayerSpell(ident)
                        or (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(
                            ident
                        ))
                        or IsSetBonusSpellActive(ident)
                    then
                        M = M + extra
                    end
                end
            end
            local dur = castBarFrame._endTime - castBarFrame._startTime
            local startT = castBarFrame._startTime
            -- Chain carry is computed ONCE per cast, keyed on the channel
            -- castID: a mid-cast CHANNEL_UPDATE can re-time the reported
            -- window while the live channel keeps its snapshotted cadence
            -- (observed with Bloodlust landing mid-channel), and hover
            -- refires duplicate events -- both re-enter here for the SAME
            -- cast and must not chain the cast onto itself. The 0.5s start
            -- window is the fallback when no castID is available.
            local castID = castBarFrame._castID
            local sameCast
            if castID and castBarFrame._mslCastID then
                sameCast = (castID == castBarFrame._mslCastID)
            else
                sameCast = castBarFrame._mslStart and (startT - castBarFrame._mslStart) < 0.5
            end
            if not sameCast then
                local carry = 0
                local pEnd = castBarFrame._mslPrevEnd
                local pInt = castBarFrame._mslPrevInterval
                if
                    castBarFrame._mslPrevSpell == spellId
                    and pEnd
                    and pInt
                    and pInt > 0
                    and startT < pEnd - 0.01
                then
                    -- The missile grid is anchored at the channel END, so
                    -- time-to-next-missile is (pEnd - startT) mod pInt.
                    carry = math.fmod(pEnd - startT, pInt)
                    -- Near-zero carry is grid-aligned, and a recast right
                    -- after a missile (carry ~= a full interval) has been
                    -- observed to LOSE the bonus missile: both lay out
                    -- like a fresh cast.
                    if carry < 0.01 or carry > pInt - 0.05 then
                        carry = 0
                    end
                end
                castBarFrame._mslCarry = carry
                castBarFrame._mslCastID = castID
                castBarFrame._mslStart = startT
            end
            local carry = castBarFrame._mslCarry or 0
            -- Chained layout: the reported duration is carry plus M-1
            -- intervals, so marks sit at carry + k*interval as fractions of
            -- the reported window.
            local chained = false
            if carry > 0 and dur > 0 then
                local interval = (dur - carry) / (M - 1)
                if interval > 0.01 then
                    positions = {}
                    local t = carry
                    while t < dur - interval * 0.05 and #positions < 12 do
                        positions[#positions + 1] = t / dur
                        t = t + interval
                    end
                    if #positions > 0 then
                        chained = true
                    else
                        positions = nil
                    end
                end
            end
            -- Fresh layout: pure fractions, independent of the reported
            -- window. Also the fallback when the chained math degenerates
            -- (carry at or past the reported end, non-positive duration), so
            -- a mid-channel re-report can never blank the marks outright.
            if not positions then
                positions = {}
                for index = 1, min(M - 2, 12) do
                    positions[index] = index / (M - 1)
                end
            end
            -- Bank this cast's cadence for a possible chain into the next.
            if dur > 0 then
                castBarFrame._mslPrevEnd = castBarFrame._endTime
                castBarFrame._mslPrevInterval = (chained and (dur - carry) or dur) / (M - 1)
                castBarFrame._mslPrevSpell = spellId
            end
        else
            local numTicks
            if tickData.tickInterval then
                local channelDuration = castBarFrame._endTime - castBarFrame._startTime
                if channelDuration > 0 then
                    numTicks = floor(channelDuration / tickData.tickInterval)
                else
                    numTicks = 0
                end
            else
                numTicks = tickData.ticks
                if tickData.modSpell and IsPlayerSpell(tickData.modSpell) then
                    numTicks = tickData.modTicks
                end
            end
            if numTicks and numTicks > 1 then
                positions = {}
                for index = 1, numTicks - 1 do
                    positions[index] = index / numTicks
                end
            end
        end

        local count = positions and #positions or 0

        -- Pre-read colors once outside the loop
        local showTickMarks = callback.showTickMarks
        local showLastTick = callback.showLastTick
        local tmR, tmG, tmB, tmA =
            callback.tickMarksR or 1.0, callback.tickMarksG or 1.0, callback.tickMarksB or 1.0, callback.tickMarksA or 0.7
        local ltR, ltG, ltB, ltA =
            callback.lastTickR or 1.0, callback.lastTickG or 0.82, callback.lastTickB or 0.0, callback.lastTickA or 0.95

        for index = 1, count do
            local isLastTick = (index == count)

            -- Every index is filled, including the ones this pass hides: _ticks
            -- is walked with # (the stale-mark trims below, HideChannelTicks),
            -- so a hole at [1] would make the length 0 and end every sweep.
            local tick = castBarFrame._ticks[index]
            if not tick then
                tick = barFrame:CreateTexture(nil, "OVERLAY", nil, 3)
                -- Exact-width 1px-class art: keep the engine's texel
                -- snapping out of it or it re-rounds our aligned edges.
                if tick.SetSnapToPixelGrid then
                    tick:SetSnapToPixelGrid(false)
                    tick:SetTexelSnappingBias(0)
                end
                castBarFrame._ticks[index] = tick
            end

            if not showTickMarks and not isLastTick then
                tick:Hide()
            else
                local isGold = isLastTick and showLastTick
                local wid = isGold and highlightWidth or tickWidth
                -- The bar drains, so a mark at time-fraction f draws at
                -- (1 - f) of the width from the left. The center is snapped
                -- WIDTH-AWARE so both edges land on the physical grid -- an
                -- odd-pixel mark centered on a plain grid point straddles it
                -- and blurs.
                local rawOffset = barWidth * (1 - positions[index])
                local snappedOffset = (PPc and PPc.SnapCenterForDim)
                        and PPc.SnapCenterForDim(rawOffset, wid, effectiveScale)
                    or (floor(rawOffset * effectiveScale + 0.5) / effectiveScale)

                if isGold then
                    tick:SetColorTexture(ltR, ltG, ltB, ltA)
                else
                    tick:SetColorTexture(tmR, tmG, tmB, tmA)
                end
                tick:SetSize(wid, snappedHeight)

                tick:ClearAllPoints()
                tick:SetPoint("CENTER", barFrame, "LEFT", snappedOffset, 0)
                tick:Show()
            end
        end

        -- Hide extras from a previous channel that had more marks
        for index = count + 1, #castBarFrame._ticks do
            castBarFrame._ticks[index]:Hide()
        end

        castBarFrame._numTicks = count + 1
    else
        for index = 1, #castBarFrame._ticks do
            castBarFrame._ticks[index]:Hide()
        end
        castBarFrame._numTicks = 0
    end

    -- GCD boundary mark removed (UnitSpellHaste returns secret values in combat)
    if castBarFrame._gcdMark then
        castBarFrame._gcdMark:Hide()
    end
end

HideChannelTicks = function()
    if not castBarFrame or not castBarFrame._ticks then
        return
    end
    for index = 1, #castBarFrame._ticks do
        castBarFrame._ticks[index]:Hide()
    end
    castBarFrame._numTicks = 0
    if castBarFrame._gcdMark then
        castBarFrame._gcdMark:Hide()
    end
end

-- Cast/channel timer label. It shows one decimal, changing ~10x/sec while this runs
-- every frame: unconditional formatting would rebuild an identical string five of every
-- six frames (format+concat allocations plus SetText). Only touch the FontString when
-- the displayed tenth actually changes. On ns, not a file local.
function mod.SetCastTimerText(frame, nowTime, totalDurMode, totalSuffix, latSuffix)
    local remaining = frame._endTime - nowTime
    if frame._craftExtra then
        CludesUI.SetCraftTimerText(frame, frame._timerText, remaining, totalDurMode)
        return
    end
    if remaining > 0 then
        local isShown = totalDurMode and (nowTime - frame._startTime) or remaining
        local tenths = floor(isShown * 10)
        if tenths ~= frame._timerTenths then
            frame._timerTenths = tenths
            if totalDurMode then
                frame._timerText:SetText(format("%.1f", isShown) .. (totalSuffix or "") .. (latSuffix or ""))
            elseif latSuffix then
                frame._timerText:SetText(format("%.1f", isShown) .. latSuffix)
            else
                frame._timerText:SetText(format("%.1f", isShown))
            end
        end
    elseif frame._timerTenths ~= -1 then
        -- -1 marks "already blanked" so the empty case skips the re-SetText too.
        frame._timerTenths = -1
        frame._timerText:SetText("")
    end
end

-- Engine-driven cast fill, same plumbing as nameplate cast bars: hand the cast's
-- duration object to the inner StatusBar and the C engine animates the fill with
-- zero Lua per frame (pushback, haste, stage changes included). Falls back to
-- the Lua fill in UpdateCastBar when the duration API is unavailable or returns
-- nil. Re-called from DELAYED/CHANNEL_UPDATE/EMPOWER_UPDATE so a mid-cast time
-- change retargets the engine timer. Returns true when the timer is armed.
-- kind "craft" is a merged craft batch (Craft Batches: Merge Bar): the cast's
-- own duration covers one craft, so the bar takes a duration object of ours
-- over the whole batch (_startTime to _endTime), set again at every craft
-- start and pushback and never read back.
mod.ApplyCastTimer = function(kind)
    if not castBarFrame then
        return
    end
    castBarFrame._nativeFill = nil
    local barFrame = castBarFrame._bar
    local scrollBar = barFrame and barFrame._sb
    if not (scrollBar and scrollBar.SetTimerDuration and Enum and Enum.StatusBarTimerDirection) then
        return
    end
    local durObj, direction
    if kind == "channel" then
        durObj = UnitChannelDuration and UnitChannelDuration("player")
        direction = Enum.StatusBarTimerDirection.RemainingTime
    elseif kind == "empower" then
        -- true = include the hold-at-max window, matching the event mirrors
        durObj = UnitEmpoweredChannelDuration and UnitEmpoweredChannelDuration("player", true)
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    elseif kind == "craft" then
        local s, e = castBarFrame._startTime, castBarFrame._endTime
        if e > s and C_DurationUtil and C_DurationUtil.CreateDuration then
            durObj = castBarFrame._craftDur
            if not durObj then
                durObj = C_DurationUtil.CreateDuration()
                castBarFrame._craftDur = durObj
            end
            durObj:SetTimeFromStart(s, e - s)
        end
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    else
        durObj = UnitCastingDuration and UnitCastingDuration("player")
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    end
    if not durObj then
        return
    end
    scrollBar:SetTimerDuration(durObj, nil, direction)
    -- Snap to the timer's current position or the fill sweeps in from whatever
    -- value the previous cast left behind.
    if scrollBar.SetToTargetValue then
        scrollBar:SetToTargetValue()
    end
    castBarFrame._nativeFill = true
    return true
end

SetUpdateCastBar(function(dt)
    if not castBarFrame then
        return
    end
    -- NEVER gate this on IsShown(): SetElementVisibility fades an idle cast bar to
    -- alpha 0 instead of calling Hide(), so IsShown() is constant-true for the
    -- whole session and the entire body would run every frame with no cast in
    -- flight. The cast-state gate below is the real guard.
    if not (castBarFrame._casting or castBarFrame._empowering or castBarFrame._channeling) then
        return
    end

    local nowTime = GetTime()
    local barFrame = castBarFrame._bar

    -- Per-cast constants: none can change while a cast is in flight, so resolving
    -- them per frame is a three-deep config walk plus field reads 60x/sec.
    -- Resolved once per cast, keyed on start time (changes on every new cast and
    -- each channel update, so no stale cache is possible).
    if castBarFrame._cstKey ~= castBarFrame._startTime then
        castBarFrame._cstKey = castBarFrame._startTime
        local callback = ERB.db.profile.castBar
        castBarFrame._cstShowTimer = callback.showTimer
        castBarFrame._cstTotalMode = callback.showTimer and callback.showTotalDuration
        castBarFrame._cstEmpStages = callback.coloredEmpowerStages
        castBarFrame._cstFillAlpha = (callback.fillOpacity or 100) / 100
        -- The fill texture only changes on rebuild, so caching it here removes a
        -- GetStatusBarTexture call from the spark path below.
        castBarFrame._cstFillTex = barFrame:GetStatusBarTexture()
        -- bar:SetValue is NOT the widget method: BuildBar replaces it with a Lua
        -- vararg wrapper forwarding to the inner clipped StatusBar, for the
        -- optional "Smooth Bars" interpolation the cast bar never uses. Hold the
        -- inner bar and drive it directly instead of paying that call per frame.
        castBarFrame._cstSB = barFrame._sb
        -- Native easing between redraws (same mechanism as the GCD bar): the
        -- engine renders intermediate positions every frame, so the redraw rate
        -- can drop without visible stepping.
        -- Smooth Bar Animation off: plain SetValue at true progress, and no
        -- fill lead -- there is no ease to trail the timeline.
        local smooth = callback.smoothFill ~= false
        castBarFrame._cstInterp = smooth
                and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            or nil
        castBarFrame._cstLead = smooth and 0.08 or 0
        -- Raw mode hands the fill to the per-frame writer (below the cast
        -- tick): plain 20Hz SetValues visibly step, and the engine has no
        -- linear interpolation mode to carry them between redraws.
        castBarFrame._rawFill = not smooth
        if castBarFrame._rawFill and not castBarFrame._nativeFill and mod._rawFillDriver then
            mod._rawFillDriver:Show()
        end
        -- Out of Range Gray: armed for this cast only while the option is on and
        -- the spell has a range (self casts, crafting and mounts never read it).
        local spellRef = castBarFrame._spellID
        castBarFrame._cstRangeSpell = (callback.outOfRangeGray and spellRef and C_Spell.SpellHasRange(spellRef))
                and spellRef
            or nil
        castBarFrame._cstRangeAt = 0
    end
    -- Out of Range Gray: at most five target range reads a second, on this tick,
    -- during an armed cast; the fill repaints only when the answer flips.
    local rangeSpell = castBarFrame._cstRangeSpell
    if rangeSpell and nowTime >= castBarFrame._cstRangeAt then
        castBarFrame._cstRangeAt = nowTime + 0.2
        mod.ERB_CastRangeTint(C_Spell.IsSpellInRange(rangeSpell, "target") == false)
    end
    local showTimer = castBarFrame._cstShowTimer

    local latSuffix = castBarFrame._latencySuffix
    local totalDurMode = castBarFrame._cstTotalMode
    -- Cache the " / X.X" suffix once per cast (total duration is constant)
    local totalSuffix = totalDurMode and castBarFrame._totalDurSuffix

    if castBarFrame._casting or castBarFrame._empowering then
        -- Safety: if cast/empower ran 1s past expected end, force stop.
        -- Catches missed EMPOWER_STOP events under network desync.
        -- A merged craft batch checks the current craft's end, so a batch
        -- stopped between crafts goes idle too.
        local overrunAt = castBarFrame._craftCastEnd or castBarFrame._endTime
        if overrunAt and nowTime > overrunAt + 1 then
            OnCastStop()
            return
        end
        local castDur = castBarFrame._endTime - castBarFrame._startTime
        local progress = (castDur > 0) and ((nowTime - castBarFrame._startTime) / castDur) or 0
        progress = min(max(progress, 0), 1)
        -- The eased SetValue chases a target computed at the LAST 20Hz tick,
        -- so the drawn fill trails true time by roughly one tick plus the
        -- ease-out's convergence residue and dies ~4% short when the stop
        -- lands (measured: rendered 0.96 at dtEnd 0). Lead the fill target by
        -- tick + residue (user-calibrated; 0 when smoothing is off) so the
        -- ease converges ON the true timeline; stages and text below keep
        -- using true progress.
        local fillProgress = (castDur > 0)
                and ((nowTime + castBarFrame._cstLead - castBarFrame._startTime) / castDur)
            or 0
        fillProgress = min(max(fillProgress, 0), 1)
        -- Fill: only the fallback path draws from Lua. Progress is still computed
        -- above when the engine timer owns the fill (ns.ApplyCastTimer), because
        -- the empower stage coloring below derives its stage from it.
        -- Raw mode: the per-frame writer owns the fill instead.
        if not (castBarFrame._nativeFill or castBarFrame._rawFill) then
            if castBarFrame._cstSB then
                castBarFrame._cstSB:SetValue(fillProgress, castBarFrame._cstInterp)
            else
                barFrame:SetValue(fillProgress, castBarFrame._cstInterp)
            end
            -- Size the gradient clip frame to match the fill width
            if castBarFrame._gradientFullBar and castBarFrame._gradClip then
                castBarFrame._gradClip:SetWidth(max(0.01, barFrame:GetWidth() * fillProgress))
            end
        end

        -- Apply empowered stage coloring if enabled
        if
            castBarFrame._empowering
            and castBarFrame._cstEmpStages
            and not castBarFrame._rangeOut
            and not castBarFrame._uninterrupt
        then
            local numStages = castBarFrame._numStages or 0
            local stage = GetCurrentEmpowerStage(progress, numStages)
            local region, g, b = GetEmpowerStageColor(stage, numStages)

            -- Apply color to bar or gradient (fill alpha keeps Fill Opacity)
            if castBarFrame._gradientFullBar and castBarFrame._gradTex then
                empowerColorA:SetRGBA(region, g, b, 1)
                empowerColorB:SetRGBA(region, g, b, 1)
                castBarFrame._gradTex:SetGradient("HORIZONTAL", empowerColorA, empowerColorB)
            else
                castBarFrame._cstFillTex:SetVertexColor(region, g, b, castBarFrame._cstFillAlpha)
            end
            castBarFrame._empowerColorApplied = true
        end

        if showTimer then
            mod.SetCastTimerText(castBarFrame, nowTime, totalDurMode, totalSuffix, latSuffix)
        end
    elseif castBarFrame._channeling then
        -- Same 1s overrun safety the cast branch has. CHANNEL_UPDATE keeps
        -- _endTime current for every legitimate extension, so a channel still
        -- running a second past its end has lost its stop event -- and without
        -- this the bar has no way back to idle.
        if castBarFrame._endTime and nowTime > castBarFrame._endTime + 1 then
            OnCastStop()
            return
        end
        if not (castBarFrame._nativeFill or castBarFrame._rawFill) then
            local chanDur = castBarFrame._endTime - castBarFrame._startTime
            -- Same lead as the cast branch, mirrored for the drain
            -- (measured: channels ended rendered at 0.018 instead of 0).
            local progress = (chanDur > 0)
                    and ((castBarFrame._endTime - nowTime - castBarFrame._cstLead) / chanDur)
                or 0
            progress = min(max(progress, 0), 1)
            if castBarFrame._cstSB then
                castBarFrame._cstSB:SetValue(progress, castBarFrame._cstInterp)
            else
                barFrame:SetValue(progress, castBarFrame._cstInterp)
            end
            -- Size the gradient clip frame to match the fill width
            if castBarFrame._gradientFullBar and castBarFrame._gradClip then
                castBarFrame._gradClip:SetWidth(max(0.01, barFrame:GetWidth() * progress))
            end
        end
        if showTimer then
            mod.SetCastTimerText(castBarFrame, nowTime, totalDurMode, totalSuffix, latSuffix)
        end
    end

    -- Spark position. The spark anchors to the RIGHT edge of the fill and the
    -- engine already moves it as the fill grows, so re-anchoring to the same target
    -- costs two API calls for nothing. The target changes only on a gradient toggle.
    if castBarFrame._spark:IsShown() then
        local target
        if castBarFrame._gradientFullBar and castBarFrame._gradClip and castBarFrame._gradClip:IsShown() then
            target = castBarFrame._gradClip
        else
            target = castBarFrame._cstFillTex
        end
        if castBarFrame._sparkAnchor ~= target then
            castBarFrame._sparkAnchor = target
            castBarFrame._spark:ClearAllPoints()
            castBarFrame._spark:SetPoint("CENTER", target, "RIGHT", 0, 0)
        end
    end
end)

-- Per-cast latency: from the cast request (CURRENT_SPELL_CAST_CHANGED, tied to its cast
-- by the UNIT_SPELLCAST_SENT that follows) to the server starting it. A request made
-- mid-cast or mid-GCD is queued (its time includes the wait): not measured. Watched
-- only while the cast bar and its latency overlay are on; BuildCastBar syncs it.
local latSend = {}
local function LatencyRequestQueued()
    if UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil then
        return true
    end
    -- A GCD that began before this request belongs to an earlier spell. One that
    -- cannot be read counts as queued: a reading that cannot be checked is not taken.
    local cd = C_Spell.GetSpellCooldown(CludesUI.GCD_SPELL)
    local s, skinData = cd and cd.startTime, cd and cd.duration
    if not (s and skinData) then
        return false
    end
    if issecretvalue and (issecretvalue(s) or issecretvalue(skinData)) then
        return true
    end
    local nowTime = GetTime()
    return s > 0 and s < nowTime - 0.05 and s + skinData > nowTime
end
function mod.ERB_LatencySendWatch(on)
    local wid = latSend.frame
    if on and not wid then
        wid = CreateFrame("Frame")
        wid:SetScript("OnEvent", function(_, evt, arg1, _, _, spellId)
            if evt == "CURRENT_SPELL_CAST_CHANGED" then
                if not arg1 then
                    latSend.reqAt, latSend.reqQueued = GetTimePreciseSec(), LatencyRequestQueued()
                end
                return
            end
            -- The send claims the latest request (one request per send)
            latSend.at, latSend.queued = latSend.reqAt, latSend.reqQueued
            latSend.reqAt = nil
            latSend.spellID = not (issecretvalue and issecretvalue(spellId)) and spellId or nil
        end)
        latSend.frame = wid
    end
    if not wid then
        return
    end
    if on then
        wid:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
        wid:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    else
        wid:UnregisterAllEvents()
        latSend.at, latSend.reqAt, latSend.off = nil, nil, nil
    end
end

-- Latency overlay helper. Called once per cast/channel start: sizes the
-- overlay as this cast's latency over the total cast duration.
local function ShowLatencyOverlay(castType)
    if not castBarFrame then
        return
    end
    -- Channels use the front twin: the bar starts full, so the drain-side
    -- zone must draw above the fill to be visible at all. Casts keep the
    -- behind texture -- the fill sweeps over the zone as it completes.
    local behind = castBarFrame._latencyOverlay
    local front = castBarFrame._latencyOverlayFront
    local overlayFrame = (castType == "channel") and (front or behind) or behind
    local other = (overlayFrame == front) and behind or front
    if other then
        other:Hide()
    end
    if not overlayFrame then
        return
    end

    local callback = ERB.db.profile.castBar
    if not callback.latencyEnabled then
        overlayFrame:Hide()
        castBarFrame._latencySuffix = nil
        return
    end

    -- Live network latency (world, home until world is measured): a rolling
    -- average, so only the fallback's base and the sanity bound for this cast's reading.
    local _, _, latencyHome, latencyWorld = GetNetStats()
    local latencyMs = latencyWorld
    if latencyMs <= 0 then
        latencyMs = latencyHome
    end
    local netSec = latencyMs / 1000
    -- This cast's request-to-start time (precise clock). Queued, mismatched or out
    -- of range readings are skipped; those casts take the network average plus how
    -- far clean readings run above it (server processing, frame timing), smoothed
    -- so no single reading decides and a new route follows the average.
    local latencySec
    local sentAt = latSend.at
    latSend.at = nil
    local spellRef = castBarFrame._spellID
    local match = not latSend.spellID
        or (issecretvalue and issecretvalue(spellRef))
        or latSend.spellID == spellRef
    if sentAt and not latSend.queued and match then
        local skinData = GetTimePreciseSec() - sentAt
        if skinData > 0.01 and skinData < netSec + 0.25 then
            latencySec = skinData
            if netSec > 0 then
                local off, previous = skinData - netSec, latSend.off
                latSend.off = previous and (previous + (off - previous) * 0.3) or off
            end
        end
    end
    if not latencySec then
        latencySec = netSec > 0 and max(netSec + (latSend.off or 0), 0.01) or 0
    end
    local castDur = castBarFrame._endTime - castBarFrame._startTime
    local barWidth = castBarFrame._bar:GetWidth()

    if latencySec <= 0 or castDur <= 0 or barWidth <= 0 then
        overlayFrame:Hide()
        castBarFrame._latencySuffix = nil
        return
    end

    -- Build the suffix string once; reused every frame by UpdateCastBar
    if callback.latencyShowText then
        castBarFrame._latencySuffix = " (" .. floor(latencySec * 1000 + 0.5) .. "ms)"
    else
        castBarFrame._latencySuffix = nil
    end

    -- Size as a fraction of the cast, clamped to [1px, full bar] so it always
    -- renders something and never overruns the bar on a lag spike.
    local width = barWidth * (latencySec / castDur)
    if width < 1 then
        width = 1
    elseif width > barWidth then
        width = barWidth
    end

    local clip = castBarFrame._barClip
    overlayFrame:ClearAllPoints()
    if castType == "channel" then
        overlayFrame:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
        overlayFrame:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", 0, 0)
    else
        overlayFrame:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        overlayFrame:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
    end
    overlayFrame:SetWidth(width)
    overlayFrame:Show()
end

local function HideLatencyOverlay()
    if not castBarFrame then
        return
    end
    if castBarFrame._latencyOverlay then
        castBarFrame._latencyOverlay:Hide()
    end
    if castBarFrame._latencyOverlayFront then
        castBarFrame._latencyOverlayFront:Hide()
    end
    castBarFrame._latencySuffix = nil
end

-- Cast bar background anchoring. At Fill Opacity 100 the background spans the
-- whole frame. Below 100 it anchors to the fill texture's moving right edge so
-- the translucent fill reveals the world behind it -- the anchor is
-- relational, so it tracks cast progress on its own. An idle bar has no fill to
-- trail and that anchoring would leave the spell icon's slot uncovered, so the
-- idle state always spans the frame.
function mod.ApplyCastBgAnchor()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar
    -- The Blizzard texture draws an atlas background that always spans the
    -- frame; BuildCastBar anchors that one itself. Same for Blizzard Style
    -- (the build stamp, never the profile: the style is latched per session).
    if callback.texture == "blizzard" or castBarFrame._blizzFill then
        return
    end
    local barFrame = castBarFrame._bar
    local casting = castBarFrame._casting or castBarFrame._channeling or castBarFrame._empowering
    castBarFrame._bg:ClearAllPoints()
    if casting and (callback.fillOpacity or 100) < 100 then
        castBarFrame._bg:SetPoint("TOPLEFT", barFrame:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        castBarFrame._bg:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    else
        castBarFrame._bg:SetAllPoints(castBarFrame)
    end
end

-- Idle / active cast bar state. Every path that ends a cast routes through
-- ns.ShowIdleCastBar, so the idle look never depends on how the cast finished.
-- With "Always Show" off it fades to alpha 0; with it on the frame stays on
-- screen showing just background and border. ns.ActivateCastBar is the mirror
-- image: undoes whatever the idle state suppressed for a live cast.
function mod.ShowIdleCastBar()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar

    -- Empty the fill. A plain SetValue also cancels the engine-driven cast
    -- timer armed by ns.ApplyCastTimer, which would otherwise keep animating
    -- the fill from the finished cast's duration object.
    castBarFrame._bar:SetValue(0)
    castBarFrame._nativeFill = nil
    castBarFrame._cstKey = nil
    castBarFrame._craftMerge, castBarFrame._craftCastEnd = nil, nil
    mod.ERB_CraftStopWatch(false)
    if mod._rawFillDriver then
        mod._rawFillDriver:Hide()
    end
    if castBarFrame._castUninterruptible or castBarFrame._channelPaint then
        castBarFrame._castUninterruptible = nil
        mod.ERB_CastOverrideApply(true)
    end
    if castBarFrame._rangeOut then
        mod.ERB_CastRangeTint(false)
    end

    -- Cast decoration has nothing to show without a cast. The spark in
    -- particular is anchored to the RIGHT edge of the fill, so at value 0 it
    -- would sit as a sliver on the empty bar's left edge.
    castBarFrame._nameText:SetText("")
    castBarFrame._timerText:SetText("")
    castBarFrame._timerTenths = -1 -- "already blanked" (see ns.SetCastTimerText)
    if castBarFrame._iconFrame then
        castBarFrame._iconFrame:Hide()
    end
    if castBarFrame._spark then
        castBarFrame._spark:Hide()
    end
    if castBarFrame._pips then
        for index = 1, #castBarFrame._pips do
            castBarFrame._pips[index]:Hide()
        end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()
    HideLatencyOverlay()
    mod.ApplyCastBgAnchor()

    if callback.alwaysShow and callback.enabled and not mod._erbCastPadHidden then
        castBarFrame:Show()
        CludesUI.SetElementVisibility(castBarFrame, true)
    else
        CludesUI.SetElementVisibility(castBarFrame, false)
    end
end

function mod.ActivateCastBar()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar
    -- The idle state hides the spark unconditionally; a live cast brings it
    -- back if the user wants one. The icon is owned by the per-cast code,
    -- which knows whether the spell actually has one.
    if castBarFrame._spark then
        castBarFrame._spark:SetShown(callback.showSpark and true or false)
    end
    mod.ApplyCastBgAnchor()
    castBarFrame:Show()
    CludesUI.SetElementVisibility(castBarFrame, true)
end

-- Spell name plus its rank subtext ("Name (Rank 2)") when Show Spell Rank is on.
-- Spell ranks exist only on WoW Forever (retail's subtext is "Racial" and the
-- like), so the option and this read are Forever-only.
function mod.CastDisplayName(callback, name, spellId)
    name = CludesUI.CleanCastName(name)
    if callback.showSpellRank and spellId and CludesUI.IS_FOREVER then
        local rank = C_Spell.GetSpellSubtext(spellId)
        if rank and rank ~= "" then
            return name .. " (" .. rank .. ")"
        end
    end
    return name
end

-- Show Full Spell Name: shrink the spell text to fit its width instead of
-- cutting it off (player cast names are always clean strings).
function mod.ERB_FitCastName(callback)
    local frame = castBarFrame
    if not (frame and callback.showSpellText) then
        return
    end
    local fontStr = frame._nameText
    -- The layout's timer slot fits a plain countdown; Show Total Duration,
    -- latency text and Full Craft Time write wider strings. Size the name's
    -- room (and its push, when it shares the timer's side) off the widest one
    -- this cast will show. Blizzard Style moves the name off the bar.
    if callback.showTimer and frame._endTime and frame._startTime and not mod.ERB_CastBlizz() then
        local sum = callback.showTotalDuration
        local sample
        if frame._craftExtra and frame._craftTotal then
            local t = frame._craftTotal
            sample = format("%d:%02d", floor(t / 60), t % 60) .. (sum and frame._craftTotalSuffix or "")
        else
            sample = format("%.1f", frame._endTime - frame._startTime)
                .. (sum and (frame._totalDurSuffix or "") or "")
                .. (frame._latencySuffix or "")
        end
        local timerW = max((callback.timerSize or 11) * 2.2, CludesUI.MeasureCastText(frame._timerText, sample) + 6)
        local barFrame = frame._bar
        local barW = barFrame:GetWidth()
        if not barW or barW < 10 then
            barW = callback.width
        end
        local spellSide = callback.spellTextSide or "left"
        if (callback.timerSide or "right") == spellSide then
            local pt, xb = mod.GetCastTextAnchor(spellSide, true, timerW)
            fontStr:ClearAllPoints()
            fontStr:SetPoint(pt, barFrame, pt, xb + (callback.spellTextX or 0), callback.spellTextY or 0)
        end
        fontStr:SetWidth(max(20, barW - 8 - (spellSide == "center" and 2 or 1) * timerW))
    end
    CludesUI.FitCastName(fontStr, fontStr:GetText(), callback.spellTextSize or 11)
end

OnCastStart = function()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar
    if not callback.enabled or mod._erbCastPadHidden then
        return
    end

    local name, _, _, startTimeMS, endTimeMS, isTradeSkill, _, notInterruptible, spellId, barID =
        UnitCastingInfo("player")
    if not name then
        return
    end
    local castDurSec = (endTimeMS - startTimeMS) / 1000
    CludesUI.SetCraftBatch(
        castBarFrame,
        (callback.fullCraftTime or callback.mergeCrafts) and isTradeSkill,
        spellId,
        barID,
        castDurSec
    )

    -- Merge Bar: one bar spans the whole batch. The batch start is kept
    -- from the first craft (or backdated by the crafts done). _craftExtra becomes
    -- 0 (queued time now lives in _endTime) so the craft timer reads the batch end.
    local merge = callback.mergeCrafts and castBarFrame._craftExtra
    local batchStart = merge
            and castBarFrame._craftMerge
            and castBarFrame._craftDone > 0
            and castBarFrame._startTime
        or startTimeMS / 1000 - (merge and castBarFrame._craftDone * castDurSec or 0)
    castBarFrame._casting = true
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = barID
    if merge then
        castBarFrame._craftMerge = true
        mod.ERB_CraftStopWatch(true)
        castBarFrame._craftCastEnd = endTimeMS / 1000
        castBarFrame._startTime = batchStart
        castBarFrame._endTime = endTimeMS / 1000 + castBarFrame._craftExtra
        castBarFrame._craftExtra = 0
    else
        castBarFrame._craftMerge = nil
        castBarFrame._craftCastEnd = nil
        castBarFrame._startTime = startTimeMS / 1000
        castBarFrame._endTime = endTimeMS / 1000
    end
    castBarFrame._spellName = name
    castBarFrame._spellID = spellId
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(
        mod.CastDisplayName(callback, name, spellId)
            .. (castBarFrame._craftExtra and castBarFrame._craftCountSuffix or "")
    )
    mod.ERB_SetBlizzCastFill("cast")
    mod.ERB_CastOverrideStart(callback, notInterruptible)
    -- The engine timer animates the fill (a merged batch over the whole
    -- batch); the Lua fill is the fallback.
    if not mod.ApplyCastTimer(merge and "craft" or "cast") then
        local s, e = castBarFrame._startTime, castBarFrame._endTime
        local initProgress = (e > s) and ((GetTime() - s) / (e - s)) or 0
        castBarFrame._bar:SetValue(min(max(initProgress, 0), 1))
    end

    -- Hide empower pips
    if castBarFrame._pips then
        for index = 1, #castBarFrame._pips do
            castBarFrame._pips[index]:Hide()
        end
    end
    castBarFrame._numStages = 0
    HideChannelTicks()

    do
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    ShowLatencyOverlay("cast")
    -- After the latency overlay: its " (NNms)" suffix widens the timer.
    if callback.fitSpellName then
        mod.ERB_FitCastName(callback)
    end

    mod.ActivateCastBar()
end

OnChannelStart = function()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar
    if not callback.enabled or mod._erbCastPadHidden then
        return
    end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellId, _, _, channelCastID =
        UnitChannelInfo("player")
    if not name then
        -- UnitChannelInfo can be empty on rapid channel restarts (e.g. SCK spam).
        -- Single retry on the next frame; if still nil the channel was cancelled.
        if not castBarFrame._channelRetry then
            castBarFrame._channelRetry = true
            C_Timer.After(0, function()
                castBarFrame._channelRetry = nil
                OnChannelStart()
            end)
        end
        return
    end

    castBarFrame._casting = false
    castBarFrame._channeling = true
    castBarFrame._empowering = false
    castBarFrame._craftExtra = nil
    castBarFrame._craftMerge, castBarFrame._craftCastEnd = nil, nil
    castBarFrame._castID = channelCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._spellID = spellId
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    castBarFrame._nameText:SetText(mod.CastDisplayName(callback, name, spellId))
    mod.ERB_SetBlizzCastFill("channel")
    mod.ERB_CastOverrideStart(callback, notInterruptible)
    if not mod.ApplyCastTimer("channel") then
        local chanDur = endTimeMS - startTimeMS
        local initProgress = (chanDur > 0) and ((endTimeMS / 1000 - GetTime()) / (chanDur / 1000)) or 1
        castBarFrame._bar:SetValue(min(max(initProgress, 0), 1))
    end

    -- Hide empower pips
    if castBarFrame._pips then
        for index = 1, #castBarFrame._pips do
            castBarFrame._pips[index]:Hide()
        end
    end
    castBarFrame._numStages = 0

    do
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Channel tick marks
    ShowChannelTicks(spellId)

    ShowLatencyOverlay("channel")
    if callback.fitSpellName then
        mod.ERB_FitCastName(callback)
    end

    mod.ActivateCastBar()
end

OnChannelUpdate = function()
    if not castBarFrame then
        return
    end
    if not castBarFrame._channeling then
        return
    end

    local name, _, _, startTimeMS, endTimeMS, _, _, spellId = UnitChannelInfo("player")
    if not name then
        return
    end

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    mod.ApplyCastTimer("channel")

    -- Recompute tick mark and GCD boundary positions for new duration
    if spellId then
        ShowChannelTicks(spellId)
    end
end

-- Called for UNIT_SPELLCAST_STOP only (normal cast completion).
-- Ignores the event if the castID doesn't match the active cast -- this
-- prevents hiding the bar when a new cast has already started.
local function OnCastComplete(eventCastID)
    if not castBarFrame then
        return
    end
    if not castBarFrame._casting then
        return
    end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then
        return
    end
    -- Merge Bar: more crafts queued, keep the bar running into the next one.
    if castBarFrame._craftMerge and (castBarFrame._craftLeft or 0) > 0 then
        return
    end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    mod.ShowIdleCastBar()
end

-- Called for UNIT_SPELLCAST_FAILED / INTERRUPTED. These fire for the spell that FAILED,
-- which may be a completely different spell than the one currently being cast (e.g.
-- pressing an instant while casting). Only hide if the castID matches our active cast.
local function OnCastFailed(eventCastID)
    if not castBarFrame then
        return
    end
    if not castBarFrame._casting then
        return
    end
    if not eventCastID or not castBarFrame._castID or eventCastID ~= castBarFrame._castID then
        -- Merged craft batch: a cancelled craft can report another ID; end it
        -- once nothing is casting.
        if not castBarFrame._craftMerge or UnitCastingInfo("player") then
            return
        end
    end
    castBarFrame._casting = false
    castBarFrame._castID = nil
    mod.ShowIdleCastBar()
end

-- Called for UNIT_SPELLCAST_CHANNEL_STOP. Deliberately matches no ID: castBarID
-- is documented Nilable on BOTH UnitChannelInfo and this event's payload, so an
-- equality test rejects real stops. Blizzard's own CastingBarFrame matches a
-- castID for plain casts only and accepts any channel/empower stop, which is
-- what OnEmpowerStop below already does. Instead the live channel is re-queried:
-- an instantly restarted channel (Clearcasting Arcane Missiles) can deliver the
-- OLD channel's STOP after the NEW channel's START, and that late stop must not
-- tear down the bar that is still channeling. The opposite order happens too:
-- a channel re-issued mid-flight (Hover cast during Disintegrate) can deliver
-- its STOP in a frame where UnitChannelInfo is already empty and the re-issuing
-- START has not landed, so going idle here blanks the bar for that frame and
-- the retry in OnChannelStart rebuilds it from scratch. Re-check next frame;
-- a real channel end reads empty both times.
local function OnChannelStop()
    if not castBarFrame then
        return
    end
    if not castBarFrame._channeling then
        return
    end
    if UnitChannelInfo("player") then
        return
    end
    if castBarFrame._channelStopPending then
        return
    end
    castBarFrame._channelStopPending = true
    C_Timer.After(0, function()
        castBarFrame._channelStopPending = nil
        if not castBarFrame._channeling then
            return
        end
        local name, _, _, _, _, _, _, _, empowering = UnitChannelInfo("player")
        if name then
            -- An empower dispatched in the emptied frame was declined by
            -- OnEmpowerStart, which has no retry; pick it up here.
            if empowering then
                OnEmpowerStart()
            end
            return
        end
        castBarFrame._channeling = false
        castBarFrame._castID = nil
        mod.ShowIdleCastBar()
    end)
end

-- Put the configured fill back after a tint (empower stages, Out of Range
-- Gray): Blizzard Style white, the gradient re-issued, or the solid colour.
-- On ns.
mod.ERB_RestoreCastFill = function()
    local callback = ERB.db.profile.castBar
    -- Blizzard Style (build stamp): the fill atlas is its own colour; restore plain white.
    if castBarFrame._blizzFill then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, (callback.fillOpacity or 100) / 100)
        return
    end
    -- An uninterruptible cast under the Uninterruptible Color Override: its solid
    -- colour, ahead of the channel override.
    if castBarFrame._uninterrupt then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(
            callback.uninterruptibleR or 0.5,
            callback.uninterruptibleG or 0.5,
            callback.uninterruptibleB or 0.5,
            (callback.fillOpacity or 100) / 100
        )
        return
    end
    -- A channel under the Channel Color Override: its solid colour.
    if castBarFrame._channelPaint then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(
            callback.channelR or 0.3,
            callback.channelG or 0.8,
            callback.channelB or 0.3,
            (callback.fillOpacity or 100) / 100
        )
        return
    end
    local fR, fG, fB, fA = callback.fillR, callback.fillG, callback.fillB, 1
    if callback.classColored then
        local cc = CLASS_COLORS[cachedClass]
        if cc then
            fR, fG, fB = cc[1], cc[2], cc[3]
        end
    end
    if castBarFrame._gradientFullBar and castBarFrame._gradTex then
        empowerColorA:SetRGBA(fR, fG, fB, fA)
        empowerColorB:SetRGBA(callback.gradientR or fR, callback.gradientG or fG, callback.gradientB or fB, callback.gradientA or fA)
        castBarFrame._gradTex:SetGradient(callback.gradientDir or "HORIZONTAL", empowerColorA, empowerColorB)
    elseif callback.gradientEnabled then
        -- Re-ISSUE the gradient, do not just neutralise the vertex color.
        -- SetVertexColor REPLACES a texture's gradient rather than
        -- multiplying it, so the per-stage empower tint (which paints this
        -- exact texture with SetVertexColor) already destroyed the configured
        -- gradient. Whitening the vertex color therefore left a plain WHITE
        -- fill, and nothing restored it: the gradient is issued only where the
        -- bar is built, so every later cast in the session stayed white until a
        -- config edit or reload rebuilt the bar. The full-bar branch above
        -- already re-issues for the same reason. Fill Opacity is baked into
        -- both endpoint alphas, matching the build path.
        local fillTex = castBarFrame._bar:GetStatusBarTexture()
        local fillOp = (callback.fillOpacity or 100) / 100
        fillTex:SetVertexColor(1, 1, 1, 1)
        empowerColorA:SetRGBA(fR, fG, fB, fA * fillOp)
        empowerColorB:SetRGBA(
            callback.gradientR or fR,
            callback.gradientG or fG,
            callback.gradientB or fB,
            (callback.gradientA or fA) * fillOp
        )
        fillTex:SetGradient(callback.gradientDir or "HORIZONTAL", empowerColorA, empowerColorB)
    else
        local fillTex = castBarFrame._bar:GetStatusBarTexture()
        fillTex:SetVertexColor(fR, fG, fB, fA * ((callback.fillOpacity or 100) / 100))
    end
end

-- Undo the per-stage empower tint. Shared by OnEmpowerStop and OnCastStop: the
-- 1s-overrun safety path routes a missed EMPOWER_STOP through OnCastStop, which
-- clears _empowering, and OnEmpowerStop then early-returns on that very flag --
-- so without this call there the stage tint stayed painted for the rest of the
-- session, the same stuck-fill symptom by a second route.
mod.ResetEmpowerFillColor = function()
    if not (castBarFrame and castBarFrame._empowerColorApplied) then
        return
    end
    castBarFrame._empowerColorApplied = false
    mod.ERB_RestoreCastFill()
end

-- Out of Range Gray (castBar.outOfRangeGray): the fill turns gray while the
-- target is out of the cast's range and takes its configured paint back when it
-- returns or the cast ends. Writes only on a flip.
mod.ERB_CastRangeTint = function(result)
    if (castBarFrame._rangeOut or false) == result then
        return
    end
    castBarFrame._rangeOut = result or nil
    if result then
        castBarFrame._bar:GetStatusBarTexture():SetVertexColor(0.4, 0.4, 0.4, castBarFrame._cstFillAlpha or 1)
    else
        mod.ERB_RestoreCastFill()
    end
end

-- Fill colour overrides (both off by default), each a solid colour over the
-- configured fill (over a gradient too, which comes back after):
--   Channel Color Override (castBar.channelOverride): a channel, empowers
--   excepted (their stage colours own them).
--   Uninterruptible Color Override (castBar.uninterruptibleOverride): a cast
--   the player cannot be interrupted out of, read at each start and on the
--   interruptible flips of a live cast (a restricted answer counts as
--   interruptible). It wins over the channel colour.
-- Repaints only on a change. Out of Range Gray stays on top; the empower stage
-- colours wait. Not under Blizzard Style, whose fill art is stock. idle = the
-- bar just went idle: both overrides clear.
mod.ERB_CastOverrideApply = function(idle)
    local callback = ERB.db.profile.castBar
    local live = not idle and not castBarFrame._blizzFill
    local un = (live and callback.uninterruptibleOverride and castBarFrame._castUninterruptible) and true or false
    local ch = (live and callback.channelOverride and castBarFrame._channeling and not castBarFrame._empowering)
            and true
        or false
    if (castBarFrame._uninterrupt or false) == un and (castBarFrame._channelPaint or false) == ch then
        return
    end
    castBarFrame._uninterrupt = un or nil
    castBarFrame._channelPaint = ch or nil
    if not castBarFrame._rangeOut then
        mod.ERB_RestoreCastFill()
    end
end
-- From the cast, channel and empower starts: one field test while both options
-- are off and no override is painted.
mod.ERB_CastOverrideStart = function(callback, notInterruptible)
    if
        not (
            callback.uninterruptibleOverride
            or callback.channelOverride
            or castBarFrame._uninterrupt
            or castBarFrame._channelPaint
        )
    then
        return
    end
    castBarFrame._castUninterruptible = (not issecretvalue(notInterruptible) and notInterruptible) and true
        or false
    mod.ERB_CastOverrideApply()
end
-- The flips are watched only while the option applies (the cast bar on, not
-- Blizzard Style); BuildCastBar syncs it.
do
    local watch
    function mod.ERB_SyncUninterruptWatch(on)
        if on then
            if not watch then
                watch = CreateFrame("Frame")
                watch:SetScript("OnEvent", function(_, evt)
                    if
                        not (
                            castBarFrame
                            and (
                                castBarFrame._casting
                                or castBarFrame._channeling
                                or castBarFrame._empowering
                            )
                        )
                    then
                        return
                    end
                    castBarFrame._castUninterruptible = evt == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
                    mod.ERB_CastOverrideApply()
                end)
            end
            watch:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "player")
            watch:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "player")
        elseif watch then
            watch:UnregisterAllEvents()
        end
    end
end

-- Merge Bar: a cancelled batch (movement, Escape) ends the merged bar.
-- Watched only while a merged batch is on the bar.
do
    local watch
    function mod.ERB_CraftStopWatch(on)
        if on then
            if not watch then
                watch = CreateFrame("Frame")
                watch:SetScript("OnEvent", function()
                    if castBarFrame and castBarFrame._craftMerge and not UnitCastingInfo("player") then
                        OnCastStop()
                    end
                end)
            end
            watch:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
        elseif watch then
            watch:UnregisterAllEvents()
        end
    end
end

-- Called for UNIT_SPELLCAST_EMPOWER_STOP.
local function OnEmpowerStop(eventCastID)
    if not castBarFrame then
        return
    end
    if not castBarFrame._empowering then
        return
    end
    -- Accept any empower stop while we're empowering. Strict castID
    -- matching can reject valid stops due to event desync under load.
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    if castBarFrame._pips then
        for index = 1, #castBarFrame._pips do
            castBarFrame._pips[index]:Hide()
        end
    end
    castBarFrame._numStages = 0

    -- Reset empower stage coloring if it was applied
    mod.ResetEmpowerFillColor()

    SetStageThresholds(nil)

    mod.ShowIdleCastBar()
end

OnCastStop = function()
    if not castBarFrame then
        return
    end
    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = false
    castBarFrame._castID = nil
    castBarFrame._craftExtra = nil
    -- The overrun safety path forces a stop here on a missed EMPOWER_STOP, and
    -- clearing _empowering above is exactly what makes OnEmpowerStop early-return
    -- later, so this is the only chance to undo the stage tint.
    mod.ResetEmpowerFillColor()
    -- Pip textures, channel ticks and the latency overlay are all cleared by
    -- the idle pass below.
    mod.ShowIdleCastBar()
end

-- Blizzard's player cast bar is ours to hide while our cast bar is on, except
-- while ours stands down for the controller under WoW Forever's Gamepad
-- interface style: from build 70425 that style draws the cast on Blizzard's
-- player bar itself.
function mod.RB_SyncBlizzCastSuppress()
    local callback = ERB.db and ERB.db.profile and ERB.db.profile.castBar
    local on = callback and callback.enabled and not (mod._erbCastPadHidden and CludesUI.PadGamepadUI())
    CludesUI.SetPlayerCastBarSuppressed("ResourceBars", on and true or false)
end

-- Hide While Using Gamepad (Global Settings > Gamepad): Blizzard's gamepad UI
-- draws its own player cast bar, so this one stands down while
-- CludesUI.PadModeOn says gamepad mode is on (WoW Forever's Gamepad
-- interface style, elsewhere a connected controller). A runtime flag (ns._erbCastPadHidden) gates the cast starts and
-- the idle pass the way `enabled` does; the saved `enabled` is never written,
-- Blizzard's bar stays suppressed (handed back under WoW Forever's Gamepad
-- interface style, ns.RB_SyncBlizzCastSuppress) and the frame keeps its
-- layout. The pad edges are watched only while the option and the bar are
-- both on. padOn is the watcher's verdict; ApplyAll and the options page pass
-- nothing and it is read live. On ns.
function mod.RB_ApplyGamepadCastbar(padOn)
    local callback = ERB.db and ERB.db.profile and ERB.db.profile.castBar
    local wanted = (callback and callback.enabled and callback.gamepadHide == true) and true or false
    if wanted ~= (mod._erbCastPadWatched == true) then
        mod._erbCastPadWatched = wanted
        if wanted then
            CludesUI.WatchPad("ERB_CastBar", mod.RB_ApplyGamepadCastbar)
        else
            CludesUI.UnwatchPad("ERB_CastBar")
        end
    end
    local hide = false
    if wanted then
        if padOn == nil then
            padOn = CludesUI.PadModeOn()
        end
        hide = padOn and true or false
    end
    if hide == (mod._erbCastPadHidden == true) then
        return
    end
    mod._erbCastPadHidden = hide
    mod.RB_SyncBlizzCastSuppress()
    if not castBarFrame then
        return
    end
    if hide then
        -- Drop the live cast: the idle pass hides the bar and the cast tick
        -- stops itself on its next loop.
        OnCastStop()
        return
    end
    -- Back on, mid-cast included: re-derive the live cast (the starts refuse
    -- a disabled bar), else settle into the idle state.
    if UnitCastingInfo("player") then
        OnCastStart()
    else
        local name, _, _, _, _, _, _, _, empowering = UnitChannelInfo("player")
        if name then
            if empowering then
                OnEmpowerStart()
            else
                OnChannelStart()
            end
        end
    end
    if castBarFrame._casting or castBarFrame._channeling or castBarFrame._empowering then
        mod.StartCastTick()
    else
        mod.ShowIdleCastBar()
    end
end

OnEmpowerStart = function()
    if not castBarFrame then
        return
    end
    local callback = ERB.db.profile.castBar
    if not callback.enabled or mod._erbCastPadHidden then
        return
    end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellId, empowering, _, empowerCastID =
        UnitChannelInfo("player")
    if not name or not empowering then
        return
    end

    -- Add hold-at-max time to the end
    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._casting = false
    castBarFrame._channeling = false
    castBarFrame._empowering = true
    castBarFrame._craftExtra = nil
    castBarFrame._craftMerge, castBarFrame._craftCastEnd = nil, nil
    castBarFrame._castID = empowerCastID
    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    castBarFrame._spellName = name
    castBarFrame._spellID = spellId
    castBarFrame._totalDurSuffix = " / " .. format("%.1f", (endTimeMS - startTimeMS) / 1000)
    HideLatencyOverlay()
    castBarFrame._nameText:SetText(mod.CastDisplayName(callback, name, spellId))
    if callback.fitSpellName then
        mod.ERB_FitCastName(callback)
    end
    mod.ERB_SetBlizzCastFill("cast")
    mod.ERB_CastOverrideStart(callback, notInterruptible)
    if not mod.ApplyCastTimer("empower") then
        local empDur = endTimeMS - startTimeMS
        local empProgress = (empDur > 0) and ((GetTime() - startTimeMS / 1000) / (empDur / 1000)) or 0
        castBarFrame._bar:SetValue(min(max(empProgress, 0), 1))
    end
    HideChannelTicks()

    do
        local spellInfo = C_Spell.GetSpellInfo(spellId)
        local iconTex = spellInfo and spellInfo.iconID
        if iconTex and ERB.db.profile.castBar.showIcon ~= false then
            castBarFrame._icon:SetTexture(iconTex)
            castBarFrame._iconFrame:Show()
        else
            castBarFrame._iconFrame:Hide()
        end
    end

    -- Stage pips (hash marks) -- pixel-perfect positioning
    local stages = UnitEmpoweredStagePercentages("player")
    -- Cache cumulative thresholds for per-frame stage color lookup
    if stages then
        SetStageThresholds({})
        local cum = 0
        for index = 1, #stages do
            cum = cum + stages[index]
            cachedStageThresholds[index] = cum
        end
    else
        SetStageThresholds(nil)
    end
    if stages then
        -- Stashed so a mid-empower bar rebuild can re-lay this cast's stage
        -- pips (see the BuildCastBar tail; the channel ticks' stash twin).
        -- Stale values are inert: the re-lay gates on _empowering, and every
        -- empower start restores the stash.
        castBarFrame._empStages = stages
        mod.ERB_LayoutEmpowerPips(stages)
    end

    mod.ActivateCastBar()
end

-- Stage pip layout for an empowered cast, shared by OnEmpowerStart and the
-- BuildCastBar tail (a mid-empower rebuild must re-lay the marks against
-- the rebuilt bar, exactly like the channel-tick re-show -- without it the
-- build reset's pip wipe sticks for the rest of that cast; field: Evokers
-- randomly losing all stage ticks for one cast). On ns.
function mod.ERB_LayoutEmpowerPips(stages)
    if not (castBarFrame and stages) then
        return
    end
    local barFrame = castBarFrame._bar
    local barWidth = barFrame:GetWidth()
    local barHeight = barFrame:GetHeight()
    local numStages = #stages
    castBarFrame._numStages = numStages

    -- Physical-pixel sizing: PP.perfect / effectiveScale = one PHYSICAL
    -- pixel in the bar's local units, so the pip is exactly 2 physical
    -- pixels wide at every UI scale (the old effectiveScale rounding
    -- treated 2 as UI units and drifted between 1 and 3 physical pixels).
    local effectiveScale = barFrame:GetEffectiveScale()
    local PPc = CludesUI and CludesUI.PP
    local onePx = ((PPc and PPc.perfect) or 1) / effectiveScale
    local pipWidth = 2 * onePx
    local snappedHeight = (PPc and PPc.SnapForES) and PPc.SnapForES(barHeight, effectiveScale) or barHeight

    -- Position a pip at each stage boundary (skip the last -- it's the bar end)
    local lastOffset = 0
    for index = 1, numStages - 1 do
        local pip = castBarFrame._pips[index]
        if not pip then
            pip = barFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            pip:SetColorTexture(1, 1, 1, 0.85)
            if pip.SetSnapToPixelGrid then
                pip:SetSnapToPixelGrid(false)
                pip:SetTexelSnappingBias(0)
            end
            castBarFrame._pips[index] = pip
        end
        local rawOffset = lastOffset + (barWidth * stages[index])
        lastOffset = rawOffset
        -- Width-aware center snap: both pip edges land on the physical
        -- grid (a centered even-width mark on a grid point is exact).
        local snappedOffset = (PPc and PPc.SnapCenterForDim)
                and PPc.SnapCenterForDim(rawOffset, pipWidth, effectiveScale)
            or (floor(rawOffset * effectiveScale + 0.5) / effectiveScale)
        pip:SetSize(pipWidth, snappedHeight)
        pip:ClearAllPoints()
        pip:SetPoint("CENTER", barFrame, "LEFT", snappedOffset, 0)
        pip:Show()
    end

    -- Hide any extra pips from a previous cast with more stages
    for index = numStages, #castBarFrame._pips do
        castBarFrame._pips[index]:Hide()
    end
end

OnEmpowerUpdate = function()
    if not castBarFrame then
        return
    end
    if not castBarFrame._empowering then
        return
    end

    local name, _, _, startTimeMS, endTimeMS, _, notInterruptible, spellId, empowering =
        UnitChannelInfo("player")
    if not name or not empowering then
        return
    end

    local holdAtMax = GetUnitEmpowerHoldAtMaxTime("player")
    endTimeMS = endTimeMS + holdAtMax

    castBarFrame._startTime = startTimeMS / 1000
    castBarFrame._endTime = endTimeMS / 1000
    mod.ApplyCastTimer("empower")
end

Inner.BuildCastBar, Inner.OnCastComplete, Inner.OnCastFailed = BuildCastBar, OnCastComplete, OnCastFailed
Inner.OnCastStart, Inner.OnChannelStart, Inner.OnChannelStop = OnCastStart, OnChannelStart, OnChannelStop
Inner.OnChannelUpdate, Inner.OnEmpowerStart = OnChannelUpdate, OnEmpowerStart
Inner.OnEmpowerStop, Inner.OnEmpowerUpdate = OnEmpowerStop, OnEmpowerUpdate
Inner.broken = false
