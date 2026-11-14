if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Castbar.lua
--
--  Cast icon geometry, the kick tick and cast colors, CreateCastBar, show on
--  cast bar and the Blizzard cast bar state. Publishes through I; loads before
--  Builders, which re-imports from it. db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local issecretvalue = issecretvalue
local Pix = CludesUI.PP

local Inner = mod._internals
local frameList, GetSettingsForUnit = Inner.frames, Inner.GetSettingsForUnit
local GetCastbarColor, SetFSFont = Inner.GetCastbarColor, Inner.SetFSFont
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- Cast-bar icon "part of the bar" resolver. True = icon counts inside the cast bar's
-- width (icon inside footprint, fill inset to its right, like Resource Bars). False =
-- icon outside the width. Requires the icon shown; a hidden icon is never "in width".
local function CastIconInWidth(unitToken, s)
    s = s or GetSettingsForUnit(unitToken)
    if not s then
        return true
    end
    -- The stock styles count a shown icon as part of the bar whatever the
    -- toggle says: their frame art wraps bar and icon together, and a width
    -- match lines up with that footprint.
    if mod.UF_Blizz() then
        if unitToken == "player" then
            return s.showPlayerCastIcon ~= false
        end
        return s.showCastIcon ~= false
    end
    -- An icon moved onto the portrait (Show Icon on Portrait) is never in width.
    if mod.UF_CastIconOnPortrait(unitToken, s) then
        return false
    end
    if unitToken == "player" then
        return s.showPlayerCastIcon ~= false and s.playerCastbarIconInWidth ~= false
    end
    return s.showCastIcon ~= false and s.castbarIconInWidth ~= false
end
-- Shared with the options preview, so it lays the icon out the same way.
mod.UF_CastIconInWidth = CastIconInWidth

-- Whether the cast spell icon is shown at all. Independent of "part of the
-- bar" (CastIconInWidth folds this in already for its own purposes, but
-- ns.UF_ApplyCastIconBorder needs the shown state on its own: a hidden icon
-- shares no edge with the bar).
local function CastIconShown(unitToken, s)
    s = s or GetSettingsForUnit(unitToken)
    if not s then
        return true
    end
    if unitToken == "player" then
        return s.showPlayerCastIcon ~= false
    end
    return s.showCastIcon ~= false
end

-- Show Icon on Portrait (player / target / focus, opt-in): true while the
-- cast icon sits over the unit's portrait instead of beside the bar. Needs
-- the icon shown and a visible portrait (Portrait Mode and Art Style not
-- None); the stock styles own the icon. Settings only, so the options preview
-- and the cast bar's size-match pad read the same answer. On ns (local cap).
function mod.UF_CastIconOnPortrait(unitToken, s)
    if not s then
        return false
    end
    local key = (unitToken == "player") and "playerCastbarIconOnPortrait" or "castbarIconOnPortrait"
    if s[key] ~= true or mod.UF_Blizz() or not CastIconShown(unitToken, s) then
        return false
    end
    local p = saved.profile
    if (s.portraitStyle or p.portraitStyle or "attached") == "none" or s.showPortrait == false then
        return false
    end
    return (s.portraitMode or p.portraitMode or "2d") ~= "none"
end

-- Whether the cast spell icon sits on the RIGHT of the bar instead of the
-- default left. Independent of "part of the bar"; defaults off (left).
local function CastIconOnRight(unitToken, s)
    s = s or GetSettingsForUnit(unitToken)
    if not s then
        return false
    end
    if unitToken == "player" then
        return s.playerCastbarIconRight == true
    end
    return s.castbarIconRight == true
end

-- Additive X/Y nudge for the cast spell icon. Applies to the icon frame's anchors
-- only -- the bar fill and footprint never move.
local function CastIconOffsets(unitToken, s)
    s = s or GetSettingsForUnit(unitToken)
    if not s then
        return 0, 0
    end
    if unitToken == "player" then
        return s.playerCastIconOffsetX or 0, s.playerCastIconOffsetY or 0
    end
    return s.castIconOffsetX or 0, s.castIconOffsetY or 0
end

-- Border Wraps Icon (s.castBorderWrapIcon, opt-in): the Custom Border Style
-- takes in an integrated icon, only while it sits flush (no offset); else
-- the border wraps the bar alone. Settings only, so the border, the shared
-- edge pass and the size-match pad read one answer. On ns (local cap).
function mod.UF_CastBorderWrapsIcon(unitToken, s)
    if not (s and s.castBorderCustom == true and s.castBorderWrapIcon == true) then
        return false
    end
    if not CastIconInWidth(unitToken, s) then
        return false
    end
    local offX, offY = CastIconOffsets(unitToken, s)
    return offX == 0 and offY == 0
end

-- Vertical Separator: the divider draws as Solid's flat line (also with
-- Custom Border Style off) or in a style's own divider art; a textured style
-- without that art, or a Border Size of 0, draws none. Shared with the
-- options row's disabled state. On ns (local cap).
function mod.UF_CastIconSeamOK(s)
    if not (s and s.castBorderCustom == true) then
        return true
    end
    if (s.castBorderSize or 1) <= 0 then
        return false
    end
    local texture = s.castBorderStyle or "solid"
    return texture == "solid" or texture == "" or CludesUI.GetBorderCompanion(texture, "sepV") ~= nil
end

-- Classic WoW UI: the settings key holding a cast bar's frame size (its
-- Border Size percentage; player keys carry the player prefix). On ns for
-- the local cap.
function mod.UF_CastClassicKey(unitToken)
    return unitToken == "player" and "playerCastbarStockBorderScale" or "castbarStockBorderScale"
end

