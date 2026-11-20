if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Portrait.lua
--
--  The party frames' portrait (Party tab PORTRAIT section), under every
--  style. Portrait Mode: None, Attached (a square the frame's height beside
--  the bars; the party box widens by it through ns.RF_PartyDims) or Detached
--  (off the health bar's edge with a shape mask and border, or inside the
--  bar with a 3D model). Art Style: 2D portrait, 3D model or class art. The
--  Party Frames kit keeps its own portrait socket and takes the Art Style
--  alone (2D or class).
--
--  Nothing here exists until the portrait is first turned on: the backdrop,
--  its textures, the bars' area frame and (3D only) the model are built on
--  that first pass, and the portrait events register only while the party
--  frames are shown with a portrait that needs them (RF_KitPortraitEvents).
--  State lives on our own backdrop frame, st.pt, where `st` is a header
--  button's FFD entry (never a key on the button) or the preview frame.
--  Layout is out of combat only (the aura containers make the bars
--  protected); painting runs any time.
-------------------------------------------------------------------------------
local _, mod = ...

local Pix = CludesUI.PP

local MASKS, BORDERS = CludesUI.SHAPE_MASKS, CludesUI.SHAPE_BORDERS
local MASK_INSETS = CludesUI.SHAPE_INSETS
local CLASS_ART = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local QMARK_MODEL = "Interface\\Buttons\\TalkToMeQuestionMark.m2"

