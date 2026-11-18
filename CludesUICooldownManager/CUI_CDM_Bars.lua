if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Bars.lua
--
--  Bar position helpers, BuildCDMBar, LayoutCDMBar and the tooltip state.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor = math.floor

local ECME, FC, IsPlaceholderRenderHidden = Inner.ECME, Inner.FC, Inner.IsPlaceholderRenderHidden
local SnapForScale, _cdmMouseState, _ecmeFC = Inner.SnapForScale, Inner._cdmMouseState, Inner._ecmeFC
local _getFD, barDataByKey, cdmBarFrames = Inner._getFD, Inner.barDataByKey, Inner.cdmBarFrames
local cdmBarIcons = Inner.cdmBarIcons

local BuildCDMBar, LayoutCDMBar

local _CDMApplyVisibility
Inner.SetCDMApplyVisibility = function(func)
    _CDMApplyVisibility = func
end

-------------------------------------------------------------------------------
--  CDM Bar Position Helpers
-------------------------------------------------------------------------------

-- Resolve the frame anchor point for a bar from its growth direction and optional row growth direction.
--
-- Without rowGrowDirection: the single growth edge (RIGHT -> LEFT, DOWN -> TOP, ...) so the
-- fixed edge stays put as the bar resizes along its growth axis; the perpendicular axis stays
-- unpinned (centered), which is why a horizontal bar re-centers vertically when it grows a
-- second row. rowGrowDirection applies the same growth->opposite-edge mapping to the
-- PERPENDICULAR axis, yielding a corner/edge anchor (e.g. TOPLEFT): horizontal bars take "DOWN"
-- (pin TOP) or "UP" (pin BOTTOM); vertical bars take "RIGHT" (pin LEFT) or "LEFT" (pin RIGHT);
-- nil keeps centered growth. Icons lay out from the frame's TOPLEFT, so "UP"/"LEFT" also need
-- LayoutCDMBar's visual row reversal to keep the pinned row's icons from jumping when a row
-- spills in/out. ns.* fields rather than file-scope locals: Lua 5.1's 200-local main-chunk ceiling.
--
-- ignoreRowGrow: resolve the plain growth edge even when a row growth direction is set -- for
-- unlock-snapped bars, whose saved-edge consumers (ApplyAnchorPosition edge preservation/target follow) only understand single-edge points.
function mod.ResolveGrowAnchorPoint(barInfo, ignoreRowGrow)
    local growDir = (barInfo and barInfo.growDirection) or "CENTER"
    local horiz, vert -- "LEFT"/"RIGHT" and "TOP"/"BOTTOM" components
    if growDir == "RIGHT" then
        horiz = "LEFT"
    elseif growDir == "LEFT" then
        horiz = "RIGHT"
    elseif growDir == "DOWN" then
        vert = "TOP"
    elseif growDir == "UP" then
        vert = "BOTTOM"
    end
    local rowGrow = barInfo and barInfo.rowGrowDirection
    if rowGrow and not ignoreRowGrow then
        -- Same opposite-edge mapping applied to the perpendicular axis. The orientation guards keep a value left stale by an orientation flip from clobbering the main-axis component.
        if barInfo.verticalOrientation then
            if rowGrow == "RIGHT" then
                horiz = horiz or "LEFT"
            elseif rowGrow == "LEFT" then
                horiz = horiz or "RIGHT"
            end
        else
            if rowGrow == "DOWN" then
                vert = vert or "TOP"
            elseif rowGrow == "UP" then
                vert = vert or "BOTTOM"
            end
        end
    end
    local point = (vert or "") .. (horiz or "")
    if point == "" then
        return "CENTER"
    end
    return point
end

-- Convert a frame CENTER coord to the coord for anchor point `pt`. An axis with no LEFT/RIGHT
-- (or TOP/BOTTOM) component keeps the center; a zero-extent frame yields a zero offset, so this is safe for empty bars.
function mod.CenterToAnchorCoord(point, x, y, fw, fh)
    local sx, sy = x, y
    if point:find("LEFT", 1, true) then
        sx = x - fw / 2
    elseif point:find("RIGHT", 1, true) then
        sx = x + fw / 2
    end
    if point:find("TOP", 1, true) then
        sy = y + fh / 2
    elseif point:find("BOTTOM", 1, true) then
        sy = y - fh / 2
    end
    return sx, sy
end

-- Inverse of CenterToAnchorCoord: recover the frame CENTER coord from a stored anchor-point coord. Round-trips losslessly for edges, corners, and CENTER.
function mod.AnchorCoordToCenter(point, sx, sy, fw, fh)
    local x, y = sx, sy
    if point:find("LEFT", 1, true) then
        x = sx + fw / 2
    elseif point:find("RIGHT", 1, true) then
        x = sx - fw / 2
    end
    if point:find("TOP", 1, true) then
        y = sy - fh / 2
    elseif point:find("BOTTOM", 1, true) then
        y = sy + fh / 2
    end
    return x, y
end

-- "Additional Bar Offset" (bd.addOffsetX/Y; ADDITIONAL BAR OFFSET options
-- section): a render-only displacement stacked on top of whatever positioned
-- the bar -- saved position, module anchor (party/player/ERB), or the shared
-- unlock anchor system (which folds it through _anchorExtraOffset instead of
-- this helper). Suppressed while unlock mode is active so movers show and save
-- TRUE positions; the shift-provider lifecycle hooks strip it on unlock entry
-- and re-apply it on exit. nil/0 = zero work and zero movement (purely
-- additive feature). On ns: this file is at the 200-local cap.
mod.CDMAddOffset = function(edge)
    if not edge then
        return 0, 0
    end
    local ox = edge.addOffsetX or 0
    local oy = edge.addOffsetY or 0
    if ox == 0 and oy == 0 then
        return 0, 0
    end
    if CludesUI._unlockActive then
        return 0, 0
    end
    return ox, oy
end

local function ApplyBarPositionCentered(widget, place, barId)
    if not place or not place.point then
        return
    end
    local fw = widget:GetWidth() or 0
    local fh = widget:GetHeight() or 0
    local pixelX, pixelY = place.x or 0, place.y or 0
    local anchorFrame = place.point
    local edge = barId and barDataByKey[barId]

    -- Corner-capable re-derivation, taken ONLY when a row growth direction is in play (or the
    -- stored point is a leftover corner): recover the frame center from the stored anchor coord,
    -- then re-project onto the anchor resolved from the bar's CURRENT growth + row growth.
    -- Lossless round-trip -- the bar does not move, only the pinned edge/corner changes. Bars without a row growth direction take the conversion below. No persistence: positions are only saved by unlock mode's Save & Exit.
    local storedIsCorner = (anchorFrame:find("TOP", 1, true) or anchorFrame:find("BOTTOM", 1, true))
        and (anchorFrame:find("LEFT", 1, true) or anchorFrame:find("RIGHT", 1, true))
    if (edge and edge.rowGrowDirection) or storedIsCorner then
        local cx, cy = mod.AnchorCoordToCenter(anchorFrame, pixelX, pixelY, fw, fh)
        anchorFrame = mod.ResolveGrowAnchorPoint(edge)
        pixelX, pixelY = mod.CenterToAnchorCoord(anchorFrame, cx, cy, fw, fh)
    elseif anchorFrame == "CENTER" and barId then
        -- Runtime conversion: a non-CENTER-grow bar with a CENTER position (legacy data,
        -- Blizzard import) converts to edge format for SetPoint so it grows from the correct edge.
        local growDir = edge and edge.growDirection or "CENTER"
        if growDir ~= "CENTER" then
            if growDir == "RIGHT" and fw > 0 then
                anchorFrame = "LEFT"
                pixelX = pixelX - fw / 2
            elseif growDir == "LEFT" and fw > 0 then
                anchorFrame = "RIGHT"
                pixelX = pixelX + fw / 2
            elseif growDir == "DOWN" and fh > 0 then
                anchorFrame = "TOP"
                pixelY = pixelY + fh / 2
            elseif growDir == "UP" and fh > 0 then
                anchorFrame = "BOTTOM"
                pixelY = pixelY - fh / 2
            end
        end
    end

    -- Additional Bar Offset: applied PRE-snap so the sum lands on the pixel
    -- grid; a zero offset is a guaranteed no-op.
    local aox, aoy = mod.CDMAddOffset(edge)
    pixelX, pixelY = pixelX + aox, pixelY + aoy

    -- Snap to physical pixel grid. CENTER anchor: SnapCenterForDim preserves the +0.5 offset
    -- odd-pixel-dim frames need for whole-pixel edges. Single-edge anchors: the growth-axis
    -- coord is an EDGE (whole-pixel snap) but the perpendicular coord is the frame's CENTER on
    -- that axis -- parity-aware snap keeps whole-pixel edges there too. Corner anchors (row growth pin) are edges on BOTH axes.
    local PPa = CludesUI and CludesUI.PP
    if PPa then
        local effScale = widget:GetEffectiveScale()
        if anchorFrame == "CENTER" and PPa.SnapCenterForDim then
            pixelX = PPa.SnapCenterForDim(pixelX, fw, effScale)
            pixelY = PPa.SnapCenterForDim(pixelY, fh, effScale)
        elseif PPa.SnapForES then
            if PPa.SnapCenterForDim and (anchorFrame == "LEFT" or anchorFrame == "RIGHT") then
                pixelX = PPa.SnapForES(pixelX, effScale)
                pixelY = PPa.SnapCenterForDim(pixelY, fh, effScale)
            elseif PPa.SnapCenterForDim and (anchorFrame == "TOP" or anchorFrame == "BOTTOM") then
                pixelX = PPa.SnapCenterForDim(pixelX, fw, effScale)
                pixelY = PPa.SnapForES(pixelY, effScale)
            else
                pixelX = PPa.SnapForES(pixelX, effScale)
                pixelY = PPa.SnapForES(pixelY, effScale)
            end
        end
    end

    widget:ClearAllPoints()
    widget:SetPoint(anchorFrame, UIParent, place.relPoint or anchorFrame, pixelX, pixelY)
end

