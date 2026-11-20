if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_Advance.lua
--
--  AdvanceGrid, the fan at run time (center, strip, cancel, AdvanceFan),
--  the hub text and ns.CreatePaletteView.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._qdInternals
-- CludesUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local tonumber = tonumber
local GetCursorPosition = GetCursorPosition

local MAX_SLOTS, AdoptFontString = Inner.MAX_SLOTS, Inner.AdoptFontString
local ApplyModuleFont, CreateSlotWidget = Inner.ApplyModuleFont, Inner.CreateSlotWidget
local PaletteView, PaletteViewMeta = Inner.PaletteView, Inner.PaletteViewMeta
local SelectedZoom, views, FalloffK = Inner.SelectedZoom, Inner.views, Inner.FalloffK
local FalloffRatios, FAN_EDIT_MIN_ALPHA = Inner.FalloffRatios, Inner.FAN_EDIT_MIN_ALPHA
local FAN_EDIT_MIN_SCALE, FanOffset = Inner.FAN_EDIT_MIN_SCALE, Inner.FanOffset
local FAN_CANCEL_REACH, GRID_REACH = Inner.FAN_CANCEL_REACH, Inner.GRID_REACH
local NEST_DIM_ALPHA, NEST_DIM_SCALE = Inner.NEST_DIM_ALPHA, Inner.NEST_DIM_SCALE