-- 3D Zoom (100..ZOOM3D_MAX, also the options slider's max) -> portrait
-- zoom, camera distance. Up to 300 it is the distance alone (1..3); above,
-- the camera blends to the full body (portrait zoom 1 -> 0, distance 3 -> 1).
local ZOOM3D_STOCK, ZOOM3D_MAX = 300, 500
mod.RF_PT_ZOOM3D_MAX = ZOOM3D_MAX
local function Zoom3DOf(z)
    z = z or 100
    if z <= ZOOM3D_STOCK then
        return 1, z / 100
    end
    if z > ZOOM3D_MAX then
        z = ZOOM3D_MAX
    end
    local t = (z - ZOOM3D_STOCK) / (ZOOM3D_MAX - ZOOM3D_STOCK)
    local skinData = ZOOM3D_STOCK / 100
    return 1 - t, skinData - (skinData - 1) * t
end

local function Point(region, p, rel, rp, posX, posY)
    if Pix and Pix.Point then
        Pix.Point(region, p, rel, rp, posX, posY)
    else
        region:SetPoint(p, rel, rp, posX, posY)
    end
end

-- Class art from the shared sprite sheets.
function mod.RF_PtClassArt(texture, ct, style)
    local c = CludesUI.CLASS_ICON_SPRITE_COORDS and CludesUI.CLASS_ICON_SPRITE_COORDS[ct]
    if not (texture and c) then
        return
    end
    texture:SetTexture(CLASS_ART .. (style or "modern") .. ".tga")
    texture:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- The attached portrait's width in the party box (callers snap): a square
-- the frame's full height. Detached and inside take no room.
function mod.RF_PtReserve(cfg, hgt)
    if (cfg.partyPortraitStyle or "none") ~= "attached" then
        return 0
    end
    return hgt
end

-- Effective side and whether it sits inside the bar: an attached portrait
-- takes the left or right edge only, inside needs Detached.
local function SideOf(cfg, style)
    local side = cfg.partyPortraitSide or "left"
    local inside = side == "insideleft" or side == "insideright" or side == "insidecenter"
    if style == "attached" then
        if side ~= "right" then
            side = "left"
        end
        return side, false
    end
    return side, inside
end

-- 2D art re-seated on its stored rect (the backdrop, or the mask-expanded
-- rect of a shaped portrait): the portrait paint resets its anchors.
local function SeatArt2D(edge)
    local t = edge._2d
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(t)
    end
    t:ClearAllPoints()
    Point(t, "TOPLEFT", edge, "TOPLEFT", edge._oL, edge._oT)
    Point(t, "BOTTOMRIGHT", edge, "BOTTOMRIGHT", edge._oR, edge._oB)
end
local function SeatClassArt(edge, hgt)
    local t = edge._class
    local ci = math.floor(hgt * 0.08)
    t:ClearAllPoints()
    Point(t, "TOPLEFT", edge, "TOPLEFT", ci + edge._oL, -ci + edge._oT)
    Point(t, "BOTTOMRIGHT", edge, "BOTTOMRIGHT", -ci + edge._oR, ci + edge._oB)
end

-- The 3D model drops its model while hidden: every re-show repaints it.
local function ModelOnShow(self)
    local edge = self._bd
    local st = edge and edge._st
    if not (st and edge._on) then
        return
    end
    local ownerFrame = edge._owner
    local u = edge._pvUnit or (ownerFrame and not edge._preview and ownerFrame:GetAttribute("unit"))
    if u and UnitExists(u) then
        mod.RF_PtPaint(st, u, "Show")
    end
end
local function Ensure3D(edge)
    local m = edge._3d
    if m then
        return m
    end
    m = CreateFrame("PlayerModel", nil, edge)
    m:SetAllPoints(edge)
    m:SetCamera(0)
    m:EnableMouse(false)
    m._bd = edge
    m:SetScript("OnShow", ModelOnShow)
    m:Hide()
    edge._3d = m
    mod._ptModelOn = true
    return m
end

-- Character Size: a scaled model renders on a canvas the box's size times
-- k, bottom-centred on the Inside box, which clips it; the box never
-- changes. At k = 1 the model fills the box.
local function ModelCanvas(edge, key, wid, hgt)
    local m = edge._3d
    if key == 1 or not (wid and hgt and wid > 0 and hgt > 0) then
        -- Back from a canvas: drop its BOTTOM anchor first.
        if edge._charCanvas then
            m:ClearAllPoints()
            edge._charCanvas = nil
        end
        m:SetAllPoints(edge)
        return
    end
    m:ClearAllPoints()
    m:SetSize(wid * key, hgt * key)
    m:SetPoint("BOTTOM", edge, "BOTTOM", 0, 0)
    edge._charCanvas = true
end
-- Installed only while scaled: the canvas follows the box's real size (the
-- Inside box's height comes from its anchors).
local function BoxSizeChanged(self, wid, hgt)
    ModelCanvas(self, self._charK or 1, wid, hgt)
end
-- Scaled only for a 3D model of an available unit (the question mark keeps
-- the box's size); a change of _charK, _3dOn or _state re-seats. Unscaled
-- (the default) is the stock re-anchor alone: no script, no size reads.
local function SeatModel(edge)
    if not edge._3d then
        return
    end
    local key = edge._charK or 1
    local scaled = key ~= 1 and edge._3dOn and edge._state ~= false or false
    if scaled ~= (edge._charHook or false) then
        edge:SetScript("OnSizeChanged", scaled and BoxSizeChanged or nil)
        edge._charHook = scaled
    end
    if scaled then
        ModelCanvas(edge, key, edge:GetWidth(), edge:GetHeight())
    else
        ModelCanvas(edge, 1)
    end
end

-- First enable: the backdrop and the bars' area. Health, power, the Top
-- Name Bar, the uniform anchor and the strips above the frame move onto
-- the area once; from then on a portrait change moves the area alone.
local function Ensure(ownerFrame, st, health)
    local edge = CreateFrame("Frame", nil, ownerFrame)
    edge:EnableMouse(false)
    local bgTex = edge:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0.1, 0.1, 0.1, 1)
    local t2 = edge:CreateTexture(nil, "ARTWORK")
    t2:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    t2:Hide()
    local tc = edge:CreateTexture(nil, "ARTWORK")
    tc:SetAlpha(0.8)
    tc:Hide()
    edge._bg, edge._2d, edge._class = bgTex, t2, tc
    edge._oL, edge._oT, edge._oR, edge._oB = 0, 0, 0, 0
    edge._owner, edge._st = ownerFrame, st
    edge._preview = (st == ownerFrame) or nil
    edge:Hide()

    local area = CreateFrame("Frame", nil, ownerFrame)
    area:EnableMouse(false)
    area:SetAllPoints(ownerFrame)
    edge._area = area
    health._cuiBarArea = area
    local _, _, _, _, hy = health:GetPoint(1)
    health:ClearAllPoints()
    health:SetPoint("TOPLEFT", area, "TOPLEFT", 0, hy or 0)
    health:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, hy or 0)
    local power = st.power or st._power
    if power then
        power:ClearAllPoints()
        power:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 0, 0)
        power:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    end
    local tnb = st.topNameBar or st._topNameBar
    if tnb then
        tnb:ClearAllPoints()
        tnb:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
        tnb:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    end
    local uref = st.uniformRef or st._uniformRef
    if uref then
        uref:ClearAllPoints()
        uref:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        uref:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
    end
    -- The absorb strips re-lay out on their next settings pass.
    local ab = st.absorbBar or st._absorbBar
    if ab then
        if ab._topBar then
            ab._topBar._lpPos = nil
        end
        if ab._healTopBar then
            ab._healTopBar._lpPos = nil
        end
    end
    st.pt = edge
    return edge