local function SaveCDMBarPosition(barId, widget)
    if not widget then
        return
    end
    local p = ECME.db.profile
    local scale = widget:GetScale() or 1
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = widget:GetEffectiveScale()
    local uiW, uiH = UIParent:GetSize()
    local ratio = fScale / uiScale

    -- Anchor point from grow + row growth direction, so the bar's fixed edge/corner stays put when icon count changes (spec swaps, combat buff churn, a row spilling in/out).
    local edge = barDataByKey[barId]
    local point = mod.ResolveGrowAnchorPoint(edge)

    -- Read each axis from the matching frame edge (corner points pin both).
    local cx, cy = widget:GetCenter()
    if not cx or not cy then
        return
    end
    local ax, ay
    if point:find("LEFT", 1, true) then
        local lx = widget:GetLeft()
        if not lx then
            return
        end
        ax = lx * ratio
    elseif point:find("RIGHT", 1, true) then
        local rx = widget:GetRight()
        if not rx then
            return
        end
        ax = rx * ratio
    else
        ax = cx * ratio
    end
    if point:find("TOP", 1, true) then
        local ty = widget:GetTop()
        if not ty then
            return
        end
        ay = ty * ratio
    elseif point:find("BOTTOM", 1, true) then
        local by = widget:GetBottom()
        if not by then
            return
        end
        ay = by * ratio
    else
        ay = cy * ratio
    end

    -- Store relative to UIParent CENTER so offset math is consistent.
    -- Additional Bar Offset: live geometry includes the render-only offset
    -- while out of unlock mode -- subtract it so the SAVED position is always
    -- the BASE (else the Row Growth recapture bakes it in and the bar drifts
    -- by one offset per edit). In unlock mode both terms are already base:
    -- the frame carries no offset and CDMAddOffset returns 0.
    local aox, aoy = mod.CDMAddOffset(edge)
    p.cdmBarPositions[barId] = {
        point = point,
        relPoint = "CENTER",
        x = (ax - uiW / 2) / scale - aox,
        y = (ay - uiH / 2) / scale - aoy,
    }
end

-- Re-persist a bar's saved position in its CURRENT anchor format from live geometry. Needed
-- when the row growth direction changes: a stored center/single-edge position can't pin the
-- row edge across row changes (only a stored corner can), so recapture the corner from where
-- the bar sits now. Free-standing bars only -- snapped bars are owned by the unlock anchor system, which reads unlockAnchors, not cdmBarPositions.
function mod.RecaptureBarAnchor(barId)
    local widget = cdmBarFrames[barId]
    if not widget then
        return
    end
    -- anchorTo bars (cursor, party/player frame, ERB, another bar) are positioned by their
    -- anchor, not cdmBarPositions -- saving live geometry would overwrite the free-standing position with the anchored spot.
    local edge = barDataByKey[barId]
    if edge and edge.anchorTo and edge.anchorTo ~= "none" then
        return
    end
    if CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("CDM_" .. barId) then
        return
    end
    if not widget:GetLeft() then
        return
    end
    SaveCDMBarPosition(barId, widget)
end

-------------------------------------------------------------------------------
--  Frame anchor point for a CDM bar: the near-edge center (the edge facing away
--  from the target). RIGHT -> LEFT, LEFT -> RIGHT, DOWN -> TOP, UP -> BOTTOM.
-------------------------------------------------------------------------------
local function CDMFrameAnchorPoint(anchorSide, growDir, centered)
    if growDir == "RIGHT" then
        return "LEFT"
    end
    if growDir == "LEFT" then
        return "RIGHT"
    end
    if growDir == "DOWN" then
        return "TOP"
    end
    if growDir == "UP" then
        return "BOTTOM"
    end
    if growDir == "CENTER" then
        return "CENTER"
    end
    return "CENTER"
end

-------------------------------------------------------------------------------
--  Recursive click-through helper -- disables/restores mouse on a frame tree
-------------------------------------------------------------------------------
local function SetFrameClickThrough(widget, clickThrough)
    if not widget then
        return
    end
    if clickThrough then
        if _cdmMouseState[widget] == nil then
            _cdmMouseState[widget] = widget:IsMouseEnabled()
        end
        widget:EnableMouse(false)
        if widget.EnableMouseClicks then
            widget:EnableMouseClicks(false)
        end
        if widget.EnableMouseMotion then
            widget:EnableMouseMotion(false)
        end
    else
        if _cdmMouseState[widget] ~= nil then
            widget:EnableMouse(_cdmMouseState[widget])
            _cdmMouseState[widget] = nil
        end
    end
    for _, childFrame in ipairs({ widget:GetChildren() }) do
        SetFrameClickThrough(childFrame, clickThrough)
    end
end

