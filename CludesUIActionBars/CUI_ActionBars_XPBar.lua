if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI Action Bars - XP Bar
--  The XP bar's own runtime: its frame art styles and profession flipbook
--  fill, the dividers and Smart Ticks, the Quest XP Overlay, the XP / rested
--  update and tooltip, the text positions (texts in and around the bar, each
--  showing one or more items, with the session clock, XP rate, completed
--  quest and time this level trackers behind them), and the style getter
--  and setter the XP Bar options tab uses. What it shares with the reputation and House Favor bars
--  (the data bar frame, layout, border, Center text placement, visibility,
--  hover and Unlock Mode) is in CUI_ActionBars_DataBars.lua and the main
--  file, which load first and call into this file through ns at run time.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local ABAR = mod.EAB
local EAB_VTABLE = mod.EAB_VTABLE
local BAR_LOOKUP = mod.BAR_LOOKUP
local dataBarFrames = mod.dataBarFrames
local ApplyDataBarLayout = mod.ApplyDataBarLayout
local CreateDataBarFrame = mod.CreateDataBarFrame
local ResolveBorderThickness = mod.ResolveBorderThickness
local Pix = CludesUI.PP
local ipairs, pairs = ipairs, pairs
local floor, min, max = math.floor, math.min, math.max

-- XP bar colors
local XP_BAR_COLORS = {
    xpRested = { r = 0.00, g = 0.44, b = 0.87 }, -- shaman blue (XP when rested)
    xpNoRest = { r = 0.60, g = 0.40, b = 0.85 }, -- purple (XP when no rested)
    xpRestedBG = { r = 0.15, g = 0.30, b = 0.60 }, -- dark blue (rested overlay)
    gradStart = { r = 0.60, g = 0.40, b = 0.85, a = 1 }, -- Gradient fill: the purple
    gradEnd = { r = 0.00, g = 0.44, b = 0.87, a = 1 }, -- into the rested blue
}

-- Fill Style's gradients (s.fillGradient = "HORIZONTAL" | "VERTICAL"; nil = a
-- flat colour): the direction and both colours (s.fillGradStart /
-- s.fillGradEnd, the defaults above until set). Direction nil = no gradient.
function mod.XPBarGradient(cfg)
    local direction = cfg and cfg.fillGradient
    if direction ~= "HORIZONTAL" and direction ~= "VERTICAL" then
        direction = nil
    end
    local a = (cfg and cfg.fillGradStart) or XP_BAR_COLORS.gradStart
    local b = (cfg and cfg.fillGradEnd) or XP_BAR_COLORS.gradEnd
    return direction, a.r or 1, a.g or 1, a.b or 1, a.a or 1, b.r or 1, b.g or 1, b.b or 1, b.a or 1
end

-- Paints the fill texture from the start colour to the end colour
-- (Horizontal: left to right; Vertical: bottom to top), only when the
-- direction, a colour or the texture changed. A flat colour (the fill's
-- SetStatusBarColor) overwrites it and drops the memo, as does a layout pass.
local _xpGradA, _xpGradB = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)
local function XPPaintGradient(barFrame, direction, sr, sg, scrollBar, sa, er, eg, eb, ea)
    local texture = barFrame:GetStatusBarTexture()
    if not texture then
        return
    end
    local m = barFrame._xpGrad
    if
        m
        and m.on
        and m.tex == texture
        and m.dir == direction
        and m[1] == sr
        and m[2] == sg
        and m[3] == scrollBar
        and m[4] == sa
        and m[5] == er
        and m[6] == eg
        and m[7] == eb
        and m[8] == ea
    then
        return
    end
    if not m then
        m = {}
        barFrame._xpGrad = m
    end
    m.on, m.tex, m.dir = true, texture, direction
    m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8] = sr, sg, scrollBar, sa, er, eg, eb, ea
    barFrame:SetStatusBarColor(1, 1, 1, 1)
    _xpGradA:SetRGBA(sr, sg, scrollBar, sa)
    _xpGradB:SetRGBA(er, eg, eb, ea)
    texture:SetGradient(direction, _xpGradA, _xpGradB)
end

