if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarFrames.lua
--
--  Bar frame creation, threshold overlays, tick marks, charge hash lines, the
--  spark anchor and ApplyTrackedBuffBarSettings.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pcall = pcall
local upper = math.max

local _classB, _classG, _classR, SetFont = Inner._classB, Inner._classG, Inner._classR, Inner.SetFont
local SetTBBTextColor, TBB_TEXTURES = Inner.SetTBBTextColor, Inner.TBB_TEXTURES
local _MarkTBBReflowDirty = Inner._MarkTBBReflowDirty

-------------------------------------------------------------------------------
--  Frame Creation
-------------------------------------------------------------------------------
local function CreateTrackedBuffBarFrame(hostFrame, position)
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. position, hostFrame)
    -- MEDIUM strata at level 100 by default (cfg.strata can move the whole bar via
    -- ApplyTrackedBuffBarSettings); level 100 keeps it above overlapping buff-icon
    -- displays (MEDIUM, low levels). Internal level order: strips +6 < glow +7 < text +8.
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(100)
    -- Visibility is a group reflow input: every Show/Hide edge, whichever path drives it, dirties the reflow.
    wrapFrame:SetScript("OnShow", _MarkTBBReflowDirty)
    wrapFrame:SetScript("OnHide", _MarkTBBReflowDirty)

    local barFrame = CreateFrame("StatusBar", "ECME_TBB" .. position, wrapFrame)
    if barFrame.EnableMouseClicks then
        barFrame:EnableMouseClicks(false)
    end
    barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0.65)
    barFrame:SetClipsChildren(true)
    wrapFrame._bar = barFrame

    local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 0.4)
    wrapFrame._bg = backdrop

    -- Spark on a dedicated overlay above the (gradient) fill and threshold overlays
    -- so it always draws OVER both; ApplyTrackedBuffBarSettings owns the final level
    -- (this value only holds until the first apply). Clipped to the bar so it never
    -- spills past the ends. SnapToPixelGrid off so it tracks the smoothly-interpolated
    -- fill edge at sub-pixel precision instead of jumping a pixel at a grid line.
    local sparkOverlay = CreateFrame("Frame", nil, barFrame)
    sparkOverlay:SetAllPoints(barFrame)
    sparkOverlay:SetClipsChildren(true)
    sparkOverlay:SetFrameLevel(barFrame:GetFrameLevel() + 2)
    wrapFrame._sparkOverlay = sparkOverlay
    local spark = sparkOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:SetSnapToPixelGrid(false)
    spark:SetTexelSnappingBias(0)
    spark:Hide()
    wrapFrame._spark = spark

    -- Gradient clip frame (created lazily in ApplySettings)
    wrapFrame._gradClip = nil
    wrapFrame._gradTex = nil

    -- Text overlay: parented to wrapFrame (not bar) so bar's SetClipsChildren can't
    -- chop text when font size exceeds bar height. Level sits above the border (bar+6
    -- in ApplySettings, PP strips at +7) and the pandemic glow overlay (bar+8), so
    -- timer/name/stacks render on top of both; keyed off bar so they track together.
    local textOverlay = CreateFrame("Frame", nil, wrapFrame)
    textOverlay:SetAllPoints(barFrame)
    textOverlay:SetFrameLevel(barFrame:GetFrameLevel() + 9)
    wrapFrame._textOverlay = textOverlay

    -- Timer text
    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(timerText, 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", barFrame, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    wrapFrame._timerText = timerText

    -- Name text
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(nameText, 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", barFrame, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    wrapFrame._nameText = nameText

    -- Stacks text
    local stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(stacksText, 11)
    stacksText:SetTextColor(1, 1, 1, 0.9)
    stacksText:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
    stacksText:Hide()
    wrapFrame._stacksText = stacksText

    -- Icon
    local glyph = CreateFrame("Frame", nil, wrapFrame)
    glyph:SetSize(24, 24)
    glyph:Hide()
    local iconTex = glyph:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    glyph._tex = iconTex
    wrapFrame._icon = glyph

    -- Border container
    local bdrContainer = CreateFrame("Frame", nil, wrapFrame)
    bdrContainer:SetAllPoints(wrapFrame)
    bdrContainer:SetFrameLevel(wrapFrame:GetFrameLevel() + 5)
    bdrContainer:Hide()
    wrapFrame._barBorder = bdrContainer

    -- Pandemic glow overlay above the border, whose PP strips draw at bar+7
    -- (border frame +6 plus the +1 the strip container adds), so a border
    -- cannot bury the edge-hugging glow (wrapFrame+9 = bar+8).
    local panGlow = CreateFrame("Frame", nil, wrapFrame)
    panGlow:SetAllPoints(wrapFrame)
    panGlow:SetFrameLevel(wrapFrame:GetFrameLevel() + 9)
    panGlow:SetAlpha(0)
    panGlow:EnableMouse(false)
    wrapFrame._pandemicGlowOverlay = panGlow

    wrapFrame:Hide()
    return wrapFrame
end

-------------------------------------------------------------------------------
--  Threshold Overlays (stacked StatusBars, secret-safe)
--
--  bar._stackCount may be a secret number, so it can NEVER be compared or sorted in
--  Lua. Each threshold gets its own StatusBar with range (value-1, value): SetValue
--  compares in the C layer, and the overlay snaps 0 -> full as the count crosses it.
--  With several thresholds every crossed overlay is full at once, so "highest
--  crossed wins" must be draw order, not an if: overlay i is parented to overlay i-1
--  (a child renders above its parent) and the list stays sorted ascending, so the
--  highest crossed threshold paints last. Frame levels stay pinned at sb+2, leaving
--  the tick overlay (sb+3) and charge hash lines (sb+4) on top.
-------------------------------------------------------------------------------
local function EnsureTBBThresholdOverlay(barFrame, i)
    local pool = barFrame._threshOverlays
    if not pool then
        pool = {}
        barFrame._threshOverlays = pool
    end
    if pool[i] then
        return pool[i]
    end
    local scrollBar = barFrame._bar
    if not scrollBar then
        return nil
    end
    local overlayFrame = CreateFrame("StatusBar", nil, pool[i - 1] or scrollBar)
    overlayFrame:SetAllPoints(scrollBar:GetStatusBarTexture())
    overlayFrame:SetFrameLevel(scrollBar:GetFrameLevel() + 2)
    overlayFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    overlayFrame:SetMinMaxValues(0, 1)
    overlayFrame:SetValue(0)
    overlayFrame:Hide()
    pool[i] = overlayFrame
    return overlayFrame
end

local function HideTBBThresholdOverlaysFrom(barFrame, first)
    local pool = barFrame._threshOverlays
    if not pool then
        return
    end
    for i = first, #pool do
        if pool[i] then
            pool[i]:Hide()
        end
    end
end

-- Multi-threshold list only when opted in and non-empty; nil means the legacy single-threshold keys own the rendering.
local function TBBMultiThresholdList(conf)
    if not conf.stackThresholdMulti then
        return nil
    end
    local entries = conf.stackThresholds
    if not entries or #entries == 0 then
        return nil
    end
    return entries
end

local function ApplyTBBThresholdOverlay(
    overlayFrame,
    scrollBar,
    texPath,
    orient,
    reverse,
    i,
    r,
    g,
    b,
    a,
    value,
    blizzAtlas
)
    overlayFrame:SetStatusBarTexture(texPath)
    overlayFrame:SetOrientation(orient)
    overlayFrame:SetReverseFill(reverse)
    local tex = overlayFrame:GetStatusBarTexture()
    -- Blizzard Style: the segment takes the same atlas as the fill it covers.
    if blizzAtlas then
        tex:SetAtlas("UI-HUD-CoolDownManager-Bar")
    end
    tex:SetVertexColor(r, g, b, a)
    tex:SetDrawLayer("ARTWORK", i)
    overlayFrame:ClearAllPoints()
    overlayFrame:SetAllPoints(scrollBar:GetStatusBarTexture())
    overlayFrame:SetMinMaxValues(value - 1, value)
    overlayFrame:SetValue(0)
    overlayFrame:Show()
end

local function SetupTBBThresholdOverlay(barFrame, conf)
    if not conf.stackThresholdEnabled or (conf.trackType == "cooldown" and conf.chargeHashLines == true) then
        HideTBBThresholdOverlaysFrom(barFrame, 1)
        return
    end
    local scrollBar = barFrame._bar
    if not scrollBar then
        return
    end
    local texPath =
        CludesUI.ResolveTexturePath(TBB_TEXTURES, conf.texture or "none", "Interface\\Buttons\\WHITE8x8")
    local orient = conf.verticalOrientation and "VERTICAL" or "HORIZONTAL"
    local reverse = conf.reverseFill and true or false

    local num = 0
    local entries = TBBMultiThresholdList(conf)
    if entries then
        -- Sorted ascending by the options editor, so index order is draw order.
        for i = 1, #entries do
            local t = entries[i]
            local overlayFrame = EnsureTBBThresholdOverlay(barFrame, i)
            if not overlayFrame then
                break
            end
            ApplyTBBThresholdOverlay(
                overlayFrame,
                scrollBar,
                texPath,
                orient,
                reverse,
                i,
                t.r or 0.8,
                t.g or 0.1,
                t.b or 0.1,
                t.a or 1,
                t.value or 5,
                barFrame._blizzFillAtlas
            )
            num = i
        end
    else
        local overlayFrame = EnsureTBBThresholdOverlay(barFrame, 1)
        if overlayFrame then
            ApplyTBBThresholdOverlay(
                overlayFrame,
                scrollBar,
                texPath,
                orient,
                reverse,
                1,
                conf.stackThresholdR or 0.8,
                conf.stackThresholdG or 0.1,
                conf.stackThresholdB or 0.1,
                conf.stackThresholdA or 1,
                conf.stackThreshold or 5,
                barFrame._blizzFillAtlas
            )
            num = 1
        end
    end
    HideTBBThresholdOverlaysFrom(barFrame, num + 1)
end

local function FeedTBBThresholdOverlay(barFrame)
    local pool = barFrame._threshOverlays
    if not pool then
        return
    end
    local val = barFrame._stackCount or 0
    for i = 1, #pool do
        local overlayFrame = pool[i]
        if overlayFrame and overlayFrame:IsShown() then
            overlayFrame:SetValue(val)
        end
    end
end

-------------------------------------------------------------------------------
--  Tick Marks
-------------------------------------------------------------------------------
-- Cooldown state must follow the SAVED spell, not the transient override
-- returned for an icon while a proc is active. The base fallback only handles
-- a saved talent override that is no longer learned.
local function StableCooldownSpellID(conf)
    local spellRef = conf and conf.spellID
    if type(spellRef) ~= "number" or spellRef <= 0 then
        return nil
    end
    local baseValue = conf.baseSpellID
    if
        type(baseValue) == "number"
        and baseValue > 0
        and IsPlayerSpell
        and not IsPlayerSpell(spellRef)
        and IsPlayerSpell(baseValue)
    then
        return baseValue
    end
    return spellRef
end

local function GetTBBMaxCharges(conf)
    if not conf or conf.trackType ~= "cooldown" then
        return nil
    end
    local spellRef = StableCooldownSpellID(conf)
    local ch = spellRef and C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellRef)
    local maxCharges = ch and ch.maxCharges
    if issecretvalue and issecretvalue(maxCharges) then
        return nil
    end
    if type(maxCharges) == "number" and maxCharges > 1 then
        return math.floor(maxCharges + 0.5)
    end
    return nil
end
mod.GetTBBMaxCharges = GetTBBMaxCharges

-- "all" (any case, anywhere in the list) puts a tick between every stack: N
-- stacks give N-1 interior divisions, the same convention as the charge hash
-- lines below. Numbers listed alongside it are redundant and ignored.
local function ParseTickValues(str, maxStacks)
    if not str or str == "" then
        return nil
    end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local tok = s:match("^%s*(.-)%s*$")
        if tok:lower() == "all" then
            local m = maxStacks and math.floor(maxStacks) or 0
            if m < 2 then
                return nil
            end
            local result = {}
            for i = 1, m - 1 do
                result[i] = i
            end
            return result
        end
        local num = tonumber(tok)
        if num and num > 0 then
            vals[#vals + 1] = num
        end
    end
    return #vals > 0 and vals or nil
end

local function ApplyTBBTickMarks(scrollBar, conf, tickCache, isVert, tickParent)
    local maxStacks = conf.stackThresholdMax or 10
    local vals = ParseTickValues(conf.stackThresholdTicks, maxStacks)
    if tickCache then
        for i = 1, #tickCache do
            tickCache[i]:Hide()
        end
    end
    -- Ticks are governed by Max Stacks alone (the options input unlocks with it); Enable Stack Threshold only drives the recolor overlay, not ticks.
    if
        (conf.trackType == "cooldown" and conf.chargeHashLines == true)
        or not conf.stackThresholdMaxEnabled
        or not vals
        or maxStacks < 1
        or not tickCache
    then
        return
    end

    local Pix = CludesUI and CludesUI.PP
    local hostFrame = tickParent or scrollBar
    while #tickCache < #vals do
        local t = hostFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    -- Legacy bars carry no tick-color fields: fall back to white so their ticks render unchanged.
    local tickR = conf.stackThresholdTickR or 1
    local tickG = conf.stackThresholdTickG or 1
    local tickB = conf.stackThresholdTickB or 1
    local tickA = conf.stackThresholdTickA
    if tickA == nil then
        tickA = 1
    end

    local onePx = Pix and Pix.Scale(1) or 1
    local barW, barH = scrollBar:GetWidth(), scrollBar:GetHeight()
    -- Ticks measure stack fractions from the fill's ORIGIN, so they mirror when Reverse Fill moves the origin to the other end.
    local reverse = conf.reverseFill and true or false
    for i, val in ipairs(vals) do
        if val <= maxStacks then
            local t = tickCache[i]
            local frac = val / maxStacks
            t:SetColorTexture(tickR, tickG, tickB, tickA)
            t:ClearAllPoints()
            if isVert then
                local off = Pix and Pix.Scale(barH * frac) or (barH * frac)
                t:SetSize(barW, onePx)
                if reverse then
                    t:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, -off)
                else
                    t:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, off)
                end
            else
                local off = Pix and Pix.Scale(barW * frac) or (barW * frac)
                t:SetSize(onePx, barH)
                if reverse then
                    t:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", -off, 0)
                else
                    t:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", off, 0)
                end
            end
            t:Show()
        end
    end