end

-- The portrait and the bars' area for a style/side (out of combat).
local function Seat(ownerFrame, edge, health, style, side, inside, size, px, py, bh)
    local area = edge._area
    edge:ClearAllPoints()
    area:ClearAllPoints()
    local wid, hgt
    if style == "none" then
        area:SetAllPoints(ownerFrame)
        return 0, 0
    elseif style == "attached" then
        wid, hgt = bh, bh
        edge:SetSize(wid, hgt)
        if side == "right" then
            edge:SetPoint("TOPRIGHT", ownerFrame, "TOPRIGHT", 0, 0)
            area:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", 0, 0)
            area:SetPoint("BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", -bh, 0)
        else
            edge:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", 0, 0)
            area:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", bh, 0)
            area:SetPoint("BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", 0, 0)
        end
        edge._lvl = 1
    elseif inside then
        -- Over the health bar, the frame's height, clipped to itself.
        area:SetAllPoints(ownerFrame)
        wid = bh + size
        if wid < 8 then
            wid = 8
        end
        hgt = bh
        edge:SetWidth(wid)
        if side == "insideleft" then
            edge:SetPoint("TOPLEFT", health, "TOPLEFT", px, py)
            edge:SetPoint("BOTTOMLEFT", ownerFrame, "BOTTOMLEFT", px, 0)
        elseif side == "insideright" then
            edge:SetPoint("TOPRIGHT", health, "TOPRIGHT", px, py)
            edge:SetPoint("BOTTOMRIGHT", ownerFrame, "BOTTOMRIGHT", px, 0)
        else
            edge:SetPoint("TOP", health, "TOP", px, py)
            edge:SetPoint("BOTTOM", ownerFrame, "BOTTOM", px, 0)
        end
        -- Above the fills, absorbs, power and Top Name Bar; under the
        -- dispel overlay, the border, text and auras.
        edge._lvl = 6
    else
        -- Detached: off the health bar's edge, a little larger than the
        -- frame, over its neighbours' borders.
        area:SetAllPoints(ownerFrame)
        wid = bh + size + 10
        if wid < 8 then
            wid = 8
        end
        hgt = wid
        edge:SetSize(wid, hgt)
        local posY = py + 5
        if side == "top" then
            edge:SetPoint("BOTTOM", health, "TOP", px, 15 + posY)
        elseif side == "right" then
            edge:SetPoint("TOPLEFT", health, "TOPRIGHT", 15 + px, posY)
        else
            edge:SetPoint("TOPRIGHT", health, "TOPLEFT", -15 + px, posY)
        end
        edge._lvl = 11
    end
    edge:SetClipsChildren(inside and true or false)
    return wid, hgt
end

local function Unmask(edge)
    local mk = edge._mask
    if not (mk and edge._masked) then
        return
    end
    edge._2d:RemoveMaskTexture(mk)
    edge._class:RemoveMaskTexture(mk)
    edge._bg:RemoveMaskTexture(mk)
    if edge._border then
        edge._border:RemoveMaskTexture(mk)
    end
    edge._masked = nil
    mk:Hide()
end