-------------------------------------------------------------------------------
--  XP bar art styles (the XP Bar tab's style selector) and the profession
--  fill (the XP Bar tab's Fill cog). Both opt-in, saved on the XP bar's
--  profile settings:
--    s.xpArt  = nil (the CludesUI bar) | "prof" (the Professions skill-bar
--               frame) | "forever" (WoW Forever's bronze border, the one the
--               chat panel and the Damage Meters windows wear; Forever only)
--    s.fvFill = nil | a Skillbar_Fill_Flipbook_* atlas, tiled at its own
--               proportions (s.fvFillStretch: one copy across the bar);
--               it plays once on each XP gain unless s.fvFillSmart is
--               false, or loops while s.fvFillAnim is true
--  Applied from ApplyDataBarLayout only (style and layout changes); an XP update
--  only plays the smart flash. A bar that never opted in reads two fields per
--  layout; leaving a style undoes its art once. On ns: ApplyDataBarLayout
--  (CUI_ActionBars_DataBars.lua) and the dividers below call into it.
-------------------------------------------------------------------------------
mod._XPArtAtlas = { prof = "Professions-skillbar-frame" }
-- Fit of each frame around the bar (px): cap share of a flat atlas, overlay
-- offsets, top / bottom rail reach, divider tick inset and solid-tick reach,
-- fill / trough end tucks, fill vertical inset. The Forever border (ring) has
-- only the divider fit: the ticks start past its line.
mod._XPArtFit = {
    prof = {
        capFrac = 0.2,
        offX = -2,
        offY = -2,
        top = 0,
        bot = -3,
        tickInset = 4,
        solidExt = 2,
        endInset = 0,
        bgInset = 2,
        fillV = 1,
    },
    forever = { ring = true, tickInset = 1, solidExt = 0 },
}

-- The fit (and frame atlas) of the XP bar's art style, or nil while it shows
-- the CludesUI bar or the style's art is missing on this client. A frame
-- style is horizontal art (nil on a vertical bar); the Forever border frames
-- either orientation.
function mod.XPArtFit(cfg)
    local art = cfg and cfg.xpArt
    if not art then
        return nil
    end
    if art == "forever" then
        return CludesUI.ForeverBorderOK() and mod._XPArtFit.forever or nil
    end
    if (cfg.orientation or "HORIZONTAL") ~= "HORIZONTAL" then
        return nil
    end
    local atlasName = mod._XPArtAtlas[art]
    if not (atlasName and C_Texture.GetAtlasInfo(atlasName)) then
        return nil
    end
    return mod._XPArtFit[art], atlasName
end

-- A bar-frame atlas on `overlay` at any width. An atlas with sliceData keeps
-- its own slice margins (only the middle stretches); a flat one gets a manual
-- 3-slice: fixed caps (fit.capFrac of the art, drawn undistorted), a uniform
-- stretched middle, and the bottom rail mirrored from the top so both match.
function mod._XPFrameSlice(overlayFrame, atlasName, fitWidth)
    local details = C_Texture.GetAtlasInfo(atlasName)
    local sd = details and details.sliceData
    overlayFrame._frameTex = overlayFrame._frameTex or overlayFrame:CreateTexture(nil, "OVERLAY")
    local tx = overlayFrame._frameTex
    if sd then
        if overlayFrame._flat then
            for _, t in pairs(overlayFrame._flat) do
                t:Hide()
            end
        end
        tx:ClearAllPoints()
        tx:SetAllPoints(overlayFrame)
        tx:SetAtlas(atlasName)
        tx:SetTextureSliceMargins(
            sd.marginLeft or 0,
            sd.marginTop or 0,
            sd.marginRight or 0,
            sd.marginBottom or 0
        )
        tx:SetTextureSliceMode(sd.sliceMode or 0)
        tx:Show()
        return
    end
    tx:Hide()
    local cfg = overlayFrame._flat
    if not cfg then
        cfg = {}
        for _, k in ipairs({ "TL", "TM", "TR", "BL", "BM", "BR" }) do
            local t = overlayFrame:CreateTexture(nil, "OVERLAY")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            cfg[k] = t
        end
        overlayFrame._flat = cfg
    end
    local lineColor, restColor, textColor, bc =
        details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
    local du = restColor - lineColor
    local capFrac = max(0.02, min(0.48, fitWidth.capFrac))
    local lMid, rMid = lineColor + du * capFrac, restColor - du * capFrac
    local midU, band = (lineColor + restColor) / 2, du * 0.004
    local midValue = (textColor + bc) / 2
    local oh = overlayFrame:GetHeight()
    if not oh or oh <= 0 then
        oh = details.height or 20
    end
    local scale = (details.height and details.height > 0) and (oh / details.height) or 1
    local capW = capFrac * (details.width or 0) * scale
    if capW <= 0 then
        capW = oh
    end
    local file = details.file or details.filename
    for _, t in pairs(cfg) do
        t:SetTexture(file)
        t:ClearAllPoints()
    end
    -- Each column samples the TOP half of the art; the bottom row samples the
    -- same rail flipped, so the two edges always match.
    cfg.TL:SetTexCoord(lineColor, lMid, textColor, midValue)
    cfg.TL:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT")
    cfg.TL:SetPoint("BOTTOMLEFT", overlayFrame, "LEFT")
    cfg.TL:SetWidth(capW)
    cfg.BL:SetTexCoord(lineColor, lMid, midValue, textColor)
    cfg.BL:SetPoint("TOPLEFT", overlayFrame, "LEFT")
    cfg.BL:SetPoint("BOTTOMLEFT", overlayFrame, "BOTTOMLEFT")
    cfg.BL:SetWidth(capW)
    cfg.TR:SetTexCoord(rMid, restColor, textColor, midValue)
    cfg.TR:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT")
    cfg.TR:SetPoint("BOTTOMRIGHT", overlayFrame, "RIGHT")
    cfg.TR:SetWidth(capW)
    cfg.BR:SetTexCoord(rMid, restColor, midValue, textColor)
    cfg.BR:SetPoint("TOPRIGHT", overlayFrame, "RIGHT")
    cfg.BR:SetPoint("BOTTOMRIGHT", overlayFrame, "BOTTOMRIGHT")
    cfg.BR:SetWidth(capW)
    cfg.TM:SetTexCoord(midU - band, midU + band, textColor, midValue)
    cfg.TM:SetPoint("TOPLEFT", cfg.TL, "TOPRIGHT")
    cfg.TM:SetPoint("BOTTOMRIGHT", cfg.TR, "BOTTOMLEFT")
    cfg.BM:SetTexCoord(midU - band, midU + band, midValue, textColor)
    cfg.BM:SetPoint("TOPLEFT", cfg.BL, "TOPRIGHT")
    cfg.BM:SetPoint("BOTTOMRIGHT", cfg.BR, "BOTTOMLEFT")
    for _, t in pairs(cfg) do
        t:Show()
    end
end

-- The flipbook's idle frame (frame 0 of 2 columns x `rows`), drawn from the
-- sheet file: an atlas-mode texture does not take sheet coords in SetTexCoord.
function mod._XPFlipStatic(texture, details, rowList)
    texture:SetTexture(details.file or details.filename)
    local l, region, t, b =
        details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
    texture:SetTexCoord(l, l + (region - l) / 2, t, t + (b - t) / rowList)
end

-- Flipbooks whose first frames start abruptly: their pass fades in as slowly
-- as it fades out.
mod._XPFlipSlowIn = {
    Skillbar_Fill_Flipbook_Jewelcrafting = true,
    Skillbar_Fill_Flipbook_Leatherworking = true,
}

-- The profession flipbook over the XP fill (s.fvFill), shown only up to the
-- fill's edge (the plain fill hides under it) through a holder-sized mask
-- whose right edge rides the fill's, moved by the bar itself on every value
-- change. The art (the client's skill bar: 2 columns, a row per 34 px of the
-- atlas's height, 856 x 34 px frames, 2 s per pass) is tiled at its own
-- proportions: copies scaled to the bar's height side by side, the last one
-- cut by the mask, which also ends at the bar's edge. Stretch to Bar
-- (s.fvFillStretch) draws one copy across the whole bar instead. A tile is an
-- idle frame behind and an animated layer in front with its own animation
-- groups; every tile is started in the same pass, so they stay in step.
-- Animate on XP Gain (on unless s.fvFillSmart is false) fades one pass in
-- over the idle frame, holds its last frame and fades back out; Loop
-- Animation (s.fvFillAnim, off by default; the options turn one off when the
-- other goes on) plays it on repeat instead. Laid out on layout passes only;
-- horizontal bars only (the art is horizontal).
local FLIP_MAX_TILES = 24 -- a very long, thin bar widens its tiles past this

-- One tile, masked by the reveal, with its one-pass and looping groups.
local function NewFlipTile(barFrame, mask)
    local tbl = {}
    tbl.idle = barFrame:CreateTexture(nil, "OVERLAY", nil, 0)
    tbl.flip = barFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    tbl.idle:AddMaskTexture(mask)
    tbl.flip:AddMaskTexture(mask)
    local function Book(set)
        local fb = set:CreateAnimation("FlipBook")
        fb:SetTarget(tbl.flip)
        fb:SetDuration(2)
        fb:SetFlipBookColumns(2)
        fb:SetFlipBookFrameWidth(0)
        fb:SetFlipBookFrameHeight(0)
        return fb
    end
    -- One pass: the flipbook and its fade-in together, then the last frame
    -- held and faded out onto the idle frame behind it. The layer rests at
    -- alpha 0 between passes.
    local firstRun = barFrame:CreateAnimationGroup()
    firstRun._fb = Book(firstRun)
    local fadeIn = firstRun:CreateAnimation("Alpha")
    fadeIn:SetTarget(tbl.flip)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    firstRun._fadeIn = fadeIn
    local fadeOut = firstRun:CreateAnimation("Alpha")
    fadeOut:SetTarget(tbl.flip)
    fadeOut:SetOrder(2)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(0.2)
    fadeOut:SetDuration(0.5)
    tbl.once = firstRun
    local loop = barFrame:CreateAnimationGroup()
    loop._fb = Book(loop)
    loop:SetLooping("REPEAT")
    tbl.loop = loop
    return tbl
end

local function HideFlipTile(tbl)
    tbl.once:Stop()
    tbl.loop:Stop()
    tbl.flip:Hide()
    tbl.idle:Hide()
end

-- A tile's layer at x across the bar, tw wide, the bar's full height.
local function PlaceFlipLayer(region, barFrame, posX, tw)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", barFrame, "TOPLEFT", posX, 0)
    region:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", posX, 0)
    region:SetWidth(tw)
end

function mod.ApplyXPFlipFill(widget, cfg)
    local barFrame = widget._bar
    local texture = barFrame:GetStatusBarTexture()
    local atlasName = (cfg.orientation or "HORIZONTAL") == "HORIZONTAL" and cfg.fvFill
    local details = atlasName and C_Texture.GetAtlasInfo(atlasName)
    local tiles = widget._fvTiles
    if not details then
        if widget._fvFlipOn then
            widget._fvFlipOn, widget._fvFlipSmart, widget._fvTileN, widget._fvFlipAtlas = nil, nil, nil, nil
            for index = 1, #tiles do
                HideFlipTile(tiles[index])
            end
            texture:SetAlpha(1)
        end
        return
    end
    local mask = widget._fvFlipMask
    if not tiles then
        -- The reveal: a fixed, holder-sized rect, never the fill's own (that
        -- is zero-wide at no XP, where a mask samples undefined; this one
        -- then sits wholly left of the bar).
        mask = barFrame:CreateMaskTexture()
        mask:SetTexture(
            "Interface\\Buttons\\WHITE8x8",
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE",
            "NEAREST"
        )
        widget._fvFlipMask = mask
        tiles = {}
        widget._fvTiles = tiles
    end
    -- The holder's size covers the bar inside it, whatever the art style's insets.
    mask:ClearAllPoints()
    mask:SetPoint("RIGHT", texture, "RIGHT")
    mask:SetSize(widget:GetSize())

    -- Rows differ per atlas (Enchanting 37, Jewelcrafting 22, the rest 30).
    local rowList = max(1, floor(details.height / 34 + 0.5))
    -- Tile width: a frame's width at the bar's height, snapped to whole
    -- pixels so neighbours meet exactly; one bar-wide copy to stretch.
    local bw, bh = barFrame:GetSize()
    local num, tw = 1, bw
    if not cfg.fvFillStretch and bh > 0 then
        tw = max(1, Pix.Scale(bh * (details.width / 2) / (details.height / rowList)))
        num = max(1, math.ceil(bw / tw))
        if num > FLIP_MAX_TILES then
            num = FLIP_MAX_TILES
            tw = bw / num
        end
    end
    -- A new tile count or art restarts every tile together.
    local resync = num ~= widget._fvTileN or atlasName ~= widget._fvFlipAtlas
    for index = #tiles + 1, num do
        tiles[index] = NewFlipTile(barFrame, mask)
    end
    for index = num + 1, #tiles do
        HideFlipTile(tiles[index])
    end
    local fadeIn = mod._XPFlipSlowIn[atlasName] and 0.5 or 0.25
    for index = 1, num do
        local tbl = tiles[index]
        if resync then
            tbl.once:Stop()
            tbl.loop:Stop()
        end
        if tbl.atlas ~= atlasName then
            tbl.once._fb:SetFlipBookRows(rowList)
            tbl.once._fb:SetFlipBookFrames(rowList * 2)
            tbl.loop._fb:SetFlipBookRows(rowList)
            tbl.loop._fb:SetFlipBookFrames(rowList * 2)
            tbl.once._fadeIn:SetDuration(fadeIn)
            tbl.flip:SetAtlas(atlasName)
            mod._XPFlipStatic(tbl.idle, details, rowList)
            tbl.atlas = atlasName
        end
        local posX = (index - 1) * tw
        PlaceFlipLayer(tbl.flip, barFrame, posX, tw)
        PlaceFlipLayer(tbl.idle, barFrame, posX, tw)
        tbl.idle:Show()
    end
    widget._fvFlipOn, widget._fvTileN, widget._fvFlipAtlas = true, num, atlasName
    texture:SetAlpha(0)

    local loopOn = cfg.fvFillAnim == true
    local smart = not loopOn and cfg.fvFillSmart ~= false
    widget._fvFlipSmart = smart or nil
    for index = 1, num do
        local tbl = tiles[index]
        if loopOn then
            tbl.once:Stop()
            tbl.flip:SetAlpha(1)
            tbl.flip:Show()
            if not tbl.loop:IsPlaying() then
                tbl.loop:Play()
            end
        else
            -- Smart: a running pass carries on; static: the idle frame alone.
            tbl.loop:Stop()
            tbl.flip:SetAlpha(0)
            if smart then
                tbl.flip:Show()
            else
                tbl.once:Stop()
                tbl.flip:Hide()
            end
        end
    end
end

-- Smart fill: one pass of the flipbook on an XP gain (UpdateXPBar), on every
-- tile together; a gain during a pass lets it finish.
function mod.PlayXPFlipOnce(widget)
    local tiles, num = widget._fvTiles, widget._fvTileN
    if not (tiles and num) or tiles[1].once:IsPlaying() then
        return
    end
    for index = 1, num do
        tiles[index].once:Play()
    end
end

-- The Forever style: WoW Forever's bronze border (CludesUI.ForeverBorder)
-- in place of our 1px line, its outer edge on the bar's edge as on the
-- Damage Meters windows, so size matching and snapping are unchanged. The
-- fill, rested bar and trough start FOREVER_BORDER.fill in from that edge
-- (under the line's inner shadow, their square corners inside the chamfers)
-- and keep the bar's own texture and colours. Built once on its own child
-- above the fill (holder+1) and the ticks (holder+2).
local function ApplyXPForeverBorder(widget, barFrame, backdrop, rb)
    local owner = widget._fvRingHost
    if not owner then
        owner = CreateFrame("Frame", nil, widget)
        owner:SetAllPoints(widget)
        owner:EnableMouse(false)
        widget._fvRing = CludesUI.ForeverBorder(owner)
        CludesUI.ForeverBorderSeat(widget._fvRing, widget)
        widget._fvRingHost = owner
    end
    owner:SetFrameLevel(widget:GetFrameLevel() + 3)
    owner:Show()
    local e = CludesUI.FOREVER_BORDER.fill
    Pix.SetInside(barFrame, widget, e, e)
    Pix.SetInside(backdrop, widget, e, e)
    if rb then
        Pix.SetInside(rb, widget, e, e)
    end
end

-- The XP bar's art style. frame._xpArtOn names the style on the bar ("frame"
-- art or the Forever "ring"); leaving it undoes its pieces once (the layout
-- already restored the fill and rested textures), and back on the CludesUI
-- bar the insets and the plain border return unless Custom Border owns the
-- edge.
local function ApplyXPArt(widget, cfg)
    local fitWidth, atlasName = mod.XPArtFit(cfg)
    local barFrame, backdrop, rb = widget._bar, widget._bg, widget._restedBar
    local line = widget._border and widget._border._frame
    local kindName = fitWidth and (fitWidth.ring and "ring" or "frame") or nil
    local was = widget._xpArtOn
    if was and was ~= kindName then
        widget._xpArtOn = nil
        if was == "frame" then
            widget._fvOverlay:Hide()
            backdrop:SetTextureSliceMargins(0, 0, 0, 0)
            backdrop:SetTexCoord(0, 1, 0, 1)
            backdrop:SetColorTexture(0.06, 0.06, 0.08, 0.85)
        else
            widget._fvRingHost:Hide()
        end
        if not kindName then
            Pix.SetInside(barFrame, widget, 1, 1)
            Pix.SetInside(backdrop, widget, 1, 1)
            if rb then
                Pix.SetInside(rb, widget, 1, 1)
            end
            if line and not cfg.customBorder then
                line:Show()
            end
        end
    end
    if not kindName then
        return
    end
    widget._xpArtOn = kindName
    -- The art replaces our 1px border.
    if line then
        line:Hide()
    end
    if kindName == "ring" then
        ApplyXPForeverBorder(widget, barFrame, backdrop, rb)
        return
    end
    -- Fill: flat and square-ended, tinted by the bar's Color setting (UpdateXPBar).
    local texture = barFrame:GetStatusBarTexture()
    texture:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    texture:SetDrawLayer("ARTWORK", 4)
    -- Trough: the client's own XP-bar background; its rounded ends keep their
    -- radius through its slice margins.
    backdrop:SetAtlas("UI-HUD-ExperienceBar-Background")
    backdrop:SetTextureSliceMargins(10, 0, 10, 0)
    backdrop:SetTextureSliceMode(0)
    -- Frame art on its own overlay above the fill (holder+1) and ticks (+2).
    local shade = widget._fvOverlay
    if not shade then
        shade = CreateFrame("Frame", nil, widget)
        shade:EnableMouse(false)
        widget._fvOverlay = shade
    end
    shade:ClearAllPoints()
    shade:SetPoint("TOPLEFT", widget, "TOPLEFT", -2 + fitWidth.offX, 2 + fitWidth.offY + fitWidth.top)
    shade:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 2 + fitWidth.offX, -2 + fitWidth.offY - fitWidth.bot)
    shade:SetFrameLevel(widget:GetFrameLevel() + 3)
    shade:Show()
    mod._XPFrameSlice(shade, atlasName, fitWidth)
    -- The fill and rested bar tuck their ends under the frame's caps and match
    -- the trough's visible height; the trough tucks a little further.
    local endInset, fillV = fitWidth.endInset, fitWidth.fillV
    local bgInset = endInset + fitWidth.bgInset
    barFrame:ClearAllPoints()
    barFrame:SetPoint("TOPLEFT", widget, "TOPLEFT", endInset, -1 - fillV)
    barFrame:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -endInset, 1 + fillV)
    backdrop:ClearAllPoints()
    backdrop:SetPoint("TOPLEFT", widget, "TOPLEFT", bgInset, -1)
    backdrop:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -bgInset, 1)
    if rb then
        rb:GetStatusBarTexture():SetTexture("Interface\\BUTTONS\\WHITE8X8")
        rb:ClearAllPoints()
        rb:SetPoint("TOPLEFT", widget, "TOPLEFT", endInset, -1 - fillV)
        rb:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -endInset, 1 + fillV)
    end