end
mod.ApplyTBBTickMarks = ApplyTBBTickMarks

-- Charge separators are fixed geometry over the full StatusBar: N charges give
-- N-1 separators. Equal divisions do not move when Reverse Fill changes the
-- recovery origin; vertical bars just rotate the marks.
local function ApplyTBBChargeHashLines(barFrame, conf, maxCharges)
    if not barFrame or not conf then
        return
    end
    local scrollBar = barFrame._bar
    if not scrollBar then
        return
    end

    local ticks = barFrame._chargeHashTicks
    if
        conf.chargeHashLines ~= true
        or conf.trackType ~= "cooldown"
        or type(maxCharges) ~= "number"
        or maxCharges <= 1
    then
        if ticks then
            for i = 1, #ticks do
                ticks[i]:Hide()
            end
        end
        barFrame._chargeHashLineCacheValid = nil
        if barFrame._chargeHashOverlay then
            barFrame._chargeHashOverlay:Hide()
        end
        return
    end

    local barW, barH = scrollBar:GetWidth(), scrollBar:GetHeight()
    if not barW or not barH or barW <= 0 or barH <= 0 then
        if ticks then
            for i = 1, #ticks do
                ticks[i]:Hide()
            end
        end
        if barFrame._chargeHashOverlay then
            barFrame._chargeHashOverlay:Hide()
        end
        barFrame._chargeHashLineCacheValid = nil
        return
    end

    local width = tonumber(conf.chargeHashLineWidth) or 2
    width = math.max(1, math.min(10, math.floor(width + 0.5)))
    local lineR = conf.chargeHashLineR or 0
    local lineG = conf.chargeHashLineG or 0
    local lineB = conf.chargeHashLineB or 0
    local lineA = conf.chargeHashLineA
    if lineA == nil then
        lineA = 1
    end
    local isVert = conf.verticalOrientation and true or false
    local reverse = conf.reverseFill and true or false
    local effectiveScale = scrollBar:GetEffectiveScale() or 1
    -- Also runs from the shared timer tick, so the cache stays SCALAR: synthesized table/string keys would allocate even on a cache hit.
    if
        barFrame._chargeHashLineCacheValid
        and barFrame._chargeHashLineMaxCharges == maxCharges
        and barFrame._chargeHashLineWidth == width
        and barFrame._chargeHashLineVertical == isVert
        and barFrame._chargeHashLineReverse == reverse
        and barFrame._chargeHashLineBarW == barW
        and barFrame._chargeHashLineBarH == barH
        and barFrame._chargeHashLineScale == effectiveScale
        and barFrame._chargeHashLineR == lineR
        and barFrame._chargeHashLineG == lineG
        and barFrame._chargeHashLineB == lineB
        and barFrame._chargeHashLineA == lineA
        and barFrame._chargeHashOverlay
        and barFrame._chargeHashOverlay:IsShown()
    then
        return
    end

    if ticks then
        for i = 1, #ticks do
            ticks[i]:Hide()
        end
    end

    if not barFrame._chargeHashOverlay then
        local overlayFrame = CreateFrame("Frame", nil, scrollBar)
        overlayFrame:SetAllPoints(scrollBar)
        overlayFrame:SetFrameLevel(scrollBar:GetFrameLevel() + 5)
        barFrame._chargeHashOverlay = overlayFrame
    end
    barFrame._chargeHashOverlay:Show()
    if not ticks then
        ticks = {}
        barFrame._chargeHashTicks = ticks
    end

    while #ticks < maxCharges - 1 do
        local tick = barFrame._chargeHashOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
        tick:SetSnapToPixelGrid(false)
        tick:SetTexelSnappingBias(0)
        ticks[#ticks + 1] = tick
    end

    -- Divider boundary bars: hidden StatusBars frozen at value i of maxCharges (clean
    -- constants). Their texture edges come from the same engine math as the charge hash
    -- fill's live countTexture edge, so ticks centered here leave no sub-pixel sliver
    -- beside the partial-charge shade at any bar width (a PP.Scale-snapped offset could
    -- sit up to a physical pixel off that native edge and shimmer at unlucky widths).
    local divBars = barFrame._chargeHashDivBars
    if not divBars then
        divBars = {}
        barFrame._chargeHashDivBars = divBars
    end
    for i = 1, maxCharges - 1 do
        local db2 = divBars[i]
        if not db2 then
            db2 = CreateFrame("StatusBar", nil, scrollBar)
            db2:SetAllPoints(scrollBar)
            db2:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            local dt = db2:GetStatusBarTexture()
            dt:SetSnapToPixelGrid(false)
            dt:SetTexelSnappingBias(0)
            db2:SetAlpha(0)
            db2:EnableMouse(false)
            divBars[i] = db2
        end
        db2:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        db2:SetReverseFill(reverse)
        db2:SetMinMaxValues(0, maxCharges)
        db2:SetValue(i)
        db2:Show()
    end
    for i = maxCharges, #divBars do
        divBars[i]:Hide()
    end

    local Pix = CludesUI and CludesUI.PP
    local lineWidth = Pix and Pix.Scale(width) or width
    local halfLine = lineWidth / 2
    for i = 1, maxCharges - 1 do
        local tick = ticks[i]
        local divTex = divBars[i] and divBars[i]:GetStatusBarTexture()
        tick:SetColorTexture(lineR, lineG, lineB, lineA)
        tick:ClearAllPoints()
        if isVert then
            tick:SetSize(barW, lineWidth)
            if divTex then
                if reverse then
                    tick:SetPoint("TOP", divTex, "BOTTOM", 0, halfLine)
                else
                    tick:SetPoint("BOTTOM", divTex, "TOP", 0, -halfLine)
                end
            else
                local offset = Pix and Pix.Scale(barH * (i / maxCharges)) or (barH * (i / maxCharges))
                tick:SetPoint("CENTER", scrollBar, "BOTTOM", 0, offset)
            end
        else
            tick:SetSize(lineWidth, barH)
            if divTex then
                if reverse then
                    tick:SetPoint("RIGHT", divTex, "LEFT", halfLine, 0)
                else
                    tick:SetPoint("LEFT", divTex, "RIGHT", -halfLine, 0)
                end
            else
                local offset = Pix and Pix.Scale(barW * (i / maxCharges)) or (barW * (i / maxCharges))
                tick:SetPoint("CENTER", scrollBar, "LEFT", offset, 0)
            end
        end
        tick:Show()
    end
    for i = maxCharges, #ticks do
        ticks[i]:Hide()
    end
    barFrame._chargeHashLineCacheValid = true
    barFrame._chargeHashLineMaxCharges = maxCharges
    barFrame._chargeHashLineWidth = width
    barFrame._chargeHashLineVertical = isVert
    barFrame._chargeHashLineReverse = reverse
    barFrame._chargeHashLineBarW = barW
    barFrame._chargeHashLineBarH = barH
    barFrame._chargeHashLineScale = effectiveScale
    barFrame._chargeHashLineR = lineR
    barFrame._chargeHashLineG = lineG
    barFrame._chargeHashLineB = lineB
    barFrame._chargeHashLineA = lineA
end
-- Exported for the options popout preview: its bars have no timer tick to re-drive width-gated geometry once the fill's anchor-derived size resolves.
mod.ApplyTBBChargeHashLines = ApplyTBBChargeHashLines

local function AnchorTBBSparkState(barFrame, anchorFrame, isVert, reverse, flushToEdge)
    local scrollBar, spark = barFrame and barFrame._bar, barFrame and barFrame._spark
    if not scrollBar or not spark or not anchorFrame then
        return
    end
    isVert = isVert and true or false
    reverse = reverse and true or false
    flushToEdge = flushToEdge and true or false
    local barW, barH = scrollBar:GetWidth(), scrollBar:GetHeight()
    if
        barFrame._sparkAnchorTarget == anchorFrame
        and barFrame._sparkAnchorVertical == isVert
        and barFrame._sparkAnchorReverse == reverse
        and barFrame._sparkAnchorFlush == flushToEdge
        and barFrame._sparkAnchorBarW == barW
        and barFrame._sparkAnchorBarH == barH
    then
        return
    end
    -- Blizzard Style pip is an atlas: an 8-coord rotation would sample the
    -- whole sheet, so its coords are left to the atlas (vertical bars keep the
    -- upright pip).
    -- The classic pip is the vanilla cast bar spark, a 32px square on a 13px
    -- bar, scaled by the bar's thickness (the overlay clips it to the bar).
    local classicSz = barFrame._classicSpark and ((isVert and barW or barH) * (32 / 13))
    if isVert then
        if classicSz then
            spark:SetSize(classicSz, classicSz)
        else
            spark:SetSize(barW, 8)
        end
        if not barFrame._blizzSpark then
            spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
        end
    else
        if classicSz then
            spark:SetSize(classicSz, classicSz)
        else
            spark:SetSize(8, barH)
        end
        if not barFrame._blizzSpark then
            spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
        end
    end
    spark:ClearAllPoints()
    if isVert then
        spark:SetPoint("CENTER", anchorFrame, reverse and "BOTTOM" or "TOP", 0, 0)
    else
        spark:SetPoint(
            "CENTER",
            anchorFrame,
            reverse and "LEFT" or "RIGHT",
            flushToEdge and 0 or (reverse and 1 or -1),
            0
        )
    end
    barFrame._sparkAnchorTarget = anchorFrame
    barFrame._sparkAnchorVertical = isVert
    barFrame._sparkAnchorReverse = reverse
    barFrame._sparkAnchorFlush = flushToEdge
    barFrame._sparkAnchorBarW = barW
    barFrame._sparkAnchorBarH = barH
end

local function AnchorTBBSpark(barFrame, conf, anchorFrame, flushToEdge)
    if not conf then
        return
    end
    AnchorTBBSparkState(barFrame, anchorFrame, conf.verticalOrientation, conf.reverseFill, flushToEdge)
end

-- Stock style icon art for a tracked bar's icon over the full spell art,
-- sized to the icon square. Blizzard Style: the viewer's rounded mask and
-- ring overlay (same proportional inset as the CDM icons). Classic WoW UI:
-- the vanilla action button ring round the square icon, no mask. One-time
-- structure, size-memoized geometry; never runs unless a style is on.
mod.ApplyTBBBlizzIconArt = function(barFrame, iSize)
    local glyph = barFrame._icon
    local tex = glyph and glyph._tex
    if not tex then
        return
    end
    local classic = mod.CdmClassicBars()
    if not barFrame._blizzIconOverlay then
        tex:SetTexCoord(0, 1, 0, 1)
        if not classic then
            local maskTex = glyph:CreateMaskTexture()
            maskTex:SetAtlas(mod.CDM_BLIZZ_MASK)
            maskTex:SetAllPoints(glyph)
            tex:AddMaskTexture(maskTex)
            barFrame._blizzIconMask = maskTex
        end
        local shade = glyph:CreateTexture(nil, "OVERLAY", nil, 5)
        if classic then
            shade:SetTexture(mod.CDM_CLASSIC_RING)
        else
            mod.CdmStockAtlas(shade, mod.CDM_BLIZZ_OVERLAY, true)
        end
        shade:SetSnapToPixelGrid(false)
        shade:SetTexelSnappingBias(0)
        barFrame._blizzIconOverlay = shade
    end
    -- The ring overhangs the bar, so the icon draws above the fill (the
    -- viewer levels its icon above its bar the same way) and, under classic,
    -- above the cast bar chrome (+6) whose end caps reach under it;
    -- re-asserted here because a strata change collapses child levels.
    if barFrame._bar then
        local lvl = barFrame._bar:GetFrameLevel() + (classic and 7 or 3)
        if glyph:GetFrameLevel() ~= lvl then
            glyph:SetFrameLevel(lvl)
        end
    end
    if barFrame._blizzIconSize ~= iSize then
        barFrame._blizzIconSize = iSize
        local shade = barFrame._blizzIconOverlay
        if classic then
            mod.CdmPlaceClassicRing(shade, glyph, iSize, iSize)
        else
            shade:ClearAllPoints()
            shade:SetPoint(
                "TOPLEFT",
                glyph,
                "TOPLEFT",
                -iSize * mod.CDM_BLIZZ_RING_X,
                iSize * mod.CDM_BLIZZ_RING_Y
            )
            shade:SetPoint(
                "BOTTOMRIGHT",
                glyph,
                "BOTTOMRIGHT",
                iSize * mod.CDM_BLIZZ_RING_X,
                -iSize * mod.CDM_BLIZZ_RING_Y
            )
        end
    end
end

-- Classic WoW UI bar chrome: the vanilla cast bar frame (the shared
-- nine-slice in CludesUI_ClassicArt.lua, caps and rims at the sheet's own
-- pixel size, only the window stretching) laid over the tracked bar's fill on
-- an art frame above the fill, its threshold overlays, spark, ticks and
-- charge hash lines, below the texts and the icon. The frame's reach (14.5
-- left and right, 12 above and 11 below the fill at full size) is fixed
-- whatever the bar's size, scaled only by the bar's own Border Size
-- percentage (`pct`, nil = the shared default), so a bar in a tight group
-- never paints across its neighbour; a vertical bar turns the art a quarter
-- turn counter-clockwise. One-time regions, geometry memoized by the seat.
mod.CDM_CLASSIC_BAR_SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
mod.ApplyTBBClassicChrome = function(barFrame, scrollBar, isVert, thick, pct)
    local CF = CludesUI.ClassicFrame
    if not CF then
        return
    end
    local art = barFrame._classicArt
    if not art then
        art = CreateFrame("Frame", nil, barFrame)
        art:SetAllPoints(scrollBar)
        art:EnableMouse(false)
        barFrame._classicArt = art
        barFrame._classicChrome = CF.Create(art, "OVERLAY", 0)
    end
    -- Above the fill, threshold overlays (+2), the spark's own host, ticks
    -- (+4) and the charge hash lines (+5); below the icon (+7) and the text
    -- overlay (+7). Re-asserted because a strata change collapses child levels.
    local lvl = scrollBar:GetFrameLevel() + 6
    if art:GetFrameLevel() ~= lvl then
        art:SetFrameLevel(lvl)
    end
    CF.Seat(barFrame._classicChrome, art, CF.ScaleK(pct), isVert)