-- Detached shape: the mask over the art and background, the border ring
-- (natively 7px, grown outward so `size` px of it show past the mask) and
-- the art enlarged to fill the mask's opening. Anything else: plain square
-- art filling the backdrop. `w`/`h` = the backdrop's size.
local function Shape(edge, cfg, shaped, wid, hgt)
    local shape = shaped and (cfg.partyPortraitShape or "portrait") or nil
    if shape and not MASKS[shape] then
        shape = nil
    end
    local bs = cfg.partyPortraitBorderSize or 7
    local op = cfg.partyPortraitBorderOpacity or 100
    local art = cfg.partyPortraitArtScale or 100
    local colour = cfg.partyPortraitBorderColor
    local cr, cg, callback = colour and colour.r or 0, colour and colour.g or 0, colour and colour.b or 0
    local cc = cfg.partyPortraitBorderClassColor ~= false
    if
        edge._sShape == shape
        and edge._sBs == bs
        and edge._sOp == op
        and edge._sArt == art
        and edge._sW == wid
        and edge._sH == hgt
        and edge._sR == cr
        and edge._sG == cg
        and edge._sB == callback
        and edge._sCC == cc
        and edge._sSet
    then
        return false
    end
    edge._sShape, edge._sBs, edge._sOp, edge._sArt, edge._sW, edge._sH = shape, bs, op, art, wid, hgt
    edge._sR, edge._sG, edge._sB, edge._sCC, edge._sSet = cr, cg, callback, cc, true
    edge._tintClass = nil
    if not shape then
        Unmask(edge)
        if edge._border then
            edge._border:Hide()
        end
        edge._oL, edge._oT, edge._oR, edge._oB = 0, 0, 0, 0
    else
        local mk = edge._mask
        if not mk then
            mk = edge:CreateMaskTexture()
            edge._mask = mk
        end
        mk:ClearAllPoints()
        if bs >= 1 then
            Point(mk, "TOPLEFT", edge, "TOPLEFT", 1, -1)
            Point(mk, "BOTTOMRIGHT", edge, "BOTTOMRIGHT", -1, 1)
        else
            mk:SetAllPoints(edge)
        end
        mk:SetTexture(MASKS[shape], "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mk:Show()
        local bt = edge._border
        if not bt then
            bt = edge:CreateTexture(nil, "OVERLAY")
            edge._border = bt
        end
        local e = 7 - bs
        bt:ClearAllPoints()
        Point(bt, "TOPLEFT", edge, "TOPLEFT", -e, e)
        Point(bt, "BOTTOMRIGHT", edge, "BOTTOMRIGHT", e, -e)
        bt:SetTexture(BORDERS[shape])
        if not edge._masked then
            edge._2d:AddMaskTexture(mk)
            edge._class:AddMaskTexture(mk)
            edge._bg:AddMaskTexture(mk)
            bt:AddMaskTexture(mk)
            edge._masked = true
        end
        edge._bA = op / 100
        bt:SetVertexColor(cr, cg, callback, edge._bA)
        edge._tintClass = cc or nil
        bt:Show()
        local vis = (128 - 2 * (MASK_INSETS[shape] or 17)) / 128
        local ex = ((1 / vis) * (art / 100) - 1) * 0.5
        edge._oL, edge._oT, edge._oR, edge._oB = -(ex * wid), ex * hgt, ex * wid, -(ex * hgt)
    end
    SeatArt2D(edge)
    SeatClassArt(edge, hgt)
    -- A model is never masked: it seats on the backdrop.
    SeatModel(edge)
    return true
end

-- Class-coloured shape border: the unit's class for players, its reaction
-- colour otherwise, the player's own class in dark mode or with no unit.
local function PlayerClassColor()
    local _, classTok = UnitClass("player")
    local color = classTok and CludesUI.GetClassColor(classTok)
    if color then
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end
local function TintBorder(edge, unitToken, ctOverride)
    local bt = edge._border
    if not (bt and edge._tintClass) then
        return
    end
    local red, green, blue
    local cfg = mod._scaledPartyProxy
    if ctOverride then
        local color = CludesUI.GetClassColor(ctOverride)
        if color then
            red, green, blue = color.r, color.g, color.b
        end
    elseif cfg and cfg.healthColorMode == "dark" then
        red, green, blue = PlayerClassColor()
    elseif unitToken and UnitExists(unitToken) then
        local _, classTok = UnitClass(unitToken)
        local isPl = UnitIsPlayer(unitToken)
        if not issecretvalue(classTok) and not issecretvalue(isPl) and isPl and classTok then
            local color = CludesUI.GetClassColor(classTok)
            if color then
                red, green, blue = color.r, color.g, color.b
            end
        else
            local re = UnitReaction(unitToken, "player")
            local color = (not issecretvalue(re)) and re and FACTION_BAR_COLORS and FACTION_BAR_COLORS[re]
            if color then
                red, green, blue = color.r, color.g, color.b
            end
        end
    end
    if not red then
        red, green, blue = PlayerClassColor()
    end
    bt:SetVertexColor(red, green, blue, edge._bA or 1)
end

-- Which art region shows. Leaving 3D drops the model (frees it). True when
-- the mode changed.
local function SetMode(edge, mode)
    if edge._mode == mode then
        return false
    end
    edge._mode = mode
    edge._guid, edge._state, edge._ct = nil, nil, nil
    edge._2d:SetShown(mode == "2d")
    edge._class:SetShown(mode == "class")
    if mode == "3d" then
        Ensure3D(edge)
        edge._3dOn = true
        edge._3d:Show()
        if not edge._preview then
            mod.RF_PtModelAlphaApply(edge)
        end
    elseif edge._3d then
        edge._3dOn = nil
        edge._3d:ClearModel()
        edge._3d:Hide()
    end
    return true
end

-- Paint (any time, combat included: our own textures and model only).
-- Repaints on a new occupant, an availability change or a real appearance
-- event; a secret guid never matches, so it always repaints. An
-- unavailable 3D paint never stamps its guid, so the next trigger heals it.
function mod.RF_PtPaint(st, unitToken, evt)
    if st.kitPortrait then
        return mod.RF_KitPortrait(st, unitToken)
    end
    local edge = st.pt
    if not (edge and edge._on and unitToken) then
        return
    end
    local mode = edge._mode
    local unitGuid = UnitGUID(unitToken)
    local changed
    if issecretvalue(unitGuid) or issecretvalue(edge._guid) then
        changed = true
    else
        changed = edge._guid ~= unitGuid
    end
    local repainted = false
    if mode == "class" then
        local _, classTok = UnitClass(unitToken)
        if issecretvalue(classTok) then
            classTok = nil
        end
        classTok = classTok or "WARRIOR"
        -- (A change of art set clears _ct at its write in RF_PtApply.)
        if edge._ct ~= classTok or evt == "Force" then
            edge._ct = classTok
            mod.RF_PtClassArt(edge._class, classTok, edge._style)
            repainted = true
        end
        if not issecretvalue(unitGuid) then
            edge._guid = unitGuid
        end
    elseif mode == "3d" then
        local c, val = UnitIsConnected(unitToken), UnitIsVisible(unitToken)
        local avail = true
        if not (issecretvalue(c) or issecretvalue(val)) then
            avail = (c and val) and true or false
        end
        local m = edge._3d
        if
            m
            and (
                changed
                or edge._state ~= avail
                or evt == "Force"
                or evt == "UNIT_MODEL_CHANGED"
                or evt == "UNIT_PORTRAIT_UPDATE"
                or evt == "Show"
                or evt == "PLAYER_ENTERING_WORLD"
                or (evt == "PORTRAITS_UPDATED" and m:GetModelFileID() == nil)
            )
        then
            if avail then
                m:ClearModel()
                m:SetUnit(unitToken)
                edge._camP = edge._pz3d or 1
                m:SetPortraitZoom(edge._camP)
                m:SetPosition(0, 0, 0)
                edge._camZ = edge._zoom3d or 1
                m:SetCamDistanceScale(edge._camZ)
            else
                m:SetCamDistanceScale(0.25)
                m:SetPortraitZoom(0)
                m:SetPosition(0, 0, 0.25)
                m:ClearModel()
                m:SetModel(QMARK_MODEL)
                edge._camZ = nil
            end
            edge._guid = (avail and not issecretvalue(unitGuid)) and unitGuid or nil
            -- The question mark takes the box's size: a scaled model re-seats
            -- when availability flips.
            local reseat = (edge._charK or 1) ~= 1 and (edge._state == false) ~= (avail == false)
            edge._state = avail
            if reseat then
                SeatModel(edge)
            end
            repainted = true
        end
    else
        -- "Resync": the portrait events turning on (art may have streamed
        -- in while they were off).
        if
            changed
            or evt == "Force"
            or evt == "UNIT_PORTRAIT_UPDATE"
            or evt == "PORTRAITS_UPDATED"
            or evt == "UnitChanged"
            or evt == "Resync"
        then
            local t = edge._2d
            SetPortraitTexture(t, unitToken)
            SeatArt2D(edge)
            t:SetDesaturated(edge._desat or false)
            if not issecretvalue(unitGuid) then
                edge._guid = unitGuid
            end
            repainted = true
        end
    end
    -- The class-coloured border follows the occupant (a real assignment
    -- too: a same-guid return after a no-unit re-shape).
    if repainted or changed or evt == "UnitChanged" then
        TintBorder(edge, unitToken)
    end
end

-- Offline grey (from the health-background pass, which every connection
-- edge reaches): 2D and class desaturate, 3D swaps to the question mark.
function mod.RF_PtOffline(st, unitToken, connected)
    local edge = st.pt
    if not (edge and edge._on) then
        return
    end
    local off = not connected
    if edge._desat == off then
        return
    end
    edge._desat = off
    edge._2d:SetDesaturated(off)
    edge._class:SetDesaturated(off)
    if edge._mode == "3d" and unitToken then
        mod.RF_PtPaint(st, unitToken, "Conn")
    end
end

-- Clickable Portrait (party, default off): a detached portrait covered by a
-- second unit button for the same occupant (CludesUI.SyncPortraitClick,
-- CludesUI_SharedHelpers.lua). The unit resolves through the header
-- button, which the header re-assigns in combat; hover replays the button's
-- own tooltip and hover border.
local PORTRAIT_CLICK = {
    wanted = function(ownerFrame)
        local skinData = mod.GetFFD(ownerFrame)
        local edge = skinData.pt
        local cfg = mod._scaledPartyProxy
        return edge
                and edge._on
                and not skinData.kitPortrait
                and cfg.partyPortraitClickable
                and (cfg.partyPortraitStyle or "none") == "detached"
            or false
    end,
    backdrop = function(ownerFrame)
        return mod.GetFFD(ownerFrame).pt
    end,
    -- CUI_RaidFrames_Style.lua loads first.
    onEnter = mod.RF_ButtonOnEnter,
    onLeave = mod.RF_ButtonOnLeave,
    -- Same registration as the party button itself (_StyleButtonSecure).
    register = function(button)
        if mod.CC_RegisterFrame then
            mod.CC_RegisterFrame(button)
        else
            if type(ClickCastFrames) ~= "table" then
                ClickCastFrames = {}
            end
            ClickCastFrames[button] = true
        end
    end,
    parentUnit = true,
}

-- The whole pass for one party button or preview frame: build on first
-- enable, seat (deferred to the regen party pass only while a frame it
-- moves is protected: the aura containers protect the bars once anchored;
-- the first layout after a combat /reload applies at once), shape, art
-- mode, then paint `unit` when given. A settings pass paints only what its
-- memos say changed (a mode swap clears them), so it never reloads a model
-- that shows the right unit.
function mod.RF_PtApply(ownerFrame, st, cfg, bw, bh, unitToken)
    local style = cfg.partyPortraitStyle or "none"
    local edge = st.pt
    if style == "none" and not edge then
        return
    end
    local health = st.health or st._health
    if not health then
        return
    end
    local side, inside = SideOf(cfg, style)
    local size = cfg.partyPortraitSize or 0
    local px, py = cfg.partyPortraitX or 0, cfg.partyPortraitY or 0
    local es = ownerFrame:GetEffectiveScale()
    if
        not (
            edge
            and edge._gStyle == style
            and edge._gSide == side
            and edge._gIn == inside
            and edge._gSize == size
            and edge._gX == px
            and edge._gY == py
            and edge._gW == bw
            and edge._gH == bh
            and edge._gEs == es
        )
    then
        if InCombatLockdown() then
            local power = st.power or st._power
            local uref = st.uniformRef or st._uniformRef
            if
                health:IsProtected()
                or (power and power:IsProtected())
                or (uref and uref:IsProtected())
                or (edge and edge._area:IsProtected())
            then
                mod._partyKitDirtyInCombat = true
                return
            end
        end
        edge = edge or Ensure(ownerFrame, st, health)
        edge._gStyle, edge._gSide, edge._gIn, edge._gSize, edge._gX, edge._gY =
            style, side, inside, size, px, py
        edge._gW, edge._gH, edge._gEs = bw, bh, es
        edge._w, edge._h = Seat(ownerFrame, edge, health, style, side, inside, size, px, py, bh)
    end
    if style == "none" then
        if edge._on then
            edge._on = nil
            edge:Hide()
            SetMode(edge, nil)
            -- Off drops the Character Size script with the model.
            if (edge._charK or 1) ~= 1 then
                edge._charK = 1
                SeatModel(edge)
            end
        end
        if not edge._preview then
            CludesUI.SyncPortraitClick(ownerFrame, PORTRAIT_CLICK)
        end
        return
    end
    -- Levels re-asserted every pass (a strata change rebuilds child levels).
    local lvl = ownerFrame:GetFrameLevel() + (edge._lvl or 1)
    if edge:GetFrameLevel() ~= lvl then
        edge:SetFrameLevel(lvl)
    end
    local mode = cfg.partyPortraitMode or "2d"
    -- The class art set is a paint input: a change clears the class memo
    -- (a button with no unit repaints on its next occupant).
    local cs = cfg.partyPortraitClassStyle or "modern"
    if edge._style ~= cs then
        edge._style = cs
        edge._ct = nil
    end
    edge._pz3d, edge._zoom3d = Zoom3DOf(cfg.partyPortrait3dZoom)
    -- Character Size: Inside positions only (the box that clips it).
    local charK = inside and ((cfg.partyPortraitCharScale or 100) / 100) or 1
    local charKChanged = (edge._charK or 1) ~= charK
    edge._charK = charK
    -- Background under square and shaped art; none under a bare model.
    local shaped = style == "detached" and (cfg.partyPortraitShape or "portrait") ~= "none"
    edge._bg:SetShown(not inside and (style == "attached" or shaped))
    -- Detached: the Background Color (unset = the stock grey).
    local bgc = style == "detached" and cfg.partyPortraitBgColor
    if bgc then
        edge._bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 1)
    else
        edge._bg:SetColorTexture(0.1, 0.1, 0.1, 1)
    end
    local reshaped = Shape(edge, cfg, shaped, edge._w, edge._h)
    local wasOn = edge._on
    edge._on = true
    local swapped = SetMode(edge, mode)
    -- A new scale re-seats the model (a re-shape already did); so does a
    -- swap into or out of 3D while scaled (Shape seated before the swap).
    if (charKChanged and not reshaped) or (swapped and charK ~= 1) then
        SeatModel(edge)
    end
    if not wasOn then
        edge:Show()
    end
    -- A 3D Zoom change on a loaded model: the camera alone.
    local m = edge._3dOn and edge._3d
    if m and edge._state and edge._camZ and (edge._camZ ~= edge._zoom3d or edge._camP ~= edge._pz3d) then
        if edge._camP ~= edge._pz3d then
            edge._camP = edge._pz3d
            m:SetPortraitZoom(edge._pz3d)
        end
        edge._camZ = edge._zoom3d
        m:SetCamDistanceScale(edge._zoom3d)
    end
    if unitToken then
        mod.RF_PtPaint(st, unitToken, "Apply")
        -- The border colour is in no paint memo (a re-shape, dark mode).
        TintBorder(edge, unitToken)
        -- A new model starts at full alpha: take the unit's range fade now.
        if swapped and mode == "3d" and not edge._preview and mod._UpdateButtonRange then
            mod._UpdateButtonRange(unitToken, ownerFrame)
        end
    elseif reshaped and edge._tintClass and not edge._preview then
        -- A re-shaped border takes the default colour: re-tint it.
        local u = ownerFrame:GetAttribute("unit")
        TintBorder(edge, (u and UnitExists(u)) and u or nil)
    end
    if not edge._preview then
        CludesUI.SyncPortraitClick(ownerFrame, PORTRAIT_CLICK)
    end