local scrollCatcher
Inner.scrollCatcherSetters[#Inner.scrollCatcherSetters + 1] = function(val)
    scrollCatcher = val
end

-- Lay the grid out and select the entry nearest the pointer. noPointer draws it
-- evenly with nothing selected, which is what Layout and the editor want.
function PaletteView:AdvanceGrid(noPointer)
    local profile = self:P()
    local isShown = self.shownCount
    if not profile or isShown < 1 then
        self:SetSelection(nil)
        return
    end

    local _, iconSize = self:Geom()
    local pitch = iconSize + (profile.fanGap or 10)
    local decay, aDecay = FalloffRatios(profile)
    local minS = profile.fanMinScale or 0.30
    local minA = profile.fanMinAlpha or 0.12
    if self.opts.interactive then
        minS = max(minS, FAN_EDIT_MIN_SCALE)
        minA = max(minA, FAN_EDIT_MIN_ALPHA)
    end

    local cols, rowList = self:GridDims()
    local widget = self.frame

    -- Pointer offset from the grid's centre, or nil while the movement gate is
    -- still armed -- without it an entry is selected the instant the grid opens
    -- and "open and release" would fire instead of cancelling.
    local dx, dy
    local fx, fy = widget:GetCenter()
    if fx and not noPointer then
        local es = widget:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX, curY = curX / es, curY / es
        if not self._steered and (abs(curX - self._gateX) >= 1 or abs(curY - self._gateY) >= 1) then
            self._steered = true
        end
        if self._steered then
            dx, dy = curX - fx, curY - fy
        end
    end

    -- Nested cells first, and by CONTAINMENT rather than by nearness: a nest is
    -- somewhere you are in or out of. Inside a box, that child regardless of
    -- what the block holds underneath -- which is what lets a halo sit over the
    -- entries around its parent. Outside every box, the block answers as though
    -- the nest were not there, so leaving a run in any direction leaves the nest.
    --
    -- ONLY the armed claim, though: this is the pass-through rule. A nest
    -- earns the right to answer here by having actually had the cursor pass
    -- over its parent entry first -- see ArmedClaim and the gate frames
    -- EnsureGates builds. An unarmed claim's ground answers as though it held
    -- no nest at all, which is exactly what lets two claims share ground
    -- without one springing open behind the other's back.
    local best, bestK
    local armed = self:ArmedClaim()
    if dx then
        best = self:NestHit(dx, dy, armed)
    end

    -- Nearest of the palette's own, once the nests have declined. Past
    -- GRID_REACH cells from every one of them nothing is selected -- this
    -- layout's cancel, and it has no dead zone, a grid's centre being an
    -- ordinary cell.
    if dx and not best then
        for index = 1, isShown do
            local bx, by = self:GridBase(index, cols, rowList, pitch)
            local ox, oy = (dx - bx) / pitch, (dy - by) / pitch
            -- ^0.5, not sqrt: the snippet has no sqrt and must use the power
            -- form, and the two are not bit-identical in Lua 5.1. Matching them
            -- keeps a cursor exactly on the reach boundary from selecting one
            -- entry on screen and firing another.
            local key = (ox * ox + oy * oy) ^ 0.5
            if not bestK or key < bestK then
                best, bestK = index, key
            end
        end
        if bestK and bestK > GRID_REACH then
            best = nil
        end
    end

    -- Which nest is open, settled before anything is drawn: a style that fades
    -- the block behind it has to know while the block is being painted, not a
    -- frame later. SetSelection's own call then finds nothing left to do.
    self:UpdateNestShown(best)
    local open = self._openClaim
    local size = (open and open.dim) and NEST_DIM_ALPHA or 1
    local shrink = (open and open.dim) and NEST_DIM_SCALE or 1

    for index = 1, isShown do
        local wid = self.widgets[index]
        local bx, by = self:GridBase(index, cols, rowList, pitch)

        -- Falloff is the 2D distance, in cells. A grid has no privileged axis,
        -- so projecting onto one -- as the strip does -- would make the zoom
        -- respond to sideways movement it should ignore.
        --
        -- Each axis is flattened over the cell before they are combined, so the
        -- whole of a cell -- corners included -- reads as zero cells away. See
        -- FalloffK.
        local s, a = max(minS, decay), 1
        if dx then
            local ox = FalloffK(abs(dx - bx) / pitch)
            local oy = FalloffK(abs(dy - by) / pitch)
            local key = (ox * ox + oy * oy) ^ 0.5
            s = max(minS, decay ^ key)
            a = max(minA, aDecay ^ key)
        end
        -- The entry a nest hangs off keeps its colour: it is what the nest is
        -- about, and dimming it would leave nothing on screen saying which entry
        -- was opened. It may still draw back to make room -- the halo needs the
        -- ground its parent would otherwise be standing on.
        if open then
            if index ~= open.parent then
                s, a = s * shrink, a * size
            elseif open.parentScale then
                s = s * open.parentScale
            end
        end

        wid:SetAlpha(a)
        wid.baseSize = iconSize * s
        wid:SetSize(iconSize * s, iconSize * s)
        wid:ClearAllPoints()
        wid:SetPoint("CENTER", widget, "CENTER", bx, by)
        wid:Show()
    end

    -- Nested cells are drawn at a flat size. They live inside boxes rather than
    -- on a falloff, and a child shrinking as the pointer crossed its own box
    -- would suggest a nearness that decides nothing here.
    local claims = self.claims
    for ck = 1, (claims and #claims or 0) do
        local claim = claims[ck]
        for jdx = 1, claim.n do
            local cell = claim.cells and claim.cells[jdx]
            local wid = claim.base and self.widgets[claim.base + jdx]
            if cell and wid then
                wid:SetAlpha(1)
                wid.baseSize = claim.icon
                wid:SetSize(claim.icon, claim.icon)
                wid:ClearAllPoints()
                wid:SetPoint("CENTER", widget, "CENTER", cell.x, cell.y)
            end
        end
    end

    -- Magnify the chosen cell where it stands. Applied here rather than left to
    -- the selection paint because the sizes above are rewritten every frame,
    -- which would erase a zoom applied only when the selection changed.
    if best then
        local wid = self.widgets[best]
        local z = SelectedZoom()
        wid:SetSize(wid.baseSize * z, wid.baseSize * z)
    end
    self:SetSelection(best)
end

-- Centre the strip on a slot with no animation. The options preview uses this
-- to follow the entry the user has clicked.
function PaletteView:SetFanCenter(index)
    if not index or self.shownCount < 1 then
        return
    end
    self.fanTarget = index
    self.fanVisual = index
    self:ApplyFanGeometry()
    self:SetSelection(index)
end

-- Half the drawn strip, along its own axis, out to the far edge of the last
-- visible entry. Sizes the frame and bounds the cancel, from one number: a
-- second copy of this would drift the moment either falloff setting moved.
function PaletteView:FanHalfLength()
    local profile = self:P()
    local _, iconSize = self:Geom()
    -- One window for editor and play alike: the editor draws the same
    -- fanVisible-each-side strip a hold does and scrolls the rest into view.
    local window = (profile and profile.fanVisible) or 2
    local minS = self.opts.interactive and FAN_EDIT_MIN_SCALE or ((profile and profile.fanMinScale) or 0.30)
    -- Plus the room ApplyFanGeometry leaves for the selected entry to grow into,
    -- which every offset past the centre carries. Left out, the frame would be
    -- narrower than the strip drawn in it and the cancel box would sit inside
    -- the last entry rather than beyond it.
    return FanOffset(window, iconSize, (profile and profile.fanGap) or 10, (FalloffRatios(profile)), minS)
        + iconSize
        + iconSize * (SelectedZoom() - 1) * 0.5
end

-- Pointer offset from the point the palette was opened at, which is what the
-- strip's cancel and its nests are both measured from.
function PaletteView:StripOffset()
    if not self._gateX then
        return nil
    end
    local es = self.frame:GetEffectiveScale()
    local curX, curY = GetCursorPosition()
    return curX / es - self._gateX, curY / es - self._gateY
end

-- The nest the entry at `index` opens, if it opens one.
function PaletteView:ClaimFor(index)
    local claims = self.claims
    for key = 1, (index and claims and #claims or 0) do
        if claims[key].parent == index then
            return claims[key]
        end
    end
end

-- Which entry the wheel has landed on, folded into range.
function PaletteView:StripTarget()
    local isShown = self.shownCount
    if not self.fanTarget or isShown < 1 then
        return nil
    end
    return ((self.fanTarget - 1) % isShown) + 1
end

-- The fold offset `slot` is drawn at on the strip, or nil when the window
-- culls it. One copy of the fold-plus-window arithmetic ApplyFanGeometry
-- draws by, for every reader that has to know where an entry stands: the
-- hover channel's nest tests and the sticky retention both anchor to it,
-- and the snippet's nest walk runs the identical sums.
function PaletteView:FanSlotOffset(slot)
    local isShown = self.shownCount
    local target = self:StripTarget()
    if not slot or not target or isShown < 1 then
        return nil
    end
    local skinData = (slot - target) % isShown
    if skinData * 2 > isShown then
        skinData = skinData - isShown
    end
    local profile = self:P()
    if abs(skinData) > ((profile and profile.fanVisible) or 2) + 0.5 then
        return nil
    end
    return skinData
end

-- How far the pointer has been carried toward leaving the strip: 0 while it is
-- still on it, 1 at the edge of the cancel box and beyond. Answers 0 for any
-- view with no gate origin -- the options preview, which has no pointer gesture
-- at all -- so only the live palette can be cancelled this way.
function PaletteView:FanCancelProgress()
    if not self._gateX then
        return 0
    end
    local profile = self:P()
    local _, iconSize = self:Geom()
    local along, across = self:StripOffset()
    if not self:FanHoriz() then
        along, across = across, along
    end

    local margin = FAN_CANCEL_REACH * (iconSize + ((profile and profile.fanGap) or 10))
    -- Travel toward the nest the selected entry opens does not count as leaving:
    -- its children sit past the ordinary margin, so measuring them by it would
    -- cancel the palette on the way to reaching them. Only on the side the nest
    -- is on, and only while that entry is the one the wheel is on.
    local acrossMargin = margin
    local claim = self:ClaimFor(self:StripTarget())
    if claim and claim.across and (across > 0) == (claim.sign > 0) then
        acrossMargin = max(margin, claim.across)
    end

    return max(abs(across) / acrossMargin, abs(along) / (self:FanHalfLength() + margin))
end

-- Has the pointer been thrown clear of the strip?
function PaletteView:FanCancelled()
    return self:FanCancelProgress() > 1
end

-- Advance the settle animation and publish the centred entry as the selection.
-- The LOGICAL index moves the instant the tick arrives; only the geometry is
-- interpolated. A release mid-animation therefore always fires what the user
-- last scrolled to, never whatever the strip happens to be sliding past.
function PaletteView:AdvanceFan(elapsed)
    local isShown = self.shownCount
    if isShown < 1 then
        self:SetSelection(nil)
        return
    end

    -- The live strip's index is owned by the secure snippet: an addon may not
    -- write a secure button's attributes in combat, so the mouse wheel is
    -- handled in the sandbox and left here to be read. Reading an attribute
    -- from Lua is unrestricted, so this works in combat and out. Other views
    -- (the options preview) keep driving fanTarget themselves.
    if self.opts.live and scrollCatcher then
        self.fanTarget = tonumber(scrollCatcher:GetAttribute("eqdFanTarget"))
    end

    -- Published BEFORE the geometry below, which magnifies whichever entry is
    -- selected as it places it. The strip keeps sliding to wherever the wheel
    -- has left it while the pointer is clear of it, so bringing the pointer back
    -- shows the entry that would fire, already settled.
    local target = self:StripTarget()
    local claim = self:ClaimFor(target)
    local p2 = self:P()
    local mouseSel = (p2 and p2.fanMouseSelect) ~= false
    local sel
    -- Into a nest, if the pointer has gone there. ONLY the ARMED claim's
    -- cells are live ground: hovering a parent's own icon arms its claim
    -- through the strip's lattice gates (see EnsureLatticeGates), hovering
    -- any other entry disarms, and the empty ground beside the strip changes
    -- nothing -- so the reach for the children keeps the nest, while the
    -- space where a CLOSED nest would be answers nothing at all. The snippet
    -- reads the same eqdArmed and runs the identical shifted containment
    -- (drawn == fired). Wheel-only keeps the old rule: the wheel says WHICH
    -- nest, measured from the open point.
    local dx, dy = self:StripOffset()
    if mouseSel and dx then
        local ak = self:ArmedClaim()
        local c = ak and self.claims and self.claims[ak]
        local dp = c and c.base and self:FanSlotOffset(c.parent)
        if dp then
            local fxc, fyc = self.frame:GetCenter()
            if fxc then
                local esc = self.frame:GetEffectiveScale()
                local mxc, myc = GetCursorPosition()
                local ndx, ndy = mxc / esc - fxc, myc / esc - fyc
                local pitch = self:Pitch()
                local sx, sy = 0, 0
                if self:FanHoriz() then
                    sx = dp * pitch
                else
                    sy = -(dp * pitch)
                end
                for jdx = 1, c.n do
                    local b = c.cells[jdx]
                    if abs(ndx - (b.x + sx)) <= b.hw and abs(ndy - (b.y + sy)) <= b.hh then
                        sel = c.base + jdx
                        break
                    end
                end
            end
        end
    elseif claim and dx and claim.base then
        for jdx = 1, claim.n do
            local b = claim.cells[jdx]
            if abs(dx - b.x) <= b.hw and abs(dy - b.y) <= b.hh then
                sel = claim.base + jdx
                break
            end
        end
    end
    -- The strip under the pointer ("Select Action with Mouse"): selection is
    -- EXCLUSIVELY hover -- the entry whose drawn box the pointer is inside,
    -- or nothing at all. The wheel still slides the strip, which changes what
    -- sits under a stationary pointer, but it holds no selection of its own:
    -- pointing away from every icon deselects, and a release there cancels
    -- (the snippet runs this identical test, so drawn and fired agree).
    -- Measured against the SETTLED strip -- fanTarget centred on the FRAME,
    -- full pitch -- from the frame's own centre: the gate point in cursor
    -- mode, the pinned point in Fixed Position, so the test is against what
    -- is actually drawn in both.
    if not sel and target and self.fanTarget and mouseSel then
        local fx2, fy2 = self.frame:GetCenter()
        if fx2 then
            local es2 = self.frame:GetEffectiveScale()
            local mx2, my2 = GetCursorPosition()
            local along, across = mx2 / es2 - fx2, my2 / es2 - fy2
            -- NEGATED dy, not raw: a vertical strip runs DOWNWARD --
            -- ApplyFanGeometry draws positive offsets at -off -- so below
            -- the centre is positive d. Raw dy read the strip mirrored.
            -- The snippet's hover test negates identically (drawn == fired).
            if not self:FanHoriz() then
                along, across = -across, along
            end
            local _, iconSize = self:Geom()
            local pitch = iconSize + ((p2 and p2.fanGap) or 10)
            local skinData = floor(along / pitch + 0.5)
            -- One window everywhere now -- the editor draws it too -- and
            -- the same number the snippet was pushed as eqdFanWin, so drawn
            -- and fired agree.
            local window = (p2 and p2.fanVisible) or 2
            -- Inside the icon's own box on BOTH axes -- the gaps between
            -- icons select nothing -- and only a DRAWN entry, bounded by
            -- the draw cull's own test (k <= window + 0.5): d is an
            -- integer, so a whole window reads the same either way, and a
            -- FRACTIONAL stored window draws out to the rounded edge --
            -- the hover has to accept exactly what is on screen. The fold
            -- bound is the drawing's own asymmetric one: entries land in
            -- (-shown/2, shown/2], so on an even fold the +half slot is a
            -- real icon and the -half slot is empty ground.
            if
                abs(across) <= iconSize * 0.5
                and abs(along - skinData * pitch) <= iconSize * 0.5
                and abs(skinData) <= window + 0.5
                and skinData * 2 <= isShown
                and -skinData * 2 < isShown
            then
                sel = ((self.fanTarget - 1 + skinData) % isShown) + 1
            end
        end
    end
    -- Sticky nest: the reach for a nest's children crosses ground that
    -- hovers NOTHING, and exclusive hover would drop the parent -- and the
    -- children with it -- mid-reach. The ARMED claim is the sticky itself
    -- now: an empty pointer keeps its parent selected, and only entering
    -- another entry's own position moves it on (the lattice disarms there,
    -- arming the new claim if that entry nests). The parent rather than a
    -- lingering child, so drawn == fired holds: a child is chosen strictly
    -- by containment, a parent is a door, and a release over empty ground
    -- cancels on both sides (nothover).
    if not sel and mouseSel then
        local ak = self:ArmedClaim()
        local c = ak and self.claims and self.claims[ak]
        if c and self:FanSlotOffset(c.parent) then
            sel = c.parent
        end
    end
    -- The wheel's entry stands on its own only while the hover channel is
    -- OFF: exclusive hover means an empty pointer selects nothing at all.
    if not sel and target and not mouseSel and not self:FanCancelled() then
        sel = target
    end
    self:SetSelection(sel)

    -- Nested cells. Under the hover channel each claim's children hang off
    -- their parent's DRAWN spot on the strip -- frame-anchored plus the
    -- parent's fold offset, the same anchoring the hit tests measure.
    -- Wheel-only keeps the open-point anchor: the strip's cancel and its
    -- nests are one geometry there.
    local claims = self.claims
    if claims and dx then
        local fx, fy = self.frame:GetCenter()
        local ox, oy = 0, 0
        if not mouseSel and fx then
            ox, oy = self._gateX - fx, self._gateY - fy
        end
        local pitch = self:Pitch()
        local horiz = self:FanHoriz()
        for key = 1, #claims do
            local claim = claims[key]
            local sx, sy = 0, 0
            if mouseSel then
                local dp = self:FanSlotOffset(claim.parent)
                if dp then
                    if horiz then
                        sx = dp * pitch
                    else
                        sy = -(dp * pitch)
                    end
                end
            end
            for jdx = 1, claim.n do
                local wid = claim.base and self.widgets[claim.base + jdx]
                if wid then
                    wid:ClearAllPoints()
                    wid:SetPoint(
                        "CENTER",
                        self.frame,
                        "CENTER",
                        ox + sx + claim.cells[jdx].x,
                        oy + sy + claim.cells[jdx].y
                    )
                end
            end
        end
    end

    local target = self.fanTarget or 1
    local current = self.fanVisual or target
    if current ~= target then
        -- The settle is FIXED at 0.1s (the Settle Time setting was removed;
        -- a fanAnimTime key left in stored profiles is never read).
        current = current + (target - current) * min(1, (elapsed or 0) / 0.1)
        -- Snap the tail: an asymptote would keep this view dirty forever.
        if abs(target - current) < 0.001 then
            current = target
        end
        self.fanVisual = current
        self:ApplyFanGeometry()
    end
end

-- This view's centre as a delta from UIParent's centre, in UIParent-logical
-- units. Both sides are converted through their effective scales because the
-- strip carries the user's own Scale setting while UIParent carries the game's.
function PaletteView:ScreenOffset()
    local widget = self.frame
    local cx, cy = widget:GetCenter()
    if not cx then
        return 0, 0
    end
    local ux, uy = UIParent:GetCenter()
    if not ux then
        return 0, 0
    end

    local key = widget:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * key - ux, cy * key - uy
end

-- Hang the caption on the side that faces the middle of the screen, so a strip
-- opened near an edge writes inward -- where there is room -- instead of off
-- the edge. Justification follows, always hugging the icon it belongs to: the
-- text grows away from the strip, never back across it.
--
-- Called after the frame is POSITIONED, not from Layout alone: in cursor mode
-- the strip lands somewhere new on every open, so the quadrant is only known
-- once PositionPalette has run.
function PaletteView:PlaceHubText()
    local hub = self.hub
    local mode = self:LayoutMode()
    local _, iconSize = self:Geom()
    -- A vertical nudge the view was created with (the options preview drops
    -- its caption 15px so it clears the fitted palette); the hint is anchored
    -- to the text and follows on its own.
    local dyOff = self.opts.hubTextDY or 0

    hub.text:ClearAllPoints()
    hub.hint:ClearAllPoints()

    if mode == "ARC" then
        hub.text:SetJustifyH("CENTER")
        hub.text:SetPoint("CENTER", hub, "CENTER", 0, dyOff)
        hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        return
    end

    -- Half the extent the caption has to clear on its own axis. A strip is one
    -- entry deep, but a grid is as deep as it has rows.
    local pad = iconSize * 0.5 + 14
    if mode == "GRID" then
        local profile = self:P()
        local _, rowList = self:GridDims()
        pad = rowList * (iconSize + ((profile and profile.fanGap) or 10)) * 0.5 + 14
    end
    -- The editor is pinned rather than quadrant-tested: its block sits wherever
    -- the options page happens to be scrolled to, and a caption that jumped
    -- sides as the user scrolled would read as a glitch.
    local dx, dy = 0, 0
    if not self.opts.interactive then
        dx, dy = self:ScreenOffset()
    end

    -- A nest has already claimed one side of the block, so the caption takes the
    -- other -- overriding the quadrant test below, which is about screen room
    -- rather than about what is already sitting there. Written as a nudge to
    -- dx/dy so there is still ONE placement rule underneath: the nest simply
    -- decides which way the block is "facing".
    -- Read against the tests below, which are the other way round from how they
    -- sound: dy < 0 puts the caption ABOVE, so a nest above wants dy positive.
    if self.nestAxis == "X" then
        dy = (self.nestSign > 0) and 1 or -1
    elseif self.nestAxis == "Y" then
        dx = (self.nestSign > 0) and 1 or -1
    end

    -- A grid captions like a horizontal strip: it is as wide as it is tall, so
    -- there is no side with obviously more room, and above/below keeps the text
    -- clear of every cell rather than only of the middle column.
    if mode == "GRID" or (mode == "FAN" and self:FanHoriz()) then
        -- Below the middle of the screen -> caption above the strip.
        hub.text:SetJustifyH("CENTER")
        if dy < 0 then
            hub.text:SetPoint("BOTTOM", hub, "CENTER", 0, pad + dyOff)
            hub.hint:SetPoint("BOTTOM", hub.text, "TOP", 0, 2)
        else
            hub.text:SetPoint("TOP", hub, "CENTER", 0, -pad + dyOff)
            hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)
        end
    else
        -- Right of the middle of the screen -> caption to the LEFT, right
        -- justified so its last character sits against the icon.
        if dx > 0 then
            hub.text:SetJustifyH("RIGHT")
            hub.text:SetPoint("RIGHT", hub, "CENTER", -pad, dyOff)
            hub.hint:SetPoint("TOPRIGHT", hub.text, "BOTTOMRIGHT", 0, -2)
        else
            hub.text:SetJustifyH("LEFT")
            hub.text:SetPoint("LEFT", hub, "CENTER", pad, dyOff)
            hub.hint:SetPoint("TOPLEFT", hub.text, "BOTTOMLEFT", 0, -2)
        end
    end
end

function mod.CreatePaletteView(hostFrame, options)
    local view = setmetatable({
        opts = options or {},
        widgets = {},
        paletteIndex = 1,
        slotCount = 0,
        shownCount = 0,
        -- Only the live palette arms the movement gate (see HitTest); anything
        -- else is steered from the moment it exists.
        _steered = true,
    }, PaletteViewMeta)

    -- A caller can hand in the frame instead of naming one. The live view does,
    -- because where a frame is created decides which addon its handlers are
    -- billed to -- see the top of CludesUIQuickdraw.lua.
    local widget = view.opts.frame
    if widget then
        widget:SetParent(hostFrame)
    else
        widget = CreateFrame("Frame", view.opts.frameName, hostFrame)
    end
    widget:SetSize(1, 1)
    widget:EnableMouse(false)
    view.frame = widget

    -- Hub: the center disc. Shows the selected action's name, or the palette
    -- name when nothing is selected, which is also the "release now cancels"
    -- signal.
    local hub = CreateFrame("Frame", nil, widget)
    hub:SetSize(2, 2)
    hub:SetPoint("CENTER")
    -- Above the entry widgets (created after it, so otherwise over it): the
    -- fan's caption anchors beside the SELECTED icon now, and where a long
    -- name reaches across neighbouring icons it has to stay readable.
    -- Everything else the hub draws sits on ground of its own anyway.
    hub:SetFrameLevel(widget:GetFrameLevel() + 40)
    view.hub = hub

    -- The hub logo (hardcoded art -- its settings were removed). Default
    -- blend mode: this is real artwork with its own alpha, and ADD would
    -- wash out its dark areas into whatever is behind the palette. ARTWORK
    -- so the hub's OVERLAY strings still read on top of it.
    hub.logo = hub:CreateTexture(nil, "ARTWORK")
    hub.logo:SetTexture(
        (CludesUI.MEDIA_PATH or "Interface\\AddOns\\CludesUI\\media\\") .. "logo-full-thin.png"
    )
    hub.logo:SetPoint("CENTER")
    hub.logo:Hide()

    -- The connector line to the selected entry (hub.needle) is built lazily
    -- by EnsureNeedle: a fan never draws one, and neither does a palette with
    -- the option off, so nothing is paid until a line is actually shown.

    hub.text = hub:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AdoptFontString(hub.text)
    hub.text:SetPoint("CENTER", hub, "CENTER", 0, 0)
    hub.text:SetWidth(150)
    hub.text:SetWordWrap(false)

    hub.hint = hub:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    AdoptFontString(hub.hint)
    hub.hint:SetPoint("TOP", hub.text, "BOTTOM", 0, -2)

    -- A per-view bump on the hub caption sizes (the options preview asks for
    -- +2). Folded into the strings' own module-font size so RefreshFonts
    -- keeps the delta across every later font change.
    local fontDelta = view.opts.hubFontDelta
    if fontDelta then
        hub.text.eqdFontSize = (hub.text.eqdFontSize or 12) + fontDelta
        hub.hint.eqdFontSize = (hub.hint.eqdFontSize or 10) + fontDelta
        ApplyModuleFont(hub.text)
        ApplyModuleFont(hub.hint)
    end

    -- The palette's own entries exist from the outset; nested ones are made on
    -- demand, because most palettes hold none and a full set would be another
    -- MAX_SLOTS x MAX_CHILDREN frames per view.
    for index = 1, MAX_SLOTS do
        view.widgets[index] = CreateSlotWidget(view, index)
    end

    views[#views + 1] = view
    return view
end

-- A cell's widget, created if this view has never drawn a cell that far out.
function PaletteView:Widget(index)
    local wid = self.widgets[index]
    if not wid then
        wid = CreateSlotWidget(self, index)
        self.widgets[index] = wid
    end
    return wid
end

Inner.broken = false
