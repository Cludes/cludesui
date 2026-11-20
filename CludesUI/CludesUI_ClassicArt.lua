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
local CludesUI = _G.CludesUI
if not CludesUI then
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
CludesUI.ClassicFrame = CF
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
function CF.Pad(key, vertical)
    key = key or 1
    if vertical then
        return (RIM_T + RIM_B) * key, (RIM_L + RIM_R) * key
    end
    return (RIM_L + RIM_R) * key, (RIM_T + RIM_B) * key
end

-- Piece indices.
local TL, T, TR, L, C, R, BL, B, BR = 1, 2, 3, 4, 5, 6, 7, 8, 9
local N = 9

-- Nine textures on `parent` at layer/sublevel, created once; keep the table
-- and hand it back to Seat.
function CF.Create(hostFrame, layer, sub)
    local p = {}
    for idx = 1, N do
        local t = hostFrame:CreateTexture(nil, layer or "OVERLAY", nil, sub or 2)
        t:SetTexture(FILE)
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        p[idx] = t
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
function CF.Seat(profile, rect, key, vertical)
    if not (profile and rect) then
        return
    end
    key = key or 1
    vertical = vertical and true or false
    if profile._rect == rect and profile._k == key and profile._vert == vertical then
        return
    end
    profile._rect, profile._k, profile._vert = rect, key, vertical
    for idx = 1, N do
        profile[idx]:ClearAllPoints()
    end
    local cap, topY, bot = CAP * key, TOP * key, BOT * key
    if not vertical then
        Coords(profile[TL], X0, X1, Y0, Y1)
        profile[TL]:SetSize(cap, topY)
        profile[TL]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_L * key, OVER_T * key)
        Coords(profile[TR], X2, X3, Y0, Y1)
        profile[TR]:SetSize(cap, topY)
        profile[TR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_R * key, OVER_T * key)
        Coords(profile[T], X1, X2, Y0, Y1)
        profile[T]:SetHeight(topY)
        profile[T]:SetPoint("TOPLEFT", profile[TL], "TOPRIGHT", 0, 0)
        profile[T]:SetPoint("TOPRIGHT", profile[TR], "TOPLEFT", 0, 0)
        Coords(profile[BL], X0, X1, Y2, Y3)
        profile[BL]:SetSize(cap, bot)
        profile[BL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_L * key, -OVER_B * key)
        Coords(profile[BR], X2, X3, Y2, Y3)
        profile[BR]:SetSize(cap, bot)
        profile[BR]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_R * key, -OVER_B * key)
        Coords(profile[B], X1, X2, Y2, Y3)
        profile[B]:SetHeight(bot)
        profile[B]:SetPoint("BOTTOMLEFT", profile[BL], "BOTTOMRIGHT", 0, 0)
        profile[B]:SetPoint("BOTTOMRIGHT", profile[BR], "BOTTOMLEFT", 0, 0)
        -- The window band stretches to the bar's height between the rims.
        Coords(profile[L], X0, X1, Y1, Y2)
        profile[L]:SetPoint("TOPLEFT", profile[TL], "BOTTOMLEFT", 0, 0)
        profile[L]:SetPoint("BOTTOMRIGHT", profile[BL], "TOPRIGHT", 0, 0)
        Coords(profile[R], X2, X3, Y1, Y2)
        profile[R]:SetPoint("TOPLEFT", profile[TR], "BOTTOMLEFT", 0, 0)
        profile[R]:SetPoint("BOTTOMRIGHT", profile[BR], "TOPRIGHT", 0, 0)
        Coords(profile[C], X1, X2, Y1, Y2)
        profile[C]:SetPoint("TOPLEFT", profile[L], "TOPRIGHT", 0, 0)
        profile[C]:SetPoint("BOTTOMRIGHT", profile[R], "BOTTOMLEFT", 0, 0)
    else
        -- Turned: the art's top band runs along the bar's left (width top),
        -- its bottom band along the right (width bot), its right cap sits at
        -- the bar's top and its left cap at the bottom (height cap).
        Coords(profile[TR], X2, X3, Y0, Y1, true)
        profile[TR]:SetSize(topY, cap)
        profile[TR]:SetPoint("TOPLEFT", rect, "TOPLEFT", -OVER_T * key, OVER_R * key)
        Coords(profile[TL], X0, X1, Y0, Y1, true)
        profile[TL]:SetSize(topY, cap)
        profile[TL]:SetPoint("BOTTOMLEFT", rect, "BOTTOMLEFT", -OVER_T * key, -OVER_L * key)
        Coords(profile[T], X1, X2, Y0, Y1, true)
        profile[T]:SetWidth(topY)
        profile[T]:SetPoint("TOPLEFT", profile[TR], "BOTTOMLEFT", 0, 0)
        profile[T]:SetPoint("BOTTOMLEFT", profile[TL], "TOPLEFT", 0, 0)
        Coords(profile[BR], X2, X3, Y2, Y3, true)
        profile[BR]:SetSize(bot, cap)
        profile[BR]:SetPoint("TOPRIGHT", rect, "TOPRIGHT", OVER_B * key, OVER_R * key)
        Coords(profile[BL], X0, X1, Y2, Y3, true)
        profile[BL]:SetSize(bot, cap)
        profile[BL]:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", OVER_B * key, -OVER_L * key)
        Coords(profile[B], X1, X2, Y2, Y3, true)
        profile[B]:SetWidth(bot)
        profile[B]:SetPoint("TOPRIGHT", profile[BR], "BOTTOMRIGHT", 0, 0)
        profile[B]:SetPoint("BOTTOMRIGHT", profile[BL], "TOPRIGHT", 0, 0)
        -- The window band stretches to the bar's width between the rims.
        Coords(profile[R], X2, X3, Y1, Y2, true)
        profile[R]:SetPoint("TOPLEFT", profile[TR], "TOPRIGHT", 0, 0)
        profile[R]:SetPoint("BOTTOMRIGHT", profile[BR], "BOTTOMLEFT", 0, 0)
        Coords(profile[L], X0, X1, Y1, Y2, true)
        profile[L]:SetPoint("TOPLEFT", profile[TL], "TOPRIGHT", 0, 0)
        profile[L]:SetPoint("BOTTOMRIGHT", profile[BL], "BOTTOMLEFT", 0, 0)
        Coords(profile[C], X1, X2, Y1, Y2, true)
        profile[C]:SetPoint("TOPLEFT", profile[R], "BOTTOMLEFT", 0, 0)
        profile[C]:SetPoint("BOTTOMRIGHT", profile[L], "TOPRIGHT", 0, 0)
    end
    for idx = 1, N do
        profile[idx]:Show()
    end
end