end

-- Portrait events the current settings need (RF_KitPortraitEvents): "2d",
-- "3d" or nil (class art and a portrait that is off need none). The kit
-- never runs a model.
function mod.RF_PtEventMode(kit)
    local cfg = mod._scaledPartyProxy
    local m = cfg.partyPortraitMode or "2d"
    if kit then
        return (m ~= "class") and "2d" or nil
    end
    if (cfg.partyPortraitStyle or "none") == "none" or m == "class" then
        return nil
    end
    return (m == "3d") and "3d" or "2d"
end

-- Every party button, repainted (a zone-in resets models at the same
-- guid; the shown edge re-syncs after a hidden stretch).
function mod.RF_PtRepaintAll(evt)
    local entries = mod._partyAllButtons
    if not entries then
        return
    end
    local GetFFD = mod.GetFFD
    for index = 1, #entries do
        local widget = entries[index]
        local skinData = GetFFD(widget)
        if skinData.kitPortrait or (skinData.pt and skinData.pt._on) then
            local u = widget:GetAttribute("unit")
            if u and UnitExists(u) then
                mod.RF_PtPaint(skinData, u, evt)
            end
        end
    end
end

-- The options' light path (every portrait setting but the ones that change
-- the box width): re-apply each party button, re-sync the events.
function mod.RF_PtRefreshAll()
    local entries = mod._partyAllButtons
    local saved = mod.db
    if not (entries and saved and saved.profile) then
        return
    end
    local GetFFD = mod.GetFFD
    local s = mod._scaledPartyProxy
    local pw, ph = mod.RF_PartyDims(saved.profile)
    local bw, bh = mod.PixelSnap(pw), mod.PixelSnap(ph)
    for index = 1, #entries do
        local widget = entries[index]
        local skinData = GetFFD(widget)
        if skinData.styled then
            local u = widget:GetAttribute("unit")
            if u and not UnitExists(u) then
                u = nil
            end
            if skinData.kitPortrait then
                if u then
                    mod.RF_KitPortrait(skinData, u)
                end
                -- A click button from before the kit stands down.
                if skinData.pt then
                    CludesUI.SyncPortraitClick(widget, PORTRAIT_CLICK)
                end
            else
                mod.RF_PtApply(widget, skinData, s, bw, bh, u)
            end
        end
    end
    if mod.RF_KitPortraitEvents then
        mod.RF_KitPortraitEvents(mod._partyFramesVisible)
    end