end

-- Defined with the charge renderer (CUI_CDM_BuffBarCooldown.lua). ApplySettings calls it whenever a
-- pooled bar frame is restyled so stale composite geometry cannot leak into a
-- different bar after deletion, reordering or a tracking-type change.
local _restoreTBBNormalFill
Inner.restoreNormalFillSetters[#Inner.restoreNormalFillSetters + 1] = function(val)
    _restoreTBBNormalFill = val
end

-------------------------------------------------------------------------------
--  Apply Visual Settings
-------------------------------------------------------------------------------
local function ApplyTrackedBuffBarSettings(barFrame, conf)
    if not barFrame or not conf then
        return
    end
    local scrollBar = barFrame._bar
    if not scrollBar then
        return
    end
    -- Stock styles (Global Settings > Style) with every setting still
    -- applied: Blizzard Style = the viewer's bar, background and pip art;
    -- Classic WoW UI = the vanilla cast bar frame and spark round the user's
    -- own fill and background. Reload-gated, so the per-bar one-time setup
    -- below never has to be undone.
    local blizzBar = mod.CdmBlizzBars()
    local classicBar = mod.CdmClassicBars()
    if blizzBar and not classicBar and not barFrame._blizzSpark and barFrame._spark then
        barFrame._blizzSpark = true
        barFrame._spark:SetAtlas("UI-HUD-CoolDownManager-Bar-Pip")
        barFrame._spark:SetBlendMode("BLEND")
    elseif classicBar and not barFrame._classicSpark and barFrame._spark then
        barFrame._classicSpark = true
        barFrame._spark:SetTexture(mod.CDM_CLASSIC_BAR_SPARK)
        -- The vanilla spark stands taller than the bar: its host leaves the
        -- clipping StatusBar for the wrap (same rect) so it can overhang, as
        -- the cast bar's does; the strata block below levels it over the chrome.
        local so = barFrame._sparkOverlay
        if so then
            so:SetParent(barFrame)
            so:ClearAllPoints()
            so:SetAllPoints(scrollBar)
            so:SetClipsChildren(false)
        end
    end
    if _restoreTBBNormalFill then
        _restoreTBBNormalFill(barFrame, conf)
    end

    -- User-selectable strata for the whole bar (options setter keeps grouped bars
    -- uniform). A parent strata change COLLAPSES child frame levels, so the wrap
    -- level and the constructor's internal ladder are re-asserted whenever strata
    -- actually changes; the change guard keeps the common repaint path free of it.
    local strata = conf.strata or "MEDIUM"
    if barFrame._lastStrata ~= strata then
        barFrame._lastStrata = strata
        barFrame:SetFrameStrata(strata)
        barFrame:SetFrameLevel(100)
        local baseValue = barFrame:GetFrameLevel()
        scrollBar:SetFrameLevel(baseValue + 1)
        if barFrame._gradClip then
            barFrame._gradClip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
        end
        if barFrame._chargeHashFillClip then
            barFrame._chargeHashFillClip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
        end
        if barFrame._threshOverlays then
            for i = 1, #barFrame._threshOverlays do
                local shade = barFrame._threshOverlays[i]
                if shade then
                    shade:SetFrameLevel(scrollBar:GetFrameLevel() + 2)
                end
            end
        end
        -- Spark sits one level ABOVE the threshold overlays: at equal level it
        -- loses the tie to them (created lazily, so they win) and vanishes the
        -- moment a threshold is crossed. Ticks and charge hash lines shift up
        -- in step to keep their order. The classic spark rides above the
        -- chrome instead, as the vanilla spark draws over its frame: sb+8, above
        -- the pandemic glow (base+8), level with the text.
        if barFrame._sparkOverlay then
            barFrame._sparkOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + (classicBar and 8 or 3))
        end
        -- Tick overlay MUST be re-asserted here too: SetFrameStrata collapses descendant levels, so otherwise ticks land at a default level.
        if barFrame._tickOverlay then
            barFrame._tickOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 4)
        end
        if barFrame._chargeHashOverlay then
            barFrame._chargeHashOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 5)
        end
        -- Border at base+6, not +5: tick marks sit at sb+4 (= base+5), which
        -- would TIE the border cross-subtree, and the lazily-created tick overlay wins
        -- ties, putting ticks ON TOP of the border. One level up keeps the border above
        -- ticks; charge hash lines tie it and win via later creation, as intended.
        if barFrame._barBorder then
            barFrame._barBorder:SetFrameLevel(baseValue + 6)
        end
        -- Glow +8: the border's PP strips draw at +7 and would tie it; text stays on top.
        if barFrame._pandemicGlowOverlay then
            barFrame._pandemicGlowOverlay:SetFrameLevel(baseValue + 8)
        end
        if barFrame._textOverlay then
            barFrame._textOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 8)
        end
    end

    -- width/height are always VISUAL dimensions describing the bar's TOTAL footprint,
    -- icon included: the wrap is exactly width x height and a shown icon carves its
    -- square out of the fill. Horizontal: width=long side, height=short side.
    -- Vertical: width=short side, height=long side.
    local PPt = CludesUI and CludesUI.PP
    local snap = PPt and PPt.Snap or function(val)
        return val
    end
    local wid = snap(conf.width or 270)
    local hgt = snap(conf.height or 24)
    local isVert = conf.verticalOrientation
    barFrame._lastVertical = isVert
    local iconMode = conf.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = isVert and wid or hgt
    if hasIcon then
        -- Never let the icon square consume the whole footprint
        local long = isVert and hgt or wid
        if iSize > long - 1 then
            iSize = upper(1, long - 1)
        end
    end

    barFrame:SetSize(wid, hgt)

    -- Position StatusBar inside wrapFrame
    scrollBar:ClearAllPoints()
    if hasIcon then
        if isVert then
            if iconMode == "left" then
                -- Left = Top for vertical
                scrollBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, -iSize)
                scrollBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
            else
                -- Right = Bottom for vertical
                scrollBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
                scrollBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, iSize)
            end
        else
            if iconMode == "left" then
                scrollBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", iSize, 0)
                scrollBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
            else
                scrollBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
                scrollBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -iSize, 0)
            end
        end
    else
        scrollBar:SetAllPoints(barFrame)
    end

    -- Orientation and fill direction
    scrollBar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    scrollBar:SetReverseFill(conf.reverseFill and true or false)

    -- Texture
    local texPath =
        CludesUI.ResolveTexturePath(TBB_TEXTURES, conf.texture or "none", "Interface\\Buttons\\WHITE8x8")
    if blizzBar and not classicBar then
        -- The viewer's bar atlas (tinted by Fill Color below). _lastTexPath
        -- stays a real file path: the charge hash fill re-reads it. Classic
        -- keeps the user's texture: its frame is chrome round the fill.
        texPath = "Interface\\Buttons\\WHITE8x8"
        if not barFrame._blizzFillAtlas then
            scrollBar:SetStatusBarTexture(texPath)
            scrollBar:GetStatusBarTexture():SetAtlas("UI-HUD-CoolDownManager-Bar")
            barFrame._lastTexPath = texPath
            barFrame._blizzFillAtlas = true
        end
    elseif barFrame._lastTexPath ~= texPath then
        scrollBar:SetStatusBarTexture(texPath)
        barFrame._lastTexPath = texPath
    end
    local fillTex = scrollBar:GetStatusBarTexture()
    barFrame._cachedOurFillTex = fillTex

    -- Fill color
    local fR = conf.fillR or _classR
    local fG = conf.fillG or _classG
    local fB = conf.fillB or _classB
    local fA = conf.fillA or 1
    fillTex:SetVertexColor(fR, fG, fB, fA)
    barFrame._baseFillR, barFrame._baseFillG, barFrame._baseFillB, barFrame._baseFillA = fR, fG, fB, fA

    -- Background
    if blizzBar and not classicBar then
        -- The viewer's shadowed bar background overhangs the fill, so it lives
        -- on the wrap (the StatusBar clips its own regions).
        if barFrame._bg then
            barFrame._bg:Hide()
        end
        local bbg = barFrame._blizzBg
        if not bbg then
            bbg = barFrame:CreateTexture(nil, "BACKGROUND")
            bbg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
            -- Anchored once: the fill StatusBar is the bar's for life.
            bbg:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", -2, 2)
            bbg:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 4, -7)
            barFrame._blizzBg = bbg
        end
        bbg:Show()
    elseif barFrame._bg then
        barFrame._bg:SetColorTexture(conf.bgR or 0, conf.bgG or 0, conf.bgB or 0, conf.bgA or 0.4)
    end
    -- Classic WoW UI: the vanilla cast bar frame over the fill and background.
    if classicBar then
        mod.ApplyTBBClassicChrome(barFrame, scrollBar, isVert, isVert and wid or hgt, conf.stockBorderScale)
    end

    -- Gradient (an CUI-look effect; the stock styles keep their flat fill)
    if conf.gradientEnabled and not blizzBar then
        local dir = conf.gradientDir or "HORIZONTAL"
        fillTex:SetVertexColor(1, 1, 1, 0)
        if not barFrame._gradClip then
            local clip = CreateFrame("Frame", nil, scrollBar)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            barFrame._gradClip = clip
            barFrame._gradTex = tex
        end
        barFrame._gradClip:ClearAllPoints()
        barFrame._gradClip:SetAllPoints(fillTex)
        barFrame._gradTex:SetTexture(texPath)
        barFrame._gradTex:SetVertexColor(1, 1, 1, 1)
        barFrame._gradTex:SetGradient(
            dir,
            CreateColor(fR, fG, fB, fA),
            CreateColor(
                conf.gradientR or 0.20,
                conf.gradientG or 0.20,
                conf.gradientB or 0.80,
                conf.gradientA or 1
            )
        )
        barFrame._gradClip:Show()
        barFrame._gradientActive = true
    else
        if barFrame._gradClip then
            barFrame._gradClip:Hide()
        end
        barFrame._gradientActive = nil
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Opacity
    barFrame._opacityTarget = conf.opacity or 1.0
    if not barFrame._tbbReady then
        barFrame:SetAlpha(barFrame._opacityTarget)
    end

    SetTBBTextColor(barFrame._timerText, conf, "timer")
    SetTBBTextColor(barFrame._nameText, conf, "name")
    SetTBBTextColor(barFrame._stacksText, conf, "stacks")

    -- Timer text. Vertical bars honor the same position choices as horizontal: left/right sit OUTSIDE the (thin) bar, top/bottom above/below it, center inside.
    local timerPos = conf.timerPosition or (conf.showTimer and "right" or "none")
    if timerPos ~= "none" then
        barFrame._timerText:Show()
        SetFont(barFrame._timerText, conf.timerSize or 11)
        barFrame._timerText:ClearAllPoints()
        local tX, tY = conf.timerX or 0, conf.timerY or 0
        if isVert and timerPos == "center" then
            barFrame._timerText:SetPoint("CENTER", scrollBar, "CENTER", tX, tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "top" then
            barFrame._timerText:SetPoint("BOTTOM", scrollBar, "TOP", tX, 5 + tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "bottom" then
            barFrame._timerText:SetPoint("TOP", scrollBar, "BOTTOM", tX, -5 + tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "left" then
            barFrame._timerText:SetPoint("RIGHT", scrollBar, "LEFT", -5 + tX, tY)
            barFrame._timerText:SetJustifyH("RIGHT")
        elseif isVert then
            barFrame._timerText:SetPoint("LEFT", scrollBar, "RIGHT", 5 + tX, tY)
            barFrame._timerText:SetJustifyH("LEFT")
        elseif timerPos == "center" then
            barFrame._timerText:SetPoint("CENTER", scrollBar, "CENTER", tX, tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif timerPos == "top" then
            barFrame._timerText:SetPoint("BOTTOM", scrollBar, "TOP", tX, 5 + tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif timerPos == "bottom" then
            barFrame._timerText:SetPoint("TOP", scrollBar, "BOTTOM", tX, -5 + tY)
            barFrame._timerText:SetJustifyH("CENTER")
        elseif timerPos == "left" then
            barFrame._timerText:SetPoint("LEFT", scrollBar, "LEFT", 5 + tX, tY)
            barFrame._timerText:SetJustifyH("LEFT")
        else
            barFrame._timerText:SetPoint("RIGHT", scrollBar, "RIGHT", -5 + tX, tY)
            barFrame._timerText:SetJustifyH("RIGHT")
        end
    else
        barFrame._timerText:Hide()
    end

    -- Spark anchors to the MOVING edge of the fill. With Reverse Fill the fill anchors at the far end and the near edge moves, so the spark side flips.
    barFrame._lastReverse = conf.reverseFill and true or false
    if conf.showSpark then
        local sparkAnchor = (barFrame._gradientActive and barFrame._gradClip) or fillTex
        AnchorTBBSpark(barFrame, conf, sparkAnchor)
        barFrame._spark:Show()
    else
        barFrame._spark:Hide()
    end

    -- Name text
    local namePos = conf.namePosition or ((conf.showName ~= false) and "left" or "none")
    if namePos ~= "none" and not isVert then
        barFrame._nameText:Show()
        SetFont(barFrame._nameText, conf.nameSize or 11)
        barFrame._nameText:ClearAllPoints()
        local nX, nY = conf.nameX or 0, conf.nameY or 0
        if namePos == "center" then
            barFrame._nameText:SetPoint("CENTER", scrollBar, "CENTER", nX, nY)
            barFrame._nameText:SetJustifyH("CENTER")
        elseif namePos == "top" then
            barFrame._nameText:SetPoint("BOTTOM", scrollBar, "TOP", nX, 5 + nY)
            barFrame._nameText:SetJustifyH("CENTER")
        elseif namePos == "bottom" then
            barFrame._nameText:SetPoint("TOP", scrollBar, "BOTTOM", nX, -5 + nY)
            barFrame._nameText:SetJustifyH("CENTER")
        elseif namePos == "right" then
            barFrame._nameText:SetPoint("RIGHT", scrollBar, "RIGHT", -5 + nX, nY)
            barFrame._nameText:SetJustifyH("RIGHT")
        else
            barFrame._nameText:SetPoint("LEFT", scrollBar, "LEFT", 5 + nX, nY)
            barFrame._nameText:SetJustifyH("LEFT")
        end
        -- Text width + wrap mode (icon's square is not text space). Wrap on: 2 lines within
        -- the text area. Off (default): one line truncated with an ellipsis at 85% of fill width.
        local fillW = hasIcon and (wid - iSize) or wid
        if conf.nameWrap then
            barFrame._nameText:SetWordWrap(true)
            barFrame._nameText:SetMaxLines(2)
            barFrame._nameText:SetWidth(fillW - 12 - (conf.showTimer and 50 or 0))
        else
            barFrame._nameText:SetWordWrap(false)
            barFrame._nameText:SetMaxLines(1)
            barFrame._nameText:SetWidth(fillW * 0.85)
        end
    else
        barFrame._nameText:Hide()
    end

    -- Icon
    if hasIcon and barFrame._icon then
        barFrame._icon:SetSize(iSize, iSize)
        barFrame._icon:ClearAllPoints()
        if isVert then
            if iconMode == "left" then
                barFrame._icon:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
            else
                barFrame._icon:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
            end
        else
            if iconMode == "left" then
                barFrame._icon:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
            else
                barFrame._icon:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
            end
        end
        if blizzBar then
            mod.ApplyTBBBlizzIconArt(barFrame, iSize)
        end
        barFrame._icon:Show()
    elseif barFrame._icon then
        barFrame._icon:Hide()
    end

    -- Stacks text positioning
    if barFrame._stacksText then
        local sPos = conf.stacksPosition or "center"
        if sPos == "none" then
            barFrame._stacksText:Hide()
            barFrame._stacksHidden = true
        else
            barFrame._stacksHidden = nil
            SetFont(barFrame._stacksText, conf.stacksSize or 11)
            barFrame._stacksText:ClearAllPoints()
            local sX, sY = conf.stacksX or 0, conf.stacksY or 0
            if sPos == "top" then
                barFrame._stacksText:SetPoint("BOTTOM", scrollBar, "TOP", sX, 5 + sY)
            elseif sPos == "bottom" then
                barFrame._stacksText:SetPoint("TOP", scrollBar, "BOTTOM", sX, -5 + sY)
            elseif sPos == "left" then
                barFrame._stacksText:SetPoint("LEFT", scrollBar, "LEFT", 5 + sX, sY)
            elseif sPos == "right" then
                barFrame._stacksText:SetPoint("RIGHT", scrollBar, "RIGHT", -5 + sX, sY)
            else
                barFrame._stacksText:SetPoint("CENTER", scrollBar, "CENTER", sX, sY)
            end
        end
    end

    -- Border (PP or textured via ApplyBorderStyle; none under Blizzard Style)
    if barFrame._barBorder then
        barFrame._barBorder:SetAllPoints(barFrame)
        local bSz = blizzBar and 0 or (conf.borderSize or 0)
        local textureKey = conf.borderTexture or "solid"
        -- Exact size (borderSizePx) for the bar's own step; a stock style forces 0 and stays legacy.
        local edgePx
        if not blizzBar then
            edgePx = CludesUI.BorderPx(conf.borderSizePx, bSz, textureKey)
        end
        -- Border container is a child of the bar: +6 draws in front of the fill AND above
        -- the tick marks at sb+4 (=bar+5, which would tie and lose to the lazily-created
        -- tick overlay); "Show Behind" uses level-1. Set BEFORE ApplyBorderStyle so the textured backdrop inherits it.
        local baseLvl = barFrame:GetFrameLevel()
        barFrame._barBorder:SetFrameLevel(conf.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 6))
        CludesUI.ApplyBorderStyle(
            barFrame._barBorder,
            bSz,
            conf.borderR or 0,
            conf.borderG or 0,
            conf.borderB or 0,
            1,
            textureKey,
            conf.borderTextureOffset,
            conf.borderTextureOffsetY,
            conf.borderTextureShiftX,
            conf.borderTextureShiftY,
            "resourcebars",
            bSz,
            nil,
            edgePx
        )
    end

    -- Threshold overlay + tick marks
    SetupTBBThresholdOverlay(barFrame, conf)
    if not barFrame._threshTicks then
        barFrame._threshTicks = {}
    end
    if not barFrame._tickOverlay then
        local to = CreateFrame("Frame", nil, scrollBar)
        to:SetAllPoints(scrollBar)
        to:SetFrameLevel(scrollBar:GetFrameLevel() + 4)
        barFrame._tickOverlay = to
    end
    ApplyTBBTickMarks(scrollBar, conf, barFrame._threshTicks, isVert, barFrame._tickOverlay)
    ApplyTBBChargeHashLines(barFrame, conf, GetTBBMaxCharges(conf))
    barFrame._ticksDirty = true
    -- The settings may change what the name, icon, fill colour and stacks show:
    -- the next live tick re-reads them (TBBContentDue in CUI_CDM_BuffBarTick.lua).
    barFrame._cChild = nil
end

-- Exposed for the options popout preview: preview bars are built and skinned by the SAME code as live bars, so the preview cannot drift from rendering.
mod.CreateTBBBarFrame = CreateTrackedBuffBarFrame
mod.ApplyTBBBarSettings = ApplyTrackedBuffBarSettings

-- The width and height a tracking bar's textured border draws OUTSIDE the bar,
-- in bar units, for its unlock element's getMatchPad: exactly the arguments
-- ApplyTrackedBuffBarSettings passes to ApplyBorderStyle (the numeric step as the
-- "resourcebars" size key, alpha 1, no scale normalizing). nil under the stock
-- styles (no CUI border) and for a border that draws nothing outside. `frame` is
-- the bar: its effective scale (a position scale rides on it) is the grid the
-- border's anchors snap to.
function mod.TBBBorderMatchPad(conf, widget)
    if not conf or not CludesUI.BorderMatchPad or mod.CdmBlizzBars() then
        return nil
    end
    local bSz = conf.borderSize or 0
    local textureKey = conf.borderTexture or "solid"
    if textureKey == "solid" then
        return nil
    end
    local es
    if widget then
        local success, s = pcall(widget.GetEffectiveScale, widget)
        if success then
            es = s
        end
    end
    return CludesUI.BorderMatchPad(
        bSz,
        textureKey,
        conf.borderTextureOffset,
        conf.borderTextureOffsetY,
        conf.borderTextureShiftX,
        conf.borderTextureShiftY,
        "resourcebars",
        bSz,
        CludesUI.BorderPx(conf.borderSizePx, bSz, textureKey),
        nil,
        1,
        es
    )
end

-- "TBB_" .. index and "TBBG_" .. group key, each built once, so the per-build
-- pad notifier builds no strings.
mod._tbbUKey = setmetatable({}, {
    __index = function(t, key)
        local val = "TBB_" .. key
        t[key] = val
        return val
    end,
})
mod._tbbgUKey = setmetatable({}, {
    __index = function(t, key)
        local val = "TBBG_" .. key
        t[key] = val
        return val
    end,
})

Inner.AnchorTBBSpark, Inner.AnchorTBBSparkState = AnchorTBBSpark, AnchorTBBSparkState
Inner.ApplyTBBChargeHashLines, Inner.ApplyTBBTickMarks = ApplyTBBChargeHashLines, ApplyTBBTickMarks
Inner.ApplyTrackedBuffBarSettings = ApplyTrackedBuffBarSettings
Inner.CreateTrackedBuffBarFrame = CreateTrackedBuffBarFrame
Inner.FeedTBBThresholdOverlay = FeedTBBThresholdOverlay
Inner.StableCooldownSpellID = StableCooldownSpellID
Inner.broken = false