-- Anchor the cast spell icon and inset the fill based on whether the icon is part of
-- the bar width. inWidth=true -> icon at the bar's edge, fill inset by icon width
-- (castbarBg becomes the full footprint, so unlock mode/width matching count the icon
-- for free). inWidth=false -> icon hangs outside the bar width.
--
-- Icon HEIGHT anchors to the bar bg's top AND bottom so it always equals the bar
-- height: a live bg:GetHeight() read is unreliable during creation/login (bg not yet
-- at final height/scale). iconH is the configured cast bar height (castbarHeight/
-- playerCastbarHeight), used only for the square WIDTH and matching fill inset so
-- those stay deterministic; falls back to bg:GetHeight().
--
-- portraitBd: the portrait backdrop the icon sits on (Show Icon on Portrait,
-- laid out by ns.UF_CastIconPortrait, which the callers run as this argument),
-- else nil. With it the bar takes the whole holder and no seam is shared.
local function LayoutCastbarIcon(
    castBar,
    inWidth,
    iconH,
    onRight,
    offX,
    offY,
    iconShown,
    framePct,
    portraitBd
)
    if not castBar then
        return
    end
    local bg = castBar:GetParent()
    if not bg then
        return
    end
    -- Classic WoW UI frame size, read by the style's cast pass.
    castBar._classicPct = framePct
    -- Callers pass the configured height: a holder on the Blizzard Style
    -- aura block reads back a secret rect, size included.
    local sideName = iconH or bg:GetHeight()
    if issecretvalue(sideName) then
        return
    end
    local iconFrame = castBar._iconFrame
    offX, offY = offX or 0, offY or 0
    -- The style's own icon pass (ns.UF_BlizzCastIcon) re-lays the icon from
    -- these after the stock chrome is on.
    castBar._icoInWidth, castBar._icoOnRight, castBar._icoSide = inWidth, onRight, sideName
    castBar._icoOffX, castBar._icoOffY, castBar._icoShown = offX, offY, iconShown
    if iconFrame and not portraitBd then
        iconFrame:ClearAllPoints()
        if inWidth then
            -- Icon inside the footprint, flush with the chosen edge.
            if onRight then
                Pix.Point(iconFrame, "TOPRIGHT", bg, "TOPRIGHT", offX, offY)
                Pix.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", offX, offY)
            else
                Pix.Point(iconFrame, "TOPLEFT", bg, "TOPLEFT", offX, offY)
                Pix.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMLEFT", offX, offY)
            end
        else
            -- Icon hangs outside the bar, off the chosen edge.
            if onRight then
                Pix.Point(iconFrame, "TOPLEFT", bg, "TOPRIGHT", offX, offY)
                Pix.Point(iconFrame, "BOTTOMLEFT", bg, "BOTTOMRIGHT", offX, offY)
            else
                Pix.Point(iconFrame, "TOPRIGHT", bg, "TOPLEFT", offX, offY)
                Pix.Point(iconFrame, "BOTTOMRIGHT", bg, "BOTTOMLEFT", offX, offY)
            end
        end
        iconFrame:SetWidth(sideName)
    end
    castBar:ClearAllPoints()
    if portraitBd then
        -- The icon sits on the portrait: the bar takes the whole footprint.
        Pix.Point(castBar, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        Pix.Point(castBar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    elseif inWidth and onRight then
        -- Bar occupies the left of the footprint; icon takes the right edge.
        Pix.Point(castBar, "TOPLEFT", bg, "TOPLEFT", 0, 0)
        Pix.Point(castBar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", -sideName, 0)
    else
        Pix.Point(castBar, "TOPLEFT", bg, "TOPLEFT", inWidth and sideName or 0, 0)
        Pix.Point(castBar, "BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
    end
end

-- Cast bar Custom Border Style (s.castBorderCustom, opt-in per unit; boss1-5
-- share one table). Off: the 1px black border CreateCastBar drew on the bar
-- stays as it is; only the icon decoration pass runs and nothing is built
-- unless one of its options is enabled.
-- On: that border hides and the chosen style draws on castbar._cbBorder, our
-- own child frame of the bar built on first enable, so it shows and hides with
-- the bar as the old border did. It wraps the bar alone, or icon and bar
-- together under Border Wraps Icon (ns.UF_CastBorderWrapsIcon). It sits under
-- the cast text overlay; Show Behind drops it under the bar's holder.
-- Settings passes only (creation and ReloadFrames, after LayoutCastbarIcon).
-- An exact size re-applies on a UI scale change through ApplyBorderStyle's
-- own edgePx registration. Stands down under a stock style: stock = nil reads
-- the session's latched style; the options preview (which shares this)
-- passes its own and preview = true. On ns: the local cap.
function mod.UF_ApplyCastBorder(castBar, s, stock, unitToken, glyph, preview)
    if not castBar then
        return
    end
    if stock == nil then
        stock = mod.UF_Blizz()
    end
    local hostRegion = castBar._cbBorder
    if stock or not (s and s.castBorderCustom == true) then
        if castBar._cbHost then
            castBar._cbHost = nil
            CludesUI.HideBorderStyle(hostRegion)
            hostRegion:Hide()
            -- The bar's own border back (the stock chrome keeps it hidden).
            if not stock then
                Pix.ShowBorder(castBar)
            end
        end
        mod.UF_ApplyCastIconBorder(castBar, s, stock, unitToken, glyph, preview)
        return
    end
    if not hostRegion then
        -- Through the options frame pool: a real frame for a live bar, handed
        -- back by the pool on the options preview's next build.
        hostRegion = POOL.CreateFrame("Frame", nil, castBar)
        castBar._cbBorder = hostRegion
    end
    hostRegion:ClearAllPoints()
    if mod.UF_CastBorderWrapsIcon(unitToken, s) then
        -- The fill gives up the icon's width (the configured cast bar height,
        -- as LayoutCastbarIcon insets it): reach past the fill by that much on
        -- the icon's side. Anchored to the fill so the options preview uses
        -- the same rule.
        local sideName = (unitToken == "player") and (s.playerCastbarHeight or 14) or (s.castbarHeight or 14)
        local onRight = CastIconOnRight(unitToken, s)
        Pix.Point(hostRegion, "TOPLEFT", castBar, "TOPLEFT", onRight and 0 or -sideName, 0)
        Pix.Point(hostRegion, "BOTTOMRIGHT", castBar, "BOTTOMRIGHT", onRight and sideName or 0, 0)
    else
        hostRegion:SetAllPoints(castBar)
    end
    castBar._cbHost = hostRegion
    Pix.HideBorder(castBar)
    -- Levelled before the apply: a textured style's backdrop takes the host's.
    if s.castBorderBehind then
        hostRegion:SetFrameLevel(math.max(0, (castBar:GetParent() or castBar):GetFrameLevel() - 1))
    else
        -- Over the fill, shield and kick marker (bar +2), under the text overlay.
        local lvl = castBar:GetFrameLevel() + 3
        local ovr = castBar.Text and castBar.Text:GetParent()
        if ovr and ovr ~= castBar then
            lvl = math.min(lvl, ovr:GetFrameLevel() - 1)
        end
        hostRegion:SetFrameLevel(lvl)
    end
    local texture = s.castBorderStyle or "solid"
    local dim = s.castBorderSize or 1
    local c = s.castBorderColor
    local px = CludesUI.BorderPx(s.castBorderSizePx, dim, texture)
    CludesUI.ApplyBorderStyle(
        hostRegion,
        dim,
        c and c.r or 0,
        c and c.g or 0,
        c and c.b or 0,
        s.castBorderAlpha or 1,
        texture,
        s.castBorderOffsetX,
        s.castBorderOffsetY,
        s.castBorderShiftX,
        s.castBorderShiftY,
        "unitframes",
        dim,
        nil,
        px
    )
    castBar._cbSolid = (texture == "solid" or texture == "") and dim > 0
    castBar._cbSize = px or dim
    mod.UF_ApplyCastIconBorder(castBar, s, stock, unitToken, glyph, preview)
end

-- Cast icon decoration, shared by live frames and the options preview. New
-- resources are built only on opt-in, during the existing settings pass.
-- preview = the options preview's bar: its divider is never registered for
-- the UI-scale re-layout (the preview re-lays it on every update).
function mod.UF_ApplyCastIconBorder(castBar, s, stock, unitToken, glyph, preview)
    glyph = glyph or castBar._iconFrame
    if not glyph then
        return
    end
    local isShown = CastIconShown(unitToken, s)
    local portrait = mod.UF_CastIconOnPortrait(unitToken, s)
    local inWidth = CastIconInWidth(unitToken, s)
    local onRight = CastIconOnRight(unitToken, s)
    local offX, offY = CastIconOffsets(unitToken, s)
    local custom = s and s.castBorderCustom == true
    local styled = not stock and isShown and not portrait and s and s.castIconBorder == true
    local hostRegion = glyph._castBorder
    local texture = custom and (s.castBorderStyle or "solid") or "solid"
    local dim = custom and (s.castBorderSize or 1) or 1
    local c = custom and s.castBorderColor
    local alpha = custom and (s.castBorderAlpha or 1) or 1
    local px = custom and CludesUI.BorderPx(s.castBorderSizePx, dim, texture) or nil
    if styled then
        if not hostRegion then
            -- Options frame pool: a real frame for a live bar (as above).
            hostRegion = POOL.CreateFrame("Frame", nil, glyph)
            hostRegion:SetAllPoints(glyph)
            glyph._castBorder = hostRegion
        end
        hostRegion:SetFrameLevel(
            custom and s.castBorderBehind and math.max(0, glyph:GetFrameLevel() - 1)
                or glyph:GetFrameLevel() + 1
        )
        Pix.HideBorder(glyph)
        CludesUI.ApplyBorderStyle(
            hostRegion,
            dim,
            c and c.r or 0,
            c and c.g or 0,
            c and c.b or 0,
            alpha,
            texture,
            custom and s.castBorderOffsetX or nil,
            custom and s.castBorderOffsetY or nil,
            custom and s.castBorderShiftX or nil,
            custom and s.castBorderShiftY or nil,
            "unitframes",
            dim,
            nil,
            px
        )
    elseif hostRegion then
        CludesUI.HideBorderStyle(hostRegion)
        hostRegion:Hide()
        if not stock and not portrait then
            Pix.ShowBorder(glyph)
        end
    end

    -- Icon and bar each draw a full border (the bar's own 1px one, or a custom
    -- Solid one at its size): flush, both would draw the shared edge, so each
    -- drops its facing side. Only while the icon is shown beside the bar with
    -- no offset and no Icon Border of its own; a textured or hidden custom
    -- border shares none. Under Border Wraps Icon the custom border is the
    -- outside edge of both: it keeps every side and the icon drops its facing
    -- one.
    if not stock then
        local iconEdges = Pix.GetBorders(glyph)
        local barFrame = castBar._cbHost or castBar
        local barEdges = Pix.GetBorders(barFrame)
        local barDrawn = barEdges and (barFrame == castBar or castBar._cbSolid)
        local share = isShown and not portrait and offX == 0 and offY == 0 and not styled
        local outer = castBar._cbHost and mod.UF_CastBorderWrapsIcon(unitToken, s)
        if iconEdges then
            local hide = share and (barDrawn or outer)
            iconEdges._hideLeft = hide and onRight or nil
            iconEdges._hideRight = hide and not onRight or nil
            Pix.SetBorderSize(glyph, 1)
        end
        if barEdges then
            local hide = share and barDrawn and not outer
            barEdges._hideLeft = hide and not onRight or nil
            barEdges._hideRight = hide and onRight or nil
            if barDrawn then
                Pix.SetBorderSize(barFrame, barFrame == castBar and 1 or castBar._cbSize)
            end
        end
    end

    local seam = castBar._iconSeam
    if
        not (
            s
            and s.castIconSeparator == true
            and not stock
            and isShown
            and inWidth
            and not portrait
            and mod.UF_CastIconSeamOK(s)
        )
    then
        if seam then
            seam:Hide()
            CludesUI.RegisterPxReapply(seam, nil)
        end
        return
    end
    if not seam then
        -- Options frame pool: a real frame for a live bar (as above).
        seam = POOL.CreateFrame("Frame", nil, castBar)
        seam:SetAllPoints(castBar)
        seam._tex = seam:CreateTexture(nil, "OVERLAY")
        castBar._iconSeam = seam
    end
    -- Above the cast border, including Solid's child at border level +1.
    local borderFrame = castBar._cbHost or castBar
    seam:SetFrameLevel(math.max(castBar:GetFrameLevel(), borderFrame:GetFrameLevel()) + 2)
    seam._key, seam._size, seam._px, seam._right = texture, dim, px, onRight
    seam._path = CludesUI.GetBorderCompanion(texture, "sepV")
    seam._tex:SetVertexColor(c and c.r or 0, c and c.g or 0, c and c.b or 0, alpha)
    mod.UF_LayoutCastIconSeam(seam)
    seam:Show()
    CludesUI.RegisterPxReapply(seam, (not preview) and mod.UF_LayoutCastIconSeam or nil)
end

-- Lays the divider from the values the pass above stamped (also the UI-scale
-- re-layout). A style's divider art goes through the shared placement, its
-- lead hanging past the bar's edge over the icon; Solid draws a flat line on
-- the bar's edge at the border's exact size.
function mod.UF_LayoutCastIconSeam(seam)
    local t = seam._tex
    local es = seam:GetEffectiveScale()
    if seam._path then
        CludesUI.PlaceBorderDividerV(t, seam, seam._right, false, seam._key, seam._size, seam._px, es)
        return
    end
    local onePixel = es > 0 and Pix.perfect / es or Pix.mult
    t:SetColorTexture(1, 1, 1, 1)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    if seam._right then
        t:SetPoint("TOPRIGHT", seam, "TOPRIGHT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", seam, "BOTTOMRIGHT", 0, 0)
    else
        t:SetPoint("TOPLEFT", seam, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", seam, "BOTTOMLEFT", 0, 0)
    end
    t:SetWidth(math.max(1, math.floor((seam._px or seam._size) + 0.5)) * onePixel)
    t:Show()
end

-- Size matching: the width and height a Custom Border Style cast border
-- draws OUTSIDE the cast bar holder (the unlock element's frame), from the
-- same arguments ns.UF_ApplyCastBorder passes; nil while the opt-in is off,
-- for Solid and under the stock styles, so the pad stays exactly as before.
-- The border wraps the bar, which an in-width icon insets inside the holder
-- by the icon's width (the configured cast bar height): that side's reach
-- shrinks by it. Under Border Wraps Icon (ns.UF_CastBorderWrapsIcon) it
-- wraps the whole holder instead. Each side clamps at 0 before the sum.
-- Settings only.
function mod.UF_CastBorderPad(unitToken, s)
    if not (s and s.castBorderCustom == true) or mod.UF_Blizz() then
        return nil
    end
    local texture = s.castBorderStyle or "solid"
    local dim = s.castBorderSize or 1
    local l, r, t, b = CludesUI.BorderReach(
        dim,
        texture,
        s.castBorderOffsetX,
        s.castBorderOffsetY,
        s.castBorderShiftX,
        s.castBorderShiftY,
        "unitframes",
        dim,
        CludesUI.BorderPx(s.castBorderSizePx, dim, texture),
        nil,
        s.castBorderAlpha or 1
    )
    if not l then
        return nil
    end
    if CastIconInWidth(unitToken, s) and not mod.UF_CastBorderWrapsIcon(unitToken, s) then
        local iw = (unitToken == "player") and (s.playerCastbarHeight or 14) or (s.castbarHeight or 14)
        if CastIconOnRight(unitToken, s) then
            r = r - iw
        else
            l = l - iw
        end
    end
    local wid = (l > 0 and l or 0) + (r > 0 and r or 0)
    local hgt = (t > 0 and t or 0) + (b > 0 and b or 0)
    if wid <= 0 and hgt <= 0 then
        return nil
    end
    return wid, hgt
end

-- While the cast icon shows on the portrait (backdrop +2), the backdrop's shape
-- border, inner shadow and Outer Ring move onto an overlay at backdrop +3, so
-- the icon sits under them; when it hides they go back to the backdrop, the
-- shape border to its rest over a 3D model (bd._ringHome, from
-- ns.UF_PortraitShapeModel). The overlay is a child of the backdrop, so the
-- backdrop's shape mask still clips them. Built through the options page pool
-- (the preview shares this), which also hands a pooled texture back to its
-- own frame on reset.
local function MoveDecoration(texture, hostFrame)
    if texture and texture:GetParent() ~= hostFrame then
        texture:SetParent(hostFrame)
    end
end
local function CastIconPortraitOverlay(edge, enabled)
    local overlayFrame = edge._castIconOverlay
    if enabled then
        if not overlayFrame then
            overlayFrame = POOL.CreateFrame("Frame", nil, edge)
            overlayFrame:SetAllPoints(edge)
            edge._castIconOverlay = overlayFrame
        end
        overlayFrame:SetFrameStrata(edge:GetFrameStrata())
        overlayFrame:SetFrameLevel(edge:GetFrameLevel() + 3)
    elseif not overlayFrame then
        return
    end
    local hostFrame = enabled and overlayFrame or edge
    MoveDecoration(edge._shapeBorderTex, enabled and overlayFrame or edge._ringHome or edge)
    MoveDecoration(edge._innerShadow, hostFrame)
    MoveDecoration(edge._outerRing, hostFrame)
end

-- Show Icon on Portrait: lays the cast icon over the portrait backdrop bd, or
-- (bd nil) hands it back to the bar layout. ico = the cast icon frame, tex =
-- its texture, s = the unit's settings. Our own frames only (the options
-- preview shares this with its own icon and portrait). The icon's 1px border
-- and black plate hide and its texture fills the frame; on a shaped detached
-- portrait it is clipped by the icon frame's OWN mask (built on first use)
-- carrying the portrait's shape art, since a mask owned by the portrait's
-- frame tree is not relied on across trees. That mask sits inset so its
-- opening stops at the shape border's inner edge, which keeps the ring in
-- view round the icon. Levelled over the backdrop and its 3D model.
-- ico._pbd = the backdrop it sits on.
function mod.UF_CastIconPortraitLayout(ico, texture, edge, s)
    if ico._pbd and ico._pbd ~= edge then
        CastIconPortraitOverlay(ico._pbd, false)
    end
    if not edge then
        if not ico._pbd then
            return
        end
        ico._pbd = nil
        Pix.ShowBorder(ico)
        if ico._bg then
            ico._bg:Show()
        end
        if texture then
            if ico._pMaskOn then
                texture:RemoveMaskTexture(ico._pMask)
                ico._pMaskOn = nil
            end
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", ico, "TOPLEFT", 1, -1)
            texture:SetPoint("BOTTOMRIGHT", ico, "BOTTOMRIGHT", -1, 1)
        end
        local holderFrame = ico:GetParent()
        if holderFrame then
            ico:SetFrameStrata(holderFrame:GetFrameStrata())
            ico:SetFrameLevel(holderFrame:GetFrameLevel() + 1)
        end
        return
    end
    ico._pbd = edge
    Pix.HideBorder(ico)
    if ico._bg then
        ico._bg:Hide()
    end
    ico:ClearAllPoints()
    ico:SetAllPoints(edge)
    -- The portrait's strata, not the raised cast bar's: the frame border
    -- (frame +10) still closes an attached portrait's edges over the icon.
    ico:SetFrameStrata(edge:GetFrameStrata())
    ico:SetFrameLevel(edge:GetFrameLevel() + 2)
    if not ico._pOverlayHooked then
        ico:HookScript("OnShow", function(self)
            if self._pbd then
                CastIconPortraitOverlay(self._pbd, true)
            end
        end)
        ico:HookScript("OnHide", function(self)
            if self._pbd then
                CastIconPortraitOverlay(self._pbd, false)
            end
        end)
        ico._pOverlayHooked = true
    end
    CastIconPortraitOverlay(edge, ico:IsShown())
    if not texture then
        return
    end
    texture:ClearAllPoints()
    texture:SetAllPoints(ico)
    -- A detached portrait's shape; attached and shape-less ones are square.
    local shape = ((s.portraitStyle or saved.profile.portraitStyle or "attached") == "detached")
            and (s.detachedPortraitShape or "portrait")
        or "none"
    local maskPath = shape ~= "none" and mod.PORTRAIT_MASKS[shape]
    if maskPath then
        local m = ico._pMask
        if not m then
            m = ico:CreateMaskTexture()
            ico._pMask = m
        end
        -- The backdrop mask's own inset, widened until the icon's opening meets
        -- the shape border's inner edge (all in backdrop px, W wide): the ring
        -- art's solid band ends at MASK_INSETS texels of its 128 (an unmasked
        -- ring, ns.UF_UNMASKED_RING: 9 texels into its inset rect), the ring
        -- rect grows by 7 - Size per side, and the mask's opening lies about
        -- 12 of its 128 texels in.
        local band = s.detachedPortraitBorderSize or 7
        local inset = (band >= 1) and 1 or 0
        if band >= 1 and mod.PORTRAIT_BORDERS[shape] then
            local Widgets = edge:GetWidth()
            if Widgets < 1 then
                Widgets = 46
            end
            local exp = 7 - band
            local unmasked = mod.UF_UNMASKED_RING[shape]
            local inner
            if unmasked then
                local ri = unmasked - exp
                inner = ri + 9 / 128 * (Widgets - 2 * ri)
            else
                inner = -exp + (mod.MASK_INSETS[shape] or 17) / 128 * (Widgets + 2 * exp)
            end
            local need = (inner - 12 / 128 * Widgets) * 128 / 104
            if need > inset then
                inset = need
            end
        end
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", edge, "TOPLEFT", inset, -inset)
        m:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", -inset, inset)
        if m._path ~= maskPath then
            m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m._path = maskPath
        end
        m:Show()
        if not ico._pMaskOn then
            texture:AddMaskTexture(m)
            ico._pMaskOn = true
        end
    elseif ico._pMaskOn then
        texture:RemoveMaskTexture(ico._pMask)
        ico._pMaskOn = nil
    end
end

-- Resource Bars' Embed in Player Portrait lays its cast icon out with the same geometry:
-- the player portrait's backdrop and settings, or nil plus why. "uf": the Unit Frames
-- player cast bar already shows its icon there (two icons would stack); else there is no
-- CludesUI player portrait to embed in (the stock styles own the icon, as for ours).
function mod.UF_GetPlayerCastPortrait()
    local p = saved and saved.profile
    if not p or mod.GetUnitFrameSource("player") ~= "cui" or mod.UF_Blizz() then
        return nil
    end
    local s = GetSettingsForUnit("player")
    if
        s.showPortrait == false
        or (s.portraitStyle or p.portraitStyle or "attached") == "none"
        or (s.portraitMode or p.portraitMode or "2d") == "none"
    then
        return nil
    end
    if s.showPlayerCastbar and mod.UF_CastIconOnPortrait("player", s) then
        return nil, nil, "uf"
    end
    local pt = frameList.player and frameList.player.Portrait
    return pt and pt.backdrop, s
end

-- A module that lays something over the player portrait asks to be called back after
-- each frame reload, which can move, reshape or remove the portrait: one callback per
-- key, nil drops it. The reload pays one table walk, empty unless a module asked.
local portraitWatchers = {}
function mod.UF_WatchPlayerPortrait(key, func)
    portraitWatchers[key] = func
end
function mod.UF_PlayerPortraitChanged()
    for _, func in pairs(portraitWatchers) do
        func()
    end
end

-- The live cast bar's side of Show Icon on Portrait, run as LayoutCastbarIcon's
-- portraitBd argument: returns the backdrop the icon now sits on, or nil. One
-- settings test while off; the layout runs only while on or on the pass that
-- turns it off.
function mod.UF_CastIconPortrait(castBar, widget, s, unitToken)
    local ico = castBar and castBar._iconFrame
    if not ico then
        return nil
    end
    local pt = widget and widget.Portrait
    local edge = pt and mod.UF_CastIconOnPortrait(unitToken, s) and pt.backdrop or nil
    if edge or ico._pbd then
        mod.UF_CastIconPortraitLayout(ico, castBar.Icon, edge, s)
    end
    return edge
end

-- Unlock position key for a unit's castbar, or nil.
local function CastbarUnlockKey(unitToken)
    if unitToken == "player" then
        return "playerCastbar"
    elseif unitToken == "target" then
        return "targetCastbar"
    elseif unitToken == "focus" then
        return "focusCastbar"
    elseif unitToken == "pet" then
        return "petCastbar"
    end
end

-- Cast bar positioning is owned by the centralized unlock/anchor system
-- (ApplySavedPositions).

local function GetActiveKickSpell()
    return CludesUI.GetActiveKickSpell()
end
local function ComputeCastBarTint(readyTint, baseTint)
    if CludesUI and CludesUI.ComputeCastBarTint then
        return CludesUI.ComputeCastBarTint(readyTint, baseTint)
    end
    return baseTint.r, baseTint.g, baseTint.b
end
local function IsKickCastbarUnit(unitToken)
    return unitToken == "target" or unitToken == "focus" or (unitToken and unitToken:match("^boss") ~= nil)
end
local function GetCastbarKickTickEnabled(prefs)
    if not prefs then
        return true
    end
    if prefs.castbarKickTickEnabled ~= nil then
        return prefs.castbarKickTickEnabled
    end
    return true
end
local function GetCastbarInterruptMidCastEnabled(prefs)
    if not prefs then
        return false
    end
    if prefs.castbarInterruptMidCastEnabled ~= nil then
        return prefs.castbarInterruptMidCastEnabled
    end
    return false
end
local function GetCastbarUninterruptible(castBar)
    local val = castBar and castBar.notInterruptible
    if type(val) == "nil" then
        return false
    end
    return val
end
local function HideUnitFrameKickTick(castBar)
    if not castBar or not castBar.kickPositioner then
        return
    end
    castBar.kickPositioner:Hide()
    castBar.kickMarker:Hide()
    castBar.kickReadyFill:Hide()
    if castBar._kickTicker then
        castBar._kickTicker:Cancel()
        castBar._kickTicker = nil
    end
end
-- Hoisted defaults for the zero-alloc paint below: as inline literals these would
-- allocate on EVERY call when the setting was absent (the common case).
local UF_KICK_READY_TINT = { r = 0.92, g = 0.35, b = 0.20 }
local UF_UNINTERRUPT_GREY = { r = 0.5, g = 0.5, b = 0.5 }
local function ApplyUnitFrameCastColor(castBar)
    if not castBar or not castBar.castTintLayer then
        return
    end
    local prefs = castBar._eufSettings
    local ownerUnit = castBar.__owner and castBar.__owner._cuiUnit
    -- Zero-alloc: values flow as scalars instead of building up to three throwaway
    -- color tables per call (two default literals + the blended kick tint).
    local r, g, b
    -- Base fill colour (what ReloadFrames gives the StatusBar), before the kick blend.
    local br, bg, bb
    if prefs and prefs.castbarClassColored and ownerUnit == "player" then
        local _, classToken = UnitClass(ownerUnit)
        if issecretvalue(classToken) then
            classToken = nil
        end
        if classToken and CludesUI.GetClassColor then
            local cc = CludesUI.GetClassColor(classToken)
            if cc then
                r, g, b = cc.r, cc.g, cc.b
            end
        end
        br, bg, bb = r, g, b
    end
    if not r then
        local baseTint = (prefs and prefs.castbarFillColor) or GetCastbarColor()
        br, bg, bb = baseTint.r, baseTint.g, baseTint.b
        if IsKickCastbarUnit(ownerUnit) then
            local readyTint = (prefs and prefs.castbarInterruptReadyColor) or UF_KICK_READY_TINT
            r, g, b = ComputeCastBarTint(readyTint, baseTint)
        else
            r, g, b = br, bg, bb
        end
    end
    local uc = (prefs and prefs.castbarUninterruptibleColor) or UF_UNINTERRUPT_GREY
    if not castBar._blizzCast then
        -- Uninterruptible colour folded into the textured tint layer and the base
        -- fill under it (the nameplates' approach): the texture stays visible and
        -- its transparent pixels cannot show the interruptible colour. The flat
        -- shield wash below would cover the texture. The fold is secret-safe.
        local ev = C_CurveUtil.EvaluateColorValueFromBoolean
        local uninterruptible = GetCastbarUninterruptible(castBar)
        -- Vertex alpha is the texture's alpha: keep Fill Opacity (and idle 0), not 1.
        castBar.castTintLayer:SetVertexColor(
            ev(uninterruptible, uc.r, r),
            ev(uninterruptible, uc.g, g),
            ev(uninterruptible, uc.b, b),
            castBar._castTintOn and (castBar._fillOp or 1) or 0
        )
        -- Same alpha as the ReloadFrames SetStatusBarColor sites.
        local baseA = ((prefs and prefs.castFillOpacity or 100) < 100) and 0
            or (saved and saved.profile.castbarOpacity or 1)
        castBar:SetStatusBarColor(
            ev(uninterruptible, uc.r, br),
            ev(uninterruptible, uc.g, bg),
            ev(uninterruptible, uc.b, bb),
            baseA
        )
        if castBar._shieldHost and not castBar._shieldOff then
            castBar._shieldHost:SetAlpha(0)
            castBar._shieldOff = true
        end
        return
    end
    castBar._shieldOff = nil
    castBar.castTintLayer:SetVertexColor(r, g, b)
    if castBar._shieldedTint then
        -- Uninterruptible overlay colour (defaults to grey). Its alpha is toggled
        -- from the secret "not interruptible" flag, so the colour is always set and
        -- only becomes visible on uninterruptible casts. Only Blizzard Style
        -- (tint layer hidden) still uses this wash.
        -- Explicit vertex alpha: Midnight's 3-arg SetVertexColor leaves the
        -- vertex alpha at an unexpected value (measured 0.5 with the gray
        -- default -- GetVertexColor returned a=r), and the composite with the
        -- region alpha rendered the shield faint-to-invisible. Visibility
        -- stays owned by SetAlphaFromBoolean below on the region slot.
        castBar._shieldedTint:SetVertexColor(uc.r, uc.g, uc.b, 1)
        local uninterruptible = GetCastbarUninterruptible(castBar)
        -- Visible alpha honors Fill Opacity (castbar._fillOp, nil at 100); both
        -- branches pass it as a plain number, never touching the secret. The
        -- boolean alpha drives the HOST FRAME -- texture SetAlphaFromBoolean
        -- renders 0 on Midnight despite healthy readbacks (see creation).
        local shieldTarget = castBar._shieldHost or castBar._shieldedTint
        if shieldTarget.SetAlphaFromBoolean then
            shieldTarget:SetAlphaFromBoolean(uninterruptible, castBar._fillOp or 1, 0)
        else
            shieldTarget:SetAlpha(uninterruptible and (castBar._fillOp or 1) or 0)
        end
    end
end
local function UpdateUnitFrameKickTick(castBar)
    if not castBar or not castBar.kickPositioner then
        return
    end
    local prefs = castBar._eufSettings
    local ownerUnit = castBar.__owner and castBar.__owner._cuiUnit
    if not IsKickCastbarUnit(ownerUnit) then
        HideUnitFrameKickTick(castBar)
        return
    end
    local tickOn = GetCastbarKickTickEnabled(prefs)
    local midOn = GetCastbarInterruptMidCastEnabled(prefs)
    if (not (tickOn or midOn)) or not GetActiveKickSpell() then
        HideUnitFrameKickTick(castBar)
        return
    end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castBar)
        return
    end
    local kickProtected = GetCastbarUninterruptible(castBar)
    castBar._kickProtected = kickProtected
    local isChannel = castBar.channeling and true or false
    local isEmpowered = false
    if not (UnitCastingDuration and ownerUnit) then
        HideUnitFrameKickTick(castBar)
        return
    end
    local castDuration
    if isChannel then
        if UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
            if castDuration then
                isEmpowered = true
            end
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss during an ongoing cast: skip, do NOT hide (a Hide/re-Show
        -- cycle on every SPELL_UPDATE_COOLDOWN would blink the tick during rotation).
        -- Cast end is handled by the cast-stop path.
        return
    end
    -- Cache cast identity so the light per-event refresh re-pins bar values from it
    -- without re-deriving channel/empower or re-minting fill geometry.
    castBar._kickIsChannel = isChannel
    castBar._kickIsEmpowered = isEmpowered
    local totalDur = castDuration:GetTotalDuration()
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    local barW = castBar:GetWidth()
    local barH = castBar:GetHeight()
    -- Blizzard Style: a bar hanging off its frame's aura block resolves its
    -- rect through the engine aura container, a secret value under aura
    -- restriction. The tick keeps the size it took out of combat (the bar
    -- never resizes in combat), so nothing here may compare a secret.
    if issecretvalue(barW) or issecretvalue(barH) then
        return
    end
    if not barW or barW <= 0 then
        -- Transient zero-width during resize: skip, do not hide.
        return
    end
    castBar.kickPositioner:SetSize(barW, barH)
    castBar.kickPositioner:SetMinMaxValues(0, totalDur)
    castBar.kickMarker:SetMinMaxValues(0, totalDur)
    castBar.kickMarker:SetSize(barW, barH)
    castBar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castBar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    castBar.kickTick:SetColorTexture(1, 1, 1, 1)
    if isChannel and not isEmpowered then
        castBar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        castBar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Reverse)
        -- LOAD-BEARING: SetFillStyle resets the inner fill to snap-ON and the global
        -- hook does not re-fire on a cached bar. Re-disable snap so the summed
        -- elapsed+remaining edge stays an exact float.
        local pt = castBar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then
            pt:SetSnapToPixelGrid(false)
            pt:SetTexelSnappingBias(0)
        end
        local mt = castBar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then
            mt:SetSnapToPixelGrid(false)
            mt:SetTexelSnappingBias(0)
        end
        castBar.kickMarker:ClearAllPoints()
        castBar.kickTick:ClearAllPoints()
        castBar.kickMarker:SetPoint("RIGHT", castBar.kickPositioner:GetStatusBarTexture(), "LEFT")
        castBar.kickTick:SetPoint("TOP", castBar.kickMarker, "TOP", 0, 0)
        castBar.kickTick:SetPoint("BOTTOM", castBar.kickMarker, "BOTTOM", 0, 0)
        castBar.kickTick:SetPoint("RIGHT", castBar.kickMarker:GetStatusBarTexture(), "LEFT")
        -- Reverse fill (draining channel): kick-ready point is the marker texture LEFT
        -- edge; the available window runs from the channel end (bar left) to it.
        -- Not-in-time pushes that edge past the left edge, crossing anchors to zero width.
        castBar.kickReadyFill:ClearAllPoints()
        castBar.kickReadyFill:SetPoint("TOP", castBar, "TOP", 0, 0)
        castBar.kickReadyFill:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 0)
        castBar.kickReadyFill:SetPoint("LEFT", castBar, "LEFT", 0, 0)
        castBar.kickReadyFill:SetPoint("RIGHT", castBar.kickMarker:GetStatusBarTexture(), "LEFT")
    else
        castBar.kickPositioner:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        castBar.kickMarker:SetFillStyle(Enum.StatusBarFillStyle.Standard)
        -- LOAD-BEARING: re-disable snap on the re-minted fill textures (see the
        -- reverse branch) so the tick stays stationary across every re-pin.
        local pt = castBar.kickPositioner:GetStatusBarTexture()
        if pt and pt.SetSnapToPixelGrid then
            pt:SetSnapToPixelGrid(false)
            pt:SetTexelSnappingBias(0)
        end
        local mt = castBar.kickMarker:GetStatusBarTexture()
        if mt and mt.SetSnapToPixelGrid then
            mt:SetSnapToPixelGrid(false)
            mt:SetTexelSnappingBias(0)
        end
        castBar.kickMarker:ClearAllPoints()
        castBar.kickTick:ClearAllPoints()
        castBar.kickMarker:SetPoint("LEFT", castBar.kickPositioner:GetStatusBarTexture(), "RIGHT")
        castBar.kickTick:SetPoint("TOP", castBar.kickMarker, "TOP", 0, 0)
        castBar.kickTick:SetPoint("BOTTOM", castBar.kickMarker, "BOTTOM", 0, 0)
        castBar.kickTick:SetPoint("LEFT", castBar.kickMarker:GetStatusBarTexture(), "RIGHT")
        -- Standard fill (cast/empowered channel): kick-ready point is the marker
        -- texture RIGHT edge; the window runs from it to the cast end (bar right).
        -- Not-in-time pushes that edge past the right edge, crossing anchors to zero width.
        castBar.kickReadyFill:ClearAllPoints()
        castBar.kickReadyFill:SetPoint("TOP", castBar, "TOP", 0, 0)
        castBar.kickReadyFill:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 0)
        castBar.kickReadyFill:SetPoint("LEFT", castBar.kickMarker:GetStatusBarTexture(), "RIGHT")
        castBar.kickReadyFill:SetPoint("RIGHT", castBar, "RIGHT", 0, 0)
    end
    castBar.kickPositioner:Show()
    castBar.kickMarker:Show()
    -- Mid-cast fill: CLEAN DB color tint + CLEAN per-toggle visibility; its alpha (the
    -- SECRET on-CD x interruptible gate) is applied with the tick alpha below. Geometry
    -- above runs whenever the tick OR fill is enabled; SetShown gates each element to
    -- its own toggle so one never forces the other.
    local mc = (prefs and prefs.castbarInterruptMidCastColor) or { r = 0.318, g = 0.820, b = 0.357 }
    castBar.kickReadyFill:SetVertexColor(mc.r, mc.g, mc.b, 1)
    castBar.kickTick:SetShown(tickOn)
    castBar.kickReadyFill:SetShown(midOn)
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(kickProtected, 0, 1)
        local kickReady = interruptCD:IsZero()
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
        castBar.kickTick:SetAlpha(alpha)
        castBar.kickReadyFill:SetAlpha(alpha)
    else
        castBar.kickTick:SetAlpha(0)
        castBar.kickReadyFill:SetAlpha(0)
    end
    if castBar._kickTicker then
        castBar._kickTicker:Cancel()
    end
    castBar._kickTicker = C_Timer.NewTicker(0.1, function()
        if not castBar:IsShown() or not ownerUnit then
            HideUnitFrameKickTick(castBar)
            return
        end
        if not GetActiveKickSpell() then
            HideUnitFrameKickTick(castBar)
            return
        end
        local icd = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
        if icd and icd.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castBar._kickProtected, 0, 1)
            local kickReady = icd:IsZero()
            local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(kickReady, 0, interruptible)
            castBar.kickTick:SetAlpha(alpha)
            castBar.kickReadyFill:SetAlpha(alpha)
        end
    end)