end

-- The bar's background: the XP Bar tab's Background slider (s.barBgOpacity,
-- 0-100) and its colour (s.barBgColor). Unset keeps each style's own: the
-- dark CludesUI body at 85%, the Professions trough untinted at 100%.
-- Returns r, g, b and the opacity (0-100).
function mod.XPBarBackground(cfg)
    local fitWidth = mod.XPArtFit(cfg)
    local art = fitWidth and not fitWidth.ring
    local color = cfg.barBgColor
    local red, green, blue
    if color then
        red, green, blue = color.r or 0, color.g or 0, color.b or 0
    elseif art then
        red, green, blue = 1, 1, 1
    else
        red, green, blue = 0.06, 0.06, 0.08
    end
    return red, green, blue, cfg.barBgOpacity or (art and 100 or 85)
end

-- The Professions trough is art, so it is tinted and faded; every other
-- style's background is a flat colour.
local function PaintXPBackground(widget, s)
    local backdrop = widget._bg
    local red, green, blue, op = mod.XPBarBackground(s)
    if widget._xpArtOn == "frame" then
        backdrop:SetVertexColor(red, green, blue, op / 100)
    else
        backdrop:SetVertexColor(1, 1, 1, 1)
        backdrop:SetColorTexture(red, green, blue, op / 100)
    end
end

-- The XP bar's art style, background and fill, from ApplyDataBarLayout
-- (after it set the bar texture, before the dividers and the Custom Border).
-- The fill comes last: its tiles size from the bar the art style left.
function mod.ApplyXPBarStyle(widget, s)
    ApplyXPArt(widget, s)
    PaintXPBackground(widget, s)
    mod.ApplyXPFlipFill(widget, s)
    mod.ApplyXPQuestOverlay(widget, s)
end

-- Quest XP Overlay (s.questOverlay): two bars over the fill's own rect,
-- between the rested bar (ARTWORK 1) and the fill (4): incomplete quests
-- (s.questOverlayColor, gold; ARTWORK 2) under completed ones
-- (s.questOverlayDoneColor, green; ARTWORK 3). Built on first enable; off,
-- built ones hide.
-- A colour, its unset fields at the default (green / gold at 60%); the
-- options swatches read it too.
local QUEST_DONE = { r = 0, g = 127 / 255, b = 0, a = 0.6 }
local QUEST_INC = { r = 1, g = 0.82, b = 0, a = 0.6 }
function mod.XPQuestColor(cfg, done)
    local skinData, c
    if done then
        skinData, c = QUEST_DONE, cfg.questOverlayDoneColor
    else
        skinData, c = QUEST_INC, cfg.questOverlayColor
    end
    c = c or skinData
    return c.r or skinData.r, c.g or skinData.g, c.b or skinData.b, c.a or skinData.a
end

local function StyleQuestBar(questBar, cfg, texture, sub, done)
    local orient = cfg.orientation or "HORIZONTAL"
    questBar:SetStatusBarTexture(texture)
    questBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", sub)
    questBar:SetOrientation(orient)
    questBar:SetRotatesTexture(orient ~= "HORIZONTAL")
    questBar:SetStatusBarColor(mod.XPQuestColor(cfg, done))
    questBar:Show()
end

function mod.ApplyXPQuestOverlay(widget, cfg)
    local questBar, saved = widget._questBar, widget._questDoneBar
    if not cfg.questOverlay then
        if questBar then
            questBar:Hide()
            saved:Hide()
        end
        return
    end
    if not questBar then
        local barFrame = widget._bar
        questBar = CreateFrame("StatusBar", nil, widget)
        questBar:SetAllPoints(barFrame)
        saved = CreateFrame("StatusBar", nil, widget)
        saved:SetAllPoints(barFrame)
        widget._questBar, widget._questDoneBar = questBar, saved
    end
    local texture = widget._xpArtOn == "frame" and "Interface\\BUTTONS\\WHITE8X8"
        or mod.ResolveDataBarTexture(cfg.barTexture)
    StyleQuestBar(questBar, cfg, texture, 2, false)
    StyleQuestBar(saved, cfg, texture, 3, true)
end