-------------------------------------------------------------------------------
--  Build a single CDM bar frame
-------------------------------------------------------------------------------
BuildCDMBar = function(barIndex)
    local p = ECME.db.profile
    local barList = p.cdmBars.bars
    local barInfo = barList[barIndex]
    if not barInfo then
        return
    end

    local barKey = barInfo.key
    local widget = cdmBarFrames[barKey]

    if not widget then
        widget = CreateFrame("Frame", "ECME_CDMBar_" .. barKey, UIParent)
        -- Per-bar Bar Strata (Extras); MEDIUM = the historical hardcoded value.
        widget:SetFrameStrata(barInfo.barStrata or "MEDIUM")
        widget:SetFrameLevel(5)
        if widget.SetSnapToPixelGrid then
            widget:SetSnapToPixelGrid(false)
        end
        if widget.SetTexelSnappingBias then
            widget:SetTexelSnappingBias(0)
        end
        if widget.EnableMouseClicks then
            widget:EnableMouseClicks(false)
        end
        -- Containers NEVER capture mouse motion: the rect spans the bar's full layout area and a
        -- motion-enabled frame with no unit steals mouseover focus from unit frames underneath. Hover is managed per-icon, gated on the bar's tooltip setting.
        if widget.EnableMouseMotion then
            widget:EnableMouseMotion(false)
        end
        widget._barKey = barKey
        widget._barIndex = barIndex
        cdmBarFrames[barKey] = widget
        cdmBarIcons[barKey] = {}
    end

    if not barInfo.enabled then
        if widget._mouseTrack then
            widget:SetScript("OnUpdate", nil)
            if CludesUI.Mouse then
                CludesUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(barKey))
                CludesUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(barKey) .. ":watch")
            end
            widget._mouseResume = nil
            widget._mouseTrack = nil
            if widget._preMousePos and not p.cdmBarPositions[barKey] then
                p.cdmBarPositions[barKey] = widget._preMousePos
            end
            widget._preMousePos = nil
            SetFrameClickThrough(widget, false)
            if widget.EnableMouseMotion then
                widget:EnableMouseMotion(false)
            end
        end
        CludesUI.SetElementVisibility(widget, false)
        return
    end

    -- All sizing is width/height based; scale stays 1.
    if not InCombatLockdown() then
        widget:SetScale(1)
    end

    -- Restore configured strata/level (cursor-anchored uses TOOLTIP/9980)
    if not widget._mouseTrack then
        widget:SetFrameStrata(barInfo.barStrata or "MEDIUM")
        widget:SetFrameLevel(5)
    end

    -- Clear any previous mouse-tracking subscriptions
    if widget._mouseTrack then
        widget:SetScript("OnUpdate", nil)
        if CludesUI.Mouse then
            CludesUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(barKey))
            CludesUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(barKey) .. ":watch")
        end
        widget._mouseResume = nil
        widget._mouseTrack = nil
        -- Restore position/strata/mouse from before the cursor anchor
        if widget._preMousePos and not p.cdmBarPositions[barKey] then
            p.cdmBarPositions[barKey] = widget._preMousePos
        end
        widget._preMousePos = nil
        widget:SetFrameStrata(barInfo.barStrata or "MEDIUM")
        widget:SetFrameLevel(5)
        SetFrameClickThrough(widget, false)
        if widget.EnableMouseMotion then
            widget:EnableMouseMotion(false)
        end
    end
    widget._mouseGrow = nil

    -- FocusKick bar is exclusively owned by ApplyFocusKickAnchor: skipping the generic position
    -- block keeps the else-branch default from snapping it to UIParent CENTER 0,0 between a rebuild and the next nameplate event. Literal key: FOCUSKICK_BAR_KEY is declared later and would be nil here.
    if barKey == "focuskick" then
        widget:Show()
        return
    end

    -- Cursor-anchored bar already tracking and still configured for mouse: skip the
    -- teardown+rebuild cycle. It is already repositioning correctly, and tearing it down blinks to BOTTOMLEFT 0,0 on every FullCDMRebuild.
    if widget._mouseTrack and barInfo.anchorTo == "mouse" then
        widget:Show()
        return
    end

    -- Position
    local anchorKey = barInfo.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position for restore on unanchor
        if p.cdmBarPositions[barKey] then
            widget._preMousePos = p.cdmBarPositions[barKey]
        end
        -- Anchor position acts as build direction for cursor tracking
        local anchorPoint = barInfo.anchorPosition or "right"
        local offX = barInfo.anchorOffsetX or 0
        local offY = barInfo.anchorOffsetY or 0
        -- SetPoint anchor + 15px directional nudge
        local pointFrom, baseOX, baseOY, forceGrow
        if anchorPoint == "left" then
            pointFrom = "RIGHT"
            forceGrow = "LEFT"
            baseOX = -15 + offX
            baseOY = offY
        elseif anchorPoint == "right" then
            pointFrom = "LEFT"
            forceGrow = "RIGHT"
            baseOX = 15 + offX
            baseOY = offY
        elseif anchorPoint == "top" then
            pointFrom = "BOTTOM"
            forceGrow = "UP"
            baseOX = offX
            baseOY = 15 + offY
        elseif anchorPoint == "bottom" then
            pointFrom = "TOP"
            forceGrow = "DOWN"
            baseOX = offX
            baseOY = -15 + offY
        else
            pointFrom = "LEFT"
            forceGrow = "RIGHT"
            baseOX = 15 + offX
            baseOY = offY
        end
        widget._mouseGrow = forceGrow
        widget._mousePoint = pointFrom -- park/heal sites outside this closure need it
        -- TOOLTIP strata so the bar renders above all UI; fully click-through (frame + children) while following the cursor.
        widget:SetFrameStrata("TOOLTIP")
        widget:SetFrameLevel(9980)
        SetFrameClickThrough(widget, true)
        local lastMX, lastMY
        widget:ClearAllPoints()
        widget:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        widget._mouseTrack = true
        widget._mouseHiddenByPanel = false
        -- Cursor glue rides the suite Mouse service (CludesUI_Mouse.lua): per render frame
        -- while the cursor MOVES (position must track raw -- easing/deferral shows cadence
        -- stepping), parked by the service while still or mouselooking, re-armed within one 20 Hz
        -- watch interval of the first moved pixel. The 0.15s CursorWatch below owns panel/unlock/visibility state, so the glue body is position-only.
        local glueKey = "cdmCursor:" .. tostring(barKey)
        local Mouse = CludesUI.Mouse
        local glueActive = false
        local function CursorGlue(cx, cy)
            if cx ~= lastMX or cy ~= lastMY then
                local firstMove = lastMX == nil
                lastMX, lastMY = cx, cy
                local s = UIParent:GetEffectiveScale()
                if firstMove then
                    widget:ClearAllPoints()
                end
                widget:SetPoint(
                    pointFrom,
                    UIParent,
                    "BOTTOMLEFT",
                    floor(cx / s + 0.5) + baseOX,
                    floor(cy / s + 0.5) + baseOY
                )
            end
        end
        widget._mouseResume = function()
            lastMX, lastMY = nil, nil
            widget._mouseParked = false
            glueActive = true
            Mouse.SubscribeFrame(glueKey, CursorGlue, true)
        end
        local function GlueOff()
            if glueActive then
                glueActive = false
                Mouse.UnsubscribeFrame(glueKey)
            end
        end
        local function CursorWatch()
            -- Hide while the CUI options panel or unlock mode is open
            local panelOpen = (CludesUI._mainFrame and CludesUI._mainFrame:IsShown())
                or CludesUI._unlockActive
            if panelOpen then
                GlueOff()
                widget._mouseHiddenByPanel = true
                if widget:GetAlpha() > 0 then
                    widget:SetAlpha(0)
                end
                local iconList = cdmBarIcons[barKey]
                if iconList then
                    for iconIndex = 1, #iconList do
                        if iconList[iconIndex] and iconList[iconIndex]:GetFrameStrata() == "TOOLTIP" then
                            iconList[iconIndex]:SetFrameStrata(barInfo.barStrata or "MEDIUM")
                            iconList[iconIndex]:SetFrameLevel(5 + iconIndex)
                        end
                    end
                end
                return
            elseif widget._mouseHiddenByPanel then
                -- Panel just closed: restore visibility and icon strata
                widget._mouseHiddenByPanel = false
                local iconList = cdmBarIcons[barKey]
                if iconList then
                    for iconIndex = 1, #iconList do
                        if iconList[iconIndex] then
                            iconList[iconIndex]:SetFrameStrata("TOOLTIP")
                            iconList[iconIndex]:SetFrameLevel(9980 + iconIndex)
                        end
                    end
                end
                _CDMApplyVisibility()
            end
            -- Visibility-hidden: park the bar offscreen instead of tracking the cursor. Alpha
            -- alone CANNOT keep icons invisible -- the engine re-raises item alpha through paths
            -- no hook sees (SetAlphaFromBoolean, alpha animations) on cooldown/aura state changes,
            -- so a hidden bar flashes back mid-screen riding the cursor (same lesson as the
            -- unclaimed-frame park in CludesUICdmHooks). Icons anchor to this container so the park carries them, immune to every alpha path. Movers-while-parked heal via ns._parkEdges + the LayoutCDMBar guard -- no patrol.
            if widget._visHidden then
                GlueOff()
                if not widget._mouseParked or (widget:GetLeft() or 0) > -9000 then
                    widget._mouseParked = true
                    lastMX, lastMY = nil, nil
                    widget:ClearAllPoints()
                    widget:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", -10000, -10000)
                end
                return
            end
            -- Visible and unobstructed: ensure the glue rides the service (covers the visibility show edge and setup re-runs; resume snaps to the cursor via the lastMX reset).
            if widget._mouseParked or not glueActive then
                widget._mouseResume()
            end
            -- Mouse-through re-assert: the Decorate/Show/Cooldown path can re-enable mouse on
            -- icons mid-session, and an icon riding the cursor with mouse enabled intermittently
            -- kills [@mouseover] hovercast keys. MUST live here (0.15s, motion-independent) not in the glue: cooldown repaints re-enable mouse with the cursor perfectly still. Cheap no-op when state is clean.
            local iconList = cdmBarIcons[barKey]
            if iconList then
                for iconIndex = 1, #iconList do
                    local ic = iconList[iconIndex]
                    if ic then
                        if ic:IsMouseEnabled() then
                            ic:EnableMouse(false)
                        end
                        if ic.IsMouseMotionEnabled and ic:IsMouseMotionEnabled() then
                            ic:EnableMouseMotion(false)
                        end
                    end
                end
            end
        end
        Mouse.SubscribeTick(glueKey .. ":watch", 0.15, CursorWatch)
        CursorWatch()
    elseif anchorKey == "partyframe" then
        local partyFrame = CludesUI.FindPlayerPartyFrame()
        if partyFrame then
            widget:ClearAllPoints()
            local edgeSide = barInfo.partyFrameSide or "LEFT"
            local offX = barInfo.partyFrameOffsetX or 0
            local offY = barInfo.partyFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = mod.CDMAddOffset(barInfo)
                offX, offY = offX + aox, offY + aoy
            end
            local PPa = CludesUI and CludesUI.PP
            if PPa and PPa.SnapForES then
                local effScale = widget:GetEffectiveScale()
                offX = PPa.SnapForES(offX, effScale)
                offY = PPa.SnapForES(offY, effScale)
            end
            local growDir = barInfo.growDirection or "CENTER"
            local centered = barInfo.growCentered ~= false
            local fp = CDMFrameAnchorPoint(edgeSide, growDir, centered)
            widget._anchorSide = edgeSide:upper()
            if edgeSide == "LEFT" then
                widget:SetPoint(fp, partyFrame, "LEFT", offX, offY)
            elseif edgeSide == "RIGHT" then
                widget:SetPoint(fp, partyFrame, "RIGHT", offX, offY)
            elseif edgeSide == "TOP" then
                widget:SetPoint(fp, partyFrame, "TOP", offX, offY)
            elseif edgeSide == "BOTTOM" then
                widget:SetPoint(fp, partyFrame, "BOTTOM", offX, offY)
            end
        else
            -- No party frame: fall back to saved position
            local place = p.cdmBarPositions[barKey]
            if place and place.point then
                ApplyBarPositionCentered(widget, place, barKey)
            else
                widget:ClearAllPoints()
                widget:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        local playerFrame = CludesUI.FindPlayerUnitFrame()
        if playerFrame then
            widget:ClearAllPoints()
            local edgeSide = barInfo.playerFrameSide or "LEFT"
            local offX = barInfo.playerFrameOffsetX or 0
            local offY = barInfo.playerFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = mod.CDMAddOffset(barInfo)
                offX, offY = offX + aox, offY + aoy
            end
            local PPa = CludesUI and CludesUI.PP
            if PPa and PPa.SnapForES then
                local effScale = widget:GetEffectiveScale()
                offX = PPa.SnapForES(offX, effScale)
                offY = PPa.SnapForES(offY, effScale)
            end
            local growDir = barInfo.growDirection or "CENTER"
            local centered = barInfo.growCentered ~= false
            local fp = CDMFrameAnchorPoint(edgeSide, growDir, centered)
            widget._anchorSide = edgeSide:upper()
            if edgeSide == "LEFT" then
                widget:SetPoint(fp, playerFrame, "LEFT", offX, offY)
            elseif edgeSide == "RIGHT" then
                widget:SetPoint(fp, playerFrame, "RIGHT", offX, offY)
            elseif edgeSide == "TOP" then
                widget:SetPoint(fp, playerFrame, "TOP", offX, offY)
            elseif edgeSide == "BOTTOM" then
                widget:SetPoint(fp, playerFrame, "BOTTOM", offX, offY)
            end
        else
            -- No player frame: fall back to saved position
            local place = p.cdmBarPositions[barKey]
            if place and place.point then
                ApplyBarPositionCentered(widget, place, barKey)
            else
                widget:ClearAllPoints()
                widget:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to Resource Bars frames
        local erbFrameNames = {
            erb_castbar = "ERB_CastBarFrame",
            erb_powerbar = "ERB_PrimaryBar",
            erb_classresource = "ERB_SecondaryFrame",
        }
        local erbFrame = _G[erbFrameNames[anchorKey]]
        if erbFrame then
            local anchorPoint = barInfo.anchorPosition or "left"
            widget:ClearAllPoints()
            local gap = barInfo.spacing or 2
            local offX = barInfo.anchorOffsetX or 0
            local offY = barInfo.anchorOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = mod.CDMAddOffset(barInfo)
                offX, offY = offX + aox, offY + aoy
            end
            local PPa = CludesUI and CludesUI.PP
            if PPa and PPa.SnapForES then
                local effScale = widget:GetEffectiveScale()
                gap = PPa.SnapForES(gap, effScale)
                offX = PPa.SnapForES(offX, effScale)
                offY = PPa.SnapForES(offY, effScale)
            end
            local growDir = barInfo.growDirection or "CENTER"
            local centered = barInfo.growCentered ~= false
            local fp = CDMFrameAnchorPoint(anchorPoint:upper(), growDir, centered)
            widget._anchorSide = anchorPoint:upper()
            local success
            if anchorPoint == "left" then
                success = pcall(widget.SetPoint, widget, fp, erbFrame, "LEFT", -gap + offX, offY)
            elseif anchorPoint == "right" then
                success = pcall(widget.SetPoint, widget, fp, erbFrame, "RIGHT", gap + offX, offY)
            elseif anchorPoint == "top" then
                success = pcall(widget.SetPoint, widget, fp, erbFrame, "TOP", offX, gap + offY)
            elseif anchorPoint == "bottom" then
                success = pcall(widget.SetPoint, widget, fp, erbFrame, "BOTTOM", offX, -gap + offY)
            end
            -- Circular anchor: fall back to center
            if not success then
                widget:ClearAllPoints()
                widget:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- ERB frame unavailable: fall back to saved position
            local place = p.cdmBarPositions[barKey]
            if place and place.point then
                ApplyBarPositionCentered(widget, place, barKey)
            else
                widget:ClearAllPoints()
                widget:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    else
        -- Unlock-anchored and already positioned: DO NOT touch the position. ApplyAnchorPosition/
        -- PropagateAnchorChain are authoritative there. A rebuild falling into the "no saved pos"
        -- branch below would teleport the bar to a hardcoded default (e.g. CENTER 0,-275), and if
        -- the anchor target is temporarily unavailable (hidden frame, pre-layout race) the later re-anchor bails and the bar stays stuck at that fallback.
        local unlockKey = "CDM_" .. barKey
        local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(unlockKey)
        if anchored and widget:GetLeft() then
            -- Unlock-anchored and already has bounds: leave position alone.
        else
            local place = p.cdmBarPositions[barKey]
            if place and place.point then
                ApplyBarPositionCentered(widget, place, barKey)
            elseif not anchored then
                -- Defaults: only for truly un-anchored bars with no saved pos.
                widget:ClearAllPoints()
                if barKey == "cooldowns" then
                    widget:SetPoint("CENTER", UIParent, "CENTER", 0, -275)
                elseif barKey == "utility" then
                    widget:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
                elseif barKey == "buffs" then
                    widget:SetPoint("CENTER", UIParent, "CENTER", 0, -365)
                else
                    widget:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end
            end
            -- Anchored with no bounds yet: NO fallback position. ReapplyOwnAnchor runs
            -- after BuildAllCDMBars and places the frame once the target is available.
        end
    end

    -- Always Show() so layout/children work; _CDMApplyVisibility is the single
    -- authority for alpha/hiding.
    widget:Show()
end