end

-- Light per-cooldown-event refresh: bar values + tick alpha only. Geometry (SetSize,
-- anchors, SetFillStyle, color) is cast-identity work done once by
-- UpdateUnitFrameKickTick. Re-pin positioner(elapsed) and marker(remaining) together to
-- keep the tick stationary; NEVER re-pin one without the other.
local function RefreshUnitFrameKickTick(castBar)
    if not castBar or not castBar.kickPositioner then
        return
    end
    if not GetActiveKickSpell() or not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        HideUnitFrameKickTick(castBar)
        return
    end
    local interruptCD = C_Spell.GetSpellCooldownDuration(GetActiveKickSpell())
    if not interruptCD then
        -- Transient read miss during an ongoing cast: skip, do not hide.
        return
    end
    local ownerUnit = castBar.__owner and castBar.__owner._cuiUnit
    if not (UnitCastingDuration and ownerUnit) then
        return
    end
    local castDuration
    if castBar._kickIsChannel then
        if castBar._kickIsEmpowered and UnitEmpoweredChannelDuration then
            castDuration = UnitEmpoweredChannelDuration(ownerUnit, true)
        end
        if not castDuration and UnitChannelDuration then
            castDuration = UnitChannelDuration(ownerUnit)
        end
    else
        castDuration = UnitCastingDuration(ownerUnit)
    end
    if not castDuration then
        -- Transient read miss (see above): skip, do not hide.
        return
    end
    castBar.kickPositioner:SetValue(castDuration:GetElapsedDuration())
    castBar.kickMarker:SetValue(interruptCD:GetRemainingDuration())
    if interruptCD.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        local interruptible = C_CurveUtil.EvaluateColorValueFromBoolean(castBar._kickProtected, 0, 1)
        local alpha = C_CurveUtil.EvaluateColorValueFromBoolean(interruptCD:IsZero(), 0, interruptible)
        castBar.kickTick:SetAlpha(alpha)
        castBar.kickReadyFill:SetAlpha(alpha)
    end