end

-------------------------------------------------------------------------------
--  3D model alpha: a PlayerModel does not take its parent's alpha, so the
--  model mirrors the button's range fade (a secret in-range boolean goes
--  straight through SetAlphaFromBoolean) and the party container's alpha
--  (the options previews hide the live frames through it). Only runs while
--  a model exists.
-------------------------------------------------------------------------------
function mod.RF_PtModelAlphaApply(edge)
    local m = edge._3dOn and edge._3d
    if not m then
        return
    end
    local pc = mod._partyContainerFrame
    -- A UIParent fade (models ignore it) scales the mirror too.
    local c = CludesUI.UIScaledAlpha(pc and pc:GetAlpha() or 1)
    if not mod._ptUIAlphaHooked then
        mod._ptUIAlphaHooked = true
        CludesUI.OnUIAlphaChanged(mod.RF_PtContainerAlpha)
    end
    if edge._rSecret then
        m:SetAlphaFromBoolean(edge._rIn, c * edge._rA1, c * edge._rA2)
    else
        m:SetAlpha(c * (edge._rA1 or 1))
    end
end
function mod.RF_PtModelAlpha(st, a)
    local edge = st.pt
    if not (edge and edge._3dOn) then
        return
    end
    edge._rSecret, edge._rIn, edge._rA1, edge._rA2 = nil, nil, a, nil
    mod.RF_PtModelAlphaApply(edge)