-- True when this bar renders data rows in REVERSED visual order: row growth "UP" (horizontal)/
-- "LEFT" (vertical) pins the trailing edge (BOTTOM/RIGHT), so the base (first data) row hugs it
-- and extra rows grow away. Shared by the layout and the options preview so both agree. ns.* field: 200-local cap.
function mod.CDMRowsReversed(barInfo)
    if not barInfo then
        return false
    end
    local growDir = barInfo.growDirection or "CENTER"
    local horizontal = (
        growDir == "RIGHT"
        or growDir == "LEFT"
        or (growDir == "CENTER" and not barInfo.verticalOrientation)
    )
    if horizontal then
        return barInfo.rowGrowDirection == "UP"
    end
    return barInfo.rowGrowDirection == "LEFT"
end

-- Stride respecting the custom row-count override (numRows == 2 only). Two MUTUALLY EXCLUSIVE
-- overrides both resolve to the BASE row count -- the first DATA row: it fills first and is the
-- row a Row Growth pin keeps in place (on top normally, bottom/right when the visual row order is reversed):
--   * Custom Base Row Count -> topRowCount icons on the base row.
--   * Custom Bottom Row Count (UI removed) -> bottomRowCount icons on the second row; the base row gets the remainder.
-- Mutual exclusivity is enforced in options; if both are set, base wins.
local function ComputeTopRowStride(barInfo, total)
    local numRows = barInfo.numRows or 1
    if numRows < 1 then
        numRows = 1
    end
    if numRows == 2 then
        local topCount
        if barInfo.customTopRowEnabled and barInfo.topRowCount and barInfo.topRowCount > 0 then
            topCount = math.min(barInfo.topRowCount, total)
        elseif barInfo.customBottomRowEnabled and barInfo.bottomRowCount and barInfo.bottomRowCount > 0 then
            topCount = total - math.min(barInfo.bottomRowCount, total)
        end
        if topCount then
            if topCount < 0 then
                topCount = 0
            end
            local bottomCount = total - topCount
            -- Custom-row mode uses a second row only once BOTH rows are non-empty; until then report ONE effective row so the bar doesn't reserve or lay out an empty row.
            if bottomCount <= 0 or topCount <= 0 then
                return total, 1, total
            end
            return math.max(topCount, bottomCount), numRows, topCount
        end
    end
    local stride = math.ceil(total / numRows)
    local topCount = total - (numRows - 1) * stride
    if topCount < 0 then
        topCount = 0
    end
    return stride, numRows, topCount
end

-- Minimum Bar Size, counted in icon slots along the GROWTH axis. That axis is ALWAYS the `stride`
-- term of the size formulas (width on horizontal bars, height on vertical), so one rule covers both
-- orientations. Returns the stride the CONTAINER reserves; the LAYOUT stride is never replaced --
-- grid wrapping (col = idx % stride) and per-row centering keep using the real icon count, and the
-- reserved surplus becomes a single centering offset. nil/0 (the default) is a straight passthrough.
local function ReserveStride(barInfo, stride)
    local minN = barInfo.minSizeIcons
    if minN and minN > stride then
        return minN
    end
    return stride
end

-- Empty custom bars still need a stable footprint so unlock mode can keep a visible mover and convert drag positions correctly before any icons exist.
local EMPTY_CDM_BAR_SIZE = { 100, 36 }

-- Count spell entries contributing real icon slots. Unlock mode uses this to estimate a footprint before the live frame has been laid out (common for freshly created Misc bars).
local function CountCDMBarSpells(barId)
    local total = 0
    local sd = mod.GetBarSpellData(barId)
    if not sd or not sd.assignedSpells then
        return 0
    end
    for _, spellRef in ipairs(sd.assignedSpells) do
        if spellRef and spellRef ~= 0 then
            total = total + 1
        end
    end
    return total
end

local function ComputeCDMBarSize(barInfo, total)
    -- Raw coord values -- see LayoutCDMBar for why we never pre-snap here.
    local iW = barInfo.iconSize or 36
    local iH = iW
    if (barInfo.iconShape or "none") == "cropped" then
        iH = math.floor((barInfo.iconSize or 36) * mod.CdmCropFactor(barInfo) + 0.5)
    end
    local sp = barInfo.spacing or 2
    -- EFFECTIVE row count from ComputeTopRowStride: collapses to 1 while a
    -- custom top-row split's second row is empty, so no empty row is reserved.
    local stride, rowList = ComputeTopRowStride(barInfo, total)
    if rowList < 1 then
        rowList = 1
    end
    -- Minimum Bar Size reserves extra growth-axis slots (no-op when unset). Unlike LayoutCDMBar
    -- there is no match gate here: this is the pre-layout footprint estimate, and a matched bar's live frame rect (checked first by GetStableCDMBarSize) always wins over it.
    local resStride = ReserveStride(barInfo, stride)
    local growDir = barInfo.growDirection or "CENTER"
    -- Same orientation rule as LayoutCDMBar: a centred bar grows along its orientation.
    local isH = (growDir == "RIGHT" or growDir == "LEFT" or (growDir == "CENTER" and not barInfo.verticalOrientation))
    if isH then
        return resStride * iW + (resStride - 1) * sp, rowList * iH + (rowList - 1) * sp
    end
    return rowList * iW + (rowList - 1) * sp, resStride * iH + (resStride - 1) * sp
end

-- Authoritative footprint for unlock mode: live frame when it has bounds, else derived from bar config, else the stable empty-bar placeholder.
local function GetStableCDMBarSize(barId, widget, barInfo)
    if widget then
        local wid, hgt = widget:GetWidth() or 0, widget:GetHeight() or 0
        if wid > 1 and hgt > 1 then
            return wid, hgt
        end
    end

    local total = CountCDMBarSpells(barId)
    if barInfo and total > 0 then
        return ComputeCDMBarSize(barInfo, total)
    end

    -- Buff-family/custom-buff bars have no assigned spells (icons are auras added live), so
    -- before the first aura count is 0. Size from one icon's configured dimensions so the empty frame -- and the unlock overlay mirroring it -- reflect icon size, not the generic placeholder.
    if
        barInfo
        and ((mod.IsBarBuffFamily and mod.IsBarBuffFamily(barInfo)) or barInfo.barType == "custom_buff")
    then
        return ComputeCDMBarSize(barInfo, 1)
    end

    return EMPTY_CDM_BAR_SIZE[1], EMPTY_CDM_BAR_SIZE[2]
end

-- A width/height match target that draws inside a larger box (getInsets:
-- Blizzard Style unit frames) matches by its visible art, converted into the
-- bar's scale, as the unlock-mode match does. nil for every other target (the
-- raw frame read stands).
function mod.CdmMatchInsetSize(targetKey, targetFrame, barFrame)
    local elementList = CludesUI._unlockRegisteredElements
    local elem = elementList and elementList[targetKey]
    if not (elem and elem.getInsets) then
        return nil
    end
    local l, region, t, b = elem.getInsets(targetKey)
    if not l then
        return nil
    end
    local k = targetFrame:GetEffectiveScale() / barFrame:GetEffectiveScale()
    return (targetFrame:GetWidth() - l - region) * k, (targetFrame:GetHeight() - t - b) * k
end

-- "CDM_" .. barKey, built once per bar key, so the layout and pad paths look a
-- bar's unlock element up without building a string each pass.
mod._cdmUKey = setmetatable({}, {
    __index = function(t, k)
        local val = "CDM_" .. k
        t[k] = val
        return val
    end,
})