end

mod._castingCastbars = {}
local activeCastbarCount = 0
local _ufCastColorTicker
local ufKickWatcher = CreateFrame("Frame")
ufKickWatcher:SetScript("OnEvent", function(_, evt)
    if evt == "SPELL_UPDATE_COOLDOWN" or evt == "SPELL_UPDATE_USABLE" then
        for cb in pairs(mod._castingCastbars) do
            if cb:IsShown() and cb.__owner and cb.__owner._cuiUnit then
                ApplyUnitFrameCastColor(cb)
                -- Light refresh once the kick bars are set up; re-run the full geometry/
                -- fill setup only when not shown (kick learned mid-cast, CD info late,
                -- toggle flipped on). Stops SetFillStyle from re-minting the inner fill
                -- textures every cooldown event, which re-snapped them to the pixel grid.
                if cb.kickPositioner and not cb.kickPositioner:IsShown() then
                    UpdateUnitFrameKickTick(cb)
                else
                    RefreshUnitFrameKickTick(cb)
                end
            end
        end
    end
end)
local function NotifyCastbarStarted(castBar)
    if not castBar or not castBar.__owner then
        return
    end
    if not IsKickCastbarUnit(castBar.__owner._cuiUnit) then
        return
    end
    if mod._castingCastbars[castBar] then
        return
    end
    mod._castingCastbars[castBar] = true
    activeCastbarCount = activeCastbarCount + 1
    if activeCastbarCount == 1 then
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _ufCastColorTicker then
            _ufCastColorTicker = C_Timer.NewTicker(0.2, function()
                for cb in pairs(mod._castingCastbars) do
                    if cb:IsShown() then
                        ApplyUnitFrameCastColor(cb)
                    end
                end
            end)
        end
    end