-------------------------------------------------------------------------------
--  Dividers and Smart Ticks (the XP Bar tab's Show Dividers row)
-------------------------------------------------------------------------------
-- Show Dividers (a data bar's showDividers, offered on the XP Bar tab;
-- ApplyDataBarLayout calls this for a bar that has it on or a built host):
-- a dashed tick at every 5% and a full line at every 10% across the bar,
-- inside its border (left to right on a horizontal bar, bottom to top on a
-- vertical one), one physical pixel thick on whole pixels, over the fill
-- and under the text. Divider Text labels the 10% lines (10%..90%), each
-- centred on its line, drawn above it and nudged by the offsets (X along the
-- label's reading direction, Y across it); rotateDividerText turns them to
-- run along a vertical bar. A rotated string pivots about the top centre of
-- its unrotated region, so a label's anchor is moved back by that
-- displacement. Pooled on a child host built the first time the option is
-- on; off, a built host hides.
function mod.AB_DataBarDividers(holderFrame, wid, hgt, orient, cfg)
    local owner = holderFrame._divHost
    if not cfg.showDividers then
        if owner then
            owner:Hide()
            owner._nTick = nil
        end
        return
    end
    if not owner then
        owner = CreateFrame("Frame", nil, holderFrame)
        owner:SetAllPoints(holderFrame)
        owner._tick = {}
        owner._lbl = {}
        holderFrame._divHost = owner
    end
    owner:SetFrameLevel(holderFrame:GetFrameLevel() + 2)
    owner:Show()
    local tick, labelFS = owner._tick, owner._lbl
    local isVertical = (orient == "VERTICAL")
    -- The border's inner edge across the bar: 1 in, or a thicker solid
    -- Custom Border's own width, so no line or dash reaches into it.
    local e = 1
    if cfg.customBorder then
        local bt = cfg.borderTexture
        if not bt or bt == "" or bt == "solid" then
            local sz, px = ResolveBorderThickness(cfg)
            e = max(1, floor((px or sz) + 0.5) * Pix.mult)
        end
    end
    -- An XP bar frame art style: the ticks sit inside its rails.
    local fitWidth = holderFrame._isXP and mod.XPArtFit(cfg)
    if fitWidth then
        e = e + fitWidth.tickInset * Pix.mult
    end
    -- Length along the bar (the fill's) and across it, inside the border.
    local L = (isVertical and hgt or wid) - 2
    local C = (isVertical and wid or hgt) - 2 * e
    local tickCount, nLbl = 0, 0
    if L > 0 and C > 0 then
        local Snap, onePx = Pix.Snap, Pix.mult
        -- 5% Line Style: "dashed" (default), "dotted" (1px dots), "solid" (a
        -- continuous line like the 10% lines) or "none" (the 10% lines alone).
        local style5 = cfg.divider5Style or "dashed"
        local dash = style5 == "dotted" and onePx or max(onePx, Snap(2))
        local gap = max(onePx, Snap(2))
        local step = dash + gap
        local count = max(1, floor((C + gap) / step))
        local c0 = Snap(e)
        local dash0 = c0 + Snap(max(0, (C - (count * step - gap)) / 2))
        local full = Snap(e + C) - c0
        -- Inside an art frame the solid lines reach a little past the tick inset.
        local solidExt = fitWidth and fitWidth.solidExt * onePx or 0
        local solidFull = full + 2 * solidExt
        local solidC0 = c0 - solidExt
        local color = cfg.tick5Color
        local r5, g5, b5 = color and color.r or 220 / 255, color and color.g or 167 / 255, color and color.b or 127 / 255
        local a5 = color and color.a or 0.9
        color = cfg.tick10Color
        local r10, g10, b10 = color and color.r or 1, color and color.g or 1, color and color.b or 1
        local a10 = color and color.a or 0.9
        local showLbl = cfg.showDividerText
        local lsz, lflag, lr, lg, lb, lrot, lcos, lsin, lox, loy, across
        if showLbl then
            local pi = math.pi
            lsz = cfg.dividerTextSize or 8
            lflag = CludesUI.GetFontOutlineFlag("actionBars")
            color = cfg.dividerTextColor
            lr, lg, lb = color and color.r or 1, color and color.g or 1, color and color.b or 1
            lrot = (isVertical and cfg.rotateDividerText) and (cfg.textReadDown and -pi / 2 or pi / 2) or 0
            lcos, lsin = math.cos(lrot), math.sin(lrot)
            local ox, oy = cfg.dividerTextOffX or 0, cfg.dividerTextOffY or 0
            lox, loy = ox * lcos - oy * lsin, ox * lsin + oy * lcos
            across = e + C / 2
        end
        for percent = 5, 95, 5 do
            local place = Snap(1 + percent / 100 * L)
            if percent % 10 == 0 then
                tickCount = tickCount + 1
                local t = tick[tickCount]
                if not t then
                    t = owner:CreateTexture(nil, "OVERLAY")
                    tick[tickCount] = t
                end
                t:SetColorTexture(r10, g10, b10, a10)
                t:ClearAllPoints()
                if isVertical then
                    t:SetSize(solidFull, onePx)
                    t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", solidC0, place)
                else
                    t:SetSize(onePx, solidFull)
                    t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", place, solidC0)
                end
                t._pct = percent
                t:Show()
                if showLbl then
                    -- Slot k is the (10 * k)% line; its text is set once.
                    nLbl = nLbl + 1
                    local fontStr = labelFS[nLbl]
                    if not fontStr then
                        fontStr = owner:CreateFontString(nil, "OVERLAY")
                        -- Sublevel 1: above the lines (OVERLAY 0) it sits on.
                        fontStr:SetDrawLayer("OVERLAY", 1)
                        -- The font first: SetText needs one.
                        CludesUI.ApplyModuleFont(fontStr, nil, lsz, "actionBars", lflag)
                        fontStr:SetText(nLbl * 10 .. "%")
                        labelFS[nLbl] = fontStr
                    end
                    CludesUI.ApplyModuleFont(fontStr, nil, lsz, "actionBars", lflag)
                    fontStr:SetTextColor(lr, lg, lb, 1)
                    fontStr:SetRotation(lrot)
                    local hh = fontStr:GetStringHeight()
                    if not hh or hh <= 0 then
                        hh = fontStr:GetLineHeight()
                    end
                    if not hh or hh <= 0 then
                        hh = lsz
                    end
                    hh = hh / 2
                    -- The line's centre along the bar (it spans pos to pos + one).
                    local mid = place + onePx / 2
                    local posX, posY = mid, across
                    if isVertical then
                        posX, posY = across, mid
                    end
                    fontStr:ClearAllPoints()
                    fontStr:SetPoint(
                        "CENTER",
                        holderFrame,
                        "BOTTOMLEFT",
                        posX + lox - hh * lsin,
                        posY + loy - hh * (1 - lcos)
                    )
                    fontStr._pct = percent
                    fontStr:Show()
                end
            elseif style5 == "none" then
                -- No 5% marks: the 10% lines alone.
            elseif style5 == "solid" then
                -- A single continuous line across the bar (like the 10% lines).
                tickCount = tickCount + 1
                local t = tick[tickCount]
                if not t then
                    t = owner:CreateTexture(nil, "OVERLAY")
                    tick[tickCount] = t
                end
                t:SetColorTexture(r5, g5, b5, a5)
                t:ClearAllPoints()
                if isVertical then
                    t:SetSize(solidFull, onePx)
                    t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", solidC0, place)
                else
                    t:SetSize(onePx, solidFull)
                    t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", place, solidC0)
                end
                t._pct = percent
                t:Show()
            else
                -- Dashes/dots across the bar, the run centred.
                for skinData = 0, count - 1 do
                    tickCount = tickCount + 1
                    local t = tick[tickCount]
                    if not t then
                        t = owner:CreateTexture(nil, "OVERLAY")
                        tick[tickCount] = t
                    end
                    t:SetColorTexture(r5, g5, b5, a5)
                    t:ClearAllPoints()
                    if isVertical then
                        t:SetSize(dash, onePx)
                        t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", dash0 + skinData * step, place)
                    else
                        t:SetSize(onePx, dash)
                        t:SetPoint("BOTTOMLEFT", holderFrame, "BOTTOMLEFT", place, dash0 + skinData * step)
                    end
                    t._pct = percent
                    t:Show()
                end
            end
        end
    end
    for index = tickCount + 1, #tick do
        tick[index]:Hide()
    end
    for index = nLbl + 1, #labelFS do
        labelFS[index]:Hide()
    end
    -- Every mark is shown here; Smart Ticks then hides the passed ones.
    owner._nTick, owner._nLbl, owner._smart, owner._anyHidden = tickCount, nLbl, cfg.smartTicks and true or nil, nil
    mod.ApplyDataBarSmartTicks(holderFrame)
end

-- Smart Ticks: the marks the fill has passed hide, the ones ahead stay. Called
-- on every XP bar value change; returns at once while dividers are off, and
-- while Smart Ticks is off with every mark shown.
function mod.ApplyDataBarSmartTicks(holderFrame)
    local owner = holderFrame._divHost
    if not (owner and owner._nTick) then
        return
    end
    local smart = owner._smart
    if not smart and not owner._anyHidden then
        return
    end
    local barFrame = holderFrame._bar
    local _, maxv = barFrame:GetMinMaxValues()
    local curPct = (smart and maxv > 0) and (barFrame:GetValue() / maxv * 100) or -1
    local tick, labelFS = owner._tick, owner._lbl
    local anyHidden
    for index = 1, owner._nTick do
        local t = tick[index]
        local on = t._pct >= curPct
        if not on then
            anyHidden = true
        end
        t:SetShown(on)
    end
    for index = 1, owner._nLbl do
        local fontStr = labelFS[index]
        fontStr:SetShown(fontStr._pct >= curPct)
    end
    owner._anyHidden = anyHidden
end

-- The XP Bar tab's style selector (options addon): "default" = Blizzard's
-- own XP and reputation bars (the profile's one useBlizzardDataBars switch,
-- which the Use Blizzard's Rep Bars toggle also sets), "cui" = the
-- CludesUI bar, "prof" = in the Professions frame, "forever" = in WoW
-- Forever's border.
function CludesUI._GetXPBarStyle()
    local p = ABAR.db and ABAR.db.profile
    if not p then
        return "cui"
    end
    if p.useBlizzardDataBars then
        return "default"
    end
    local cfg = p.bars and p.bars.XPBar
    return (cfg and cfg.xpArt) or "cui"
end

-- A Blizz Default <-> CludesUI swap flips that switch live through
-- ns.SetUseBlizzardDataBars; the frame art applies live. Returns true when the
-- swap needs a reload (our bars wanted but never built, or Blizzard's bars
-- back after their events were dropped), so the caller can offer it.
function CludesUI._SetXPBarStyle(look)
    local p = ABAR.db and ABAR.db.profile
    if not p then
        return false
    end
    local wantBlizz = look == "default"
    local cfg = p.bars and p.bars.XPBar
    if cfg and not wantBlizz then
        cfg.xpArt = (look == "prof" or look == "forever") and look or nil
    end
    local reload = false
    if (p.useBlizzardDataBars and true or false) ~= wantBlizz then
        reload = mod.SetUseBlizzardDataBars(wantBlizz)
    end
    if not wantBlizz and dataBarFrames.XPBar then
        ApplyDataBarLayout("XPBar")
    end
    return reload or (not wantBlizz and not dataBarFrames.XPBar)
end

-- Whether an art style exists on this client ("forever" = WoW Forever's
-- border, on that client only).
function CludesUI._XPBarArtAvailable(look)
    if look == "forever" then
        return CludesUI.ForeverBorderOK()
    end
    local atlasName = mod._XPArtAtlas[look]
    return atlasName ~= nil and C_Texture.GetAtlasInfo(atlasName) ~= nil
end

-------------------------------------------------------------------------------
--  XP Bar
-------------------------------------------------------------------------------
-- Max-level check with layered fallbacks. The Is* helpers are nil-guarded, so client
-- API churn can silently disable them -- a plain numeric compare against the expansion
-- max level backstops the check so the bar can never show for a max-level character.
function mod.XPBarAtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then
        return true
    end
    if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then
        return true
    end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

-- WoW Forever: raw XP under 10,000 is not abbreviated (CludesUI_NumberFormat.lua).
mod.AbbreviateLargeNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateLargeNumbers)
    or AbbreviateLargeNumbers

-------------------------------------------------------------------------------
--  Text positions (the XP Bar tab's CORE TEXT POSITIONS section). Seven positions,
--  each holding up to XP_TEXTS_PER_POS texts, each showing one or more items
--  (XPTextItems below; its Show Rested in <key>Rested). A position's first
--  text is s.textSlot<Stem> (Center nil = "classic", the bar's original text;
--  every other nil = "none"), its second and third s.textSlot<Stem>2 / 3.
--  Center's first text is the readout the data bar kit
--  places (frame._text, ns.DataBarPlaceText); Left and Right sit inside a
--  horizontal bar, Top Left / Top Right above it and Bottom Left / Bottom
--  Right below it. Every text but Center's first has its own size and
--  offsets, is built the first time it shows something and is hidden on a
--  vertical bar; a text sharing its position lines up after the one before it
--  (corners stacked away from the bar, the rest side by side).
--  ns.XPBarTextSlots (every layout pass) lays them out and works out what the
--  items in use need; nothing below runs for an item no text shows:
--    completed quests  QUEST_LOG_UPDATE while the bar shows, one scan a frame
--    XP per hour       the XP gained since the rate started, counted on every
--                      XP update (also while the bar is hidden)
--    time this level   learned from /played (asked once per session while
--                      unknown), then counted on; saved at logout for the
--                      next load
--    the minute clock  a ticker while the bar shows, for the time items
--  The session clock, the rate and the saved level time live per character in
--  CludesUIDB.xpBarChars[guid] (built the first time an item needs it;
--  never exported). A text is set only when its string changed.
-------------------------------------------------------------------------------
-- The positions: the first text's point placed on the bar's point (inside:
-- the text host over the fill; outside: the holder's edge), its base offset
-- and justification, then where a later text at the same position goes (its
-- point on the previous text's point, plus a gap). Center's first text is the
-- kit's own, so its own texts start at 2.
local XP_TEXTS_PER_POS = 3
local XP_POS = {
    {
        stem = "Left",
        point = "LEFT",
        rel = "LEFT",
        bx = 4,
        by = 0,
        justify = "LEFT",
        cPoint = "LEFT",
        cRel = "RIGHT",
        cx = 8,
        cy = 0,
    },
    {
        stem = "Right",
        point = "RIGHT",
        rel = "RIGHT",
        bx = -4,
        by = 0,
        justify = "RIGHT",
        cPoint = "RIGHT",
        cRel = "LEFT",
        cx = -8,
        cy = 0,
    },
    {
        stem = "TopLeft",
        outside = true,
        point = "BOTTOMLEFT",
        rel = "TOPLEFT",
        bx = 0,
        by = 2,
        justify = "LEFT",
        cPoint = "BOTTOMLEFT",
        cRel = "TOPLEFT",
        cx = 0,
        cy = 2,
    },
    {
        stem = "TopRight",
        outside = true,
        point = "BOTTOMRIGHT",
        rel = "TOPRIGHT",
        bx = 0,
        by = 2,
        justify = "RIGHT",
        cPoint = "BOTTOMRIGHT",
        cRel = "TOPRIGHT",
        cx = 0,
        cy = 2,
    },
    {
        stem = "BottomLeft",
        outside = true,
        point = "TOPLEFT",
        rel = "BOTTOMLEFT",
        bx = 0,
        by = -2,
        justify = "LEFT",
        cPoint = "TOPLEFT",
        cRel = "BOTTOMLEFT",
        cx = 0,
        cy = -2,
    },
    {
        stem = "BottomRight",
        outside = true,
        point = "TOPRIGHT",
        rel = "BOTTOMRIGHT",
        bx = 0,
        by = -2,
        justify = "RIGHT",
        cPoint = "TOPRIGHT",
        cRel = "BOTTOMRIGHT",
        cx = 0,
        cy = -2,
    },
    {
        stem = "Center",
        first = 2,
        point = "CENTER",
        rel = "CENTER",
        bx = 0,
        by = 0,
        justify = "CENTER",
        cPoint = "LEFT",
        cRel = "RIGHT",
        cx = 8,
        cy = 0,
    },
}
-- Every text besides Center's first, in position order then text order (a
-- position's first text keeps the textSlot<Stem> keys): its settings keys.
local XP_SLOTS = {}
for _, p in ipairs(XP_POS) do
    for index = p.first or 1, XP_TEXTS_PER_POS do
        local key = "textSlot" .. p.stem .. (index > 1 and index or "")
        XP_SLOTS[#XP_SLOTS + 1] = {
            pos = p,
            key = key,
            size = key .. "Size",
            x = key .. "XOffset",
            y = key .. "YOffset",
            rested = key .. "Rested",
        }
    end
end

-- What a text shows: items of the top group, " - " between them in the order
-- saved, or one item of the bottom group on its own. Its value is the item
-- ids joined by "," (one id alone for one item) or "none". A value saved
-- before the items existed reads as the items it showed (the old Default:
-- its Show Level / Show Raw Values / Show % settings, with its rested part,
-- which Show Rested keeps on until set); nothing is rewritten until the text
-- is edited. Until then the old Default and the values marked drawn, which
-- no set of items reproduces, are drawn exactly as they were (XPLegacyText).
local XP_ITEM_TOP = {
    pct = true,
    cur = true,
    curMax = true,
    curMaxRem = true,
    restVal = true,
    restPct = true,
    questVal = true,
    questPct = true,
    level = true,
}
local XP_ITEM_SOLO = { xpPerHour = true, levelingIn = true, timeLevel = true, timeSession = true }
local XP_ITEM_LEGACY = {
    xp = { "curMax" },
    xpRemaining = { "curMaxRem" },
    remaining = { "curMaxRem", drawn = true },
    percent = { "pct" },
    percentProjected = { "pct", "questPct", drawn = true },
    completed = { "questPct" },
    rested = { "restPct" },
    completedRested = { "questPct", "restPct" },
}
-- Show Rested adds the rested XP to the first of these in a text.
local XP_ITEM_RESTED = { pct = true, cur = true, curMax = true }
-- The items each tracker serves (the clock: every time-based one).
local XP_ITEM_QUEST = { questVal = true, questPct = true }
local XP_ITEM_RATE = { xpPerHour = true, levelingIn = true }
local XP_ITEM_CLOCK = { xpPerHour = true, levelingIn = true, timeLevel = true, timeSession = true }

-- A text's value as its items (out, refilled). Returns "top", "solo" (the
-- item in out[1]) or nil for nothing, then true for the old Default text,
-- then the value itself when it is still drawn as it was (XPLegacyText).
local function XPTextItems(val, cfg, result)
    wipe(result)
    if type(val) ~= "string" or val == "none" then
        return nil
    end
    if XP_ITEM_SOLO[val] then
        result[1] = val
        return "solo"
    end
    if val == "classic" then
        if cfg.showLevel then
            result[1] = "level"
        end
        if cfg.showRawValues then
            result[#result + 1] = "curMax"
            if cfg.showPercent then
                result[#result + 1] = "pct"
            end
        else
            result[#result + 1] = "pct"
        end
        return "top", true, val
    end
    local old = XP_ITEM_LEGACY[val]
    if old then
        for index = 1, #old do
            result[index] = old[index]
        end
        return "top", nil, old.drawn and val or nil
    end
    for ident in val:gmatch("[^,]+") do
        if XP_ITEM_TOP[ident] then
            local dup
            for index = 1, #result do
                if result[index] == ident then
                    dup = true
                    break
                end
            end
            if not dup then
                result[#result + 1] = ident
            end
        end
    end
    if result[1] then
        return "top"
    end
    return nil
end
mod.XPTextItems = XPTextItems

-- Show Rested for a text (restedKey: its key .. "Rested"): its own setting,
-- else on for the old Default text.
local function XPTextRested(cfg, restedKey, legacy)
    local region = cfg[restedKey]
    if region == nil then
        return legacy and true or false
    end
    return region and true or false
end
mod.XPTextRested = XPTextRested

-- Parse scratch for the layout pass.
local xpScratch = {}

local xpPlayerGUID -- the store key, read once
local xpLoginAt -- GetTime() at this session's login (nil after a /reload)
-- Time this level, once known: the level and the seconds played at it as of
-- xpLvlStamp (a GetTime()). Kept for the rest of the UI session (GetTime()
-- counts on and every level-up resets it), so turning the content off and on
-- again needs no second /played.
local xpLvl, xpLvlBase, xpLvlStamp
local xpLvlAsked -- /played was requested this session
local xpWorldSeen -- this load's first PLAYER_ENTERING_WORLD was handled
local xpClock -- the minute clock: its aligning timer, then the ticker
local questWatch -- QUEST_LOG_UPDATE and the one-shot scan (built on first need)
-- The first PLAYER_ENTERING_WORLD of a load, then TIME_PLAYED_MSG and
-- PLAYER_LOGOUT while Time This Level is in use.
local xpTextEv = mod.TakeShell()

-- A number: in full below 10,000 (6,811), abbreviated from there (17.6K).
local function FmtNum(num)
    num = floor(num)
    if num < 10000 then
        return BreakUpLargeNumbers(num)
    end
    return mod.AbbreviateLargeNumbers(num)
end

-- A percentage: one decimal, a whole number without one (89.6%, 0%).
local function FmtPct(val)
    local t = floor(val * 10 + 0.5)
    if t % 10 == 0 then
        return format("%d%%", t / 10)
    end
    return format("%.1f%%", t / 10)
end

-- A duration: 3d 4h, 1h 24m, 22m.
local FmtDur = CludesUI.FormatDuration

-- This character's entry in CludesUIDB.xpBarChars (create: build it, and
-- the store, when missing). nil while the player's GUID cannot be read.
local function XPCharEntry(create)
    local saved = CludesUIDB
    if type(saved) ~= "table" then
        return nil
    end
    if not xpPlayerGUID then
        local g = UnitGUID("player")
        if not g or (issecretvalue and issecretvalue(g)) then
            return nil
        end
        xpPlayerGUID = g
    end
    local all = saved.xpBarChars
    if type(all) ~= "table" then
        if not create then
            return nil
        end
        all = {}
        saved.xpBarChars = all
    end
    local e = all[xpPlayerGUID]
    if type(e) ~= "table" then
        if not create then
            return nil
        end
        e = { sStart = xpLoginAt or GetTime() }
        all[xpPlayerGUID] = e
    end
    return e
end

-- XP per Hour counts from here: now, nothing gained yet.
local function XPRateBaseline(e)
    e.rStart, e.gained = GetTime(), 0
    e.lastXP, e.lastMax, e.lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

-- Adds the XP gained since the last reading to the rate; the same values
-- again add nothing. A level-up adds what the old level still needed plus
-- the XP into the new one. A lower reading on the same level is taken mid
-- level-up and waits for the settled one. Returns true when XP was added.
local function XPTrackRate()
    local e = XPCharEntry(false)
    if not (e and e.rStart) then
        return
    end
    local current, lv = UnitXP("player"), UnitLevel("player")
    local lastXP, lastLv = e.lastXP, e.lastLevel
    local added
    if lastXP and lastLv then
        if lv == lastLv then
            if current <= lastXP then
                return
            end
            e.gained = (e.gained or 0) + (current - lastXP)
            added = true
        elseif lv > lastLv then
            e.gained = (e.gained or 0) + max(0, (e.lastMax or lastXP) - lastXP) + current
            added = true
        end
    end
    e.lastXP, e.lastMax, e.lastLevel = current, UnitXPMax("player"), lv
    return added
end

-- XP per hour since the rate started: 0 until a minute has passed with XP
-- gained.
local function XPRate(nowTime)
    local e = XPCharEntry(false)
    local start, gained = e and e.rStart, e and e.gained
    if not (start and gained) or gained <= 0 or nowTime - start < 60 then
        return 0
    end
    return gained * 3600 / (nowTime - start)
end

-- A value saved before the items existed, drawn exactly as the bar drew it
-- then until the text is edited: Remaining alone, the percentage with the
-- one completed quests would bring, or the old Default (Level, the raw
-- values or the percentage to one decimal, Show % after raw values, then the
-- rested XP, which follows its Show Rested).
local function XPLegacyText(widget, record, current, mx, rested, level)
    local region = record.render
    if region == "remaining" then
        return format(CludesUI.L("Remaining: %s"), FmtNum(mx - current))
    elseif region == "percentProjected" then
        return FmtPct(current / mx * 100)
            .. " ("
            .. FmtPct((current + (widget._xpQuestXP or 0)) / mx * 100)
            .. ")"
    end
    local raw = record.raw
    local text = record.lvl and format("%s %d - ", LEVEL, level) or ""
    if raw then
        text = text .. format("%s / %s", mod.AbbreviateLargeNumbers(current), mod.AbbreviateLargeNumbers(mx))
        if record.pcts then
            text = text .. format(" (%.1f%%)", current / mx * 100)
        end
    else
        text = text .. format("%.1f%%", current / mx * 100)
    end
    if record.rested and rested > 0 then
        text = text
            .. format(
                CludesUI.L(" (Rested: %s)"),
                raw and mod.AbbreviateLargeNumbers(rested) or format("%.1f%%", rested / mx * 100)
            )
    end
    return text
end

-- One item's string; rest: the rested XP after it (Show Rested, while there
-- is some). Rested and remaining XP always carry their label.
local function XPItemText(widget, ident, current, mx, rested, level, nowTime, rest)
    if ident == "pct" then
        local text = FmtPct(current / mx * 100)
        if rest then
            text = text .. format(CludesUI.L(" (Rested: %s)"), FmtPct(rested / mx * 100))
        end
        return text
    elseif ident == "cur" then
        local text = FmtNum(current)
        if rest then
            text = text .. format(CludesUI.L(" (Rested: %s)"), FmtNum(rested))
        end
        return text
    elseif ident == "curMax" then
        local text = FmtNum(current) .. " / " .. FmtNum(mx)
        if rest then
            text = text .. format(CludesUI.L(" (Rested: %s)"), FmtNum(rested))
        end
        return text
    elseif ident == "curMaxRem" then
        return format(
            "%s / %s (%s)",
            FmtNum(current),
            FmtNum(mx),
            format(CludesUI.L("Remaining: %s"), FmtNum(mx - current))
        )
    elseif ident == "restVal" then
        return format(CludesUI.L("Rested: %s"), FmtNum(rested))
    elseif ident == "restPct" then
        return format(CludesUI.L("Rested: %s"), FmtPct(rested / mx * 100))
    elseif ident == "questVal" then
        return format(CludesUI.L("Completed: %s"), FmtNum(widget._xpQuestXP or 0))
    elseif ident == "questPct" then
        return format(CludesUI.L("Completed: %s"), FmtPct((widget._xpQuestXP or 0) / mx * 100))
    elseif ident == "level" then
        return format("%s %d", LEVEL, level)
    elseif ident == "xpPerHour" then
        return format(CludesUI.L("%s XP/Hour"), FmtNum(XPRate(nowTime)))
    elseif ident == "levelingIn" then
        local rate = XPRate(nowTime)
        return format(
            CludesUI.L("Leveling in: %s (%s XP/Hour)"),
            rate > 0 and FmtDur((mx - current) / rate * 3600) or "--",
            FmtNum(rate)
        )
    elseif ident == "timeLevel" then
        return format(
            CludesUI.L("Time this level: %s"),
            xpLvlBase and FmtDur(xpLvlBase + (nowTime - xpLvlStamp)) or "--"
        )
    elseif ident == "timeSession" then
        local e = XPCharEntry(false)
        local start = e and e.sStart or xpLoginAt
        return format(CludesUI.L("Time this session: %s"), start and FmtDur(nowTime - start) or "--")
    end
    return ""
end

-- A text's string: its items, " - " between them ("" for nothing). The parts
-- table is the frame's own, refilled.
local function XPTextString(widget, record, current, mx, rested, level, nowTime)
    local kindName, itemList = record.kind, record.items
    if not kindName then
        return ""
    end
    if record.render then
        return XPLegacyText(widget, record, current, mx, rested, level)
    end
    local rest = kindName == "top" and record.rested and rested > 0
    local num = #itemList
    if num == 1 then
        return XPItemText(
            widget,
            itemList[1],
            current,
            mx,
            rested,
            level,
            nowTime,
            rest and XP_ITEM_RESTED[itemList[1]]
        )
    end
    local parts = widget._xpParts
    for index = 1, num do
        local ident = itemList[index]
        local region = rest and XP_ITEM_RESTED[ident]
        if region then
            rest = false
        end
        parts[index] = XPItemText(widget, ident, current, mx, rested, level, nowTime, region)
    end
    return table.concat(parts, " - ", 1, num)
end

-- Paints the texts in use (filter: nil = every one, else only those with
-- that need, "nq" quests or "nc" the clock), each only when its string
-- changed. A rotated Center is placed again after a new string (its
-- placement is measured from it).
local function XPPaintText(widget, s, filter, current, mx, rested, level)
    local nowTime = GetTime()
    local c = widget._xpC
    if c and (not filter or c[filter]) then
        local text = XPTextString(widget, c, current, mx, rested, level, nowTime)
        if text ~= c.str then
            c.str = text
            widget._text:SetText(text)
            if widget._textPost then
                mod.DataBarPlaceText(widget, s)
                if not c.kind and widget._textBg then
                    widget._textBg:Hide()
                end
            end
        end
    end
    local recs = widget._xpAny and widget._xpRecs
    if not recs then
        return
    end
    for index = 1, #recs do
        local record = recs[index]
        if not filter or record[filter] then
            local text = XPTextString(widget, record, current, mx, rested, level, nowTime)
            if text ~= record.str then
                record.str = text
                record.fs:SetText(text)
            end
        end
    end
end

-- Repaints the texts showing a content in `filter` outside an XP update (the
-- minute clock, a quest scan, /played, the bar showing again).
local function XPRepaint(widget, filter)
    local s = ABAR.db and ABAR.db.profile.bars.XPBar
    if not s then
        return
    end
    local mx = UnitXPMax("player")
    if mx <= 0 then
        mx = 1
    end
    XPPaintText(widget, s, filter, UnitXP("player"), mx, GetXPExhaustion() or 0, UnitLevel("player"))
end

-- The XP of every quest in the log that is ready to hand in (the quest
-- texts), then the Quest XP Overlay's completed and incomplete XP, filtered
-- by Completed Quests Only (s.questOverlayCompleted) and Current Zone Only
-- (s.questOverlayZone).
local GetQuestLogRewardXP = GetQuestLogRewardXP -- missing on a client: reads 0
local function XPQuestXP(cfg)
    if not GetQuestLogRewardXP then
        return 0, 0, 0
    end
    local QL = C_QuestLog
    local shade = cfg.questOverlay
    local all, onlyZone = shade and not cfg.questOverlayCompleted, shade and cfg.questOverlayZone
    local sum, done, inc = 0, 0, 0
    for index = 1, QL.GetNumQuestLogEntries() do
        local q = QL.GetQuestIDForLogIndex(index)
        if q and q > 0 then
            local complete = QL.IsComplete(q)
            if complete or all then
                local xp = GetQuestLogRewardXP(q) or 0
                if complete then
                    sum = sum + xp
                end
                if shade and (not onlyZone or QL.IsOnMap(q)) then
                    if complete then
                        done = done + xp
                    else
                        inc = inc + xp
                    end
                end
            end
        end
    end
    return sum, done, inc
end

-- The Quest XP Overlay: completed quest XP ahead of the fill, incomplete
-- quest XP past it (built on first enable, ns.ApplyXPQuestOverlay).
local function XPPaintQuestOverlay(widget, current, mx)
    local questBar = widget._questBar
    if not (questBar and questBar:IsShown()) then
        return
    end
    local done = current + (widget._xpQuestDone or 0)
    questBar:SetMinMaxValues(0, mx)
    questBar:SetValue(min(done + (widget._xpQuestInc or 0), mx))
    local saved = widget._questDoneBar
    saved:SetMinMaxValues(0, mx)
    saved:SetValue(min(done, mx))
end

-- QUEST_LOG_UPDATE only shows the hidden scan frame; its one-shot OnUpdate
-- hides it, scans once for the whole burst and repaints the quest texts and
-- overlay when a total changed.
local function OnXPQuestScan(self)
    self:Hide()
    local widget = dataBarFrames.XPBar
    local s = ABAR.db and ABAR.db.profile.bars.XPBar
    if not (widget and s) then
        return
    end
    widget._xpQuestOK = true
    local sum, done, inc = XPQuestXP(s)
    if sum ~= widget._xpQuestXP then
        widget._xpQuestXP = sum
        XPRepaint(widget, "nq")
    end
    if done ~= widget._xpQuestDone or inc ~= widget._xpQuestInc then
        widget._xpQuestDone, widget._xpQuestInc = done, inc
        local mx = UnitXPMax("player")
        XPPaintQuestOverlay(widget, UnitXP("player"), mx > 0 and mx or 1)
    end
end

local function OnXPQuestEvent(self)
    self:Show()
end

-- Quest events only while a quest content is in use and the bar shows. Going
-- hidden (or out of use) leaves the total stale: it is scanned again on the
-- next show.
local function XPSyncQuestEvents(widget, vis)
    if widget._xpNeedQuest and vis then
        if not questWatch then
            questWatch = mod.TakeShell()
            questWatch:Hide()
            questWatch:SetScript("OnEvent", OnXPQuestEvent)
            questWatch:SetScript("OnUpdate", OnXPQuestScan)
        end
        if not widget._xpQuestOn then
            widget._xpQuestOn = true
            questWatch:RegisterEvent("QUEST_LOG_UPDATE")
        end
        -- Current Zone Only: a new zone changes which quests count.
        if widget._xpQuestZone then
            questWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        else
            questWatch:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        end
        if not widget._xpQuestOK then
            questWatch:Show()
        end
    elseif widget._xpQuestOn then
        widget._xpQuestOn, widget._xpQuestOK = nil, nil
        questWatch:UnregisterEvent("QUEST_LOG_UPDATE")
        questWatch:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
        questWatch:Hide()
    end
end

-- The minute clock: repaints the time contents once a minute while the bar
-- shows, its first tick on the session clock's next whole minute.
local function OnXPClockTick()
    local widget = dataBarFrames.XPBar
    if widget then
        XPRepaint(widget, "nc")
    end
end

local function OnXPClockAlign()
    xpClock = C_Timer.NewTicker(60, OnXPClockTick)
    OnXPClockTick()
end

local function XPSyncClock(widget, vis)
    if widget._xpNeedClock and vis then
        if xpClock then
            return
        end
        local e = XPCharEntry(false)
        local start = e and e.sStart or xpLoginAt
        local nowTime = GetTime()
        xpClock = C_Timer.NewTimer(start and (60 - (nowTime - start) % 60) or 60, OnXPClockAlign)
    elseif xpClock then
        xpClock:Cancel()
        xpClock = nil
    end
end

-- Time This Level's events: TIME_PLAYED_MSG while it is in use (our request,
-- or the player's own /played), PLAYER_LOGOUT while it is in use with a known
-- time.
local function XPSyncLevelEvents(widget)
    if widget._xpNeedLevelTime then
        xpTextEv:RegisterEvent("TIME_PLAYED_MSG")
        if xpLvlBase then
            xpTextEv:RegisterEvent("PLAYER_LOGOUT")
        end
    else
        -- Our own /played still owed: its reply lands, then this drops it.
        if not (xpLvlAsked and not xpLvlBase) then
            xpTextEv:UnregisterEvent("TIME_PLAYED_MSG")
        end
        xpTextEv:UnregisterEvent("PLAYER_LOGOUT")
    end
end

-- Whether the XP bar can show at all with these settings: not Blizzard's
-- bars, not Never, not at max level, XP not turned off. Plain field reads
-- (the visibility passes normalize the settings table).
local function XPBarCanShow(cfg)
    local p = ABAR.db and ABAR.db.profile
    if not (p and cfg) or p.useBlizzardDataBars then
        return false
    end
    if cfg.enabled == false or ABAR.VisibilityCompat.IsNever(cfg) then
        return false
    end
    return not mod.XPBarAtMaxLevel() and not (IsXPUserDisabled and IsXPUserDisabled())
end

-- The time played this level, as of now: stored, then shown.
local function XPSetLevelTime(levelTime)
    xpLvl, xpLvlBase, xpLvlStamp = UnitLevel("player"), levelTime, GetTime()
    local widget = dataBarFrames.XPBar
    if widget then
        XPSyncLevelEvents(widget)
        if widget:IsVisible() then
            XPRepaint(widget, "nc")
        end
    end
end

-- /played, at most once per session: while Time This Level is in use and
-- armed (the bar can show) and its time is unknown (or for another level).
-- The game prints its two /played lines in chat for that one request; the
-- chat frames are never touched.
local function XPRequestPlayed(widget)
    -- Not before the load's first PLAYER_ENTERING_WORLD has read the time
    -- saved at the last logout.
    if xpLvlAsked or not xpWorldSeen or not widget._xpNeedLevelTime then
        return
    end
    if xpLvlBase and xpLvl == UnitLevel("player") then
        return
    end
    if mod.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
        return
    end
    xpLvlAsked = true
    local _, levelTime = CludesUI.RequestTimePlayed()
    if levelTime then
        XPSetLevelTime(levelTime)
    end
end

-- PLAYER_LEVEL_UP (the bar's own event frame): the new level starts at no
-- time played (exact, no /played needed; three numbers, kept even while no
-- text shows the time), and quest rewards change with the level.
local function XPTextLevelUp(widget, newLevel)
    xpLvl = type(newLevel) == "number" and newLevel or UnitLevel("player")
    xpLvlBase, xpLvlStamp = 0, GetTime()
    if widget._xpNeedLevelTime then
        XPSyncLevelEvents(widget)
    end
    widget._xpQuestOK = nil
    if widget._xpQuestOn then
        questWatch:Show()
    end
end

-- The holder's own show and hide (hooked the first time quests or the clock
-- are needed, a flag read otherwise): quest events and the clock follow it,
-- and the time contents catch up on the time spent hidden.
local function OnXPHolderShow(widget)
    if widget._xpNeedQuest then
        XPSyncQuestEvents(widget, true)
    end
    if widget._xpNeedClock then
        XPSyncClock(widget, true)
        XPRepaint(widget, "nc")
    end
end

local function OnXPHolderHide(widget)
    if widget._xpQuestOn then
        XPSyncQuestEvents(widget, false)
    end
    if xpClock then
        XPSyncClock(widget, false)
    end
end

-- A text record's items from the parse in xpScratch (kind from it, legacy:
-- the old Default text, render: the value when it is still drawn as it was,
-- with the old Default's Level / raw values / Show % settings), its Show
-- Rested and what its items need: nq completed quests, nr the XP rate, nc the
-- minute clock, nl the time this level.
local function XPTextTake(record, kindName, legacy, cfg, restedKey, render)
    local itemList = record.items
    wipe(itemList)
    for index = 1, #xpScratch do
        itemList[index] = xpScratch[index]
    end
    record.kind = kindName
    record.rested = kindName == "top" and XPTextRested(cfg, restedKey, legacy)
    record.render = render
    record.lvl, record.raw, record.pcts = cfg.showLevel, cfg.showRawValues, cfg.showPercent
    local nq, nr, nc, nl = false, false, false, false
    for index = 1, #itemList do
        local ident = itemList[index]
        if XP_ITEM_QUEST[ident] then
            nq = true
        end
        if XP_ITEM_RATE[ident] then
            nr = true
        end
        if XP_ITEM_CLOCK[ident] then
            nc = true
        end
        if ident == "timeLevel" then
            nl = true
        end
    end
    record.nq, record.nr, record.nc, record.nl = nq, nr, nc, nl
end

-- Lays out every text besides Center's first (font, place, Text Background;
-- hidden when unused or on a vertical bar) and arms what the items in use
-- need. ApplyDataBarLayout calls it for the XP bar right after placing
-- Center's first text.
function mod.XPBarTextSlots(widget, cfg)
    widget._xpPaintDirty = true
    -- A layout pass (Bar Texture, style) can reset the fill's colours: the
    -- update that follows repaints the gradient.
    local gm = widget._bar and widget._bar._xpGrad
    if gm then
        gm.on = nil
    end
    if not widget._xpParts then
        widget._xpParts = {}
    end
    -- Center's first text: unset (or a value no longer known) is the old
    -- Default.
    local c = widget._xpC
    if not c then
        c = { items = {} }
        widget._xpC = c
    end
    local cv = cfg.textSlotCenter
    if cv == nil then
        cv = "classic"
    end
    local kindName, legacy, render = XPTextItems(cv, cfg, xpScratch)
    if not kindName and cv ~= "none" then
        kindName, legacy, render = XPTextItems("classic", cfg, xpScratch)
    end
    XPTextTake(c, kindName, legacy, cfg, "textSlotCenterRested", render)
    -- No Center text: no Text Background behind it either.
    if not kindName and widget._textBg then
        widget._textBg:Hide()
    end

    local quest, rate, clock, levelTime = c.nq or cfg.questOverlay, c.nr, c.nc, c.nl
    local horizontal = cfg.orientation ~= "VERTICAL"
    local owner, slots = widget._textHost, widget._xpSlot
    local size, bgOn, bc = cfg.textSize or 9, cfg.showTextBg, cfg.textBgColor
    -- The texts in use, for the paint (refilled here: layout passes only).
    local recs = widget._xpRecs
    if recs then
        wipe(recs)
    end
    -- The last text placed at the current position, the one a later text
    -- lines up after (Center's: the kit's text while it shows).
    local lastPos, previous
    for index = 1, #XP_SLOTS do
        local skinData = XP_SLOTS[index]
        local p = skinData.pos
        if p ~= lastPos then
            lastPos = p
            previous = (p.stem == "Center" and c.kind) and widget._text or nil
        end
        local tk, tl, tr
        if horizontal then
            tk, tl, tr = XPTextItems(cfg[skinData.key], cfg, xpScratch)
        end
        local record = slots and slots[skinData.key]
        if tk then
            if not record then
                if not slots then
                    slots = {}
                    widget._xpSlot = slots
                end
                record = { fs = owner:CreateFontString(nil, "OVERLAY"), items = {} }
                slots[skinData.key] = record
            end
            if not recs then
                recs = {}
                widget._xpRecs = recs
            end
            recs[#recs + 1] = record
            XPTextTake(record, tk, tl, cfg, skinData.rested, tr)
            if record.nq then
                quest = true
            end
            if record.nr then
                rate = true
            end
            if record.nc then
                clock = true
            end
            if record.nl then
                levelTime = true
            end
            local fontStr = record.fs
            CludesUI.ApplyModuleFont(fontStr, nil, cfg[skinData.size] or size, "actionBars")
            fontStr:SetTextColor(1, 1, 1, 1)
            fontStr:SetJustifyH(p.justify)
            fontStr:ClearAllPoints()
            local ox, oy = cfg[skinData.x] or 0, cfg[skinData.y] or 0
            if previous then
                fontStr:SetPoint(p.cPoint, previous, p.cRel, p.cx + ox, p.cy + oy)
            else
                fontStr:SetPoint(p.point, p.outside and widget or owner, p.rel, p.bx + ox, p.by + oy)
            end
            previous = fontStr
            fontStr:Show()
            local backdrop = record.bg
            if bgOn then
                -- 3 past the text's ends and 1 above and below it, as Center's.
                if not backdrop then
                    backdrop = owner:CreateTexture(nil, "ARTWORK")
                    backdrop:SetPoint("TOPLEFT", fontStr, "TOPLEFT", -3, 1)
                    backdrop:SetPoint("BOTTOMRIGHT", fontStr, "BOTTOMRIGHT", 3, -1)
                    record.bg = backdrop
                end
                backdrop:SetColorTexture(
                    bc and bc.r or 0.06,
                    bc and bc.g or 0.06,
                    bc and bc.b or 0.08,
                    bc and bc.a or 0.9
                )
                backdrop:Show()
            elseif backdrop then
                backdrop:Hide()
            end
        elseif record then
            record.kind = nil
            record.fs:Hide()
            if record.bg then
                record.bg:Hide()
            end
        end
    end
    widget._xpAny = (recs ~= nil and #recs > 0)
    -- The options preview stops at its layout: what follows arms the live
    -- bar's trackers, which are one per module (the clock, quest events).
    if widget._preview then
        return
    end

    -- Wanted (the contents in use) vs armed (wanted and the bar can show):
    -- nothing is tracked, stored or requested for a bar that never shows.
    widget._xpWant = (quest or rate or clock or levelTime) and true or false
    widget._xpLive = widget._xpWant and XPBarCanShow(cfg) or false
    if not widget._xpLive then
        quest, rate, clock, levelTime = false, false, false, false
    end
    local wasRate, wasLevel = widget._xpNeedRate, widget._xpNeedLevelTime
    widget._xpNeedQuest = quest and true or false
    widget._xpQuestZone = (quest and cfg.questOverlay and cfg.questOverlayZone) and true or nil
    -- An overlay filter change rescans.
    local sig = (cfg.questOverlay and 1 or 0)
        + (cfg.questOverlayCompleted and 2 or 0)
        + (cfg.questOverlayZone and 4 or 0)
    if sig ~= widget._xpQuestSig then
        widget._xpQuestSig, widget._xpQuestOK = sig, nil
    end
    widget._xpNeedRate = rate and true or false
    widget._xpNeedLevelTime = levelTime
    widget._xpNeedClock = clock and true or false

    -- The store, for every time content: the session clock (a start later
    -- than now is from an earlier boot and restarts) and the rate, whose count
    -- starts again when XP per Hour is turned on (a /reload keeps it running).
    if clock then
        local e = XPCharEntry(true)
        if e then
            local nowTime = GetTime()
            if type(e.sStart) ~= "number" or e.sStart > nowTime then
                e.sStart = nowTime
            end
            if rate and (wasRate == false or not e.rStart) then
                XPRateBaseline(e)
            end
        end
    end
    if levelTime ~= (wasLevel or false) then
        XPSyncLevelEvents(widget)
    end
    if levelTime then
        XPRequestPlayed(widget)
    end

    -- Shown-only work (quest events, the minute clock), started and stopped
    -- by the holder's own show and hide from then on.
    if (quest or clock) and not widget._xpHooked then
        widget._xpHooked = true
        widget:HookScript("OnShow", OnXPHolderShow)
        widget:HookScript("OnHide", OnXPHolderHide)
    end
    if widget._xpHooked then
        local vis = widget:IsVisible()
        XPSyncQuestEvents(widget, vis)
        XPSyncClock(widget, vis)
    end
end

-- The first PLAYER_ENTERING_WORLD of a load. A login starts a new session in
-- the entry a time content built: its clock starts and the rate starts over
-- (a character's first time content turned on after a /reload counts from
-- then); a /reload keeps both (GetTime() counts on through it). The time this
-- level saved at the last logout is taken for this load and cleared from the
-- store, so a load that does not track it saves nothing; on a /reload the
-- seconds the reload took are added (/played counted on through it). Play
-- this file never sees (a crash before the save, a session with Action Bars
-- off) leaves the last saved time behind, read back short until a level-up
-- or the player's own /played. The bar can be built before this (its build
-- waits on a timer), so what it armed is brought up to date here.
local function XPOnFirstWorld(isInitialLogin)
    local nowTime = GetTime()
    xpWorldSeen = true
    if isInitialLogin then
        xpLoginAt = nowTime
    end
    local e = XPCharEntry(false)
    local widget = dataBarFrames.XPBar
    if e then
        if isInitialLogin then
            e.sStart = nowTime
            e.rStart, e.gained, e.lastXP, e.lastMax, e.lastLevel = nil, nil, nil, nil, nil
            if widget and widget._xpNeedRate then
                XPRateBaseline(e)
            end
        end
        local t, at = e.lvlTime, e.lvlAt
        e.lvlTime, e.lvlAt = nil, nil
        if type(t) == "number" and e.lvl == UnitLevel("player") then
            if not isInitialLogin and type(at) == "number" and at <= nowTime then
                t = t + (nowTime - at)
            end
            xpLvl, xpLvlBase, xpLvlStamp = e.lvl, t, nowTime
        end
    end
    if widget then
        if widget._xpNeedLevelTime then
            XPSyncLevelEvents(widget)
        end
        XPRequestPlayed(widget)
        if isInitialLogin and xpClock then
            -- Realigned on the session clock that starts now.
            XPSyncClock(widget, false)
            XPSyncClock(widget, widget:IsVisible())
        end
        if widget._xpNeedClock and widget:IsVisible() then
            XPRepaint(widget, "nc")
        end
    end
end

xpTextEv:SetScript("OnEvent", function(self, evt, arg1, arg2)
    if evt == "TIME_PLAYED_MSG" then
        -- arg2: the time played this level, as of now.
        if type(arg2) ~= "number" then
            return
        end
        XPSetLevelTime(arg2)
    elseif evt == "PLAYER_LOGOUT" then
        -- Also fires on /reload, before SavedVariables are written.
        if xpLvlBase then
            local e = XPCharEntry(true)
            if e then
                local nowTime = GetTime()
                e.lvl, e.lvlTime, e.lvlAt = xpLvl, xpLvlBase + (nowTime - xpLvlStamp), nowTime
            end
        end
    else
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        XPOnFirstWorld(arg1)
    end
end)
xpTextEv:RegisterEvent("PLAYER_ENTERING_WORLD")

-- The fill at these values: the bar's value and Smart Ticks, a gradient (Fill
-- Style) or the flat colour, which overwrites a gradient painted before it,
-- the rested overlay and the Quest XP Overlay. UpdateXPBar paints the live bar
-- with the player's XP; the options preview paints its own frame with sample
-- values. On ns.
function mod.PaintXPFill(widget, cfg, current, mx, rested)
    local barFrame = widget._bar
    barFrame:SetMinMaxValues(0, mx)
    barFrame:SetValue(current)
    mod.ApplyDataBarSmartTicks(widget)

    local gradDir, gsr, gsg, gsb, gsa, ger, geg, geb, gea = mod.XPBarGradient(cfg)
    local flat = not gradDir
    if gradDir then
        XPPaintGradient(barFrame, gradDir, gsr, gsg, gsb, gsa, ger, geg, geb, gea)
    elseif barFrame._xpGrad then
        barFrame._xpGrad.on = nil
    end

    local restBar = widget._restedBar
    if rested > 0 then
        if flat then
            barFrame:SetStatusBarColor(
                mod.ResolveDataBarColor(
                    cfg,
                    XP_BAR_COLORS.xpRested.r,
                    XP_BAR_COLORS.xpRested.g,
                    XP_BAR_COLORS.xpRested.b
                )
            )
        end
        restBar:SetMinMaxValues(0, mx)
        restBar:SetValue(min(current + rested, mx))
        -- Rested Color (the XP Bar tab), else the dark blue at half opacity.
        local restColor = cfg.restedColor or XP_BAR_COLORS.xpRestedBG
        restBar:SetStatusBarColor(restColor.r, restColor.g, restColor.b, restColor.a or 0.5)
        restBar:Show()
    else
        if flat then
            barFrame:SetStatusBarColor(
                mod.ResolveDataBarColor(
                    cfg,
                    XP_BAR_COLORS.xpNoRest.r,
                    XP_BAR_COLORS.xpNoRest.g,
                    XP_BAR_COLORS.xpNoRest.b
                )
            )
        end
        restBar:Hide()
    end
    XPPaintQuestOverlay(widget, current, mx)
end

-- The texts, for the options preview (filter nil: every one).
mod.PaintXPText = XPPaintText

-- levelUp: called from PLAYER_LEVEL_UP, whose values can be half updated.
local function UpdateXPBar(levelUp)
    -- XP per Hour counts the XP gained while the bar's visibility hides it
    -- too; after a level-up, the XP update that follows counts the gain.
    local holderFrame = dataBarFrames.XPBar
    if holderFrame and holderFrame._xpWant then
        -- Max level, Never or Blizzard's bars reached or left: re-arm.
        local s0 = ABAR.db.profile.bars.XPBar
        if XPBarCanShow(s0) ~= holderFrame._xpLive then
            mod.XPBarTextSlots(holderFrame, s0)
        end
        if holderFrame._xpNeedRate and not levelUp and XPTrackRate() then
            holderFrame._xpPaintDirty = true
        end
    end

    local widget, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("XPBar")
    if not widget then
        return
    end

    -- Hide at max level (or XP disabled)
    if mod.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["XPBar"], widget, s, false, true)
        return
    end

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    if maxXP <= 0 then
        maxXP = 1
    end
    local restedXP = GetXPExhaustion() or 0
    local level = UnitLevel("player")

    -- Smart profession fill: one flipbook pass on each XP gain (a level-up
    -- resets XP low but is still a gain).
    if widget._fvFlipSmart then
        local lv = widget._lastXPLevel
        if lv and (level > lv or (level == lv and currentXP > widget._lastXP)) then
            mod.PlayXPFlipOnce(widget)
        end
        widget._lastXP, widget._lastXPLevel = currentXP, level
    end

    mod.PaintXPFill(widget, s, currentXP, maxXP, restedXP)

    -- The texts (Center's "classic" is the bar's original text), only when an
    -- input changed: the XP values, a layout pass or a rate gain
    -- (_xpPaintDirty). Time, quests and /played repaint through XPRepaint.
    if
        widget._xpPaintDirty
        or currentXP ~= widget._xpPCur
        or maxXP ~= widget._xpPMax
        or restedXP ~= widget._xpPRest
        or level ~= widget._xpPLvl
    then
        widget._xpPaintDirty = nil
        widget._xpPCur, widget._xpPMax, widget._xpPRest, widget._xpPLvl = currentXP, maxXP, restedXP, level
        XPPaintText(widget, s, nil, currentXP, maxXP, restedXP, level)
    end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("XPBar", widget, s)
end

-- The XP bar's frame: the data bar frame plus its rested overlay bar (behind
-- the main bar). parent: the options preview's frame (CreateDataBarFrame),
-- nil the live bar. On ns.
function mod.CreateXPBarFrame(updateFunc, hostFrame)
    local holderFrame = CreateDataBarFrame("XPBar", updateFunc, hostFrame)
    local restBar = CreateFrame("StatusBar", not hostFrame and "CludesEAB_XPBar_Rested" or nil, holderFrame)
    restBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.SetInside(restBar, holderFrame, 1, 1)
    else
        restBar:SetPoint("TOPLEFT", 1, -1)
        restBar:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    restBar:SetMinMaxValues(0, 1)
    restBar:SetValue(0)
    restBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    restBar:Hide()
    holderFrame._restedBar = restBar
    return holderFrame
end

-- Called by CreateManagedDataBarFrames (CUI_ActionBars_DataBars.lua) when the
-- data bars are built at enable.
function mod.CreateXPBar()
    local holderFrame = mod.CreateXPBarFrame(UpdateXPBar)
    holderFrame:SetPoint("TOP", UIParent, "TOP", 0, -100)

    -- Tooltip. Click Through suppresses it: on a mouseover bar the holder keeps mouse
    -- motion only so the hover fade can see the cursor.
    holderFrame:EnableMouse(true)
    holderFrame:SetScript("OnEnter", function(self)
        local conf = ABAR
            and ABAR.db
            and ABAR.db.profile
            and ABAR.db.profile.bars
            and ABAR.db.profile.bars["XPBar"]
        if conf and conf.clickThrough then
            return
        end
        if mod.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        if maxXP <= 0 then
            maxXP = 1
        end
        local restedXP = GetXPExhaustion() or 0
        local percent = (currentXP / maxXP) * 100
        local remain = maxXP - currentXP
        GameTooltip:AddLine(CludesUI.L("Experience"), 1, 1, 1)
        GameTooltip:AddDoubleLine(CludesUI.L("Level"), tostring(UnitLevel("player")), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(
            CludesUI.L("XP"),
            format("%s / %s (%.1f%%)", BreakUpLargeNumbers(currentXP), BreakUpLargeNumbers(maxXP), percent),
            1,
            1,
            1,
            1,
            1,
            1
        )
        GameTooltip:AddDoubleLine(CludesUI.L("Remaining"), BreakUpLargeNumbers(remain), 1, 1, 1, 1, 1, 1)
        if restedXP > 0 then
            GameTooltip:AddDoubleLine(
                CludesUI.L("Rested"),
                format("+%s (%.1f%%)", BreakUpLargeNumbers(restedXP), (restedXP / maxXP) * 100),
                1,
                1,
                1,
                1,
                1,
                1
            )
        end
        GameTooltip:Show()
    end)
    holderFrame:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)

    -- Events. A level-up also starts Time This Level over and rescans the
    -- completed quests; a zone change asks for /played if that is still owed.
    local evFrame = mod.TakeShell()
    evFrame:RegisterEvent("PLAYER_XP_UPDATE")
    evFrame:RegisterEvent("PLAYER_LEVEL_UP")
    evFrame:RegisterEvent("UPDATE_EXHAUSTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:SetScript("OnEvent", function(_, evt, arg1)
        if evt == "PLAYER_LEVEL_UP" then
            XPTextLevelUp(holderFrame, arg1)
            UpdateXPBar(true)
            return
        end
        if evt == "PLAYER_ENTERING_WORLD" then
            XPRequestPlayed(holderFrame)
        end
        UpdateXPBar()
    end)

    ApplyDataBarLayout("XPBar")
    UpdateXPBar()
end