end
function mod.RF_PtModelAlphaSecret(st, inRange, a1, a2)
    local edge = st.pt
    if not (edge and edge._3dOn) then
        return
    end
    local m = edge._3d
    if not m.SetAlphaFromBoolean then
        return mod.RF_PtModelAlpha(st, a1)
    end
    edge._rSecret, edge._rIn, edge._rA1, edge._rA2 = true, inRange, a1, a2
    mod.RF_PtModelAlphaApply(edge)
end
-- The container's alpha moved (callers gate on ns._ptModelOn): re-mirror.
function mod.RF_PtContainerAlpha()
    local entries = mod._partyAllButtons
    if not entries then
        return
    end
    local GetFFD = mod.GetFFD
    for index = 1, #entries do
        local edge = GetFFD(entries[index]).pt
        if edge and edge._3dOn then
            mod.RF_PtModelAlphaApply(edge)
        end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the party preview frame takes the same pass (built on
--  its first need; the raid preview never reaches here), then a mock paint:
--  the player's own portrait or model in the player's slot, the class crest
--  in the others (five copies of one face, or five models, would read
--  wrong), class art per slot, the offline slot greyed.
-------------------------------------------------------------------------------
function mod.RF_PtPreview(frame, cfg, classToken, isPlayer, offline)
    if (cfg.partyPortraitStyle or "none") == "none" and not frame.pt then
        return
    end
    local saved = mod.db
    local pw, ph = mod.RF_PartyDims(mod._pvOverlayProxy or (saved and saved.profile) or cfg)
    local bw, bh = mod.PixelSnap(pw), mod.PixelSnap(ph)
    frame:SetSize(bw, bh)
    mod.RF_PtApply(frame, frame, cfg, bw, bh, nil)
    local edge = frame.pt
    if not (edge and edge._on) then
        return
    end
    local _, playerCT = UnitClass("player")
    local mode = edge._mode
    local tc = (not isPlayer) and classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    edge._pvUnit = nil
    if mode == "class" then
        mod.RF_PtClassArt(edge._class, classToken or playerCT or "WARRIOR", edge._style)
    else
        local t2 = edge._2d
        if tc then
            if edge._3d then
                edge._3d:Hide()
            end
            t2:SetTexture(CLASS_SHEET)
            t2:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            SeatArt2D(edge)
            t2:Show()
        elseif mode == "3d" then
            t2:Hide()
            local m = edge._3d
            if m then
                -- Loaded once: the paint memos keep a preview refresh from
                -- reloading it (a hidden model paints on its show edge).
                edge._pvUnit = "player"
                if m:IsShown() then
                    mod.RF_PtPaint(frame, "player", "Apply")
                else
                    m:Show()
                end
            end
        else
            t2:SetTexCoord(0.15, 0.85, 0.15, 0.85)
            SetPortraitTexture(t2, "player")
            SeatArt2D(edge)
            t2:Show()
        end
    end
    local grey = offline and true or false
    edge._desat = grey
    edge._2d:SetDesaturated(grey)
    edge._class:SetDesaturated(grey)
    TintBorder(edge, nil, classToken or playerCT)
end
