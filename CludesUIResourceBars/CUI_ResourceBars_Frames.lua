if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Frames.lua
--
--  Shared state and the bar helpers: orientation, gradient and flat fills,
--  fill opacity, empower stage colors, pip geometry, pixel borders,
--  CreateStatusBar, CreatePip, the main frame, the spec and power-bar checks.
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

local CLASS_COLORS, DARK_BG_A, ERB = Inner.CLASS_COLORS, Inner.DARK_BG_A, Inner.ERB
local GetPrimaryPowerType, GetRBFont = Inner.GetPrimaryPowerType, Inner.GetRBFont
local GetSecondaryResource, SetRBFont, SnapXY = Inner.GetSecondaryResource, Inner.SetRBFont, Inner.SnapXY
local DEFAULTS, SetMainFrame = Inner.DEFAULTS, Inner.SetMainFrame

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local mainFrame
Inner.mainFrameSetters[#Inner.mainFrameSetters + 1] = function(val)
    mainFrame = val
end
local secondaryBarTicks = {} -- tick mark texture cache for bar-type secondary
local secondaryPipTicks = {} -- tick mark texture cache for pip-type secondary hash lines
local _totemBorderOverlays = setmetatable({}, { __mode = "k" })
-- Engine-entry frames are created at FILE SCOPE on purpose: CPU bills a handler's
-- whole call tree to the addon whose execution context CREATED the entry frame
-- (inherited taint-style from the entry point, not the file the code lives in).
-- OnEnable/build code run under the parent's lifecycle dispatch, so a frame born
-- there bills the parent forever; born in this main chunk it stamps to
-- ResourceBars. Handlers/event registrations can attach later anywhere.
local _erbEventFrame = CreateFrame("Frame") -- event entry; events registered in OnEnable

-- Shell pool for runtime handler hosts (the combat queue below, and up to three
-- mouse-follow anchors): born HERE so their work bills ResourceBars (attribution
-- rule above). One spare.
do
    local pool = {
        CreateFrame("Frame"),
        CreateFrame("Frame"),
        CreateFrame("Frame"),
        CreateFrame("Frame"),
        CreateFrame("Frame"),
    }
    local num = 5
    mod.TakeShell = function()
        if num > 0 then
            local frame = pool[num]
            pool[num] = nil
            num = num - 1
            return frame
        end
        return CreateFrame("Frame")
    end
end
mod.CombatQueue = CludesUI.NewCombatQueue(mod.TakeShell())
local isInCombat = false
Inner.isInCombatSetters[#Inner.isInCombatSetters + 1] = function(val)
    isInCombat = val
end
local currentAlpha = 1
local targetAlpha = 1

-- GCD bar shell at file scope, same attribution reason as _erbEventFrame:
-- BuildGCDBar adopts this shell rather than creating its own, so its OnEvent work
-- bills ResourceBars. Child textures/sub-frames stay lazy (no handlers, birth
-- context doesn't matter).
mod.GCDShell = CreateFrame("Frame", "ERB_GCDBarFrame", UIParent)

-- Effective bar alpha: oocAlpha when "Fade Out of Combat" is on and out of combat, else
-- normal opacity (off by default). EVERY SetAlpha site routes through this -- some
-- events (UNIT_MAXHEALTH/UNIT_MAXPOWER) rebuild with no following UpdateVisibility, so
-- folding the fade in here keeps a rebuild from clobbering it. The Health and Power
-- bars go through ns.ERB_MissingBarAlpha, which keeps a bar Show When Missing reveals
-- at its normal opacity (its wrapper carries the fade). On ns.
function mod.ResolveBarAlpha(conf)
    if conf and conf.oocFadeEnabled and not isInCombat then
        return conf.oocAlpha or 0.5
    end
    return (conf and conf.barAlpha) or 1
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = CludesUI and CludesUI.CLUDES_GREEN
    if eg then
        return eg.r, eg.g, eg.b
    end
    return 76 / 255, 201 / 255, 240 / 255
end

local function IsVerticalOrientation(ori)
    return ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
end
-- Shared with the options file, which needs a bar's drawn axes to grey the right
-- size slider when a dimension is matched. Exported, not duplicated, to avoid drift.
mod.IsVerticalOrientation = IsVerticalOrientation

-- Orientation-aware MatchGuard. Size sliders are labelled/stored in HORIZONTAL terms,
-- but a match locks the axis the bar is DRAWN on (swapped on a vertical bar); guarding
-- by the slider's own label would grey the wrong field and leave the written one
-- editable, silently dropping the player's change. Both guards are built and picked
-- when the widget asks (not at page build), so flipping orientation with the panel open
-- is honoured. getOri returns the bar's effective orientation.
mod.OrientedMatchGuard = function(barId, propKey, getOri, existingDisabled, existingTooltip)
    local hD, hT, hR = CludesUI.MatchGuard(barId, "Height", existingDisabled, existingTooltip)
    local wD, wT, wR = CludesUI.MatchGuard(barId, "Width", existingDisabled, existingTooltip)
    local function byAxis(sameAxis, swappedAxis)
        return function(...)
            if IsVerticalOrientation(getOri and getOri()) then
                return swappedAxis(...)
            end
            return sameAxis(...)
        end
    end
    if propKey == "Height" then
        return byAxis(hD, wD), byAxis(hT, wT), byAxis(hR, wR)
    end
    return byAxis(wD, hD), byAxis(wT, hT), byAxis(wR, hR)
end

-- Cached empower stage thresholds (set once at empower start, avoids per-frame API call)
local cachedStageThresholds
Inner.stageThresholdsSetters[#Inner.stageThresholdsSetters + 1] = function(val)
    cachedStageThresholds = val
end
-- Reusable CreateColor objects for gradient (avoids per-frame allocation)
local empowerColorA = CreateColor(1, 0, 0, 1)
local empowerColorB = CreateColor(1, 0, 0, 1)

-- Bar gradients use two REUSED color objects so applying one allocates nothing
-- (CreateColor would allocate two tables/call). Re-issued on every color update
-- (cheap, same order as flat bars' SetVertexColor) and never skipped or cached,
-- so it can never go stale.
local _gradColorA = CreateColor(1, 1, 1, 1)
local _gradColorB = CreateColor(1, 1, 1, 1)

local function ApplyBarGradient(ft, direction, br, backdrop, bb, ba, er, eg, eb, ea)
    -- Bar colour only changes on a config edit or threshold/band crossing, but this
    -- runs on every power/health event, so skip when inputs (plus the fill-opacity
    -- multiplier scaling the alphas below) are unchanged -- else four C calls
    -- repaint an identical gradient a dozen times a second. State lives on our own
    -- texture (already carries _erbSetVC/_erbFillOp).
    if
        ft._lgOn
        and ft._lgDir == direction
        and ft._lgFop == ft._erbFillOp
        and ft._lgBr == br
        and ft._lgBg == backdrop
        and ft._lgBb == bb
        and ft._lgBa == ba
        and ft._lgEr == er
        and ft._lgEg == eg
        and ft._lgEb == eb
        and ft._lgEa == ea
    then
        return
    end
    ft._lgOn, ft._lgDir, ft._lgFop = true, direction, ft._erbFillOp
    ft._lgBr, ft._lgBg, ft._lgBb, ft._lgBa = br, backdrop, bb, ba
    ft._lgEr, ft._lgEg, ft._lgEb, ft._lgEa = er, eg, eb, ea
    ft._lfOn = nil -- a gradient invalidates any cached flat colour

    -- Bypass the Fill Opacity SetVertexColor wrapper (if installed): gradient
    -- opacity is carried in the endpoint alphas below, and its re-assert would
    -- fight the corner alphas.
    local rawVC = ft._erbSetVC or ft.SetVertexColor
    rawVC(ft, 1, 1, 1, 1)
    local _fop = ft._erbFillOp
    if _fop then
        ba = (ba or 1) * _fop
        ea = (ea or 1) * _fop
    end
    _gradColorA:SetRGBA(br, backdrop, bb, ba)
    _gradColorB:SetRGBA(er, eg, eb, ea)
    ft:SetGradient(direction, _gradColorA, _gradColorB)
end

-- Flat-color a bar fill (no gradient).
local function ApplyBarFlat(ft, red, green, blue, a)
    -- As ApplyBarGradient: re-asserting an unchanged colour every event is waste.
    a = a or 1
    if ft._lfOn and ft._lfR == red and ft._lfG == green and ft._lfB == blue and ft._lfA == a then
        return
    end
    ft._lfOn, ft._lfR, ft._lfG, ft._lfB, ft._lfA = true, red, green, blue, a
    ft._lgOn = nil -- a flat fill invalidates any cached gradient
    ft:SetVertexColor(red, green, blue, a)
end
-- Shared with CUI_ResourceBars_SwingTimer.lua, which paints its rows the way the
-- GCD bar paints its fill. Exported, not duplicated, so the change-gates stay one.
mod.ApplyBarGradient = ApplyBarGradient
mod.ApplyBarFlat = ApplyBarFlat
mod.SnapXY = SnapXY
mod.CLASS_COLORS = CLASS_COLORS

-- Fill Opacity (continuous bars). Below 100 the fill turns translucent via texture
-- REGION alpha (survives every runtime SetVertexColor/SetGradient writer) and the
-- bg re-anchors to cover ONLY the empty portion, so the world shows through the
-- fill instead of the background. Fully inert at 100 (untouched unless previously
-- applied, _fillOpApplied). Value-blind by design (region alpha + relational
-- anchors only), so it renders identically when values are secret. On ns.
-- AnchorBgToFillEdge: empty side depends on fill direction --
-- VERTICAL_UP bottom-up (empty top), VERTICAL_DOWN top-down (empty bottom),
-- horizontal left-to-right (empty right); anchor is relational to the fill
-- texture's moving edge, so it tracks value changes with no per-frame work.
mod.AnchorBgToFillEdge = function(backdrop, texture, boxHolder, orientation)
    backdrop:ClearAllPoints()
    if orientation == "VERTICAL_UP" then
        backdrop:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", texture, "TOPRIGHT", 0, 0)
    elseif orientation == "VERTICAL_DOWN" or orientation == "VERTICAL" then
        backdrop:SetPoint("TOPLEFT", texture, "BOTTOMLEFT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", 0, 0)
    else
        backdrop:SetPoint("TOPLEFT", texture, "TOPRIGHT", 0, 0)
        backdrop:SetPoint("BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", 0, 0)
    end
end

mod.ApplyFillOpacity = function(barFrame, orientation, fillOpacity)
    local op = fillOpacity or 100
    local scrollBar, backdrop = barFrame._sb, barFrame._bg
    if not scrollBar or not backdrop then
        return
    end
    if op >= 100 then
        if barFrame._fillOpApplied then
            barFrame._fillOpApplied = nil
            local texture = scrollBar:GetStatusBarTexture()
            if texture then
                texture._erbFillOp = nil
                -- Uninstall the wrapper: clearing the shadow key restores the metatable method.
                if texture._erbVCWrapped then
                    texture.SetVertexColor = nil
                    texture._erbVCWrapped = nil
                    texture._erbSetVC = nil
                end
                texture:SetAlpha(1)
            end
            backdrop:ClearAllPoints()
            backdrop:SetAllPoints(scrollBar)
        end
        return
    end
    local texture = scrollBar:GetStatusBarTexture()
    if not texture then
        return
    end
    barFrame._fillOpApplied = true
    -- Alpha is UNIFIED on this client: SetAlpha and SetVertexColor's 4th arg write
    -- the same slot, so any runtime color writer (threshold curves, band colors,
    -- power-type recolors) would wipe a build-time alpha. Shadow SetVertexColor on
    -- this one fill texture with a wrapper that passes args through UNTOUCHED (no
    -- arithmetic, so secret color components flow safely) then re-asserts opacity.
    -- Installed only while below 100; gradient writers bypass it, carrying opacity
    -- in their endpoint alphas.
    texture._erbFillOp = op / 100
    if not texture._erbVCWrapped then
        texture._erbVCWrapped = true
        texture._erbSetVC = texture.SetVertexColor
        texture.SetVertexColor = function(t, ...)
            t._erbSetVC(t, ...)
            local o = t._erbFillOp
            if o then
                t:SetAlpha(o)
            end
        end
    end
    texture:SetAlpha(op / 100)
    mod.AnchorBgToFillEdge(backdrop, texture, scrollBar, orientation)
end

-- Restore a pip/rune to full opacity after Fill Opacity was on. Only called on the
-- 100-or-above build pass while _fillOp is still set, so untouched profiles skip it.
mod.ClearPipFillOpacity = function(pip)
    pip._fillOp = nil
    pip._fill:SetAlpha(1)
    pip._bg:SetAlpha(1)
    local function reset(scrollBar)
        if scrollBar then
            local t = scrollBar:GetStatusBarTexture()
            if t then
                t:SetAlpha(1)
            end
        end
    end
    reset(pip._secretBar)
    reset(pip._secretThreshBar)
    reset(pip._bandResetBar)
    if pip._bandBars then
        for k = 1, #pip._bandBars do
            reset(pip._bandBars[k])
        end
    end
    if pip._sbgAnchored then
        pip._sbgAnchored = nil
        pip._bg:ClearAllPoints()
        pip._bg:SetAllPoints(pip)
    end
end

-- Returns the current empowered stage (0-based) based on progress and cached thresholds
local function GetCurrentEmpowerStage(progress, numStages)
    if not numStages or numStages <= 0 then
        return 0
    end
    local thresholds = cachedStageThresholds
    if not thresholds then
        return 0
    end

    for i = 1, #thresholds do
        if progress < thresholds[i] then
            return i - 1
        end
    end
    return #thresholds
end

-- Returns RGB color for the current empower stage (red -> yellow -> green gradient)
local function GetEmpowerStageColor(stage, maxStages)
    if maxStages <= 1 then
        return 0, 1, 0
    end

    local t = stage / maxStages

    if t < 0.5 then
        return 1, t * 2, 0
    else
        return 1 - (t - 0.5) * 2, 1, 0
    end
end

local function OrientedSize(wid, hgt, orientation)
    if IsVerticalOrientation(orientation) then
        return hgt, wid -- swap width and height for vertical bars
    end
    return wid, hgt
end

local function ApplyBarOrientation(barFrame, orientation)
    if not barFrame then
        return
    end
    if orientation == "VERTICAL_UP" then
        barFrame:SetOrientation("VERTICAL")
        barFrame:SetRotatesTexture(true)
        barFrame:SetReverseFill(false)
    elseif orientation == "VERTICAL_DOWN" then
        barFrame:SetOrientation("VERTICAL")
        barFrame:SetRotatesTexture(true)
        barFrame:SetReverseFill(true)
    else
        barFrame:SetOrientation("HORIZONTAL")
        barFrame:SetRotatesTexture(false)
        barFrame:SetReverseFill(false)
    end
end

-- Bar texture helper
local function ApplyBarTexture(barFrame, texKey)
    if not barFrame then
        return
    end
    local filePath = CludesUI.ResolveTexturePath(_G._CURB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    barFrame:SetStatusBarTexture(filePath)
    -- Blizzard Style: a path swap can mint a new fill object; re-seat the
    -- bar-shape mask on it (memoized per object, so a no-op otherwise).
    if barFrame._blizzBarMask then
        mod.ERB_SeatBlizzMask(barFrame)
    end
end

-- Textured Background: the bar's own texture on a background, tinted by the
-- background colour. Callers repaint the flat colour around it; nil path clears
-- the tint a texture left behind (SetColorTexture keeps it).
function mod.ERB_BgTexture(backdrop, filePath, red, green, blue, a)
    if filePath then
        backdrop:SetTexture(filePath)
        backdrop:SetVertexColor(red, green, blue, a)
        backdrop._erbBgTex = true
    elseif backdrop._erbBgTex then
        backdrop._erbBgTex = nil
        backdrop:SetVertexColor(1, 1, 1, 1)
    end
end

-- Compute pixel-snapped pip geometry for a given frame's effective scale.
-- Returns a table of {x0, x1} pairs (in logical units, snapped to physical
-- pixels) for each pip index 1..numPips. Spacing between every adjacent pair
-- is guaranteed to be exactly pipSp physical pixels at any UI scale.
local function CalcPipGeometry(totalW, numPips, pipSp, widget, esOverride)
    -- esOverride: the same effective scale the caller used to snap the frame's
    -- outer dimensions (falls back to the live es). Removes a 1-px mismatch when
    -- the effective scale changes between the outer SetSize and this layout pass
    -- (reparent, scale chain update); the caller owns the source of truth.
    local es = esOverride or widget:GetEffectiveScale()
    if es <= 0 then
        es = 1
    end
    -- 1 physical pixel in this frame's coordinate space
    local onePixel = Pix.perfect / es

    -- Zero pips happens transiently while zoning (max class-resource count reads 0
    -- mid-load) and the pip division would hard-error: return empty geometry.
    if not numPips or numPips < 1 then
        return {}, 0, onePixel, 0
    end

    -- Snap spacing to nearest whole physical pixel (minimum 1px)
    local spPx = math.max(1, math.floor(pipSp / onePixel + 0.5))

    -- Total physical pixels for the whole bar
    local totalPx = math.floor(totalW / onePixel + 0.5)
    local gapPx = spPx * (numPips - 1)
    local pipPx = totalPx - gapPx
    local basePx = math.floor(pipPx / numPips)
    local extraPx = pipPx - basePx * numPips -- first extraPx pips get +1px

    -- Build per-pip positions in physical pixels, convert to logical units once.
    local slots = {}
    local cursor = 0
    for i = 1, numPips do
        local wid = basePx + (i <= extraPx and 1 or 0)
        local x1 = (cursor + wid) * onePixel
        -- Clamp last pip's right edge to totalW so it never exceeds the container
        if i == numPips and x1 > totalW then
            x1 = totalW
        end
        slots[i] = { x0 = cursor * onePixel, x1 = x1 }
        cursor = cursor + wid + spPx
    end

    return slots, spPx * onePixel, onePixel, totalPx * onePixel
end

-- Border extensions (power, class resource, cast and GCD bars), in UI units
-- along screen axes, including vertical bars.
-- Read only while the bar's style is textured, the only state that shows the
-- rows, so the stored values stay inert after a switch to Solid. Kept out of
-- ns.ERB_EuiBorderPad: size matching ignores it (the extension is meant to
-- overlap a neighbour). Callers pass nil under a stock style.
function mod.ERB_BorderExtents(cfg)
    if not cfg then
        return 0, 0, 0, 0
    end
    local texture = cfg.borderTexture
    if not texture or texture == "" or texture == "solid" then
        return 0, 0, 0, 0
    end
    return cfg.borderExtendTop or 0,
        cfg.borderExtendBottom or 0,
        cfg.borderExtendLeft or 0,
        cfg.borderExtendRight or 0
end

-- Seats a border host frame we created (bf) on its bar (parent). An extent
-- above 0 moves the corresponding edge outwards, each on
-- whole physical pixels at the host's scale (the textured backdrop snaps its
-- own anchors to the same grid); the stamp on bf makes a repeat pass with a
-- live rect a no-op. All 0 (callers that pass none: pips, health, the stock
-- styles): an extended host goes back to SetAllPoints once, and any host whose
-- rect stopped resolving is re-seated the same way -- a bar repositioned by the
-- unlock anchor system loses this frame's SetAllPoints edge (GetLeft() nil,
-- GetWidth() 0) and the border vanishes until re-issued. Build paths only.
function mod.ERB_AnchorBorderHost(bf, hostFrame, topY, bottom, leftX, right)
    topY, bottom, leftX, right = topY or 0, bottom or 0, leftX or 0, right or 0
    if topY > 0 or bottom > 0 or leftX > 0 or right > 0 then
        local es = bf:GetEffectiveScale()
        topY, bottom = Pix.SnapForES(topY, es), Pix.SnapForES(bottom, es)
        leftX, right = Pix.SnapForES(leftX, es), Pix.SnapForES(right, es)
        if
            bf._erbExtT == topY
            and bf._erbExtB == bottom
            and bf._erbExtL == leftX
            and bf._erbExtR == right
            and bf:GetLeft()
        then
            return
        end
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", -leftX, topY)
        bf:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", right, -bottom)
        bf._erbExtT, bf._erbExtB, bf._erbExtL, bf._erbExtR = topY, bottom, leftX, right
    elseif bf._erbExtT or not bf:GetLeft() then
        bf._erbExtT, bf._erbExtB, bf._erbExtL, bf._erbExtR = nil, nil, nil, nil
        bf:SetAllPoints(hostFrame)
    end
end

local function MakePixelBorder(hostFrame, red, green, blue, a, size, textureKey, texOffset, texOffsetY, shiftX, shiftY)
    local alpha = a or 1
    local sz = size or 1
    local bf = CreateFrame("Frame", nil, hostFrame)
    bf:SetAllPoints(hostFrame)
    bf:SetFrameLevel(hostFrame:GetFrameLevel() + 1)

    CludesUI.ApplyBorderStyle(
        bf,
        sz,
        red,
        green,
        blue,
        alpha,
        textureKey or "solid",
        texOffset,
        texOffsetY,
        shiftX,
        shiftY
    )

    return {
        _frame = bf,
        edges = Pix.GetBorders(bf),
        SetColor = function(self, cr, cg, callback, ca)
            CludesUI.SetBorderStyleColor(bf, cr, cg, callback, ca or 1)
        end,
        SetSize = function(self, newSz)
            Pix.SetBorderSize(bf, newSz)
        end,
        SetShown = function(self, isShown)
            if isShown then
                Pix.ShowBorder(bf)
            else
                Pix.HideBorder(bf)
            end
        end,
        -- edgePx: the bar's exact border size (CludesUI.BorderPx), nil for the legacy path.
        -- Extensions from ns.ERB_BorderExtents: full-bar borders only, never pips.
        ApplyStyle = function(
            self,
            newSz,
            cr,
            cg,
            callback,
            ca,
            texKey,
            texOff,
            texOffY,
            sX,
            sY,
            addonKey,
            sizeKey,
            edgePx,
            extTop,
            extBottom,
            extLeft,
            extRight
        )
            -- A bar repositioned by the unlock anchor system loses this frame's
            -- SetAllPoints edge: GetPoint still reports TOPLEFT/BOTTOMRIGHT to the bar,
            -- but the rect stops resolving (GetLeft() nil, GetWidth() 0). The strips are
            -- anchored here, so each one falls back to WHITE8X8's natural 8px on the
            -- dimension it takes from anchors and the border disappears until the border
            -- SIZE changes. Re-seating the host restores it (with the extents, if any).
            mod.ERB_AnchorBorderHost(bf, hostFrame, extTop, extBottom, extLeft, extRight)
            CludesUI.ApplyBorderStyle(
                bf,
                newSz,
                cr,
                cg,
                callback,
                ca or 1,
                texKey or "solid",
                texOff,
                texOffY,
                sX,
                sY,
                addonKey,
                sizeKey,
                nil,
                edgePx
            )
        end,
    }
end

-- Bar creation helpers
local function CreateStatusBar(hostFrame, name, wid, hgt, borderSize, borderR, borderG, borderB, borderA)
    -- Outer container: holds the border and text (never clipped).
    local barFrame = CreateFrame("Frame", name, hostFrame)
    barFrame:SetSize(wid, hgt)
    barFrame:EnableMouse(false)

    -- Inner StatusBar: clips its fill. Inset by a quarter of a physical pixel so
    -- the fill can never bleed past the border at any resolution. A quarter, not
    -- a half: an edge on a pixel centre hits the rasteriser's tie rule and the
    -- fill covers one more pixel on one side than the other.
    local scrollBar = CreateFrame("StatusBar", nil, barFrame)
    local clipInset = Pix.mult * 0.25
    scrollBar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", clipInset, -clipInset)
    scrollBar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -clipInset, clipInset)
    scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    scrollBar:SetClipsChildren(true)
    barFrame._sb = scrollBar

    -- Forward StatusBar methods to the inner bar so callers don't change
    barFrame.SetMinMaxValues = function(_, ...)
        scrollBar:SetMinMaxValues(...)
    end
    barFrame.SetValue = function(_, val)
        -- Native interpolation (opt-in "Smooth Bars"): _smoothing is set only on
        -- bars whose toggle is on; nil elsewhere, so every write lands at once.
        -- The toggle alone decides: callers pass the value only.
        if barFrame._smoothing then
            scrollBar:SetValue(val, barFrame._smoothing)
        else
            scrollBar:SetValue(val)
        end
    end
    barFrame.GetValue = function(_)
        return scrollBar:GetValue()
    end
    barFrame.SetStatusBarTexture = function(_, ...)
        scrollBar:SetStatusBarTexture(...)
    end
    barFrame.GetStatusBarTexture = function(_)
        return scrollBar:GetStatusBarTexture()
    end
    barFrame.SetStatusBarColor = function(_, ...)
        scrollBar:SetStatusBarColor(...)
    end
    barFrame.GetStatusBarColor = function(_)
        return scrollBar:GetStatusBarColor()
    end
    barFrame.SetFillStyle = function(_, ...)
        scrollBar:SetFillStyle(...)
    end
    barFrame.SetOrientation = function(_, ...)
        scrollBar:SetOrientation(...)
    end
    barFrame.SetRotatesTexture = function(_, ...)
        scrollBar:SetRotatesTexture(...)
    end
    barFrame.SetReverseFill = function(_, ...)
        scrollBar:SetReverseFill(...)
    end

    -- Background (inside the clipped area)
    local backdrop = scrollBar:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0x11 / 255, 0x11 / 255, 0x11 / 255, 0.75)
    barFrame._bg = backdrop

    -- Pixel-perfect border (on outer container, not clipped)
    local bSz = borderSize or 1
    barFrame._border = MakePixelBorder(barFrame, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    -- Border extensions: power bar only; nil elsewhere.
    function barFrame:ApplyBorder(
        sz,
        region,
        g,
        b,
        a,
        textureKey,
        texOffset,
        texOffsetY,
        shiftX,
        shiftY,
        addonKey,
        sizeKey,
        behind,
        edgePx,
        extTop,
        extBottom,
        extLeft,
        extRight
    )
        -- "Show Behind": set the border frame level before styling so the textured
        -- backdrop inherits it. +1 draws in front of the fill, level-1 behind it.
        if self._border._frame then
            local pl = self:GetFrameLevel()
            self._border._frame:SetFrameLevel(behind and math.max(0, pl - 1) or (pl + 1))
        end
        self._border:ApplyStyle(
            sz,
            region,
            g,
            b,
            a,
            textureKey,
            texOffset,
            texOffsetY,
            shiftX,
            shiftY,
            addonKey,
            sizeKey,
            edgePx,
            extTop,
            extBottom,
            extLeft,
            extRight
        )
    end

    -- Lift the border above an overlay that draws inside the bar's rect. The
    -- default level (+1 over the bar, strips +1 over that) only clears the
    -- legacy fill; the 12.1 Ebon Might engine slot renders its own StatusBar
    -- deeper in the tree, so it paints over the strips and Border Size/Color
    -- look like they do nothing. "Show Behind" is honored -- that border is
    -- meant to sit under the fill. Idempotent: safe to re-assert every update.
    function barFrame:RaiseBorderAbove(coverLevel, behind)
        local bf = self._border and self._border._frame
        if not bf then
            return
        end
        local lvl = behind and math.max(0, self:GetFrameLevel() - 1) or (coverLevel + 1)
        bf:SetFrameLevel(lvl)
        -- Re-assert on the PP strip container too: it was levelled off the
        -- border frame at creation, and the textured-border backdrop tracks
        -- the border frame's level directly.
        local edges = Pix and Pix.GetBorders and Pix.GetBorders(bf)
        if edges then
            edges:SetFrameLevel(lvl + 1)
        end
        -- A Bottom Separator on this bar (ns.ERB_Separators) stays above it.
        local sep = self._erbSep
        if sep and sep:IsShown() and sep:GetFrameLevel() < lvl + 2 then
            sep:SetFrameLevel(lvl + 2)
        end
    end

    -- Text overlay (above all bar borders)
    local textFrame = CreateFrame("Frame", nil, barFrame)
    textFrame:SetAllPoints(barFrame)
    textFrame:SetFrameLevel(25)
    textFrame:EnableMouse(false)
    local textValue = textFrame:CreateFontString(nil, "OVERLAY")
    SetRBFont(textValue, GetRBFont(), 11)
    textValue:SetTextColor(1, 1, 1, 0.9)
    textValue:SetPoint("CENTER", textFrame, "CENTER")
    barFrame._text = textValue

    return barFrame
end

-- Shared through I so the update chunk needs only one local for this feature.
local PipTextureHelpers = {}

function PipTextureHelpers.SetRange(pip, x0, x1, span, orientation)
    if span <= 0 or x1 <= x0 then
        return
    end
    pip._continuousStart, pip._continuousEnd = x0 / span, x1 / span
    pip._continuousOrientation = orientation
    PipTextureHelpers.SetCoordinates(pip, pip._fill)
end

function PipTextureHelpers.SetCoordinates(pip, texture)
    local first, last = pip._continuousStart, pip._continuousEnd
    if pip._continuousOrientation == "VERTICAL_UP" then
        texture:SetTexCoord(last, 0, first, 0, last, 1, first, 1)
    elseif pip._continuousOrientation == "VERTICAL_DOWN" or pip._continuousOrientation == "VERTICAL" then
        texture:SetTexCoord(first, 1, last, 1, first, 0, last, 0)
    else
        texture:SetTexCoord(first, last, 0, 1)
    end
end

function PipTextureHelpers.Configure(pip, x0, x1, span, orientation)
    if span <= 0 or x1 <= x0 then
        if pip._continuousStart then
            PipTextureHelpers.Reset(pip)
        end
        return
    end
    pip._continuousPath =
        CludesUI.ResolveTexturePath(_G._CURB_BarTextures, pip._texKey, "Interface\\Buttons\\WHITE8x8")
    PipTextureHelpers.SetRange(pip, x0, x1, span, orientation)
end

function PipTextureHelpers.Reset(pip)
    local function RestoreClip(barFrame)
        if not (barFrame and barFrame._continuousClip) then
            return
        end
        barFrame._continuousClip:Hide()
        local fillTex = barFrame:GetStatusBarTexture()
        if fillTex then
            fillTex:SetVertexColor(barFrame:GetStatusBarColor())
            if pip._fillOp and pip._fillOp < 1 then
                fillTex:SetAlpha(pip._fillOp)
            end
        end
    end
    RestoreClip(pip._rechargeBar)
    RestoreClip(pip._secretBar)
    RestoreClip(pip._secretThreshBar)
    RestoreClip(pip._bandResetBar)
    if pip._bandBars then
        for k = 1, #pip._bandBars do
            RestoreClip(pip._bandBars[k])
        end
    end
    pip._fill:SetTexCoord(0, 1, 0, 1)
    pip._continuousStart, pip._continuousEnd = nil, nil
    pip._continuousOrientation, pip._continuousPath = nil, nil
end

-- A native StatusBar rewrites its UVs on value changes. Clip a full pip slice
-- to its moving fill instead; anchors accept secret geometry without reading it.
function PipTextureHelpers.DrawFill(pip, barFrame)
    if not (pip._continuousStart and barFrame and barFrame:IsShown()) then
        return
    end
    local fillTex = barFrame:GetStatusBarTexture()
    if not fillTex then
        return
    end
    local clip = barFrame._continuousClip
    if not clip then
        clip = CreateFrame("Frame", nil, barFrame)
        clip:SetClipsChildren(true)
        local canvas = CreateFrame("Frame", nil, clip)
        canvas:SetAllPoints(pip._fill)
        local texture = canvas:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
        clip._canvas, clip._fill = canvas, texture
        barFrame._continuousClip = clip
    end
    if clip._nativeFill ~= fillTex then
        clip:ClearAllPoints()
        clip:SetAllPoints(fillTex)
        clip._nativeFill = fillTex
    end
    local level = barFrame:GetFrameLevel()
    if clip._level ~= level then
        clip:SetFrameLevel(level)
        clip._canvas:SetFrameLevel(level)
        clip._level = level
    end
    local texture = clip._fill
    if clip._path ~= pip._continuousPath then
        texture:SetTexture(pip._continuousPath)
        clip._path, clip._first = pip._continuousPath, nil
    end
    if
        clip._first ~= pip._continuousStart
        or clip._last ~= pip._continuousEnd
        or clip._orientation ~= pip._continuousOrientation
    then
        PipTextureHelpers.SetCoordinates(pip, texture)
        clip._first, clip._last, clip._orientation =
            pip._continuousStart, pip._continuousEnd, pip._continuousOrientation
    end
    texture:SetVertexColor(barFrame:GetStatusBarColor())
    if pip._fillOp and pip._fillOp < 1 then
        texture:SetAlpha(pip._fillOp)
    end
    if pip._blizzMask then
        mod.ERB_MaskTex(texture, pip._blizzMask)
    end
    fillTex:SetAlpha(0)
    clip:Show()
end

-- Create a single pip (for combo points, holy power, etc.)
local function CreatePip(hostFrame, wid, hgt, position, borderSize, borderR, borderG, borderB, borderA)
    local pip = CreateFrame("Frame", nil, hostFrame)
    pip:SetSize(wid, hgt)

    local backdrop = pip:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    pip._bg = backdrop

    local fillTex = pip:CreateTexture(nil, "ARTWORK")
    fillTex:SetAllPoints()
    fillTex:SetColorTexture(1, 1, 1, 1)
    pip._fill = fillTex
    pip._texKey = nil -- current bar texture key

    -- Pixel-perfect border with variable size
    local bSz = borderSize or 1
    pip._border = MakePixelBorder(pip, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function pip:ApplyBorder(
        sz,
        region,
        g,
        b,
        a,
        textureKey,
        texOffset,
        texOffsetY,
        shiftX,
        shiftY,
        addonKey,
        sizeKey,
        edgePx
    )
        self._border:ApplyStyle(
            sz,
            region,
            g,
            b,
            a,
            textureKey,
            texOffset,
            texOffsetY,
            shiftX,
            shiftY,
            addonKey,
            sizeKey,
            edgePx
        )
    end

    function pip:ApplyTexture(texKey)
        self._texKey = texKey
        local filePath =
            CludesUI.ResolveTexturePath(_G._CURB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
        self._fill:SetTexture(filePath)
        if self._rechargeBar then
            self._rechargeBar:SetStatusBarTexture(filePath)
        end
        -- Blizzard Style: a path swap mints a new recharge fill; re-seat the mask.
        if self._blizzMask then
            mod.ERB_MaskPip(self, self._blizzMask)
        end
    end

    pip._active = false
    pip._idx = position

    function pip:SetActive(isActive, red, green, blue, a)
        self._active = isActive
        if isActive then
            self._fill:SetVertexColor(red, green, blue, a or 1)
            -- Fill Opacity on: re-assert fill alpha (unified channel, wiped by the
            -- SetVertexColor above) and hide bg so the translucent fill shows the
            -- world. _fillOp is nil unless below 100 (inert default). At
            -- factor 1 (Background on individual pips) the colour alpha
            -- written above already is the fill alpha, so it is kept.
            if self._fillOp then
                if self._fillOp < 1 then
                    self._fill:SetAlpha(self._fillOp)
                end
                self._bg:SetAlpha(0)
            end
            self._fill:Show()
        else
            self._fill:Hide()
            if self._fillOp then
                self._bg:SetAlpha(1)
            end
        end
    end

    return pip
end

-- Optional gap-fill layer ("Bar Spacing" color). Opt-in: disabled draws nothing,
-- gaps keep showing the full-bar background; enabled places one texture per
-- inter-pip gap so spacing colors independently of the bar background. Only
-- READS the already-computed pip slot positions, never changes pip sizing or
-- spacing geometry. On ERB.

-- Per-pip empty-slot backdrop color. At Fill Opacity 100 it's just the Empty Bar
-- Overlay tint (bgR/G/B/A, dark theme override). Below 100 the full-bar backdrop
-- is hidden (can't hole itself behind active pips, would tint translucent fills),
-- so the overlay texture -- already covering exactly the empty regions via
-- SetActive/the secret fill-edge anchor -- takes over: composite the bar
-- background UNDER the overlay tint so empty slots keep the same stacked look.
-- force: Background on individual pips (ns.ERB_PipBgOn), which hides the
-- full-bar backdrop at every Fill Opacity, so the composite applies at 100 too.
function ERB.PipBgColor(sp, force)
    local ovR, ovG, ovB, ovA = sp.bgR, sp.bgG, sp.bgB, sp.bgA
    if sp.darkTheme then
        local dr, dg, saved = CludesUI.GetDarkModeBg()
        ovR, ovG, ovB, ovA = dr, dg, saved, DARK_BG_A
    end
    ovR, ovG, ovB, ovA = ovR or 0, ovG or 0, ovB or 0, ovA or 0
    if not force and (sp.fillOpacity or 100) >= 100 then
        return ovR, ovG, ovB, ovA
    end
    local bbR, bbG, bbB, bbA
    if sp.darkTheme then
        bbR, bbG, bbB, bbA = 0, 0, 0, 1
    else
        bbR, bbG, bbB, bbA = sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5
    end
    -- Standard alpha compositing: overlay OVER bar background
    local a = ovA + bbA * (1 - ovA)
    if a <= 0 then
        return bbR, bbG, bbB, 0
    end
    local region = (ovR * ovA + bbR * bbA * (1 - ovA)) / a
    local g = (ovG * ovA + bbG * bbA * (1 - ovA)) / a
    local b = (ovB * ovA + bbB * bbA * (1 - ovA)) / a
    return region, g, b, a
end

function ERB.ApplyGapFills(widget, slots, total, isVertical, isReversed, sp, pipBg)
    local fills = widget._gapFills
    -- Pip/rune Fill Opacity hides the full-bar backdrop (would tint translucent
    -- fills from behind), so the gap strips take over in bar-bg color even with
    -- "Bar Spacing" color disabled. Background on individual pips (pipBg) keeps
    -- the gaps clear instead: only the "Bar Spacing" color paints them then.
    local fillOpActive = not pipBg and (sp.fillOpacity or 100) < 100
    if not ((sp.gapColorEnabled or fillOpActive) and slots and total and total > 1) then
        if fills then
            for i = 1, #fills do
                fills[i]:Hide()
            end
        end
        return
    end
    if not fills then
        fills = {}
        widget._gapFills = fills
    end
    local red, green, blue, a
    if sp.gapColorEnabled then
        red, green, blue, a = sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1
    elseif sp.darkTheme then
        red, green, blue, a = 0, 0, 0, 1
    else
        red, green, blue, a = sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5
    end
    local num = 0
    for i = 1, total - 1 do
        local x1 = slots[i].x1 -- trailing edge of pip i
        local x0 = slots[i + 1].x0 -- leading edge of pip i+1
        local gapLen = x0 - x1
        if gapLen and gapLen > 0 then
            num = num + 1
            local texture = fills[num]
            if not texture then
                texture = widget:CreateTexture(nil, "BACKGROUND", nil, 0) -- above _barBg (sublevel -1)
                fills[num] = texture
            end
            texture:SetColorTexture(red, green, blue, a)
            texture:ClearAllPoints()
            if isVertical then
                if isReversed then
                    texture:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 0, x1)
                    texture:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, x1)
                else
                    texture:SetPoint("TOPLEFT", widget, "TOPLEFT", 0, -x1)
                    texture:SetPoint("TOPRIGHT", widget, "TOPRIGHT", 0, -x1)
                end
                texture:SetHeight(gapLen)
            else
                texture:SetPoint("TOPLEFT", widget, "TOPLEFT", x1, 0)
                texture:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", x1, 0)
                texture:SetWidth(gapLen)
            end
            texture:Show()
        end
    end
    for i = num + 1, #fills do
        fills[i]:Hide()
    end
end

-------------------------------------------------------------------------------
--  Main frame construction
-------------------------------------------------------------------------------
local pips = {}
local runeFrames = {}

-------------------------------------------------------------------------------
--  Smooth animation helper for actual bar scale / offset changes
-------------------------------------------------------------------------------
local _barAnimTimers = {}
local BAR_ANIM_DURATION = 0.18

local function SmoothBarAnimate(widget, key, targetVal, applyFn)
    if not widget then
        return
    end
    if not _barAnimTimers[widget] then
        _barAnimTimers[widget] = {}
    end
    if _barAnimTimers[widget][key] then
        _barAnimTimers[widget][key]:Cancel()
        _barAnimTimers[widget][key] = nil
    end
    local startVal = widget["_barAnim_" .. key] or targetVal
    if math.abs(startVal - targetVal) < 0.001 then
        widget["_barAnim_" .. key] = targetVal
        applyFn(targetVal)
        return
    end
    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local t = math.min(elapsed / BAR_ANIM_DURATION, 1)
        t = 1 - (1 - t) * (1 - t) -- ease-out quad
        local val = startVal + (targetVal - startVal) * t
        widget["_barAnim_" .. key] = val
        applyFn(val)
        if t >= 1 then
            widget["_barAnim_" .. key] = targetVal
            ticker:Cancel()
            if _barAnimTimers[widget] then
                _barAnimTimers[widget][key] = nil
            end
        end
    end)
    _barAnimTimers[widget][key] = ticker
end

local function BuildMainFrame()
    if mainFrame then
        return mainFrame
    end

    local g = ERB.db.profile.general or DEFAULTS.profile.general

    SetMainFrame(CreateFrame("Frame", "CludesUIResourceBarsFrame", UIParent))
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", g.anchorX or 0, g.anchorY or -100)
    mainFrame:SetSize(1, 1) -- invisible anchor point
    mainFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
    mainFrame:SetFrameLevel(5)

    return mainFrame
end

-- Per-spec bar enable check. Per-spec enables live in Spec Overrides (they flip
-- cfg.enabled per spec), so the disabledSpecs filter is permanently inert. Kept
-- as a function so call sites stand.
local function IsSpecDisabled()
    return false
end

-- Is the power bar effectively hidden right now? True when it leaves no visible slot:
-- globally disabled, filtered for the spec, spec has no primary power, hidden per druid
-- form, or hidden by "Hide Power Bar if Resource". Mirrors what ResolveShiftDirPower
-- reacts to plus the dynamic hidePowerIfResource/per-form toggles. Gates features shown
-- only in the power bar's absence (e.g. class resource "Resource Text").
local function IsPowerBarHidden()
    local p = ERB and ERB.db and ERB.db.profile
    if not p then
        return false
    end
    local pp = p.primary
    if not pp then
        return true
    end
    if pp.enabled == false then
        return true
    end
    if IsSpecDisabled(pp) then
        return true
    end
    if _G._CURB_BarHiddenByForm(pp) then
        return true
    end -- druid per-form bar disable
    if not GetPrimaryPowerType() then
        return true
    end
    if
        p.secondary
        and p.secondary.hidePowerIfResource
        and p.secondary.enabled ~= false
        and GetSecondaryResource()
    then
        return true
    end
    return false
end

Inner._erbEventFrame, Inner._totemBorderOverlays = _erbEventFrame, _totemBorderOverlays
Inner.ApplyBarFlat, Inner.ApplyBarGradient = ApplyBarFlat, ApplyBarGradient
Inner.ApplyBarOrientation, Inner.ApplyBarTexture = ApplyBarOrientation, ApplyBarTexture
Inner.BuildMainFrame, Inner.CalcPipGeometry, Inner.CreatePip = BuildMainFrame, CalcPipGeometry, CreatePip
Inner.CreateStatusBar, Inner.empowerColorA = CreateStatusBar, empowerColorA
Inner.empowerColorB, Inner.GetCurrentEmpowerStage = empowerColorB, GetCurrentEmpowerStage
Inner.GetEmpowerStageColor, Inner.IsPowerBarHidden = GetEmpowerStageColor, IsPowerBarHidden
Inner.IsSpecDisabled, Inner.IsVerticalOrientation = IsSpecDisabled, IsVerticalOrientation
Inner.MakePixelBorder, Inner.OrientedSize, Inner.pips = MakePixelBorder, OrientedSize, pips
Inner.runeFrames, Inner.secondaryBarTicks = runeFrames, secondaryBarTicks
Inner.secondaryPipTicks, Inner.SmoothBarAnimate = secondaryPipTicks, SmoothBarAnimate
Inner.PipTextureHelpers = PipTextureHelpers
Inner.broken = false