-- The width and height a CDM bar's own textured icon border draws OUTSIDE the
-- bar frame, in bar units, from exactly the arguments the icon border renderer
-- passes (bar-level size, texture, offsets and shifts, the "cdm" registry keyed
-- by the thickness label, the exact px, the colour's alpha). The outer icons sit
-- flush with the bar's edges, so their reach is the bar's. The renderer
-- normalizes the icon's scale away (UIParent / icon), so in bar units the ratio
-- is UIParent / bar. nil for buff-family bars (never in a match), the stock
-- looks (no CUI border), custom shapes (the ring sits inside the icon) and a
-- border that draws nothing outside. Reads settings and scales only.
function mod.CdmBarMatchPad(barId)
    local edge = barDataByKey[barId]
    local frame = cdmBarFrames[barId]
    if not edge or not frame or not CludesUI.BorderMatchPad then
        return nil
    end
    local texture = edge.borderTexture or "solid"
    if texture == "solid" then
        return nil
    end
    if mod.IsBarBuffFamily(edge) or edge.barType == "custom_buff" then
        return nil
    end
    if mod.CdmBlizzIcons() then
        return nil
    end
    local shape = edge.iconShape or "none"
    if shape ~= "none" and shape ~= "cropped" then
        return nil
    end
    local effScale, uiES = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local ratio = 1
    if effScale and effScale > 0.01 and uiES and uiES > 0 then
        ratio = uiES / effScale
    end
    local sz = edge.borderSize or 1
    return CludesUI.BorderMatchPad(
        sz,
        texture,
        edge.borderTextureOffset,
        edge.borderTextureOffsetY,
        edge.borderTextureShiftX,
        edge.borderTextureShiftY,
        "cdm",
        edge.borderThickness or "thin",
        CludesUI.BorderPx(edge.borderSizePx, sz, texture),
        ratio,
        edge.borderA or 1
    )
end

-- Border-aware CDM match, added to LayoutCDMBar's raw target read in the same
-- units: what the target draws outside its own rect (its getMatchPad on this
-- axis; 0 when its inset art was read, which already is the visible size) minus
-- what this bar's own icon border draws outside. Only positive pads count, as in
-- the unlock-mode match. Exactly 0 when neither side has one.
function mod.CdmMatchAdj(barId, targetKey, isWidth, insetUsed)
    local t, o = 0, 0
    if not insetUsed then
        local elementList = CludesUI._unlockRegisteredElements
        local elem = elementList and elementList[targetKey]
        if elem and elem.getMatchPad then
            local pw, ph = elem.getMatchPad(targetKey)
            local val
            if isWidth then
                val = pw
            else
                val = ph
            end
            if val and val > 0 then
                t = val
            end
        end
    end
    local ow, oh = mod.CdmBarMatchPad(barId)
    local val
    if isWidth then
        val = ow
    else
        val = oh
    end
    if val and val > 0 then
        o = val
    end
    return t - o
end

-------------------------------------------------------------------------------
--  Layout icons within a CDM bar
-------------------------------------------------------------------------------
LayoutCDMBar = function(barId)
    local widget = cdmBarFrames[barId]
    local iconList = cdmBarIcons[barId]
    if not widget or not iconList then
        return
    end

    local barInfo = barDataByKey[barId]
    if not barInfo or not barInfo.enabled then
        return
    end
    local blizzIcons = mod.CdmBlizzIcons()

    -- A visibility-hidden cursor bar must NEVER be laid back on-screen: its glue is parked and
    -- cannot re-glue it. Park here instead; the visibility show edge re-runs LayoutCDMBar via its deferred call.
    if widget._mouseTrack and widget._visHidden then
        widget._mouseParked = true
        widget:ClearAllPoints()
        widget:SetPoint(widget._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end

    -- Shift-Icons cd-state modes: shift-hidden icons are dropped from the layout entirely, so
    -- later icons close the gap and the bar resizes as if the icon were removed. Everything
    -- below (sizing, match math, slot positions) derives from this one array, so the filter IS
    -- the whole feature. Flags set by the cd-state evaluators (ns.SetCdStateShiftHidden) and by
    -- the buff route's Show When Missing active-hide (_missingActiveHidden);
    -- bars without either pay one field read per icon and never build the filtered table. Skipped frames keep their last point at alpha 0.
    do
        local filtered
        for index = 1, #iconList do
            local sfc = _ecmeFC[iconList[index]]
            if sfc and (sfc._cdStateShiftHidden or sfc._missingActiveHidden) then
                if not filtered then
                    filtered = {}
                    for jdx = 1, index - 1 do
                        filtered[jdx] = iconList[jdx]
                    end
                end
            elseif filtered then
                filtered[#filtered + 1] = iconList[index]
            end
        end
        if filtered then
            iconList = filtered
        end
    end

    local growDir = widget._mouseGrow or barInfo.growDirection or "CENTER"
    -- Row count comes from ComputeTopRowStride's EFFECTIVE rows (effRows, below), which
    -- collapses a custom top-row split to one row until its second row is populated.
    local horizontal = (
        growDir == "RIGHT"
        or growDir == "LEFT"
        or (growDir == "CENTER" and not barInfo.verticalOrientation)
    )
    -- spacing is a raw coord value; the per-frame conversion below (spacingPx = floor(spacing /
    -- onePx + 0.5)) rounds to nearest whole physical pixel. Do NOT pre-snap with SnapForScale:
    -- PP.Scale truncates and can lose a pixel where PP.mult > 1 (spacing=2 -> 1.0667 coord = 1 px instead of 2).
    local spacing = barInfo.spacing or 2

    -- Width/height match: derive iconSize live from the SOURCE bar's current width on every
    -- layout pass. The source bar IS the truth, so reading it live auto-corrects across spec swaps, source resizes, etc. NOTHING is persisted, so cross-spec corruption is impossible.
    local extraPixels = 0
    local extraPixelsH = 0
    local widthMatchTarget = CludesUI.GetWidthMatchTarget and CludesUI.GetWidthMatchTarget("CDM_" .. barId)
        or nil
    local heightMatchTarget = CludesUI.GetHeightMatchTarget and CludesUI.GetHeightMatchTarget("CDM_" .. barId)
        or nil
    local Pix = CludesUI.PP
    local pixel = Pix.mult
    local iconWidth
    -- True ONLY when the width-match math below produces an iconW. Gates the cropped-height-from-matched-width path so non-matched and height-matched bars stay byte-identical.
    local widthMatchApplied = false
    -- Matched cropped height in physical px, set ONLY when the height-match math succeeds: a
    -- cropped height-matched bar's per-icon height then uses that (not the stored iconSize), staying in lockstep with the container's extraPixelsH leftover distribution.
    local heightMatchIconHPx = nil
    -- Width-axis dim (icons spanning the width). Effective row count, so a not-yet-populated second row doesn't widen the match math.
    local function CurWidthDim()
        local s, region = ComputeTopRowStride(barInfo, #iconList)
        return horizontal and s or region
    end
    -- Height-axis dim (icons spanning the height)
    local function CurHeightDim()
        local s, region = ComputeTopRowStride(barInfo, #iconList)
        return horizontal and region or s
    end
    -- Resolve a width/height match target unlock key to a live frame. The match DB stores keys like "CDM_cooldowns" or "MainBar"; the registered unlock element provides a getFrame() callback.
    local function GetMatchTargetFrame(targetKey)
        if not targetKey then
            return nil
        end
        local elementList = CludesUI._unlockRegisteredElements
        local elem = elementList and elementList[targetKey]
        if elem and elem.getFrame then
            return elem.getFrame(targetKey)
        end
        return nil
    end
    if widthMatchTarget and #iconList > 0 then
        local targetFrame = GetMatchTargetFrame(widthMatchTarget)
        local targetW = targetFrame and targetFrame:GetWidth() or 0
        if targetFrame then
            local artW = mod.CdmMatchInsetSize(widthMatchTarget, targetFrame, widget)
            if artW then
                targetW = artW
            end
            -- Border-aware match (ns.CdmMatchAdj). Skipped at 0 (no textured
            -- border on either side, or equal ones cancelling); never moves the
            -- targetW > 1 gate below either way.
            if targetW > 1 then
                local adj = mod.CdmMatchAdj(barId, widthMatchTarget, true, artW ~= nil)
                if math.abs(adj) > 1e-6 and targetW + adj > 1 then
                    targetW = targetW + adj
                end
            end
        end
        local nowDim = CurWidthDim()
        if targetW > 1 and nowDim and nowDim > 0 then
            local physTarget = math.floor(targetW / pixel + 0.5)
            -- The match's Extra Width: whole physical px on the floored target,
            -- so no second rounding. nil = none stored.
            local mx = CludesUI.GetMatchExtra and CludesUI.GetMatchExtra("w", mod._cdmUKey[barId])
            if mx then
                physTarget = physTarget + mx
            end
            local physSp = math.floor(spacing / pixel + 0.5)
            local rawPhysIcon = (physTarget - (nowDim - 1) * physSp) / nowDim
            if rawPhysIcon < 8 then
                rawPhysIcon = 8
            end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconWidth = basePhysIcon * pixel
            widthMatchApplied = true
            local idealPhys = nowDim * basePhysIcon + (nowDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= nowDim then
                extraPixels = extra
            end
        end
    elseif heightMatchTarget and #iconList > 0 then
        local targetFrame = GetMatchTargetFrame(heightMatchTarget)
        local targetH = targetFrame and targetFrame:GetHeight() or 0
        if targetFrame then
            local _, artH = mod.CdmMatchInsetSize(heightMatchTarget, targetFrame, widget)
            if artH then
                targetH = artH
            end
            -- Border-aware match, as for width.
            if targetH > 1 then
                local adj = mod.CdmMatchAdj(barId, heightMatchTarget, false, artH ~= nil)
                if math.abs(adj) > 1e-6 and targetH + adj > 1 then
                    targetH = targetH + adj
                end
            end
        end
        local nowDim = CurHeightDim()
        if targetH > 1 and nowDim and nowDim > 0 then
            local shape = barInfo.iconShape or "none"
            local cropFactor = (shape == "cropped") and mod.CdmCropFactor(barInfo) or 1.0
            local physTarget = math.floor(targetH / pixel + 0.5)
            -- The match's Extra Height, as for width.
            local mx = CludesUI.GetMatchExtra and CludesUI.GetMatchExtra("h", mod._cdmUKey[barId])
            if mx then
                physTarget = physTarget + mx
            end
            local physSp = math.floor(spacing / pixel + 0.5)
            local rawPhysIcon = (physTarget - (nowDim - 1) * physSp) / nowDim / cropFactor
            if rawPhysIcon < 8 then
                rawPhysIcon = 8
            end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconWidth = basePhysIcon * pixel
            local basePhysIconH = math.floor(basePhysIcon * cropFactor)
            heightMatchIconHPx = basePhysIconH
            local idealPhys = nowDim * basePhysIconH + (nowDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= nowDim then
                extraPixelsH = extra
            end
        end
    end
    if not iconWidth then
        -- Not matched, or the target frame couldn't be read (early build, before the source bar
        -- exists): use the stored iconSize, a raw coord value rounded to whole physical px below. Do NOT pre-snap (see spacing).
        iconWidth = barInfo.iconSize or 36
    end

    local iconH = iconWidth
    local shape = barInfo.iconShape or "none"
    if shape == "cropped" then
        if widthMatchApplied then
            -- Width-matched: cropped height from the MATCHED icon width, so the icon keeps the
            -- same crop aspect as the non-matched path. Computed in physical px to stay on the
            -- pixel grid (matched iconW is already a clean pixel multiple). Aspect intent, not exact value: the non-matched branch rounds the crop factor in coord space, so the two can differ 1px at non-perfect scales.
            local wPx = math.floor(iconWidth / pixel + 0.5)
            iconH = math.floor(wPx * mod.CdmCropFactor(barInfo) + 0.5) * pixel
        elseif heightMatchIconHPx then
            -- Height-matched: the EXACT basePhysIconH the height-match math computed. MUST match precisely so per-icon height stays in lockstep with the container's extraPixelsH distribution.
            iconH = heightMatchIconHPx * pixel
        else
            iconH = math.floor((barInfo.iconSize or 36) * mod.CdmCropFactor(barInfo) + 0.5)
        end
    end

    -- ALL icons in the array, not just IsShown: CollectAndReanchor already filtered to frames we claimed, and Blizzard toggles IsShown independently -- we position everything we own.
    local visibleIcons = iconList
    local total = #visibleIcons
    -- Icon count is the sole sizing authority. The count==0 early return below preserves the last known size during transients (spec swap, pool churn).
    local sizeCount = total
    if total == 0 then
        -- The bar's rect stays deliberately stale here (transient
        -- protection), so tell the aura-custom tail the TRUE content extent
        -- is zero and let it re-anchor (it centers on the bar's position
        -- instead of appending to the frozen edge).
        widget._acLiveW, widget._acLiveH = 0, 0
        if mod._AuraCustomPoke then
            mod._AuraCustomPoke(barId)
        end
        local curW = widget:GetWidth() or 0
        local curH = widget:GetHeight() or 0
        if curW <= 1 or curH <= 1 then
            local fallbackW, fallbackH
            local minN = barInfo.minSizeIcons
            local growMatched
            if horizontal then
                growMatched = widthMatchTarget
            else
                growMatched = heightMatchTarget
            end
            if minN and minN > 0 and not growMatched then
                -- Minimum Bar Size: an empty bar takes its reserved slots, in the same physical px
                -- the first icon's layout gives (icons unmatched), so nothing matched to it moves
                -- when that icon lands. The assigned-spell estimate would size it for every spell
                -- on its list, learned or not (a low-level character).
                local _, rowList = ComputeTopRowStride(barInfo, 1)
                if rowList < 1 then
                    rowList = 1
                end
                local wPx = math.floor(iconWidth / pixel + 0.5)
                local hPx = math.floor(iconH / pixel + 0.5)
                local spPx = math.floor(spacing / pixel + 0.5)
                local growPx = minN * (horizontal and wPx or hPx) + (minN - 1) * spPx
                local perpPx = rowList * (horizontal and hPx or wPx) + (rowList - 1) * spPx
                if horizontal then
                    fallbackW, fallbackH = growPx * pixel, perpPx * pixel
                else
                    fallbackW, fallbackH = perpPx * pixel, growPx * pixel
                end
            else
                fallbackW, fallbackH = GetStableCDMBarSize(barId, nil, barInfo)
                -- EMPTY_CDM_BAR_SIZE is a raw coord-space placeholder; without snapping, often-empty buff-family bars render at non-pixel-aligned heights (43.20 px vs 43) at non-perfect UI scales.
                fallbackW = SnapForScale(fallbackW, 1)
                fallbackH = SnapForScale(fallbackH, 1)
            end
            widget:SetSize(fallbackW, fallbackH)
            widget._prevLayoutW = fallbackW
            widget._prevLayoutH = fallbackH
        end
        -- NEVER permanently hide containers on a transient count=0 (spec swaps, viewer pool churn): the next reanchor refills the bar, and hiding would need an explicit re-show that nothing guarantees.
        if widget._barBg then
            widget._barBg:Hide()
        end
        return
    end

    -- effRows is the EFFECTIVE row count: 1 while a custom top-row split's second row is empty, so the container never grows a blank row.
    local stride, effRows, customTopCount = ComputeTopRowStride(barInfo, sizeCount)

    -- Container size: compute in integer physical pixels, convert to coord at the end. Multiplying
    -- in coord space then snapping loses 1 phys px to float dust (3 * 21.6666... floors to 81 instead of 82), leaving the bottom icon protruding past the bar frame.
    local Pix = CludesUI.PP
    local pixel = Pix.mult
    local iconWPx = math.floor(iconWidth / pixel + 0.5)
    local iconHPx = math.floor(iconH / pixel + 0.5)
    local gapPx = math.floor(spacing / pixel + 0.5)
    -- Lock iconW/iconH/spacing to exact physical pixel multiples. Positioning (stepW, stepH) uses
    -- these coord values while the width-match math uses the iconWPx/spacingPx integers; out of
    -- lockstep, icons drift sub-pixel as col index grows -- spacing appears to "shrink" and the final icon undershoots the width-match target by 1 px.
    iconWidth = iconWPx * pixel
    iconH = iconHPx * pixel
    spacing = gapPx * pixel

    -- Per-row icon size offset (Number of Rows == 2, non-matched only): one row takes an Icon
    -- Scale pixel offset, the other keeps the base size. The match target is re-checked here (not
    -- just at the options gate) so a bar matched AFTER the toggle stays uniform. Rows are centered against each other; the larger row defines the bar's growth-axis extent.
    local perRowActive = false
    local rowWPx = { iconWPx, iconWPx } -- [1] = top row, [2] = bottom row
    local rowHPx = { iconHPx, iconHPx }
    if
        effRows == 2
        and not widthMatchTarget
        and not heightMatchTarget
        and customTopCount > 0
        and (sizeCount - customTopCount) > 0
        and (barInfo.customTopRowSizeEnabled or barInfo.customBottomRowSizeEnabled)
    then
        local base = barInfo.iconSize or 36
        local function RowSizePx(sz)
            if sz < 16 then
                sz = 16
            end -- clamp to the Icon Scale minimum
            local wpx = math.floor(sz / pixel + 0.5)
            local hCoord = (shape == "cropped") and math.floor(sz * mod.CdmCropFactor(barInfo) + 0.5) or sz
            local hpx = math.floor(hCoord / pixel + 0.5)
            return wpx, hpx
        end
        if barInfo.customTopRowSizeEnabled then
            rowWPx[1], rowHPx[1] = RowSizePx(base + (barInfo.topRowSizeOffset or 0))
        else
            rowWPx[2], rowHPx[2] = RowSizePx(base + (barInfo.bottomRowSizeOffset or 0))
        end
        perRowActive = true
    end

    -- Minimum Bar Size: reserve growth-axis room for at least minSizeIcons icon slots so a bar that
    -- loses icons (spec/talent swap, shift-hidden cooldowns) keeps its footprint -- everything
    -- matching its width or anchored to its edges then stays put, and the icons still present are
    -- centered in the surplus. SKIPPED while the GROWTH axis is match-owned: that axis measures
    -- exactly what the match target dictates and padding it would overshoot. A match on the
    -- PERPENDICULAR axis is fine -- the growth axis still varies with icon count there.
    local growMatched
    if horizontal then
        growMatched = widthMatchTarget
    else
        growMatched = heightMatchTarget
    end
    local resStride = growMatched and stride or ReserveStride(barInfo, stride)
    -- What resStride real icons measure at the BASE icon size, spacing included. Integer physical px like every other term here, so both bar edges stay on the pixel grid.
    local reservedPixels = 0
    if resStride > stride then
        local basePx = horizontal and iconWPx or iconHPx
        reservedPixels = resStride * basePx + (resStride - 1) * gapPx
    end
    -- Offset that centers the real icon block inside the surplus (uniform layout only; the per-row branch centers each row inside the total already).
    local padOffsetPx = 0

    local fullWPx, fullHPx
    if perRowActive then
        -- Two rows, independent icon sizes. Top row = customTopCount icons, the bottom takes the
        -- remainder. The bar spans the LARGER row along the growth axis and the SUM of both bands along the perpendicular axis.
        local topN = customTopCount
        local botN = sizeCount - topN
        if horizontal then
            local topRowW = topN * rowWPx[1] + math.max(0, topN - 1) * gapPx
            local botRowW = botN * rowWPx[2] + math.max(0, botN - 1) * gapPx
            fullWPx = math.max(topRowW, botRowW)
            -- No pad offset needed: both rows are centered against totalWPx below, so growing it IS the centering.
            if reservedPixels > fullWPx then
                fullWPx = reservedPixels
            end
            fullHPx = rowHPx[1] + rowHPx[2] + gapPx
        else
            local topColH = topN * rowHPx[1] + math.max(0, topN - 1) * gapPx
            local botColH = botN * rowHPx[2] + math.max(0, botN - 1) * gapPx
            fullHPx = math.max(topColH, botColH)
            if reservedPixels > fullHPx then
                fullHPx = reservedPixels
            end
            fullWPx = rowWPx[1] + rowWPx[2] + gapPx
        end
    elseif horizontal then
        fullWPx = stride * iconWPx + (stride - 1) * gapPx + extraPixels
        fullHPx = effRows * iconHPx + (effRows - 1) * gapPx + extraPixelsH
        if reservedPixels > fullWPx then
            padOffsetPx = math.floor((reservedPixels - fullWPx) / 2 + 0.5)
            fullWPx = reservedPixels
        end
    else
        fullWPx = effRows * iconWPx + (effRows - 1) * gapPx + extraPixels
        fullHPx = stride * iconHPx + (stride - 1) * gapPx + extraPixelsH
        if reservedPixels > fullHPx then
            padOffsetPx = math.floor((reservedPixels - fullHPx) / 2 + 0.5)
            fullHPx = reservedPixels
        end
    end

    -- Do NOT force an even totalWPx for CENTER grow: SnapCenterForDim (used by ApplyBarPositionCentered
    -- for CENTER-anchored frames) puts the center on a half-pixel grid for odd dimensions, so both
    -- edges already land on whole physical pixels. A forced +1 pads the frame 1 px wider than the icon layout -- visible as the unlock overlay overhanging the last icon.

    local totalW = fullWPx * pixel
    local totalH = fullHPx * pixel
    widget._acLiveW, widget._acLiveH = totalW, totalH
    -- Poke the aura-custom tail EVERY pass: an empty->occupied transition
    -- can land on the SAME total size (1 buff returning to a 1-wide stale
    -- rect), which fires no size/point event -- the tail would stay in its
    -- empty-centered mode underneath the returning real icon.
    if mod._AuraCustomPoke then
        mod._AuraCustomPoke(barId)
    end

    -- SetSize is deferred to AFTER icon positioning (below) so icons and bar resize land on the
    -- same rendered frame. Positioning first is safe: icons use absolute offsets from TOPLEFT, not the frame's current dimensions.
    local unlockKey = "CDM_" .. barId
    -- Freeze buff-family bar size during unlock mode so the mover overlay stays in sync (it doesn't dynamically resize with buff count).
    local skipResize = CludesUI._unlockActive and mod.IsBarBuffFamily(barInfo)

    -- Bar background
    if barInfo.barBgEnabled then
        if not widget._barBg then
            widget._barBg = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        widget._barBg:ClearAllPoints()
        widget._barBg:SetPoint("TOPLEFT", 0, 0)
        widget._barBg:SetPoint("BOTTOMRIGHT", 0, 0)
        widget._barBg:SetColorTexture(
            barInfo.barBgR or 0,
            barInfo.barBgG or 0,
            barInfo.barBgB or 0,
            barInfo.barBgA or 0.5
        )
        widget._barBg:Show()
    elseif widget._barBg then
        widget._barBg:Hide()
    end

    -- Row growth "UP" (horizontal)/"LEFT" (vertical): reverse the VISUAL row order so the base
    -- (first data) row hugs the pinned trailing edge (BOTTOM/RIGHT) and extra rows grow away.
    -- Data-row semantics (fill order, per-row centering, icon counts, per-row sizes) are untouched
    -- -- only the perpendicular-axis offset flips. "DOWN"/"RIGHT" need no reversal: the TOPLEFT layout already keeps the pinned leading edge's row still.
    local rowsReversed = mod.CDMRowsReversed(barInfo)

    if perRowActive then
        -- Two-row layout with a per-row icon size offset: each row laid out at its own icon size,
        -- centered along the growth axis; the perpendicular axis stacks the two bands. No match extras -- gated off when matched.
        local isMouseBar = barInfo.anchorTo == "mouse"
        local topN = customTopCount
        for index, iconTex in ipairs(visibleIcons) do
            local iconScale = iconTex:GetScale() or 1
            if iconScale < 0.01 then
                iconScale = 1
            end
            local iconScale = 1 / iconScale

            local rowIdx = (index <= topN) and 1 or 2 -- 1 = top, 2 = bottom
            local idxInRow = (rowIdx == 1) and (index - 1) or (index - topN - 1)
            local rowN = (rowIdx == 1) and topN or (sizeCount - topN)
            local wPx, hPx = rowWPx[rowIdx], rowHPx[rowIdx]

            FC(iconTex).matchExpanded = nil
            iconTex:SetSize(wPx * pixel * iconScale, hPx * pixel * iconScale)
            if blizzIcons then
                mod.CdmApplyBlizzIconArt(iconTex)
            end

            if isMouseBar then
                iconTex:SetFrameStrata("TOOLTIP")
                iconTex:SetFrameLevel(9980 + index)
            else
                iconTex:SetFrameStrata(barInfo.barStrata or "MEDIUM")
                iconTex:SetFrameLevel(5 + index)
            end
            iconTex:ClearAllPoints()

            local anchorX, anchorY
            if horizontal then
                -- Growth axis = width (center the row within the bar width);
                -- perpendicular = height (top band, then bottom band).
                local rowMainPx = rowN * wPx + math.max(0, rowN - 1) * gapPx
                local offMainPx = math.floor((fullWPx - rowMainPx) / 2 + 0.5)
                local xPx = offMainPx + idxInRow * (wPx + gapPx)
                -- Reversed when rows grow upward: rowIdx 2 on top, 1 below.
                local yPx
                if rowsReversed then
                    yPx = (rowIdx == 2) and 0 or (rowHPx[2] + gapPx)
                else
                    yPx = (rowIdx == 1) and 0 or (rowHPx[1] + gapPx)
                end
                anchorX = (xPx * pixel) * iconScale
                anchorY = -(yPx * pixel) * iconScale
            else
                -- Growth axis = height (center the row within the bar height);
                -- perpendicular = width (left band, then right band).
                local rowMainPx = rowN * hPx + math.max(0, rowN - 1) * gapPx
                local offMainPx = math.floor((fullHPx - rowMainPx) / 2 + 0.5)
                local yPx = offMainPx + idxInRow * (hPx + gapPx)
                -- Reversed when columns grow leftward: rowIdx 2 at the left.
                local xPx
                if rowsReversed then
                    xPx = (rowIdx == 2) and 0 or (rowWPx[2] + gapPx)
                else
                    xPx = (rowIdx == 1) and 0 or (rowWPx[1] + gapPx)
                end
                anchorX = (xPx * pixel) * iconScale
                anchorY = -(yPx * pixel) * iconScale
            end

            local fd = _getFD(iconTex)
            if fd then
                fd._cdmAnchor = { "TOPLEFT", widget, "TOPLEFT", anchorX, anchorY }
            end
            iconTex:SetPoint("TOPLEFT", widget, "TOPLEFT", anchorX, anchorY)
        end
    else
        -- Uniform icon size: every bar except the 2-row per-row-size case above.
        local stepW = iconWidth + spacing
        local stepH = iconH + spacing
        -- Minimum Bar Size surplus in coord space: shifts the whole icon block along the GROWTH axis so it sits centered in the reserved footprint. 0 whenever the reservation is off or already filled.
        local padOffset = padOffsetPx * pixel

        local topRowCount = customTopCount
        if topRowCount < 0 then
            topRowCount = 0
        end
        local bottomRowCount = #visibleIcons - topRowCount
        if bottomRowCount < 0 then
            bottomRowCount = 0
        end

        -- Per-row centering: rows with fewer icons than stride get centered.
        local function RowIconCount(rowIndex)
            if rowIndex == 0 then
                return topRowCount
            end
            return bottomRowCount
        end

        -- Cursor-anchored bars need explicit icon strata: icons aren't parented to
        -- the container, so they don't inherit its TOOLTIP strata.
        local isMouseBar = barInfo.anchorTo == "mouse"

        -- Position each icon: fill bottom-up so bottom rows are full and the top row gets the
        -- remainder. "col"/"row" run along the bar's GROWTH axis -- horizontal: col = width-axis,
        -- row = height-axis; vertical: swapped. extraPixels expand iconW along the width axis for the
        -- first N icons; extraPixelsH expand iconH along the height axis. Only one match can be active, but the math handles both for symmetry.
        -- growthW = extras along the GROWTH axis (col index); growthH = extras along
        -- the PERPENDICULAR axis (row index).
        local growthW = horizontal and extraPixels or extraPixelsH
        local growthH = horizontal and extraPixelsH or extraPixels
        for index, iconTex in ipairs(visibleIcons) do
            -- Compensate for Blizzard's per-icon scale so visual size matches.
            local iconScale = iconTex:GetScale() or 1
            if iconScale < 0.01 then
                iconScale = 1
            end
            local iconScale = 1 / iconScale

            -- Sequential index -> bottom-up grid position. Icons 1..topRowCount fill the top row (visual row 0); the rest fill rows 1..effRows-1.
            local colour, rowIndex
            if index <= topRowCount then
                colour = index - 1
                rowIndex = 0
            else
                local bottomIdx = index - topRowCount - 1
                colour = bottomIdx % stride
                rowIndex = 1 + math.floor(bottomIdx / stride)
            end
            -- Visual row == data row unless row growth reverses the visual order (data row 0 renders on the pinned trailing edge). Data-row logic below (RowIconCount, expansion flags) keeps `row`.
            local vRow = rowsReversed and (effRows - 1 - rowIndex) or rowIndex

            -- +1 physical pixel on expanded icons: horizontal bars expand the WIDTH axis (iconW),
            -- vertical bars (col = height-axis) expand HEIGHT (iconH). Keeps icons square on the perpendicular axis.
            local pixel = Pix.mult
            local expandedCol = (growthW > 0 and colour < growthW)
            local expandedRow = (growthH > 0 and rowIndex < growthH)
            local thisIconW, thisIconH
            if horizontal then
                thisIconW = expandedCol and (iconWidth + pixel) or iconWidth
                thisIconH = expandedRow and (iconH + pixel) or iconH
            else
                -- Vertical: col is the height-axis index, so col-extras expand iconH
                thisIconH = expandedCol and (iconH + pixel) or iconH
                thisIconW = expandedRow and (iconWidth + pixel) or iconWidth
            end
            FC(iconTex).matchExpanded = (expandedCol or expandedRow) or nil
            iconTex:SetSize(thisIconW * iconScale, thisIconH * iconScale)
            if blizzIcons then
                mod.CdmApplyBlizzIconArt(iconTex)
            end

            -- Cumulative offsets: each prior expanded icon shifts later icons by 1 physical pixel on
            -- the same axis (extraBefore = growth axis/col; extraBeforeR = perpendicular axis/row).
            -- extraBeforeR counts expanded rows VISUALLY before this one: expanded rows are data rows
            -- < growthH, so normal order has min(row, growthH) above, and reversed order has data rows in (row, effRows-1] above, of which max(0, min(growthH, effRows) - row - 1) are expanded.
            local extraBefore = math.min(colour, growthW) * pixel
            local extraBeforeR
            if rowsReversed then
                extraBeforeR = math.max(0, math.min(growthH, effRows) - rowIndex - 1) * pixel
            else
                extraBeforeR = math.min(rowIndex, growthH) * pixel
            end

            if isMouseBar then
                iconTex:SetFrameStrata("TOOLTIP")
                iconTex:SetFrameLevel(9980 + index)
            else
                iconTex:SetFrameStrata(barInfo.barStrata or "MEDIUM")
                iconTex:SetFrameLevel(5 + index)
            end
            iconTex:ClearAllPoints()

            local rowCount = RowIconCount(rowIndex)
            local rowHasLess = (rowCount > 0 and rowCount < stride)

            -- Offsets as absolute parent-space integers, divided by iconScale for SetPoint. NO per-position snapping: dividing integers by the same constant produces mathematically uniform gaps.
            local posX = colour * stepW + extraBefore
            local posY = vRow * stepH

            -- Resolve anchor params first, then stamp fd._cdmAnchor BEFORE SetPoint: the SetPoint hook
            -- fires AFTER SetPoint and compares relativeTo against fd._cdmAnchor[2]; updated after, it
            -- reads a stale anchor (the previous bar) and snaps the icon ~50px wrong when moving a
            -- spell between bars. All growth directions use the same TOPLEFT icon layout; growth only affects which FRAME edge stays fixed during resize, never icon order.
            local anchorPt, anchorRelPt, anchorX, anchorY
            local rowOffset = 0
            if horizontal then
                if rowHasLess then
                    rowOffset = math.floor((stride - rowCount) * stepW / 2 + 0.5)
                end
                anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
                anchorX = (posX + rowOffset + padOffset) * iconScale
                anchorY = -(posY + extraBeforeR) * iconScale
            else
                if rowHasLess then
                    rowOffset = math.floor((stride - rowCount) * stepH / 2 + 0.5)
                end
                anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
                anchorX = (vRow * stepW + extraBeforeR) * iconScale
                anchorY = -(colour * stepH + extraBefore + rowOffset + padOffset) * iconScale
            end

            if anchorPt then
                -- Stamp BEFORE SetPoint so the synchronous hook sees the new anchor and treats our own SetPoint as a no-op.
                local fd = _getFD(iconTex)
                if fd then
                    fd._cdmAnchor = { anchorPt, widget, anchorRelPt, anchorX, anchorY }
                end
                iconTex:SetPoint(anchorPt, widget, anchorRelPt, anchorX, anchorY)
            end
        end
    end -- perRowActive vs uniform layout branch

    -- SetSize AFTER icon positioning: bar resize and icon placement land on the same rendered frame (no 1-frame size mismatch).
    if not skipResize then
        local oldW = widget:GetWidth() or 0
        local oldH = widget:GetHeight() or 0
        -- Pre-resize center in UIParent space, captured BEFORE SetSize (an edge-pointed frame
        -- moves its center when resized); the anchor offset upkeep below validates against it.
        -- Captured only when that upkeep can run (bar has an unlockAnchors entry): measuring a bar
        -- whose rect derives from a restricted tree HARD-ERRORS (FocusKick anchored to a nameplate
        -- in a locked instance), and such bars have no entry. pcall covers the residual case; an unknown center skips the upkeep.
        local oldCX, oldCY
        if CludesUIDB and CludesUIDB.unlockAnchors and CludesUIDB.unlockAnchors[unlockKey] then
            local success, c1, c2 = pcall(widget.GetCenter, widget)
            if success and c1 and c2 then
                local region = widget:GetEffectiveScale() / UIParent:GetEffectiveScale()
                oldCX, oldCY = c1 * region, c2 * region
            end
        end
        CludesUI._layoutBarResizing = unlockKey
        pcall(widget.SetSize, widget, totalW, totalH)
        CludesUI._layoutBarResizing = nil
        -- Group loot rolls already up keep clear of a bar that grew or shrank.
        if not (issecretvalue(oldW) or issecretvalue(oldH)) and (totalW ~= oldW or totalH ~= oldH) then
            mod.RequestLootPlacement()
        end
        -- Anchor offset maintenance: a growth-direction resize shifts the center by delta/2 while
        -- the fixed edge stays put, so adjust the center-based anchor offset to keep the
        -- relationship on /reload. NOT a position write (positions save only via Save & Exit).
        -- Self-validating gate: the compensation is only correct when the PRE-resize center
        -- actually sat at the anchor-derived position (target center + stored offset on that
        -- axis). During a profile apply the bar still holds the OUTGOING profile's position while
        -- unlockAnchors carries the INCOMING offsets -- compensating that corrupts offsets
        -- cumulatively per swap, and layout passes can land before/inside/after any suppression
        -- window, so the position check is the only ordering-proof guard. A falsely skipped compensation costs at most one dw/2 nudge, fixed by the next reapply.
        local growDir = barInfo.growDirection
        if
            growDir
            and growDir ~= "CENTER"
            and not CludesUI._unlockActive
            and not CludesUI._abAnchorSuppressed
            and (oldW >= 1 or oldH >= 1)
        then
            local adb = CludesUIDB and CludesUIDB.unlockAnchors
            local anchorInfo = adb and adb[unlockKey]
            if anchorInfo and anchorInfo.mode ~= "POINT" then
                local edgeSide = anchorInfo.side
                local PPo = CludesUI and CludesUI.PP
                local uiES = PPo and UIParent:GetEffectiveScale()
                local tCX, tCY
                if CludesUI.GetAnchorTargetCenterUI then
                    tCX, tCY = CludesUI.GetAnchorTargetCenterUI(unlockKey)
                end
                local TOL = 2 -- UI px; pixel-snap noise stays well under 1
                -- Width/height-matched bars: the match owns that axis, so the bar never
                -- legitimately self-resizes there. Any resize on a matched axis is the match
                -- (re)asserting the target's size -- the saved offset already corresponds to it, and compensating corrupts the offset by dw/2 per profile swap.
                local wMatched = CludesUIDB.unlockWidthMatch and CludesUIDB.unlockWidthMatch[unlockKey]
                local hMatched = CludesUIDB.unlockHeightMatch and CludesUIDB.unlockHeightMatch[unlockKey]
                -- Horizontal growth: adjust offsetX on TOP/BOTTOM anchors
                local dw = totalW - oldW
                if
                    math.abs(dw) > 0.1
                    and (edgeSide == "TOP" or edgeSide == "BOTTOM")
                    and not wMatched
                    and oldCX
                    and tCX
                    and math.abs(oldCX - (tCX + (anchorInfo.offsetX or 0))) <= TOL
                then
                    if growDir == "RIGHT" then
                        anchorInfo.offsetX = anchorInfo.offsetX + dw / 2
                    elseif growDir == "LEFT" then
                        anchorInfo.offsetX = anchorInfo.offsetX - dw / 2
                    end
                    if PPo and uiES then
                        anchorInfo.offsetX = PPo.SnapForES(anchorInfo.offsetX, uiES)
                    end
                end
                -- Vertical growth: adjust offsetY on LEFT/RIGHT anchors
                local dh = totalH - oldH
                if
                    math.abs(dh) > 0.1
                    and (edgeSide == "LEFT" or edgeSide == "RIGHT")
                    and not hMatched
                    and oldCY
                    and tCY
                    and math.abs(oldCY - (tCY + (anchorInfo.offsetY or 0))) <= TOL
                then
                    if growDir == "DOWN" then
                        anchorInfo.offsetY = anchorInfo.offsetY - dh / 2
                    elseif growDir == "UP" then
                        anchorInfo.offsetY = anchorInfo.offsetY + dh / 2
                    end
                    if PPo and uiES then
                        anchorInfo.offsetY = PPo.SnapForES(anchorInfo.offsetY, uiES)
                    end
                end
            end
        end
    end

    if CludesUI.IsPointAnchored(unlockKey) then
        CludesUI.ReapplyOwnAnchor(unlockKey)
    end

    -- FocusKick: re-anchor against the focus nameplate after every layout pass so the bar tracks size/icon-count changes from the options panel.
    if barId == mod.FOCUSKICK_BAR_KEY and mod.ReapplyFocusKick then
        mod.ReapplyFocusKick()
    end
end

-- Shift-Icons cd-state modes: write the per-frame shift-hidden flag (on the external FC table,
-- NEVER the Blizzard frame) and, ONLY on a value change, relayout that bar so remaining icons
-- close the gap. Deferred to a clean execution context: callers run inside SetDesaturated hooks/
-- the Fake-Active poll, where LayoutCDMBar's SetSize/SetPoint could propagate taint (same pattern
-- as the _visHidden relayout in _CDMApplyVisibility). Coalesced per bar; steady-state calls return immediately.
mod._cdShiftLayoutPending = {}
function mod.SetCdStateShiftHidden(fc, shiftHidden)
    shiftHidden = shiftHidden or false
    if (fc._cdStateShiftHidden or false) == shiftHidden then
        return
    end
    fc._cdStateShiftHidden = shiftHidden
    -- Overflow-diverted frames render on the target bar, so the gap-close relayout must hit the
    -- bar the frame is actually laid out on. Normally unreachable for diverted frames (Phase 3b's no-op rule), but a one-reanchor window exists after a shift effect is first configured.
    mod.QueueShiftLayout(fc._overflowLayoutBar or fc.barKey)
end

-- The relayout a layout-dropped icon needs when it joins or leaves its bar's
-- layout without the bar's icon list changing (the reanchor pass lays a bar out
-- only when that list changes). One pass per bar on the next frame.
--
-- Growth-edge preservation is LOCAL to this relayout call: capture the fixed growth edge before
-- LayoutCDMBar and, if the resize moved it, translate the frame back through whatever point it
-- already has (offset-only SetPoint on the existing point/relTo -- no ClearAllPoints, no DB
-- writes, no anchor-system calls). A non-CENTER-grow bar's persistent point normally IS its fixed
-- growth edge (delta 0, frame untouched); this only corrects bars whose point is center/corner-
-- based at that moment (anchored bars mid-cascade, first-row corner pins, legacy CENTER
-- positions). Anchored bars still get their deferred anchor batch reapply afterwards (OnSizeChanged fired during LayoutCDMBar), which remains authoritative.
function mod.QueueShiftLayout(bk)
    if not bk or mod._cdShiftLayoutPending[bk] then
        return
    end
    mod._cdShiftLayoutPending[bk] = true
    C_Timer.After(0, function()
        mod._cdShiftLayoutPending[bk] = nil
        local widget = cdmBarFrames[bk]
        local edge = barDataByKey[bk]
        local growDir = edge and edge.growDirection or "CENTER"
        local fixedEdge
        if
            widget
            and growDir ~= "CENTER"
            and not CludesUI.IsPointAnchored("CDM_" .. bk)
            and not widget._mouseTrack
            and bk ~= mod.FOCUSKICK_BAR_KEY
            and not CludesUI._unlockActive
            and widget:GetNumPoints() == 1
        then
            if growDir == "LEFT" then
                fixedEdge = widget:GetRight()
            elseif growDir == "RIGHT" then
                fixedEdge = widget:GetLeft()
            elseif growDir == "UP" then
                fixedEdge = widget:GetBottom()
            elseif growDir == "DOWN" then
                fixedEdge = widget:GetTop()
            end
        end
        LayoutCDMBar(bk)
        if fixedEdge then
            local newEdge
            if growDir == "LEFT" then
                newEdge = widget:GetRight()
            elseif growDir == "RIGHT" then
                newEdge = widget:GetLeft()
            elseif growDir == "UP" then
                newEdge = widget:GetBottom()
            else
                newEdge = widget:GetTop()
            end
            local skinData = newEdge and (newEdge - fixedEdge)
            if skinData and (skinData > 0.25 or skinData < -0.25) then
                local anchorPoint, relTo, relPoint, x, y = widget:GetPoint(1)
                if anchorPoint then
                    if growDir == "LEFT" or growDir == "RIGHT" then
                        x = (x or 0) - skinData
                    else
                        y = (y or 0) - skinData
                    end
                    widget:SetPoint(anchorPoint, relTo or widget:GetParent(), relPoint, x, y)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Toggle Blizzard CDM Settings. Hides the CludesUI options panel first so
--  the Blizzard UI is visible. NEVER call SetCurrentCategories /
--  SetDisplayMode / ClearDisplayCategories after opening -- those taint the
--  CDM frame pool (so isBuff cannot actually select a tab).
-------------------------------------------------------------------------------
local function OpenBlizzardCDMTab(isBuff)
    if not CooldownViewerSettings then
        return
    end
    if CludesUI._mainFrame and CludesUI._mainFrame:IsShown() then
        CludesUI._mainFrame:Hide()
    end
    if CooldownViewerSettings:IsShown() then
        CooldownViewerSettings:Hide()
    else
        CooldownViewerSettings:Show()
    end
end
mod.OpenBlizzardCDMTab = OpenBlizzardCDMTab

-------------------------------------------------------------------------------
--  CDM Tooltip System
--  No OnUpdate polling: Blizzard viewer frames handle their own tooltips via
--  native OnEnter; custom injected frames (item presets, racials, custom
--  spells) get OnEnter/OnLeave scripts in DecorateFrame / preset creation.
-------------------------------------------------------------------------------
local _tooltipBars = {} -- [barKey] = true for bars with tooltips enabled
local _tooltipFrame = CreateFrame("Frame")
_tooltipFrame:Hide()

local function ApplyCDMTooltipState(barId)
    local edge = barDataByKey[barId]
    local enabled = edge and edge.showTooltip
    if enabled then
        _tooltipBars[barId] = true
    else
        _tooltipBars[barId] = nil
        -- Clear a tooltip showing for an icon on this bar
        local ownerFrame = GameTooltip:GetOwner()
        local sfc = ownerFrame and _ecmeFC[ownerFrame]
        if sfc and sfc.barKey == barId then
            GameTooltip:Hide()
        end
    end
    -- Mouse-motion follows the tooltip setting. A motion-enabled icon with no unit becomes the
    -- mouseover-focus frame and steals hover from unit frames underneath (raid frame hover
    -- highlight and [@mouseover] casts die wherever a bar overlaps them), so icons may ONLY
    -- capture the mouse when tooltips are on. Cursor-anchored bars stay fully mouse-through
    -- (SetFrameClickThrough owns their state); vis-hidden bars stay inert. Mouse calls on Blizzard CDM frames are blocked in combat.
    if not InCombatLockdown() then
        local widget = cdmBarFrames[barId]
        local wantHover = (enabled and widget and not widget._mouseTrack and not widget._visHidden) and true
            or false
        local iconList = cdmBarIcons[barId]
        if iconList then
            for index = 1, #iconList do
                local ic = iconList[index]
                if ic and ic.EnableMouseMotion then
                    -- Invisible placeholders, Empty Slots and Show When Missing
                    -- icons hidden while active are excluded even with tooltips
                    -- on: a slot with no art has nothing to hover, so capturing
                    -- here would only take mouseover away from whatever the bar
                    -- sits over.
                    local sfc = _ecmeFC[ic]
                    ic:EnableMouseMotion(
                        wantHover
                            and not ic._isEmptySlotFrame
                            and not (sfc and sfc._missingActiveHidden)
                            and not IsPlaceholderRenderHidden(ic, edge)
                    )
                end
            end
        end
    end
    -- Global tooltip frame follows whether ANY bar wants tooltips
    if next(_tooltipBars) then
        _tooltipFrame:Show()
    else
        _tooltipFrame:Hide()
    end
end
mod.ApplyCDMTooltipState = ApplyCDMTooltipState

Inner.ApplyBarPositionCentered = ApplyBarPositionCentered
Inner.ApplyCDMTooltipState, Inner.BuildCDMBar = ApplyCDMTooltipState, BuildCDMBar
Inner.ComputeTopRowStride, Inner.GetStableCDMBarSize = ComputeTopRowStride, GetStableCDMBarSize
Inner.LayoutCDMBar, Inner.ReserveStride = LayoutCDMBar, ReserveStride
Inner.SaveCDMBarPosition = SaveCDMBarPosition
Inner.OpenBlizzardCDMTab = OpenBlizzardCDMTab
Inner.broken = false