end
local function NotifyCastbarEnded(castBar)
    if not castBar or not mod._castingCastbars[castBar] then
        return
    end
    mod._castingCastbars[castBar] = nil
    activeCastbarCount = activeCastbarCount - 1
    if activeCastbarCount <= 0 then
        activeCastbarCount = 0
        wipe(mod._castingCastbars)
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        ufKickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        if _ufCastColorTicker then
            _ufCastColorTicker:Cancel()
            _ufCastColorTicker = nil
        end
    end
end

local function CreateCastBar(widget, unitToken, prefs)
    local prefs = GetSettingsForUnit(unitToken)

    -- Standalone element parented to the oUF frame for compatibility, but sized
    -- and positioned independently. Blizzard Style: created with the layout
    -- aspect so it can hang off the frame's aura block (see ns.UF_LayoutAspectOK);
    -- its pieces below are all children and inherit it.
    local aspectTemplate = mod.UF_CastbarAspectTemplate(unitToken)
    local castbarBg = CreateFrame("Frame", nil, widget, aspectTemplate)
    if aspectTemplate then
        castbarBg._blizzAspect = true
    end

    -- Width/height always come from settings; nothing is auto-derived.
    local cbWidth, cbHeight
    if unitToken == "player" then
        cbWidth = saved.profile.player.playerCastbarWidth or 181
        cbHeight = saved.profile.player.playerCastbarHeight or 14
    else
        -- castbarWidth 0 = auto (boss frames match frame width; the boss update
        -- pass re-sizes to the live frame width right after creation).
        local cbw = prefs.castbarWidth or 0
        cbWidth = cbw > 0 and cbw or 181
        cbHeight = prefs.castbarHeight or 14
    end
    Pix.Size(castbarBg, cbWidth, cbHeight)

    -- Position is owned by the centralized unlock system; this temporary anchor
    -- just gives the frame valid bounds until ApplySavedPositions runs at login
    -- (unlock default: BOTTOM of the parent unit frame).
    castbarBg:SetPoint("TOP", widget, "BOTTOM", 0, 0)

    local bgTex = castbarBg:CreateTexture(nil, "BACKGROUND")
    Pix.Point(bgTex, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    Pix.Point(bgTex, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    -- Background color/alpha default to black 0.5 unless castBgColor/castBgAlpha
    -- are set.
    local _cbgC = prefs.castBgColor
    bgTex:SetColorTexture(
        _cbgC and _cbgC.r or 0,
        _cbgC and _cbgC.g or 0,
        _cbgC and _cbgC.b or 0,
        prefs.castBgAlpha or 0.5
    )
    castbarBg._bgTex = bgTex

    local castBar = CreateFrame("StatusBar", nil, castbarBg)
    Pix.Point(castBar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
    Pix.Point(castBar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
    castBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    castBar:GetStatusBarTexture():SetHorizTile(false)
    castBar:SetReverseFill(prefs.castReverseFill and true or false)

    -- Borders draw on the castbar itself (same frame level as the fill texture) so
    -- the OVERLAY border sits above the ARTWORK fill. On castbarBg they would land
    -- BEHIND the fill, since castbar is its child and draws above it.
    Pix.CreateBorder(castBar, 0, 0, 0, 1, 1, "OVERLAY", 0)

    -- Three-zone cast bar text layout matching nameplates: [spell name LEFT 42%]
    -- [target RIGHT-of-center 42%] [timer RIGHT]. All zones ellipsize (WordWrap off,
    -- MaxLines 1); text overlay sits above the unified border (frame +10).
    local textOverlay = CreateFrame("Frame", nil, castBar)
    textOverlay:SetAllPoints(castBar)
    textOverlay:SetFrameLevel(widget:GetFrameLevel() + 11)

    local textValue = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(textValue, prefs.castSpellNameSize or 11)
    textValue:SetJustifyH("LEFT")
    textValue:SetWordWrap(false)
    textValue:SetMaxLines(1)
    textValue:SetTextColor(1, 1, 1)
    castBar.Text = textValue

    local time = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(time, prefs.castDurationSize or 10)
    time:SetJustifyH("RIGHT")
    time:SetWordWrap(false)
    time:SetMaxLines(1)
    time:SetTextColor(1, 1, 1)
    castBar.Time = time

    local targetUnit = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(targetUnit, prefs.castSpellTargetSize or 11)
    targetUnit:SetJustifyH("RIGHT")
    targetUnit:SetWordWrap(false)
    targetUnit:SetMaxLines(1)
    targetUnit:SetTextColor(1, 1, 1)
    targetUnit:Hide()
    castBar.Target = targetUnit

    -- Side-aware three-zone layout (mirrors the nameplate cast text system). Each
    -- element has a side; duration reserves its slot and pushes whichever non-center
    -- element shares that side (center is never pushed). Spell name hides on side
    -- "none"; target/duration visibility rides _showTarget/_showDuration (their
    -- dropdown "None" clears those flags).
    local function LayoutCastTextZones(cb)
        local barW = cb:GetWidth()
        -- Secret under aura restriction when the bar rides the aura block
        -- (Blizzard Style): keep the out-of-combat layout, the width is fixed.
        if issecretvalue(barW) then
            return
        end
        if not barW or barW <= 0 then
            return
        end
        -- +5px so the timer text has a little extra room before it truncates.
        local timerW = (cb._durationSize or 10) * 2.2 + 5
        local showDur = cb._showDuration ~= false
        local nameSide = cb._nameSide or "left"
        local tgtSide = cb._tgtSide or "right"
        local durSide = cb._durSide or "right"
        local textW = barW * 0.42
        -- The 42% reserves the opposite half for the cast target. When this unit never
        -- shows a target (boss frames: showCastTarget false with no UI to enable it)
        -- the name owns the row and gets 80% before truncating.
        local nameW = (cb._showTarget == false) and (barW * 0.80) or textW
        -- Show Full Spell Name: the name gets the whole row less the duration's
        -- slot (both sides when centered) and a shown target's slot, and
        -- shrinks to fit it (cb:_fitSpellName after each cast start).
        if cb._fitName then
            nameW = barW - 8 - (showDur and timerW * (nameSide == "center" and 2 or 1) or 0)
            if not cb._combineNT and cb.Target:IsShown() and tgtSide ~= nameSide then
                nameW = nameW - textW
            end
            if nameW < 20 then
                nameW = 20
            end
        end
        -- Combine Spell Name and Target suppresses the target element, so the combined
        -- name owns the row and gets the wide budget.
        cb.Text:ClearAllPoints()
        if nameSide == "none" then
            cb.Text:Hide()
        else
            local pt, xb, jh = mod.GetCastTextAnchor(nameSide, showDur and durSide == nameSide, timerW, false)
            cb.Text:SetWidth((cb._combineNT and not cb._fitName) and (barW * 0.80) or nameW)
            cb.Text:SetJustifyH(jh)
            cb.Text:SetPoint(pt, cb, pt, xb + (cb._nameOX or 0), 1 + (cb._nameOY or 0))
            cb.Text:Show()
        end
        -- Spell target; visibility is handled by _showTarget / hasTarget elsewhere.
        do
            local pt, xb, jh = mod.GetCastTextAnchor(tgtSide, showDur and durSide == tgtSide, timerW, false)
            cb.Target:ClearAllPoints()
            cb.Target:SetWidth(textW)
            cb.Target:SetJustifyH(jh)
            cb.Target:SetPoint(pt, cb, pt, xb + (cb._tgtOX or 0), (cb._tgtOY or 0))
        end
        -- Duration/timer: side is only "left"/"right"; visibility via _showDuration.
        -- Its box is wider than the room it reserves (timerW), up to half the
        -- bar: the countdown sits justified at the anchored edge, and a
        -- pushback's added time ("1.5+0.50") still fits in a wide font instead
        -- of being cut off.
        do
            local pt, xb, jh = mod.GetCastTextAnchor(durSide, false, timerW, true)
            cb.Time:ClearAllPoints()
            cb.Time:SetWidth(math.max(timerW * 2.5, barW * 0.5))
            cb.Time:SetJustifyH(jh)
            cb.Time:SetPoint(pt, cb, pt, xb + (cb._durOX or 0), (cb._durOY or 0))
        end
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        mod.ReflowFontString(cb.Text)
        mod.ReflowFontString(cb.Target)
        mod.ReflowFontString(cb.Time)
    end
    castBar._durationSize = prefs.castDurationSize or 10
    castBar._nameOX = prefs.castSpellNameX or 0
    castBar._nameOY = prefs.castSpellNameY or 0
    castBar._durOX = prefs.castDurationX or 0
    castBar._durOY = prefs.castDurationY or 0
    castBar._tgtOX = prefs.castSpellTargetX or 0
    castBar._tgtOY = prefs.castSpellTargetY or 0
    castBar._nameSide = prefs.castSpellNameSide or "left"
    castBar._tgtSide = prefs.castSpellTargetSide or "right"
    castBar._durSide = prefs.castDurationSide or "right"
    castBar._showDuration = prefs.showCastDuration ~= false
    castBar._fullCraft = prefs.castFullCraftTime == true
    castBar._fitName = prefs.castFitSpellName == true or nil
    castBar._nameSize = prefs.castSpellNameSize or 11
    castBar._showTarget = prefs.showCastTarget ~= false
    castBar._layoutTextZones = LayoutCastTextZones
    LayoutCastTextZones(castBar)

    -- Helper: sync all offset/size/side cache values from settings onto
    -- the castbar, then re-layout. Called from live refresh paths.
    castBar._syncOffsetsAndLayout = function(self, s)
        self._durationSize = s.castDurationSize or 10
        self._nameOX = s.castSpellNameX or 0
        self._nameOY = s.castSpellNameY or 0
        self._durOX = s.castDurationX or 0
        self._durOY = s.castDurationY or 0
        self._tgtOX = s.castSpellTargetX or 0
        self._tgtOY = s.castSpellTargetY or 0
        self._nameSide = s.castSpellNameSide or "left"
        self._tgtSide = s.castSpellTargetSide or "right"
        self._durSide = s.castDurationSide or "right"
        self._showDuration = s.showCastDuration ~= false
        self._fullCraft = s.castFullCraftTime == true
        self._fitName = s.castFitSpellName == true or nil
        self._nameSize = s.castSpellNameSize or 11
        if self._layoutTextZones then
            self:_layoutTextZones()
        end
        -- Settings refresh resets the name to its configured size; re-fit a
        -- cast in flight.
        if self._fitName and self.spellName then
            self:_fitSpellName()
        end
    end

    -- Show Full Spell Name: shrink the shown name (spell, craft count or
    -- "Spell - Target") to the width LayoutCastTextZones gave it. _fitStr is
    -- the clean copy built at cast start; nil (secret) keeps the size.
    castBar._fitSpellName = function(self)
        CludesUI.FitCastName(self.Text, self._fitStr, self._nameSize or 11)
    end

    local castTintLayer = castBar:CreateTexture(nil, "ARTWORK", nil, 1)
    castTintLayer:SetPoint("TOPLEFT", castBar:GetStatusBarTexture(), "TOPLEFT")
    castTintLayer:SetPoint("BOTTOMRIGHT", castBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    castTintLayer:SetTexture("Interface\\Buttons\\WHITE8X8")
    local c = GetCastbarColor()
    castTintLayer:SetVertexColor(c.r, c.g, c.b)
    castTintLayer:SetAlpha(0)
    castBar.castTintLayer = castTintLayer
    castBar._castTintOn = nil

    -- The shield tint lives on its own child FRAME: the secret-safe show/hide
    -- rides SetAlphaFromBoolean, and on Midnight that API renders 0 on
    -- TEXTURES while GetAlpha reads back the true-branch value (measured
    -- 2026-08-12 -- perfect state readbacks, nothing painted). Frame alpha is
    -- the proven boolean lane (range fading uses it suite-wide).
    local shieldHost = CreateFrame("Frame", nil, castBar)
    shieldHost:SetAllPoints(castBar)
    shieldHost:SetAlpha(0)
    local shieldedTint = shieldHost:CreateTexture(nil, "ARTWORK", nil, 2)
    shieldedTint:SetPoint("TOPLEFT", castBar:GetStatusBarTexture(), "TOPLEFT")
    shieldedTint:SetPoint("BOTTOMRIGHT", castBar:GetStatusBarTexture(), "BOTTOMRIGHT")
    shieldedTint:SetTexture("Interface\\Buttons\\WHITE8X8")
    shieldedTint:SetVertexColor(0.5, 0.5, 0.5, 1)
    castBar._shieldedTint = shieldedTint
    castBar._shieldHost = shieldHost

    -- Cast bar reuses the unit's health bar texture (overridden donor-aware in ReloadFrames).
    mod.ApplyCastBarTexture(
        castBar,
        (prefs and prefs.healthBarTexture) or saved.profile.healthBarTexture or "none"
    )
    mod.ApplyCastFillOpacity(castBar, prefs)

    local function OnCastbarCastActive(self)
        if self.castTintLayer then
            -- _fillOp is nil unless Fill Opacity is below 100 (see
            -- ns.ApplyCastFillOpacity), so the default path is unchanged.
            self.castTintLayer:SetAlpha(self._fillOp or 1)
            self._castTintOn = true
            ApplyUnitFrameCastColor(self)
            -- Blizzard Style: the fill art is its own colour, per cast kind.
            if self._blizzCast then
                self.castTintLayer:SetAlpha(0)
                self._castTintOn = nil
                mod.UF_SetBlizzCastFill(self, self.channeling and "channel" or "cast")
            end
        end
    end
    castBar.PostCastStart = OnCastbarCastActive
    castBar.PostChannelStart = OnCastbarCastActive

    castBar.PostCastInterruptible = function(self)
        ApplyUnitFrameCastColor(self)
        UpdateUnitFrameKickTick(self)
    end

    if IsKickCastbarUnit(unitToken) then
        local kickClip = CreateFrame("Frame", nil, castBar)
        kickClip:SetAllPoints(castBar)
        kickClip:SetClipsChildren(true)
        castBar.kickClip = kickClip
        local kickPositioner = CreateFrame("StatusBar", nil, kickClip)
        kickPositioner:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickPositioner:GetStatusBarTexture():SetAlpha(0)
        -- Pixel-snap OFF on the fill texture (mirrors Nameplates). The tick sits
        -- at positioner_width + marker_width; independent per-fill snapping makes
        -- round(a) + round(b) wobble 1px even though the summed fraction is
        -- invariant. Load-bearing unsnap is after each SetFillStyle below.
        if kickPositioner:GetStatusBarTexture().SetSnapToPixelGrid then
            kickPositioner:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickPositioner:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickPositioner:SetPoint("CENTER", castBar)
        kickPositioner:SetFrameLevel(castBar:GetFrameLevel() + 1)
        kickPositioner:Hide()
        castBar.kickPositioner = kickPositioner
        local kickMarker = CreateFrame("StatusBar", nil, kickClip)
        kickMarker:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        kickMarker:GetStatusBarTexture():SetAlpha(0)
        if kickMarker:GetStatusBarTexture().SetSnapToPixelGrid then
            kickMarker:GetStatusBarTexture():SetSnapToPixelGrid(false)
            kickMarker:GetStatusBarTexture():SetTexelSnappingBias(0)
        end
        kickMarker:SetPoint("LEFT", kickPositioner:GetStatusBarTexture(), "RIGHT")
        kickMarker:SetSize(1, 1)
        kickMarker:SetFrameLevel(castBar:GetFrameLevel() + 2)
        kickMarker:Hide()
        castBar.kickMarker = kickMarker
        local kickTick = kickMarker:CreateTexture(nil, "OVERLAY", nil, 3)
        kickTick:SetColorTexture(1, 1, 1, 1)
        kickTick:SetWidth(2)
        kickTick:SetPoint("TOP", kickMarker, "TOP", 0, 0)
        kickTick:SetPoint("BOTTOM", kickMarker, "BOTTOM", 0, 0)
        kickTick:SetPoint("LEFT", kickMarker:GetStatusBarTexture(), "RIGHT")
        castBar.kickTick = kickTick
        -- Interrupt-ready mid-cast fill: colors the cast-bar segment from the "kick
        -- ready here" point to the cast end (the window during which the interrupt will
        -- be available) when the kick is on cooldown now but comes off before the cast
        -- finishes. Rides the SAME kickMarker geometry as the tick; the "ready in time"
        -- two-secret test resolves by where the marker texture edge lands -- when the
        -- kick will NOT be ready in time the fill anchors cross to zero width and it
        -- self-hides with no Lua branch on a secret. ARTWORK sublevel 1 (created after
        -- castTintLayer so it draws above the fill colour) sits below the cast text
        -- (OVERLAY) and the uninterruptible grey (sublevel 2). Anchors are (re)applied
        -- per cast in UpdateUnitFrameKickTick.
        local kickReadyFill = castBar:CreateTexture(nil, "ARTWORK", nil, 1)
        kickReadyFill:SetColorTexture(1, 1, 1, 1)
        kickReadyFill:SetAlpha(0)
        kickReadyFill:Hide()
        castBar.kickReadyFill = kickReadyFill
    end

    castBar.CustomTimeText = function(self, durationObject)
        local time = self.Time
        if self._showDuration == false then
            if time:IsShown() then
                time:SetText("")
                time:Hide()
            end
            return
        end
        time:Show()
        if self._craftExtra and durationObject then
            CludesUI.SetCraftTimerText(self, time, durationObject:GetRemainingDuration(), false)
            return
        end
        if durationObject then
            -- The engine calls this only when the shown tenth can have changed
            -- (CastOnUpdate paces it), so every call formats. SetFormattedText
            -- accepts the secret durations of other units' casts in combat.
            local duration = durationObject:GetRemainingDuration()
            if self.delay and self.delay ~= 0 then
                time:SetFormattedText(
                    "%.1f|cffff0000%s%.2f|r",
                    duration,
                    self.channeling and "-" or "+",
                    self.delay
                )
            else
                time:SetFormattedText("%.1f", duration)
            end
        end
    end
    castBar.CustomDelayText = castBar.CustomTimeText

    -- Cast spell icon (oUF sets castbar.Icon texture automatically). Size from the
    -- CONFIGURED height (cbHeight), not a live castbarBg:GetHeight() which is
    -- unreliable this early; LayoutCastbarIcon anchors height to the bar regardless,
    -- this is just the initial square.
    local iconSize = cbHeight
    local iconFrame = CreateFrame("Frame", nil, castbarBg)
    iconFrame:SetSize(iconSize, iconSize)
    Pix.Point(iconFrame, "TOPRIGHT", castbarBg, "TOPLEFT", 0, 0)
    local iconBg = iconFrame:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints()
    iconBg:SetColorTexture(0, 0, 0, 1)
    iconFrame._bg = iconBg
    -- 1px black border via unified PP system
    Pix.CreateBorder(iconFrame, 0, 0, 0, 1)
    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castBar.Icon = iconTex
    castBar._iconFrame = iconFrame

    -- Initial icon/fill layout (re-applied on every reload by the per-unit
    -- update paths and whenever the cast-bar height changes).
    do
        local offX, offY = CastIconOffsets(unitToken, prefs)
        LayoutCastbarIcon(
            castBar,
            CastIconInWidth(unitToken, prefs),
            cbHeight,
            CastIconOnRight(unitToken, prefs),
            offX,
            offY,
            CastIconShown(unitToken, prefs),
            prefs and prefs[mod.UF_CastClassicKey(unitToken)],
            mod.UF_CastIconPortrait(castBar, widget, prefs, unitToken)
        )
        mod.UF_ApplyCastBorder(castBar, prefs, nil, unitToken)
    end

    return castBar
end

-- Important Cast Glow (target/focus), mirrors Nameplates.
-- The secret IsSpellImportant flag only drives overlay alpha.
do
    local IMP_GLOW_COLOR = { r = 1, g = 0.2, b = 0.2 }
    local IMP_GLOW_BG_COLOR = { r = 0, g = 0, b = 0 }
    -- One scratch spec for both cast bars: StartSpecGlow reads it synchronously.
    local impSpec = {}

    mod.ClearUnitFrameImportantGlow = function(castBar)
        local shade = castBar and castBar._importantOverlay
        if not shade or not castBar._impGlowActive then
            return
        end
        CludesUI.Glows.StopAllGlows(shade)
        shade:SetAlpha(0)
        shade:Hide()
        castBar._impGlowActive = nil
    end

    -- Called from PostCastStart; the engine has already set castbar.spellID.
    mod.UpdateUnitFrameImportantGlow = function(castBar)
        local s = castBar and castBar._eufSettings
        local Glows = CludesUI.Glows
        if not (s and s.castbarImportantGlow and C_Spell and C_Spell.IsSpellImportant) then
            mod.ClearUnitFrameImportantGlow(castBar)
            return
        end
        -- Probe first: a readable "not important" never starts a glow. A secret
        -- answer (combat restriction) still takes the alpha path below.
        local success, isImportant = pcall(C_Spell.IsSpellImportant, castBar.spellID or 0)
        if not success or (not issecretvalue(isImportant) and not isImportant) then
            mod.ClearUnitFrameImportantGlow(castBar)
            return
        end

        local shade = castBar._importantOverlay
        if not shade then
            shade = CreateFrame("Frame", nil, castBar)
            shade:SetAllPoints(castBar)
            shade:EnableMouse(false)
            castBar._importantOverlay = shade
        end
        shade:SetFrameLevel(castBar:GetFrameLevel() + 5)

        local c = s.castbarImportantGlowColor or IMP_GLOW_COLOR
        local bgc = s.castbarImportantGlowBackgroundColor or IMP_GLOW_BG_COLOR
        local specInfo = impSpec
        specInfo.style = s.castbarImportantGlowStyle or 1
        specInfo.r, specInfo.g, specInfo.b =
            Glows.ResolveColor(s.castbarImportantGlowColorMode or "custom", c.r, c.g, c.b)
        specInfo.lines = s.castbarImportantGlowLines or 8
        specInfo.thickness = s.castbarImportantGlowThickness or 2
        specInfo.speed = s.castbarImportantGlowSpeed or 4
        specInfo.bg = (s.castbarImportantGlowBackground == true) or nil
        specInfo.bgR, specInfo.bgG, specInfo.bgB = bgc.r, bgc.g, bgc.b
        local pW, pH = castBar:GetWidth(), castBar:GetHeight()
        -- Secret while the bar rides the stock-style aura block: use the last plain read
        -- (the bar never resizes in combat), else the configured holder size.
        if issecretvalue(pW) or issecretvalue(pH) then
            pW, pH = castBar._impPlainW, castBar._impPlainH
            if not pW then
                local cbw = s.castbarWidth or 0
                pW = cbw > 0 and cbw or 181
                pH = s.castbarHeight or 14
            end
        else
            castBar._impPlainW, castBar._impPlainH = pW, pH
        end
        if pW < 5 then
            pW = 100
        end
        if pH < 5 then
            pH = 14
        end
        -- Restarts only when the look or the bar size changed, so back-to-back
        -- casts keep the animation running.
        Glows.StartSpecGlow(shade, specInfo, pW, pH, "bar")
        castBar._impGlowActive = true

        shade:Show()
        shade:SetAlphaFromBoolean(isImportant)
    end
end

local function SetupShowOnCastBar(widget, unitToken)
    local castBar = widget.Castbar
    local castbarBg = castBar:GetParent()
    local iconFrame = castBar._iconFrame
    local impGlowUnit = IsKickCastbarUnit(unitToken)

    -- Read the hide-when-inactive flag dynamically so closures always reflect the
    -- current setting rather than a value captured at frame-creation time.
    local function shouldHideWhenInactive()
        local s = GetSettingsForUnit(unitToken)
        if not s then
            return true
        end
        local val = s.castbarHideWhenInactive
        if val == nil then
            return true
        end
        return val
    end

    castBar:Hide()
    if iconFrame then
        iconFrame:Hide()
    end
    if castbarBg then
        if shouldHideWhenInactive() then
            castbarBg:Hide()
        else
            castbarBg:Show()
        end
    end

    local savedCastHook = castBar.PostCastStart
    local savedInterruptHook = castBar.PostCastInterruptible

    castBar.PostCastStart = function(self, ...)
        local bg = self:GetParent()
        if bg then
            -- Boss: re-assert the configured width (castbarWidth>0=custom, 0=match
            -- frame width) at cast start, so a live cast always shows the right width
            -- even if no settings pass ran since the frame was resized.
            if unitToken and unitToken:match("^boss") then
                local s = saved and saved.profile and GetSettingsForUnit(unitToken)
                local cw = (s and s.castbarWidth) or 0
                if cw > 0 and cw < 30 then
                    cw = 30
                end
                if s then
                    Pix.Width(bg, cw > 0 and cw or widget:GetWidth())
                end
            end
            bg:Show()
        end
        self:Show()
        if self._iconFrame then
            local s = saved and saved.profile and GetSettingsForUnit(unitToken)
            local showIcon
            if unitToken == "player" then
                showIcon = (s and s.showPlayerCastIcon ~= false)
            else
                showIcon = (not s or s.showCastIcon ~= false)
            end
            if showIcon then
                self._iconFrame:Show()
            else
                self._iconFrame:Hide()
            end
        end
        -- Spell target text (who the unit is casting on)
        if self.Target then
            local spellTarget, spellTargetClass
            local ownerUnit = self.__owner and self.__owner._cuiUnit
            -- Channels are excluded: UnitSpellTargetName tracks the last CAST
            -- and keeps returning the previous hard-cast's target for the
            -- whole channel (field-verified stale), and no channel-target API
            -- exists -- so channels show no target name rather than a wrong
            -- one. Empowered casts read correctly and keep theirs.
            if
                ownerUnit
                and not self.channeling
                and UnitShouldDisplaySpellTargetName
                and UnitShouldDisplaySpellTargetName(ownerUnit)
            then
                local rawTarget = UnitSpellTargetName and UnitSpellTargetName(ownerUnit)
                if rawTarget then
                    spellTarget = rawTarget
                    spellTargetClass = UnitSpellTargetClass and UnitSpellTargetClass(ownerUnit)
                end
            end
            local hasTarget = spellTarget and true or false
            local sOwn = ownerUnit and saved and saved.profile and GetSettingsForUnit(ownerUnit)
            -- Combine Spell Name and Target (target/focus): one string in the TARGET
            -- slot ("Spell Name - Target", target class colored); the separate Spell
            -- Name element is suppressed via _combineNT in LayoutCastTextZones. Color
            -- code lives in the clean FORMAT string; (possibly secret) names ride
            -- through SetFormattedText -- never Lua-concatenated.
            local combine = sOwn
                and sOwn.castCombineNameTarget == true
                and (ownerUnit == "target" or ownerUnit == "focus")
            self._combineNT = combine or nil
            -- Show Full Spell Name: the clean string the name element shows,
            -- for measuring. Secret parts are never concatenated (nil = skip).
            if self._fitName then
                local num = self.spellName
                if num and not issecretvalue(num) then
                    if self._craftExtra and self._craftCountSuffix then
                        num = num .. self._craftCountSuffix
                    end
                    if combine and hasTarget then
                        num = (not issecretvalue(spellTarget)) and (num .. " - " .. spellTarget) or nil
                    end
                else
                    num = nil
                end
                self._fitStr = num
            end
            if combine then
                -- The separate target element is fully suppressed; the target
                -- rides appended to the spell NAME element instead.
                self.Target:SetText("")
                self.Target:Hide()
                if self.Text and hasTarget then
                    local spellName = UnitCastingInfo(ownerUnit)
                    if not spellName then
                        spellName = UnitChannelInfo(ownerUnit)
                    end
                    local hex
                    if spellTargetClass and C_ClassColor then
                        local c = C_ClassColor.GetClassColor(spellTargetClass)
                        if c and c.GenerateHexColor then
                            hex = c:GenerateHexColor()
                        end
                    end
                    if spellName then
                        if hex then
                            self.Text:SetFormattedText("%s - |c" .. hex .. "%s|r", spellName, spellTarget)
                        else
                            self.Text:SetFormattedText("%s - %s", spellName, spellTarget)
                        end
                    end
                end
                -- No cast target: oUF's plain spell name in the Text element
                -- stands untouched.
            else
                self.Target:SetText(spellTarget or "")
                self.Target:SetShown(hasTarget and self._showTarget ~= false)
                -- Class color the target name
                if hasTarget and spellTargetClass and C_ClassColor then
                    local c = C_ClassColor.GetClassColor(spellTargetClass)
                    if c then
                        self.Target:SetTextColor(c:GetRGB())
                    else
                        local tc = (sOwn and sOwn.castSpellTargetColor) or { r = 1, g = 1, b = 1 }
                        self.Target:SetTextColor(tc.r, tc.g, tc.b)
                    end
                elseif hasTarget then
                    local tc = (sOwn and sOwn.castSpellTargetColor) or { r = 1, g = 1, b = 1 }
                    self.Target:SetTextColor(tc.r, tc.g, tc.b)
                end
            end
            if self._layoutTextZones then
                self:_layoutTextZones()
            end
            if self._fitName then
                self:_fitSpellName()
            end
        end
        if savedCastHook then
            savedCastHook(self, ...)
        end
        UpdateUnitFrameKickTick(self)
        if impGlowUnit then
            mod.UpdateUnitFrameImportantGlow(self)
        end
        NotifyCastbarStarted(self)
    end
    castBar.PostChannelStart = castBar.PostCastStart
    castBar.PostCastInterruptible = function(self, ...)
        if savedInterruptHook then
            savedInterruptHook(self)
        end
    end

    local function dismissCastBar(self)
        HideUnitFrameKickTick(self)
        NotifyCastbarEnded(self)
        self:Hide()
        if self._iconFrame then
            self._iconFrame:Hide()
        end
        -- Read setting dynamically so changes take effect without a reload.
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then
                bg:Hide()
            end
        end
    end
    castBar.PostCastStop = dismissCastBar
    castBar.PostChannelStop = dismissCastBar
    castBar.PostCastFail = dismissCastBar

    -- Guard against nil stages from UnitEmpoweredStagePercentages during
    -- empower casts where stage data isn't available yet.
    castBar.UpdatePips = function(element, stages)
        if not stages then
            return
        end
        local isHoriz = element:GetOrientation() == "HORIZONTAL"
        local elementSize = isHoriz and element:GetWidth() or element:GetHeight()
        local lastOffset = 0
        for stage, stageSection in next, stages do
            local offset = lastOffset + (elementSize * stageSection)
            lastOffset = offset
            local pipTex = element.Pips[stage]
            if not pipTex then
                pipTex = (element.CreatePip or function(e)
                    return CreateFrame("Frame", nil, e, "CastingBarFrameStagePipTemplate")
                end)(element, stage)
                element.Pips[stage] = pipTex
            end
            pipTex:ClearAllPoints()
            if isHoriz then
                pipTex:SetPoint("CENTER", element, "LEFT", offset, 0)
            else
                pipTex:SetPoint("CENTER", element, "BOTTOM", 0, offset)
            end
            pipTex:Show()
        end
        for idx = #stages + 1, #element.Pips do
            element.Pips[idx]:Hide()
        end
    end

    -- Catch-all: hide the icon AND background whenever the castbar hides for any
    -- reason (oUF holdTime expiry, target/focus switch, etc.) so neither gets stuck.
    -- Key case: target/focus switching mid-cast -- oUF's CastStart hides the castbar
    -- but never fires PostCastStop, so dismissCastBar never runs and the background
    -- frame would otherwise remain visible as a black rectangle.
    castBar:HookScript("OnHide", function(self)
        HideUnitFrameKickTick(self)
        if impGlowUnit then
            mod.ClearUnitFrameImportantGlow(self)
        end
        NotifyCastbarEnded(self)
        if self._iconFrame then
            self._iconFrame:Hide()
        end
        if shouldHideWhenInactive() then
            local bg = self:GetParent()
            if bg then
                bg:Hide()
            end
        end
    end)
end

-- Toggle a frame's oUF Castbar element without rewriting Blizzard's cast bar event
-- registration. oUF silences PlayerCastingBarFrame/PetCastingBarFrame when the element
-- enables on the player frame and re-arms them when it disables; the shared helpers
-- keep whatever a standalone cast bar addon set. On ns for the 200-locals cap.
function mod.SetCastbarElement(widget, enable)
    if not widget or not widget.Castbar then
        return
    end
    if (widget:IsElementEnabled("Castbar") and true or false) == (enable and true or false) then
        return
    end
    CludesUI.CaptureBlizzCastBarEvents()
    if enable then
        widget:EnableElement("Castbar")
    else
        widget:DisableElement("Castbar")
    end
    CludesUI.RestoreBlizzCastBarEvents()
end

-- Manage Blizzard's player cast bar ownership based on whether UnitFrames renders its
-- own player cast bar. oUF already handles event plumbing for its own castbar element;
-- this helper only coordinates suppression with other CUI modules and releases control
-- cleanly for external addons.
local function ApplyBlizzCastbarState()
    if
        CludesUI
        and CludesUI.SetPlayerCastBarSuppressed
        and saved
        and saved.profile
        and saved.profile.player
    then
        -- Only suppress Blizzard's player cast bar when CUI actually provides a
        -- replacement. If the player is on the Blizzard (or hidden) frame source,
        -- there is no CUI cast bar, so leave Blizzard's alone. Visibility "never"
        -- counts as no replacement too: our cast bar is built now but hides with the
        -- frame, and taking Blizzard's away would leave no player cast bar at all.
        -- Nor while ours stands down for the controller under WoW Forever's
        -- Gamepad interface style, whose cast bar is Blizzard's own.
        local suppress = (
            saved.profile.player.showPlayerCastbar
            and mod.VisEffective(saved.profile.player) ~= "never"
            and mod.GetUnitFrameSource("player") == "cui"
            and not (mod._ufCastPadHidden and CludesUI.PadGamepadUI())
        ) or false
        CludesUI.SetPlayerCastBarSuppressed("UnitFrames", suppress)
    end
end

-- Hide While Using Gamepad (Global Settings > Gamepad): Blizzard's gamepad UI
-- draws its own player cast bar, so ours stands down while CludesUI.PadModeOn
-- says gamepad mode is on (WoW Forever's Gamepad interface style, elsewhere a
-- connected controller). It rides the same element switch "Show Player Cast Bar" off uses,
-- keyed on a runtime flag the reload and visibility passes also read
-- (ns._ufCastPadHidden); the saved toggle is never written. Blizzard's bar
-- stays suppressed, except under WoW Forever's Gamepad interface style: from
-- build 70425 that style draws the cast on Blizzard's player bar itself, so it
-- is handed back meanwhile. The pad edges are watched only while the option is
-- on and our player cast bar is on screen. padOn is the watcher's verdict; the
-- login, reload and options callers pass nothing and it is read live.
function mod.UF_ApplyGamepadCastbar(padOn)
    local s = saved and saved.profile and saved.profile.player
    local widget = frameList.player
    local cb = widget and widget.Castbar
    local wanted = (
        cb
        and s
        and s.showPlayerCastbar
        and s.castbarGamepadHide == true
        and mod.VisEffective(s) ~= "never"
        and mod.GetUnitFrameSource("player") == "cui"
    )
            and true
        or false
    if wanted ~= (mod._ufCastPadWatched == true) then
        mod._ufCastPadWatched = wanted
        if wanted then
            CludesUI.WatchPad("UF_PlayerCastbar", mod.UF_ApplyGamepadCastbar)
        else
            CludesUI.UnwatchPad("UF_PlayerCastbar")
        end
    end
    local hide = false
    if wanted then
        if padOn == nil then
            padOn = CludesUI.PadModeOn()
        end
        hide = padOn and true or false
    end
    if hide == (mod._ufCastPadHidden == true) then
        return
    end
    mod._ufCastPadHidden = hide
    ApplyBlizzCastbarState()
    if not cb then
        return
    end
    local castbarBg = cb:GetParent()
    if hide then
        mod.SetCastbarElement(widget, false)
        cb:Hide()
        if castbarBg then
            castbarBg:Hide()
        end
        return
    end
    -- Back on, mid-cast included: the enable re-derives the live cast; an idle
    -- holder follows the reload pass's hide-while-not-casting rule. A setting
    -- that turned the bar off is left to the reload pass that hides it.
    if not (s and s.showPlayerCastbar) then
        return
    end
    -- Enabled whether or not the frame is shown, as the reload pass does: a
    -- frame hidden by its visibility driver gets no element re-enable when the
    -- driver shows it again, so skipping it here would leave the bar dead. The
    -- holder is a child of the frame, so a hidden frame draws nothing.
    mod.SetCastbarElement(widget, true)
    if castbarBg then
        if s.castbarHideWhenInactive and not cb:IsShown() then
            castbarBg:Hide()
        else
            castbarBg:Show()
        end
    end
end

Inner.CastIconInWidth, Inner.CastIconShown, Inner.CastIconOnRight =
    CastIconInWidth, CastIconShown, CastIconOnRight
Inner.CastIconOffsets, Inner.LayoutCastbarIcon = CastIconOffsets, LayoutCastbarIcon
Inner.CastbarUnlockKey, Inner.IsKickCastbarUnit = CastbarUnlockKey, IsKickCastbarUnit
Inner.ApplyUnitFrameCastColor, Inner.UpdateUnitFrameKickTick =
    ApplyUnitFrameCastColor, UpdateUnitFrameKickTick
Inner.CreateCastBar, Inner.SetupShowOnCastBar = CreateCastBar, SetupShowOnCastBar
Inner.ApplyBlizzCastbarState = ApplyBlizzCastbarState
