if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_ClassicArt.lua
--
--  Classic WoW UI: the vanilla cast bar frame (Interface\CastingBar\
--  UI-CastingBar-Border, a 256x64 sheet drawn round a 195x13 bar) as a
--  nine-slice round any bar. Measured on the sheet: the top rim is opaque
--  on rows 22..27 and the bottom rim on rows 37..41, each with a soft
--  shadow fading into the window; the end caps' vertical rims sit on columns
--  27..33 and 222..228; and the window itself is NOT clear -- it carries a
--  13% black tint over the whole bar (alpha 34) plus those inner shadows,
--  which is what makes a vanilla bar read recessed. The sheet is cut at
--  columns 16 | 48 | 208 | 240 and rows 16 | 28 | 37 | 48: two 32-column
--  end caps with the middle between, each split into the 12-row top band
--  (margin + rim), the 9-row window band (shadow, clear, shadow) and the
--  11-row bottom band (rim + fade + margin). Caps and rim bands draw at the
--  sheet's own pixel size (k = 1) and only the window band stretches to the
--  bar, so a thin bar and a tall one wear the same weight of frame; the
--  window's centre piece IS drawn (its tint over the fill is the look). A
--  vertical bar turns every piece a quarter turn counter-clockwise (the
--  art's top rim along the bar's left, its right cap at the bar's top).
--  Shared by the unit frame and resource bar cast bars, the health / power
--  / class resource bars and the tracked buff bars, each of which scales it
--  by its own Border Size percentage (CF.ScaleK).
--
--  Cost: nine textures created once per bar, re-anchored only when the rect,
--  scale or orientation changes (memo on the piece table); nothing runs while
--  the style is off (no caller reaches it).
-------------------------------------------------------------------------------
local CUI = _G.CludesUI
if not CUI then
    return
end

local FILE = "Interface\\CastingBar\\UI-CastingBar-Border"
-- Sheet cut lines as texcoords (columns 16, 48, 208, 240 of 256; rows 16,
-- 28, 37, 48 of 64).
local X0, X1, X2, X3 = 0.0625, 0.1875, 0.8125, 0.9375
local Y0, Y1, Y2, Y3 = 0.25, 0.4375, 0.578125, 0.75
-- Piece sizes in sheet pixels: cap width; top and bottom band heights.
local CAP, TOP, BOT = 32, 12, 11
-- The frame's reach beyond the bar it is drawn round: the caps overhang the
-- bar's ends by 14.5, the top band sits on the bar's top edge and the bottom
-- band hangs under its bottom edge.
local OVER_L, OVER_R, OVER_T, OVER_B = 14.5, 14.5, TOP, BOT

local CF = {}
CUI.ClassicFrame = CF
CF.FILE = FILE
CF.OVER_L, CF.OVER_R, CF.OVER_T, CF.OVER_B = OVER_L, OVER_R, OVER_T, OVER_B

-- A bar's frame size: the percentage of the sheet's own size its Border Size
-- slider stores on the bar's settings (nil = BORDER_DEFAULT), as the scale k
-- Seat and Pad take. Caps, rims and reach all scale together.
CF.BORDER_DEFAULT = 60
function CF.ScaleK(pct)
    return (pct or CF.BORDER_DEFAULT) / 100
end

-- How far the frame's VISIBLE rim reaches past the bar, in sheet pixels: the
-- caps' vertical rims start at columns 27 and 228, 3.5 outside the bar's ends
-- (30.5 and 225.5); the top rim's rows 22..27 sit 6 above the bar and the
-- bottom rim's rows 37..41 hang 5 below it. The caps' transparent margin (the
-- rest of OVER_L / OVER_R) is not frame a player sees.
local RIM_L, RIM_R, RIM_T, RIM_B = 3.5, 3.5, 6, 5

-- The frame's visible rim beyond a bar's rect at scale k, for size matching
-- (a matched element lines up with the rim, not the art's margin): extra
-- width, extra height.
function CF.Pad(scale, vertical)
    scale = scale or 1
    if vertical then
        return (RIM_T + RIM_B) * scale, (RIM_L + RIM_R) * scale
    end
    return (RIM_L + RIM_R) * scale, (RIM_T + RIM_B) * scale
end

-- Piece indices.
local TL, T, TR, L, C, R, BL, B, BR = 1, 2, 3, 4, 5, 6, 7, 8, 9
local N = 9

-- Nine textures on `parent` at layer/sublevel, created once; keep the table
-- and hand it back to Seat.
function CF.Create(hostFrame, layer, sub)
    local p = {}
    for idx = 1, N do
        local tex = hostFrame:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2)
        tex:SetTexture(FILE)
        if tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
        end
        p[idx] = tex
    end
    return p
end

function CF.SetShown(profile, isShown)
    for idx = 1, N do
        profile[idx]:SetShown(isShown and true or false)
    end
end

-- A sheet sub-rectangle on a piece: upright, or turned a quarter turn
-- counter-clockwise (the sub-rectangle's top edge lands on the piece's left).
local function Coords(t, a, b, c, d, turned)
    if turned then
        t:SetTexCoord(b, c, a, c, b, d, a, d)
    else
        t:SetTexCoord(a, b, c, d)
    end
end

-- Lays the frame round `rect` at scale k (1 = the sheet's pixels). Memoized
-- on rect, k and orientation; every layout pass may call it.
function CF.Seat(pieces, rect, scale, vertical)
    if not (pieces and rect) then
        return
    end
    scale = scale or 1
    vertical = vertical and true or false
    if pieces._rect == rect and pieces._k == scale and pieces._vert == vertical then
        return
    end
    pieces._rect, pieces._k, pieces._vert = rect, scale, vertical
    for idx = 1, N do
        pieces[idx]:ClearAllPoints()
    end
    local cap, topY, bot = CAP * scale, TOP * scale, BOT * scale
    if not vertical then
        Coords(pieces[TL], X0, X1, Y0, Y1)
        pieces[TL]:SetSize(cap, topY)
        pieces[TL]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_L * scale, OVER_T * scale)
        Coords(pieces[TR], X2, X3, Y0, Y1)
        pieces[TR]:SetSize(cap, topY)
        pieces[TR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_R * scale, OVER_T * scale)
        Coords(pieces[T], X1, X2, Y0, Y1)
        pieces[T]:SetHeight(topY)
        pieces[T]:SetPoint("TOPLEFT", pieces[TL], "TOPRIGHT", 0, 0)
        pieces[T]:SetPoint("TOPRIGHT", pieces[TR], "TOPLEFT", 0, 0)
        Coords(pieces[BL], X0, X1, Y2, Y3)
        pieces[BL]:SetSize(cap, bot)
        pieces[BL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_L * scale, -OVER_B * scale)
        Coords(pieces[BR], X2, X3, Y2, Y3)
        pieces[BR]:SetSize(cap, bot)
        pieces[BR]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_R * scale, -OVER_B * scale)
        Coords(pieces[B], X1, X2, Y2, Y3)
        pieces[B]:SetHeight(bot)
        pieces[B]:SetPoint("BOTTOMLEFT", pieces[BL], "BOTTOMRIGHT", 0, 0)
        pieces[B]:SetPoint("BOTTOMRIGHT", pieces[BR], "BOTTOMLEFT", 0, 0)
        -- The window band stretches to the bar's height between the rims.
        Coords(pieces[L], X0, X1, Y1, Y2)
        pieces[L]:SetPoint("TOPLEFT", pieces[TL], "BOTTOMLEFT", 0, 0)
        pieces[L]:SetPoint("BOTTOMRIGHT", pieces[BL], "TOPRIGHT", 0, 0)
        Coords(pieces[R], X2, X3, Y1, Y2)
        pieces[R]:SetPoint("TOPLEFT", pieces[TR], "BOTTOMLEFT", 0, 0)
        pieces[R]:SetPoint("BOTTOMRIGHT", pieces[BR], "TOPRIGHT", 0, 0)
        Coords(pieces[C], X1, X2, Y1, Y2)
        pieces[C]:SetPoint("TOPLEFT", pieces[L], "TOPRIGHT", 0, 0)
        pieces[C]:SetPoint("BOTTOMRIGHT", pieces[R], "BOTTOMLEFT", 0, 0)
    else
        -- Turned: the art's top band runs along the bar's left (width top),
        -- its bottom band along the right (width bot), its right cap sits at
        -- the bar's top and its left cap at the bottom (height cap).
        Coords(pieces[TR], X2, X3, Y0, Y1, true)
        pieces[TR]:SetSize(topY, cap)
        pieces[TR]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_T * scale, OVER_R * scale)
        Coords(pieces[TL], X0, X1, Y0, Y1, true)
        pieces[TL]:SetSize(topY, cap)
        pieces[TL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_T * scale, -OVER_L * scale)
        Coords(pieces[T], X1, X2, Y0, Y1, true)
        pieces[T]:SetWidth(topY)
        pieces[T]:SetPoint("TOPLEFT", pieces[TR], "BOTTOMLEFT", 0, 0)
        pieces[T]:SetPoint("BOTTOMLEFT", pieces[TL], "TOPLEFT", 0, 0)
        Coords(pieces[BR], X2, X3, Y2, Y3, true)
        pieces[BR]:SetSize(bot, cap)
        pieces[BR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_B * scale, OVER_R * scale)
        Coords(pieces[BL], X0, X1, Y2, Y3, true)
        pieces[BL]:SetSize(bot, cap)
        pieces[BL]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_B * scale, -OVER_L * scale)
        Coords(pieces[B], X1, X2, Y2, Y3, true)
        pieces[B]:SetWidth(bot)
        pieces[B]:SetPoint("TOPRIGHT", pieces[BR], "BOTTOMRIGHT", 0, 0)
        pieces[B]:SetPoint("BOTTOMRIGHT", pieces[BL], "TOPRIGHT", 0, 0)
        -- The window band stretches to the bar's width between the rims.
        Coords(pieces[R], X2, X3, Y1, Y2, true)
        pieces[R]:SetPoint("TOPLEFT", pieces[TR], "TOPRIGHT", 0, 0)
        pieces[R]:SetPoint("BOTTOMRIGHT", pieces[BR], "BOTTOMLEFT", 0, 0)
        Coords(pieces[L], X0, X1, Y1, Y2, true)
        pieces[L]:SetPoint("TOPLEFT", pieces[TL], "TOPRIGHT", 0, 0)
        pieces[L]:SetPoint("BOTTOMRIGHT", pieces[BL], "BOTTOMLEFT", 0, 0)
        Coords(pieces[C], X1, X2, Y1, Y2, true)
        pieces[C]:SetPoint("TOPLEFT", pieces[R], "BOTTOMLEFT", 0, 0)
        pieces[C]:SetPoint("BOTTOMRIGHT", pieces[L], "TOPRIGHT", 0, 0)
    end
    for idx = 1, N do
        pieces[idx]:Show()
    end
end
