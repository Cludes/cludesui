if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Tools.lua
--  Unlock Mode tools: accent color, grid overlay, alignment guides, snap,
--  selection and arrow-key nudge, action bar visual size, mover overlay
--  helpers, Blizzard-owned info overlays.
--  Loaded after CUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}
CUI_NS.unlockParts.Tools = function(LM)
    local mod, ABAR, floor, abs = CUI_NS, LM.EAB, LM.floor, LM.abs
    local min, max, sqrt, sin = LM.min, LM.max, LM.sqrt, LM.sin
    local Pix, FONT_PATH, GRID_SPACING, SNAP_THRESH = LM.PP, LM.FONT_PATH, LM.GRID_SPACING, LM.SNAP_THRESH
    local MOVER_ALPHA, MOVER_HOVER, BAR_LOOKUP, registeredElements =
        LM.MOVER_ALPHA, LM.MOVER_HOVER, LM.BAR_LOOKUP, LM.registeredElements
    local guidePool, handles, pendingPositions, GridBaseAlpha =
        LM.guidePool, LM.movers, LM.pendingPositions, LM.GridBaseAlpha
    local GridCenterAlpha, _blizzOwnedOverlays, GetAnchorDB, GetAnchorInfo =
        LM.GridCenterAlpha, LM._blizzOwnedOverlays, LM.GetAnchorDB, LM.GetAnchorInfo
    local FadeOverlayForSelectElement, CancelPickMode, LoadBarPosition =
        LM.FadeOverlayForSelectElement, LM.CancelPickMode, LM.LoadBarPosition

    -------------------------------------------------------------------------------
    --  Accent color helper (reads live from CludesUI)
    -------------------------------------------------------------------------------
    local function AccentColor()
        local eg = CUI and CUI.CLUDES_GREEN
        if eg then return eg.r, eg.g, eg.b end
        return 76 / 255, 201 / 255, 240 / 255
    end

    -------------------------------------------------------------------------------
    --  Grid overlay
    -------------------------------------------------------------------------------
    local function CreateGrid(hostFrame)
        if LM.gridFrame then return LM.gridFrame end
        -- Grid lives on its own BACKGROUND-strata frame so it renders BEHIND the
        -- real game UI elements (action bars, unit frames).
        LM.gridFrame = CreateFrame("Frame", nil, UIParent)
        LM.gridFrame:SetFrameStrata("BACKGROUND")
        LM.gridFrame:SetAllPoints(UIParent)
        LM.gridFrame:SetFrameLevel(1)
        LM.gridFrame._lines = {}

        function LM.gridFrame:Rebuild()
            for _, texture in ipairs(self._lines) do
                texture:Hide()
            end
            local position = 0
            local wid, hgt = UIParent:GetWidth(), UIParent:GetHeight()
            local accR, accG, accB = AccentColor()
            local baseA = GridBaseAlpha()
            local centerA = GridCenterAlpha()

            -- Pixel-perfect: use PP.mult so lines are exactly 1 physical pixel
            -- and spacing aligns to the physical pixel grid.
            local mult = Pix and Pix.mult or 1
            local lineW = mult
            local spacing = GRID_SPACING * mult

            -- Snap helper: round a UI coordinate to the nearest physical pixel
            local function snap(v) return floor(v / mult + 0.5) * mult end

            local centerX = snap(wid / 2)
            local centerY = snap(hgt / 2)

            local function MakeLine(isVert, place)
                position = position + 1
                local texture = self._lines[position]
                if not texture then
                    texture = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                    if texture.SetSnapToPixelGrid then
                        texture:SetSnapToPixelGrid(false)
                        texture:SetTexelSnappingBias(0)
                    end
                    self._lines[position] = texture
                end
                texture:SetColorTexture(accR, accG, accB, baseA)
                texture._baseAlpha = baseA
                texture._isWhite = false
                texture._isVert = isVert
                texture._pos = place
                texture:ClearAllPoints()
                if isVert then
                    texture:SetSize(lineW, hgt)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", place, 0)
                else
                    texture:SetSize(wid, lineW)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -place)
                end
                texture:Show()
            end

            -- Vertical lines extending outward from center
            local posX = centerX - spacing
            while posX > 0 do
                MakeLine(true, snap(posX))
                posX = posX - spacing
            end
            posX = centerX + spacing
            while posX < wid do
                MakeLine(true, snap(posX))
                posX = posX + spacing
            end

            -- Horizontal lines extending outward from center
            local posY = centerY - spacing
            while posY > 0 do
                MakeLine(false, snap(posY))
                posY = posY - spacing
            end
            posY = centerY + spacing
            while posY < hgt do
                MakeLine(false, snap(posY))
                posY = posY + spacing
            end

            -- Center crosshair: full-length accent lines at screen center
            for _, axis in ipairs({ "V", "H" }) do
                position = position + 1
                local texture = self._lines[position]
                if not texture then
                    texture = self:CreateTexture(nil, "BACKGROUND", nil, -6)
                    if texture.SetSnapToPixelGrid then
                        texture:SetSnapToPixelGrid(false)
                        texture:SetTexelSnappingBias(0)
                    end
                    self._lines[position] = texture
                end
                texture:SetColorTexture(accR, accG, accB, centerA)
                texture._baseAlpha = centerA
                texture._isWhite = false
                texture._isVert = (axis == "V")
                texture._pos = 0
                texture:ClearAllPoints()
                if axis == "V" then
                    texture:SetSize(lineW, hgt)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX, 0)
                else
                    texture:SetSize(wid, lineW)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -centerY)
                end
                texture:Show()
            end

            -- White crosshair pip at dead center (short lines forming a +), always
            -- 50% alpha regardless of grid brightness mode
            local CROSS_ARM = 20
            local CROSS_ALPHA = 0.5
            for _, axis in ipairs({ "V", "H" }) do
                position = position + 1
                local texture = self._lines[position]
                if not texture then
                    texture = self:CreateTexture(nil, "BACKGROUND", nil, -5)
                    if texture.SetSnapToPixelGrid then
                        texture:SetSnapToPixelGrid(false)
                        texture:SetTexelSnappingBias(0)
                    end
                    self._lines[position] = texture
                end
                texture:SetColorTexture(1, 1, 1, CROSS_ALPHA)
                texture._baseAlpha = CROSS_ALPHA
                texture._isWhite = true
                texture._isVert = (axis == "V")
                texture._pos = 0
                texture:ClearAllPoints()
                if axis == "V" then
                    texture:SetSize(lineW, CROSS_ARM * 2)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX, -(centerY - CROSS_ARM))
                else
                    texture:SetSize(CROSS_ARM * 2, lineW)
                    texture:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX - CROSS_ARM, -centerY)
                end
                texture:Show()
            end

            self._lineCount = position
        end

        -- Cache accent color; refreshed when grid is rebuilt
        local cachedAR, cachedAG, cachedAB = AccentColor()

        local origRebuild = LM.gridFrame.Rebuild
        function LM.gridFrame:Rebuild()
            origRebuild(self)
            cachedAR, cachedAG, cachedAB = AccentColor()
        end

        -- Cursor flashlight: highlights grid lines near the cursor via a radial
        -- gradient texture (soft ambient glow) plus per-line segments with 2D
        -- distance-based alpha for crisp line highlights.
        local LIGHT_RADIUS = 220
        local LIGHT_DIAMETER = LIGHT_RADIUS * 2
        local LIGHT_BOOST = 0.55
        local NUM_SEGS = 5
        local FLASH_PATH = "Interface\\AddOns\\CludesUI\\media\\unlock-flash.png"

        -- Ambient glow texture (soft circle behind lines)
        local flashFill = LM.gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        flashFill:SetTexture(FLASH_PATH)
        flashFill:SetSize(LIGHT_DIAMETER, LIGHT_DIAMETER)
        flashFill:SetBlendMode("ADD")
        flashFill:SetVertexColor(1, 1, 1, 0.03)
        flashFill:Hide()

        -- Line highlight segments
        LM.gridFrame._glows = {}
        local glowIdx = 0

        local function GetGlow(position)
            local g = LM.gridFrame._glows[position]
            if not g then
                g = LM.gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
                LM.gridFrame._glows[position] = g
            end
            return g
        end

        LM.gridFrame:SetScript("OnUpdate", function(self, elapsed)
            if not self:IsShown() then
                flashFill:Hide()
                return
            end

            if not LM.flashlightEnabled then
                flashFill:Hide()
                for jdx = 1, #self._glows do
                    if self._glows[jdx] then self._glows[jdx]:Hide() end
                end
                return
            end

            local scale = UIParent:GetEffectiveScale()
            local curX, curY = GetCursorPosition()
            curX = curX / scale
            curY = curY / scale
            local screenH = UIParent:GetHeight()
            local screenW = UIParent:GetWidth()
            local cyFromTop = screenH - curY

            -- Position ambient glow
            flashFill:ClearAllPoints()
            flashFill:SetPoint("CENTER", UIParent, "BOTTOMLEFT", curX, curY)
            flashFill:Show()

            -- Highlight line segments
            glowIdx = 0
            local R2 = LIGHT_RADIUS * LIGHT_RADIUS
            local lineCount = self._lineCount or #self._lines

            for i = 1, lineCount do
                local texture = self._lines[i]
                if texture and texture:IsShown() and texture._baseAlpha then
                    local perpDist
                    if texture._isVert then
                        perpDist = abs(texture._pos - curX)
                    else
                        perpDist = abs(texture._pos - cyFromTop)
                    end

                    if perpDist < LIGHT_RADIUS then
                        local halfSpan = sqrt(R2 - perpDist * perpDist)
                        local segSize = (halfSpan * 2) / NUM_SEGS
                        local isW = texture._isWhite

                        if texture._isVert then
                            local spanStart = max(0, curY - halfSpan)
                            local spanEnd = min(screenH, curY + halfSpan)
                            local segY = spanStart
                            while segY < spanEnd do
                                local segEnd = min(segY + segSize, spanEnd)
                                local midY = (segY + segEnd) * 0.5
                                local deltaY = midY - curY
                                local deltaX = texture._pos - curX
                                local d2 = deltaX * deltaX + deltaY * deltaY
                                if d2 < R2 then
                                    local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                    local opacity = LIGHT_BOOST * t * t
                                    if opacity > 0.003 then
                                        glowIdx = glowIdx + 1
                                        local g = GetGlow(glowIdx)
                                        if isW then
                                            g:SetColorTexture(1, 1, 1, opacity)
                                        else
                                            g:SetColorTexture(cachedAR, cachedAG, cachedAB, opacity)
                                        end
                                        g:ClearAllPoints()
                                        g:SetSize(1, segEnd - segY)
                                        g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", texture._pos, segY)
                                        g:Show()
                                    end
                                end
                                segY = segEnd
                            end
                        else
                            local spanStart = max(0, curX - halfSpan)
                            local spanEnd = min(screenW, curX + halfSpan)
                            local segX = spanStart
                            while segX < spanEnd do
                                local segEnd = min(segX + segSize, spanEnd)
                                local midX = (segX + segEnd) * 0.5
                                local deltaX = midX - curX
                                local deltaY = texture._pos - cyFromTop
                                local d2 = deltaX * deltaX + deltaY * deltaY
                                if d2 < R2 then
                                    local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                    local opacity = LIGHT_BOOST * t * t
                                    if opacity > 0.003 then
                                        glowIdx = glowIdx + 1
                                        local g = GetGlow(glowIdx)
                                        if isW then
                                            g:SetColorTexture(1, 1, 1, opacity)
                                        else
                                            g:SetColorTexture(cachedAR, cachedAG, cachedAB, opacity)
                                        end
                                        g:ClearAllPoints()
                                        g:SetSize(segEnd - segX, 1)
                                        g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", segX, -texture._pos)
                                        g:Show()
                                    end
                                end
                                segX = segEnd
                            end
                        end
                    end
                end
            end

            for jdx = glowIdx + 1, #self._glows do
                if self._glows[jdx] then self._glows[jdx]:Hide() end
            end
        end)

        return LM.gridFrame
    end

    -------------------------------------------------------------------------------
    --  Alignment guide lines (snap guides between bars)
    -------------------------------------------------------------------------------
    local activeGuides = {}

    local function GetGuide(position)
        if guidePool[position] then return guidePool[position] end
        local texture = LM.unlockFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        texture:SetColorTexture(1, 1, 1, 1)
        guidePool[position] = texture
        return texture
    end

    -- Snap highlight: a pulsing white border layered ON TOP of the green one. Each
    -- mover gets a lazy _snapBrd (a second MakeBorder at a higher frame level) so the
    -- green accent border stays visible underneath.
    local snapLitKey = nil -- barKey of mover currently showing snap highlight border
    local snapHighlightAnim = nil -- OnUpdate frame for the pulsing border
    local snapHighlightElapsed = 0

    local function GetOrCreateSnapBorder(handle)
        if handle._snapBrd then return handle._snapBrd end
        local brd = CUI.MakeBorder(handle, 1, 1, 1, 0)
        -- Raise above the accent border
        brd._frame:SetFrameLevel(handle:GetFrameLevel() + 3)
        handle._snapBrd = brd
        return brd
    end

    local function DropSnapHighlight()
        if snapLitKey and handles[snapLitKey] then
            local handle = handles[snapLitKey]
            if handle._snapBrd then handle._snapBrd:SetColor(1, 1, 1, 0) end
            -- Restore normal overlay brightness
            if LM.darkOverlaysEnabled and handle._bg then
                handle._bg:SetColorTexture(
                    handle._bgR or 0.075,
                    handle._bgG or 0.113,
                    handle._bgB or 0.141,
                    0.95
                )
            end
        end
        snapLitKey = nil
        snapHighlightElapsed = 0
        if snapHighlightAnim then
            snapHighlightAnim:SetScript("OnUpdate", nil)
            snapHighlightAnim:Hide()
        end
    end

    local function ShowSnapHighlight(targetKey)
        if targetKey == snapLitKey then return end
        -- Hide old highlight
        if snapLitKey and handles[snapLitKey] then
            local old = handles[snapLitKey]
            if old._snapBrd then old._snapBrd:SetColor(1, 1, 1, 0) end
            if LM.darkOverlaysEnabled and old._bg then
                old._bg:SetColorTexture(old._bgR or 0.075, old._bgG or 0.113, old._bgB or 0.141, 0.95)
            end
        end
        local handle = handles[targetKey]
        if not handle then
            DropSnapHighlight()
            return
        end
        snapLitKey = targetKey
        snapHighlightElapsed = 0
        GetOrCreateSnapBorder(handle)
        -- Brighten the mover's base color
        if LM.darkOverlaysEnabled and handle._bg then
            handle._bg:SetColorTexture(
                (handle._bgR or 0.075) * 1.4,
                (handle._bgG or 0.113) * 1.4,
                (handle._bgB or 0.141) * 1.4,
                0.95
            )
        end
        if not snapHighlightAnim then snapHighlightAnim = CreateFrame("Frame") end
        snapHighlightAnim:SetScript("OnUpdate", function(self, elapsed)
            snapHighlightElapsed = snapHighlightElapsed + elapsed
            local target = handles[snapLitKey]
            if not target or not target._snapBrd then
                DropSnapHighlight()
                return
            end
            local opacity = 0.45 + 0.45 * sin(snapHighlightElapsed * 9.42)
            target._snapBrd:SetColor(1, 1, 1, opacity * 0.9)
        end)
        snapHighlightAnim:Show()
    end

    local function HideAllGuides()
        for _, texture in ipairs(guidePool) do
            texture:Hide()
        end
        wipe(activeGuides)
    end

    -- Full cleanup including snap highlight (used when drag stops)
    local function HideAllGuidesAndHighlight()
        HideAllGuides()
        DropSnapHighlight()
    end

    -------------------------------------------------------------------------------
    --  ShowAlignmentGuides: draws full-screen guide lines at snap positions.
    --  Called from the drag OnUpdate; snapInfo is populated by SnapPosition.
    -------------------------------------------------------------------------------
    local prevSnap = {} -- written by SnapPosition, read by ShowAlignmentGuides
    -- Expose whether each axis has an active edge snap so OnUpdate can skip
    -- SnapForES on that axis (the unsnapped value already matches the target edge).
    CUI._snapAxisLocked = function() return prevSnap.lockX, prevSnap.lockY end

    local function ShowAlignmentGuides(dragKey)
        HideAllGuides()
        if not prevSnap then return end

        local accR, accG, accB = AccentColor()
        local guideIdx = 0
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()

        -- Edge/center snap guide lines (1 physical pixel wide)
        local PPg = CUI and CUI.PP
        local onePx = PPg and PPg.mult or 1
        if prevSnap.snapXPos then
            guideIdx = guideIdx + 1
            local g = GetGuide(guideIdx)
            g:SetColorTexture(accR, accG, accB, 0.5)
            g:ClearAllPoints()
            g:SetSize(onePx, screenH)
            g:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", prevSnap.snapXPos, 0)
            g:Show()
            activeGuides[guideIdx] = g
        end
        if prevSnap.snapYPos then
            guideIdx = guideIdx + 1
            local g = GetGuide(guideIdx)
            g:SetColorTexture(accR, accG, accB, 0.5)
            g:ClearAllPoints()
            g:SetSize(screenW, onePx)
            g:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, prevSnap.snapYPos)
            g:Show()
            activeGuides[guideIdx] = g
        end

        -- Snap highlight: pulse the border of the element being snapped to
        local dragMover = handles[dragKey]
        local hasSpecificTarget = dragMover
            and dragMover._snapTarget
            and dragMover._snapTarget ~= "_disable_"
            and dragMover._snapTarget ~= "_select_"
        if hasSpecificTarget and handles[dragMover._snapTarget] then
            ShowSnapHighlight(dragMover._snapTarget)
        elseif prevSnap.closestKey then
            ShowSnapHighlight(prevSnap.closestKey)
        else
            DropSnapHighlight()
        end
    end

    -------------------------------------------------------------------------------
    --  Snap-to-element helper: 1) find the single closest mover (min edge-to-edge
    --  distance, within SNAP_PROXIMITY px). 2) check 9 X-axis + 9 Y-axis pairs against
    --  that one mover. Populates lastSnapInfo for ShowAlignmentGuides to read.
    -------------------------------------------------------------------------------

    local function SnapPosition(dragKey, cx, cy, halfW, halfH)
        wipe(prevSnap)
        if not LM.snapEnabled then return cx, cy end

        local dL = cx - halfW
        local dR = cx + halfW
        local dT = cy + halfH
        local dB = cy - halfH

        -- Step 1: find snap target mover
        -- If this mover has a specific snap target, use it; otherwise find closest
        local closestKey = nil
        local dragMover = handles[dragKey]
        local perMoverTarget = dragMover and dragMover._snapTarget
        -- "_disable_" = snapping disabled for this specific mover
        if perMoverTarget == "_disable_" then return cx, cy end
        if
            perMoverTarget
            and perMoverTarget ~= dragKey
            and handles[perMoverTarget]
            and handles[perMoverTarget]:IsShown()
        then
            closestKey = perMoverTarget
        else
            -- Find closest by true 2D edge-to-edge distance (no limit)
            local closestMinDist = math.huge
            -- Exclude from snap: all descendants (children, grandchildren, etc.) and
            -- siblings (anchored to the same parent). The direct parent IS allowed.
            local dragExcluded = {}
            local anchorDB = GetAnchorDB()
            if anchorDB then
                -- Recursively exclude all descendants
                local function ExcludeDescendants(parentKey)
                    for childKey, details in pairs(anchorDB) do
                        if details.target == parentKey and not dragExcluded[childKey] then
                            dragExcluded[childKey] = true
                            ExcludeDescendants(childKey)
                        end
                    end
                end
                ExcludeDescendants(dragKey)
                -- Exclude siblings (share the same anchor parent)
                local myInfo = anchorDB[dragKey]
                if myInfo and myInfo.target then
                    for sibKey, sibInfo in pairs(anchorDB) do
                        if sibKey ~= dragKey and sibInfo.target == myInfo.target then
                            dragExcluded[sibKey] = true
                        end
                    end
                end
            end
            for barKey, mover in pairs(handles) do
                if barKey ~= dragKey and not dragExcluded[barKey] and mover:IsShown() then
                    local oL = mover:GetLeft() or 0
                    local oR = mover:GetRight() or 0
                    local oT = mover:GetTop() or 0
                    local oB = mover:GetBottom() or 0
                    -- Signed axis distances (negative = overlapping on that axis)
                    local gapX = 0
                    if dR < oL then
                        gapX = oL - dR
                    elseif dL > oR then
                        gapX = dL - oR
                    end
                    local gapY = 0
                    if dB > oT then
                        gapY = dB - oT
                    elseif dT < oB then
                        gapY = oB - dT
                    end
                    -- 2D edge-to-edge distance (0 if overlapping)
                    local edgeDist = sqrt(gapX * gapX + gapY * gapY)
                    if edgeDist < closestMinDist then
                        closestMinDist = edgeDist
                        closestKey = barKey
                    end
                end
            end
        end

        prevSnap.closestKey = closestKey
        local bestDX, bestDistX = 0, SNAP_THRESH
        local bestDY, bestDistY = 0, SNAP_THRESH
        local snapXLinePos, snapYLinePos = nil, nil

        -- Step 2: 9+9 edge pairs against closest mover
        if closestKey then
            local handle = handles[closestKey]
            local oL = handle:GetLeft() or 0
            local oR = handle:GetRight() or 0
            local oT = handle:GetTop() or 0
            local oB = handle:GetBottom() or 0
            local oCX = (oL + oR) * 0.5
            local oCY = (oT + oB) * 0.5

            -- X-axis: dragged {left, center, right} vs target {left, center, right}
            local dragXEdges = { dL, cx, dR }
            local targXEdges = { oL, oCX, oR }
            for _, de in ipairs(dragXEdges) do
                for _, te in ipairs(targXEdges) do
                    local deltaX = de - te
                    local adx = abs(deltaX)
                    if adx < bestDistX then
                        bestDistX = adx
                        bestDX = deltaX
                        snapXLinePos = te
                    end
                end
            end

            -- Y-axis: dragged {top, center, bottom} vs target {top, center, bottom}
            local dragYEdges = { dT, cy, dB }
            local targYEdges = { oT, oCY, oB }
            for _, de in ipairs(dragYEdges) do
                for _, te in ipairs(targYEdges) do
                    local deltaY = de - te
                    local ady = abs(deltaY)
                    if ady < bestDistY then
                        bestDistY = ady
                        bestDY = deltaY
                        snapYLinePos = te
                    end
                end
            end
        end

        -- Apply edge/center snap
        local snapX = cx
        local snapY = cy
        if bestDistX < SNAP_THRESH then snapX = cx - bestDX end
        if bestDistY < SNAP_THRESH then snapY = cy - bestDY end

        -- Record guide line positions for ShowAlignmentGuides
        if bestDistX < SNAP_THRESH and snapXLinePos then
            prevSnap.snapXPos = snapXLinePos
            prevSnap.lockX = true -- skip SnapForES on X axis
        end
        if bestDistY < SNAP_THRESH and snapYLinePos then
            prevSnap.snapYPos = snapYLinePos
            prevSnap.lockY = true -- skip SnapForES on Y axis
        end

        return snapX, snapY
    end

    -------------------------------------------------------------------------------
    --  Selection + Arrow Key Nudge System
    -------------------------------------------------------------------------------
    -- Selection highlight: a low-opacity white fill over the selected element's
    -- overlay background, so the currently-selected element (the one arrow keys
    -- move) is clearly marked, like the snap-target highlight shown during drag.
    local function SetSelectionHighlight(handle, enabled)
        if not handle then return end
        if enabled then
            if not handle._selHl then
                local highlight = handle:CreateTexture(nil, "ARTWORK")
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, 1)
                handle._selHl = highlight
            end
            handle._selHl:SetAlpha(0.10)
            handle._selHl:Show()
        elseif handle._selHl then
            handle._selHl:Hide()
        end
    end

    local function SelectMover(handle)
        local accR, accG, accB = AccentColor()
        -- Selecting a mover releases any selected fallback ghost (one arrow-key
        -- target at a time)
        if CUI._DeselectFallbackGhosts then CUI._DeselectFallbackGhosts() end
        if CUI._DeselectOverrideGhosts then CUI._DeselectOverrideGhosts() end
        -- Deselect previous
        if LM.selectedMover and LM.selectedMover ~= handle then
            LM.selectedMover._selected = false
            SetSelectionHighlight(LM.selectedMover, false)
            if not LM.selectedMover._dragging and not LM.selectedMover:IsMouseOver() then
                LM.selectedMover:SetFrameLevel(LM.selectedMover._baseLevel)
                if not LM.darkOverlaysEnabled then LM.selectedMover:SetAlpha(MOVER_ALPHA) end
                LM.selectedMover._brd:SetColor(accR, accG, accB, 0.6)
                -- Collapse overlay on old selection
                if LM.selectedMover._hideOverlayText then LM.selectedMover._hideOverlayText() end
            end
            -- Hide action buttons on old selection
            if LM.selectedMover._hideCogAfterDelay then LM.selectedMover._hideCogAfterDelay() end
            -- Hide coordinates on old selection (keep if coords-always-on)
            if LM.selectedMover._coordFS and not LM.coordsEnabled then LM.selectedMover._coordFS:Hide() end
        end
        LM.selectedMover = handle
        if handle then
            handle._selected = true
            SetSelectionHighlight(handle, true)
            handle:SetFrameLevel(handle._raisedLevel)
            if not LM.darkOverlaysEnabled then handle:SetAlpha(MOVER_HOVER) end
            handle._brd:SetColor(1, 1, 1, 0.9)

            -- Update coordinates on selection (expansion is hover-only)
            if handle.UpdateCoordText then handle:UpdateCoordText() end

            -- Pulse the snap target if this mover has a specific one assigned
            local tgt = handle._snapTarget
            if tgt and tgt ~= "_disable_" and tgt ~= "_select_" and handles[tgt] then
                ShowSnapHighlight(tgt)
            else
                DropSnapHighlight()
            end
        end
    end

    local function DeselectMover()
        if LM.selectedMover then
            local accR, accG, accB = AccentColor()
            LM.selectedMover._selected = false
            SetSelectionHighlight(LM.selectedMover, false)
            if not LM.selectedMover._dragging then
                if not LM.selectedMover:IsMouseOver() then
                    LM.selectedMover:SetFrameLevel(LM.selectedMover._baseLevel)
                    if not LM.darkOverlaysEnabled then LM.selectedMover:SetAlpha(MOVER_ALPHA) end
                    LM.selectedMover._brd:SetColor(accR, accG, accB, 0.6)
                    if LM.selectedMover._hideOverlayText then LM.selectedMover._hideOverlayText() end
                end
            end
            -- Restore settings widgets to base level
            -- Hide coordinates (keep visible if coords-always-on mode is active)
            if LM.selectedMover._coordFS and not LM.coordsEnabled then LM.selectedMover._coordFS:Hide() end
            -- Clear snap highlight
            DropSnapHighlight()
            -- Cancel select-element pick mode if this mover was the picker -- restore previous target
            if LM.selectElementPicker == LM.selectedMover then
                LM.selectedMover._snapTarget = LM.selectedMover._preSelectTarget
                LM.selectedMover._preSelectTarget = nil
                if LM.selectedMover._updateSnapLabel then LM.selectedMover._updateSnapLabel() end
                LM.selectElementPicker = nil
                FadeOverlayForSelectElement(false)
            end
            -- Cancel width/height/anchor pick mode if this mover was the picker
            if LM.pickModeMover == LM.selectedMover then CancelPickMode() end
        end
        LM.selectedMover = nil
        if CUI._DeselectFallbackGhosts then CUI._DeselectFallbackGhosts() end
        if CUI._DeselectOverrideGhosts then CUI._DeselectOverrideGhosts() end
    end

    -- Namespace bridge so the fallback ghost overlays (defined earlier in the
    -- file) can release a selected mover when a ghost is clicked.
    CUI._DeselectSelectedMover = DeselectMover

    -- Selection flash: a 2 px accent border over the mover pulsed three times
    -- when Unlock Mode opens at an element (the options rows' Move in Unlock Mode
    -- button), on one shared driver that is hidden and script-less while idle.
    -- It ends at alpha 0, so the selected state's white border and fill stay as
    -- SelectMover left them; a selection change, the mover hiding or the session
    -- closing ends it early. Accent rather than white: white would vanish over
    -- the selected border.
    local FLASH_PERIOD, FLASH_PULSES = 0.4, 3
    local FLASH_DUR = FLASH_PERIOD * FLASH_PULSES
    local flashFrame, flashM, flashT, flashR, flashG, flashB

    local function EndFlash()
        if flashFrame then
            flashFrame:SetScript("OnUpdate", nil)
            flashFrame:Hide()
        end
        local handle = flashM
        flashM = nil
        if not handle then return end
        handle._selFlashBrd:SetColor(flashR, flashG, flashB, 0)
        if handle._selHl and handle._selected then handle._selHl:SetAlpha(0.10) end
    end

    local function FlashTick(self, dt)
        local handle = flashM
        if not handle or not LM.isUnlocked or not handle._selected or not handle:IsShown() then
            return EndFlash()
        end
        flashT = flashT + dt
        if flashT >= FLASH_DUR then return EndFlash() end
        local p = sin(math.pi * flashT / FLASH_PERIOD)
        p = p * p
        handle._selFlashBrd:SetColor(flashR, flashG, flashB, p)
        if handle._selHl then handle._selHl:SetAlpha(0.10 + 0.25 * p) end
    end

    local function FlashSelectHighlight(handle)
        if not handle or not handle._brd or not handle:IsShown() then return end
        if flashM and flashM ~= handle then EndFlash() end
        if not handle._selFlashBrd then
            handle._selFlashBrd = CUI.MakeBorder(handle, 1, 1, 1, 0)
            Pix.SetBorderSize(handle._selFlashBrd._frame, 2)
        end
        -- The mover is raised on select, so the border takes its level each flash.
        handle._selFlashBrd._frame:SetFrameLevel(handle:GetFrameLevel() + 4)
        flashR, flashG, flashB = AccentColor()
        flashM, flashT = handle, 0
        if not flashFrame then flashFrame = CreateFrame("Frame") end
        flashFrame:SetScript("OnUpdate", FlashTick)
        flashFrame:Show()
    end

    -- Apply dark overlay state to all movers
    local function ApplyDarkOverlays()
        for _, handle in pairs(handles) do
            if LM.darkOverlaysEnabled then
                handle._bg:SetColorTexture(
                    handle._bgR or 0.075,
                    handle._bgG or 0.113,
                    handle._bgB or 0.141,
                    0.95
                )
                if handle._label then
                    handle._label:SetAlpha(1)
                    handle._label:Show()
                end
                if handle._subtitle then
                    handle._subtitle:SetAlpha(1)
                    handle._subtitle:Show()
                end
                if handle._coordFS then handle._coordFS:SetAlpha(1) end
                -- Action row is hover-only now, don't show it here
                if not handle._dragging then handle:SetAlpha(1) end
            else
                handle._bg:SetColorTexture(0, 0, 0, 0)
                if handle._label then handle._label:Hide() end
                if handle._subtitle then handle._subtitle:Hide() end
                -- When coords-always-on is active, show coords for all movers; otherwise hide
                if handle._coordFS then
                    if LM.coordsEnabled then
                        if handle.UpdateCoordText then handle:UpdateCoordText() end
                    else
                        handle._coordFS:Hide()
                    end
                end
                -- Hide action row text
                if handle._hideOverlayText then handle._hideOverlayText() end
                -- Restore normal alpha behavior
                if not handle._dragging and not handle._selected and not handle:IsMouseOver() then
                    handle:SetAlpha(MOVER_ALPHA)
                end
            end
        end
    end
    -- Attach a mover to its bar's TOPLEFT, inset by il/-it (UIParent units). An
    -- element whose frame carries a forbidden layout aspect (a Blizzard Style unit
    -- cast bar riding its frame's aura stack, created with Blizzard's
    -- DisableUntrustedLayoutScriptsTemplate) refuses dependents that lack the
    -- aspect, so its mover takes the same screen spot by absolute anchor instead
    -- (elem.detachedMover); every sync and apply path re-runs this, so it keeps
    -- up outside of drags.
    local function AttachMoverToBar(handle, barFrame, barKey, il, it)
        handle:ClearAllPoints()
        local element = registeredElements[barKey]
        if element and element.detachedMover then
            local bL, bT = barFrame:GetLeft(), barFrame:GetTop()
            if not (issecretvalue and (issecretvalue(bL) or issecretvalue(bT))) and bL and bT then
                local r = barFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                handle:SetPoint(
                    "TOPLEFT",
                    UIParent,
                    "TOPLEFT",
                    bL * r + (il or 0),
                    bT * r - UIParent:GetHeight() - (it or 0)
                )
            else
                -- No readable rect yet: park at the screen centre (the bar's own
                -- anchor is the one this element refuses) until the next sync.
                handle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            return
        end
        handle:SetPoint("TOPLEFT", barFrame, "TOPLEFT", il or 0, -(it or 0))
    end
    -- CreateMover is at Lua's 60-upvalue cap: its closures call this through the
    -- namespace table (already an upvalue there), like NudgeMover below.
    CUI._unlockAttachMover = AttachMoverToBar

    local function NudgeMover(deltaX, deltaY, targetMover, skipCollapse)
        local handle = targetMover or LM.selectedMover
        if not handle or InCombatLockdown() then return end
        if mod.IsMoverPosLocked(handle._barKey) then return end

        -- Read bar's current position, add dx/dy, reposition.
        local barFrame = LM.GetBarFrame(handle._barKey)
        if not barFrame then return end

        -- An element that places itself (ownsPosition) moves like an unanchored one:
        -- its links are inert.
        local element = registeredElements[handle._barKey]
        local anchorInfo = not (element and element.ownsPosition) and GetAnchorInfo(handle._barKey) or nil
        if anchorInfo and anchorInfo.target then
            -- Anchored: adjust offset relative to target frame (not UIParent). Reading
            -- GetPoint(1) on an anchored element returns args relative to the target frame -- applying those to UIParent teleports the bar.
            anchorInfo.offsetX = (anchorInfo.offsetX or 0) + deltaX
            anchorInfo.offsetY = (anchorInfo.offsetY or 0) + deltaY
            -- The growth-edge pin rides the same nudge on its axis.
            if anchorInfo.edgeOffX ~= nil then anchorInfo.edgeOffX = anchorInfo.edgeOffX + deltaX end
            if anchorInfo.edgeOffY ~= nil then anchorInfo.edgeOffY = anchorInfo.edgeOffY + deltaY end
            -- An axis held by the cross-axis screen edge takes the nudge there, or the
            -- next apply overwrites it from the untouched edge offset.
            if anchorInfo.edge and anchorInfo.edge.key then
                local nAxis = CUI._ScreenEdgeAxis(anchorInfo.edge.key)
                if nAxis == "X" then
                    anchorInfo.edge.offset = (anchorInfo.edge.offset or 0) + deltaX
                elseif nAxis == "Y" then
                    anchorInfo.edge.offset = (anchorInfo.edge.offset or 0) + deltaY
                end
            end
            LM.ApplyAnchorPosition(handle._barKey, anchorInfo.target, anchorInfo.side)
            -- Capture the bar's resulting position so CommitPositions saves the real
            -- (nudged) location. ApplyAnchorPosition always anchors the bar to UIParent,
            -- so GetPoint(1) is UIParent-relative and safe to store. A coordless
            -- {_anchored=true} marker would make CommitPositions fall back to the
            -- pre-edit snapshot, reverting bars that read their saved edge on exit/reload.
            local bpt, brelTo, brp, bx, by = barFrame:GetPoint(1)
            if bpt and brelTo == UIParent and bx ~= nil and by ~= nil then
                pendingPositions[handle._barKey] = { point = bpt, relPoint = brp, x = bx, y = by }
            else
                pendingPositions[handle._barKey] = { _anchored = true }
            end
        else
            -- Unanchored: read current position, add dx/dy
            local pt, _, relPt, offX, offY = barFrame:GetPoint(1)
            if not pt then return end
            pcall(function()
                CUI.ClearFramePoints(barFrame)
                CUI.SetFramePoint(barFrame, pt, UIParent, relPt, offX + deltaX, offY + deltaY)
            end)
            -- Keep the LOGICAL pending value exact for CENTER/CENTER elements: previous
            -- pending/stored value + the exact delta, never a live geometry read-back.
            -- Odd-pixel-dimension frames apply with a half-pixel physical center, so
            -- reading the frame back here would bake that half pixel (and its rounding) into the saved value -- "nudged to -368, saves back as -369".
            local prev = pendingPositions[handle._barKey]
            if type(prev) ~= "table" or prev._anchored or not prev.point then
                local elemN = registeredElements[handle._barKey]
                prev = elemN and elemN.loadPosition and elemN.loadPosition(handle._barKey) or nil
                if not prev then prev = LoadBarPosition(handle._barKey) end
            end
            if
                type(prev) == "table"
                and prev.point == "CENTER"
                and (prev.relPoint or "CENTER") == "CENTER"
                and prev.x
                and prev.y
            then
                pendingPositions[handle._barKey] = {
                    point = "CENTER",
                    relPoint = "CENTER",
                    x = prev.x + deltaX,
                    y = prev.y + deltaY,
                }
            else
                pendingPositions[handle._barKey] = {
                    point = pt,
                    relPoint = relPt,
                    x = offX + deltaX,
                    y = offY + deltaY,
                }
            end
        end
        -- Same element follow-up the drag gives after each placement (main chat
        -- restores its size corner), before the mover and the anchor chain read
        -- the frame's rect.
        if element and element.onLiveMove then pcall(element.onLiveMove, handle._barKey) end
        LM.hasChanges = true

        -- Reanchor mover to bar, inside the element's visual insets (see Sync).
        local nIL, nIR, nIT, nIB = 0, 0, 0, 0
        if element and element.getInsets then
            local l, r, t, bt = element.getInsets(handle._barKey)
            if l then
                local es = barFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                nIL, nIR, nIT, nIB = l * es, (r or 0) * es, (t or 0) * es, (bt or 0) * es
            end
        end
        AttachMoverToBar(handle, barFrame, handle._barKey, nIL, nIT)

        -- Update stored mover center from bar's new position
        local bL, bR = barFrame:GetLeft(), barFrame:GetRight()
        local bT, bB = barFrame:GetTop(), barFrame:GetBottom()
        if bL and bR and bT and bB then
            local s = barFrame:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local ratio = s / uiS
            local cx = (bL + bR) * 0.5 * ratio + (nIL - nIR) * 0.5
            local cy = (bT + bB) * 0.5 * ratio - UIParent:GetHeight() + (nIB - nIT) * 0.5
            if handle._setCenterXY then handle._setCenterXY(cx, cy) end
        end

        -- Propagate to anchored children
        LM.PropagateAnchorChain(handle._barKey)

        -- Update coordinate readout
        if handle.UpdateCoordText then handle:UpdateCoordText() end

        -- Collapse the mover while nudging (arrow keys only). Typed cog edits pass
        -- skipCollapse so the open cog menu, which is anchored to the mover, does
        -- not jump or shrink while the user is typing in it.
        if not skipCollapse then
            if handle._forceCollapse then handle._forceCollapse() end
            handle._nudgeCollapsed = true
        end
    end

    -- Exposed so the cog X/Y edit boxes can drive the SAME pixel-exact move the
    -- arrow keys use. Calling through the namespace table (already an upvalue in
    -- CreateMover) avoids adding NudgeMover as a new upvalue to that large closure.
    CUI._unlockNudge = NudgeMover

    -- Grow-direction change for a growth bar in unlock mode, the cog's Grow row in
    -- one call: write the module's setting and relayout, put the bar's visual center
    -- back where it was (a relayout can shift the frame around its new fixed edge),
    -- re-anchor by the new growth edge and record the position for Save & Exit.
    -- Shared with the anchor picker's corner rows, which set the direction AFTER
    -- placing the bar flush so the growth-edge hold captures from where it sits.
    -- On the namespace table like the nudge: CreateMover is at the upvalue cap.
    CUI._unlockSetGrowDirection = function(barId, val)
        LM.hasChanges = true

        -- Capture the bar's visual center before changing grow
        local barFrame = LM.GetBarFrame(barId)
        local preCX, preCY
        if barFrame then
            preCX, preCY = barFrame:GetCenter()
        end

        -- Write to the bar's actual settings DB and rebuild layout
        if barId:sub(1, 4) == "CDM_" then
            local rawKey = barId:sub(5)
            local cdm = CUI.Lite.GetAddon("CludesUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, barFrame in ipairs(cdmBars.bars) do
                    if barFrame.key == rawKey then
                        barFrame.growDirection = val
                        break
                    end
                end
            end
            if CUI.LayoutCDMBar then CUI.LayoutCDMBar(rawKey) end
            CUI.RecenterBarAnchor(barId)
        elseif barId == "ERB_TotemBar" then
            local erb = CUI.Lite.GetAddon("CludesUIResourceBars", true)
            local tb = erb and erb.db and erb.db.profile and erb.db.profile.totemBar
            if tb then tb.growDirection = val end
            if CUI.LayoutTotemBar then CUI.LayoutTotemBar() end
            CUI.RecenterBarAnchor(barId)
        elseif barId == "EABR_Reminders" then
            if CUI.SetAuraBuffGrowDir then CUI.SetAuraBuffGrowDir(val) end
            CUI.RecenterBarAnchor(barId)
        elseif barId:sub(1, 4) == "PAB_" then
            local euf = CUI.Lite.GetAddon("CludesUIUnitFrames", true)
            if euf and euf.SetGrowDirectionForBar then euf:SetGrowDirectionForBar(barId, val) end
        else
            local eab = CUI.Lite.GetAddon("CludesUIActionBars", true)
            if eab and eab.SetGrowDirectionForBar then eab:SetGrowDirectionForBar(barId, val) end
        end

        -- Restore the bar's visual center so it doesn't jump,
        -- then re-anchor based on the new growth direction.
        if barFrame and preCX and preCY then
            local postCX, postCY = barFrame:GetCenter()
            if postCX and postCY then
                local deltaX = preCX - postCX
                local deltaY = preCY - postCY
                if math.abs(deltaX) > 0.5 or math.abs(deltaY) > 0.5 then
                    local pt, relTo, relPt, offX, offY = barFrame:GetPoint(1)
                    if pt then
                        CUI.ClearFramePoints(barFrame)
                        CUI.SetFramePoint(barFrame, pt, relTo, relPt, offX + deltaX, offY + deltaY)
                    end
                end
            end
        end
        CUI.RecenterBarAnchor(barId)
        -- Anchored bars: hold the new growth edge from where the bar sits NOW, the
        -- way the drag-stop path does after a drop. Left to the lazy capture, the
        -- next apply would read the rect BEFORE the move it was asked to make (a
        -- first nudge, a first drag of the target) and stamp that stale hold; and a
        -- hold left over from an earlier direction would be trusted again the day
        -- that direction comes back. Centered growth keeps no hold.
        local anchorInfo = GetAnchorInfo(barId)
        if anchorInfo and anchorInfo.target then
            anchorInfo.refFor, anchorInfo.refX, anchorInfo.refY, anchorInfo.edgeOffX, anchorInfo.edgeOffY =
                nil, nil, nil, nil, nil
            if CUI._unlockCaptureGrowPin then
                CUI._unlockCaptureGrowPin(barId, anchorInfo, anchorInfo.side)
            end
        end
        -- Store in pending (committed on Save & Exit)
        if barFrame then
            local pt2, relTo2, relPt2, offX2, offY2 = barFrame:GetPoint(1)
            if pt2 then
                pendingPositions[barId] = {
                    point = pt2,
                    relPoint = relPt2,
                    x = offX2,
                    y = offY2,
                }
                LM.hasChanges = true
            end
        end

        -- Sync the mover to the bar's new position
        if handles[barId] and handles[barId].Sync then handles[barId]:Sync() end
    end

    -- Arrow key nudge: single press only, no hold-to-repeat
    local function SetupArrowKeyFrame()
        if LM.arrowKeyFrame then return end
        LM.arrowKeyFrame = CreateFrame("Frame", nil, UIParent)
        LM.arrowKeyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        LM.arrowKeyFrame:SetFrameLevel(500)
        LM.arrowKeyFrame:EnableKeyboard(true)
        LM.arrowKeyFrame:SetPropagateKeyboardInput(true)
        LM.arrowKeyFrame:Hide()

        -- Keep scrolling passing through until the cycling modifier matches.
        LM.arrowKeyFrame:SetScript("OnShow", function(self) LM.UpdateMoverMouseWheel() end)
        LM.arrowKeyFrame:SetScript("OnHide", function(self)
            self:UnregisterEvent("MODIFIER_STATE_CHANGED")
            LM.UpdateMoverMouseWheel()
        end)
        LM.arrowKeyFrame:SetScript("OnEvent", function() LM.UpdateMoverMouseWheel() end)

        local ARROW_DIRS = {
            UP = { 0, 1 },
            DOWN = { 0, -1 },
            LEFT = { -1, 0 },
            RIGHT = { 1, 0 },
        }

        -- One arrow press in physical pixels: 1, Ctrl 10, Shift 100.
        local function ArrowStep()
            local PPs = CUI and CUI.PP
            local px = PPs and PPs.mult or 1
            if IsShiftKeyDown() then return 100 * px end
            if IsControlKeyDown() then return 10 * px end
            return px
        end

        LM.arrowKeyFrame:SetScript("OnKeyDown", function(self, barKey)
            if not LM.isUnlocked or InCombatLockdown() then return end
            local direction = ARROW_DIRS[barKey]
            if not direction then return end
            -- A selected fallback ghost answers the arrow keys with the exact
            -- same step math as movers (ArrowStep).
            if not LM.selectedMover and CUI._NudgeSelectedFallbackGhost then
                local gs = ArrowStep()
                if CUI._NudgeSelectedFallbackGhost(direction[1] * gs, direction[2] * gs) then
                    self:SetPropagateKeyboardInput(false)
                    return
                end
            end
            -- A selected override-anchor ghost answers the same way.
            if not LM.selectedMover and CUI._NudgeSelectedOverrideGhost then
                local os = ArrowStep()
                if CUI._NudgeSelectedOverrideGhost(direction[1] * os, direction[2] * os) then
                    self:SetPropagateKeyboardInput(false)
                    return
                end
            end
            if not LM.selectedMover then return end
            self:SetPropagateKeyboardInput(false)
            -- Physical pixels (ArrowStep): 1px a press, Ctrl 10, Shift 100
            local step = ArrowStep()
            -- When this element's cog/snap menu is open, keep the mover expanded
            -- (skipCollapse) so the open menu does not jump, then reanchor to the bar
            -- and refresh the cog X/Y boxes so they track the nudge.
            local handle = LM.selectedMover
            local menuOpen = handle._menuOpen
            NudgeMover(direction[1] * step, direction[2] * step, nil, menuOpen)
            if menuOpen then
                if handle.ReanchorToBar then handle:ReanchorToBar() end
                if handle._syncCogPos then handle._syncCogPos() end
            end
        end)

        LM.arrowKeyFrame:SetScript("OnKeyUp", function(self, barKey) self:SetPropagateKeyboardInput(true) end)
    end

    -------------------------------------------------------------------------------
    --  Action bar visual size helper: computes the actual visual size of an action bar
    --  accounting for overrideNumIcons, overrideNumRows, padding, and per-button scale.
    --  Returns w, h in UIParent-relative pixels, or nil if not applicable.
    -------------------------------------------------------------------------------
    local function GetActionBarVisualSize(barId)
        if not ABAR or not ABAR.db then return nil end
        local details = BAR_LOOKUP[barId]
        if not details then return nil end
        local cfg = ABAR.db.profile.bars[lookupKey]
        if not cfg then return nil end

        -- Use standard button size (45x45) -- our LayoutBar uses this for MainBar
        -- and reads from the button for others.
        local btnW, btnH = 45, 45
        local btn1 = _G[details.buttonPrefix .. "1"]
        if btn1 and lookupKey ~= "MainBar" then
            local bw = btn1:GetWidth()
            if bw and bw > 1 then
                btnW, btnH = bw, btn1:GetHeight()
            end
        end

        local numVisible = cfg.overrideNumIcons or cfg.numIcons or details.count
        if numVisible < 1 then numVisible = details.count end
        local numRows = cfg.overrideNumRows or cfg.numRows or 1
        if numRows < 1 then numRows = 1 end

        local pad = cfg.buttonPadding or 2

        -- Use explicit button dimensions if set
        local bwOverride = (cfg.buttonWidth and cfg.buttonWidth > 0) and cfg.buttonWidth or nil
        local bhOverride = (cfg.buttonHeight and cfg.buttonHeight > 0) and cfg.buttonHeight or nil
        if bwOverride then btnW = bwOverride end
        if bhOverride then btnH = bhOverride end

        local shape = cfg.buttonShape or "none"
        if shape ~= "none" and shape ~= "cropped" then
            btnW = btnW + (mod.SHAPE_BTN_EXPAND or 10)
            btnH = btnH + (mod.SHAPE_BTN_EXPAND or 10)
        end
        if shape == "cropped" then btnH = btnH * 0.80 end

        local isVert = (cfg.orientation == "vertical")
        local stride = math.ceil(numVisible / numRows)

        local gridW, gridH
        if isVert then
            gridW = numRows * btnW + (numRows - 1) * pad
            gridH = stride * btnH + (stride - 1) * pad
        else
            gridW = stride * btnW + (stride - 1) * pad
            gridH = numRows * btnH + (numRows - 1) * pad
        end

        return gridW, gridH
    end

    -------------------------------------------------------------------------------
    --  Mover overlay creation
    -------------------------------------------------------------------------------

    -- Sort movers by area so smaller elements render on top of larger ones.
    -- Called after all movers are created and synced.
    local function SortMoverFrameLevels()
        if not LM.unlockFrame then return end
        local BASE = LM.unlockFrame:GetFrameLevel() + 20
        -- A mover's border, labels, links and cog occupy levels through +12.
        local STEP = 16
        local sorted = {}
        for barKey, handle in pairs(handles) do
            local area = (handle:GetWidth() or 100) * (handle:GetHeight() or 100)
            sorted[#sorted + 1] = { key = barKey, mover = handle, area = area }
        end
        -- Largest area first -> lowest frame level
        table.sort(sorted, function(lhs, rhs) return lhs.area > rhs.area end)
        for i, record in ipairs(sorted) do
            local lvl = BASE + i * STEP
            record.mover._baseLevel = lvl
            record.mover._raisedLevel = lvl + (#sorted + 1) * STEP
            record.mover._cycleLowered = nil
            record.mover:SetFrameLevel(lvl)
            if record.mover._cogBtn then record.mover._cogBtn:SetFrameLevel(lvl + 10) end
        end
        -- Leave room above hovered movers (+100) and their point handles (+40).
        LM.moverOverlayLevel = math.max(250, BASE + (2 * #sorted + 1) * STEP + 160)
        if LM.moverOverlays then
            -- Parents are registered first; update them before their child menus.
            for _, widget in ipairs(LM.moverOverlays) do
                widget:SetFrameLevel(LM.moverOverlayLevel + widget._moverOverlayOffset)
            end
        end
        local confirm = _G.CUIConfirmDimmer
        if confirm and confirm:IsShown() then confirm:SetFrameLevel(LM.moverOverlayLevel + 100) end
    end

    -- Menus and anchor ghosts follow the stack when late registrations re-sort it.
    function LM.SetMoverOverlayLevel(widget, off)
        off = off or 0
        LM.moverOverlays = LM.moverOverlays or {}
        if widget._moverOverlayOffset == nil then LM.moverOverlays[#LM.moverOverlays + 1] = widget end
        widget._moverOverlayOffset = off
        widget:SetFrameLevel((LM.moverOverlayLevel or 250) + off)
    end

    -------------------------------------------------------------------------------
    --  Blizzard-Owned Info Overlays: visual overlays shown during unlock mode on
    --  elements whose position is controlled by Blizzard Edit Mode (chat, micro menu,
    --  bags, encounter bar). Not draggable. Hover shows accent-colored "Move via Blizz
    --  Edit Mode" text with the same animation as regular mover links; clicking closes unlock mode and opens Blizzard's Edit Mode.
    -------------------------------------------------------------------------------
    local BLIZZ_OWNED_OVERLAY_DEFS = {
        -- Chat is NOT here anymore: it is a REAL unlock element registered by
        -- CludesUIChat (position genesis-captured from Edit Mode's last spot,
        -- then enforced against Edit Mode via the chat module's anchor guard).
        {
            label = "Micro Menu",
            frame = function() return _G.MicroMenuContainer end,
        },
        {
            label = "Bags",
            frame = function() return _G.BagsBar end,
        },
        -- On WoW Forever only while the bar itself shows: no stand-in box over an
        -- empty spot.
        {
            label = "Encounter Bar",
            frame = function() return _G.PlayerPowerBarAlt end,
            showAlways = CUI.IS_FOREVER ~= true,
            fallbackW = 240,
            fallbackH = 36,
            yOffset = 44,
        },
        {
            label = "Buffs",
            frame = function() return _G.BuffFrame end,
        },
        {
            label = "Debuffs",
            frame = function() return _G.DebuffFrame end,
        },
        -- Blizzard Edit Mode's default tooltip anchor. CUI permanently owns the default
        -- tooltip position (fixed anchor in CludesUIBlizzardSkin, a real draggable
        -- mover) and Anchor to Cursor pins it to the mouse -- either way this read-only
        -- overlay steps aside. Only shows with "Reskin Tooltip" off, where Blizzard's
        -- position genuinely applies. Container is small/idle when no tooltip is up, so use the showAlways fallback like the Encounter Bar.
        {
            label = "Tooltip",
            frame = function()
                if not (CludesUIDB and CludesUIDB.customTooltips == false) then return nil end
                return _G.GameTooltipDefaultContainer
            end,
            showAlways = true,
            fallbackW = 280,
            fallbackH = 165,
        },
    }

    local function CreateBlizzOwnedOverlay(def, hostFrame)
        local accR, accG, accB = AccentColor()
        local shade = CreateFrame("Frame", nil, hostFrame)
        shade:EnableMouse(true)
        -- Background: same as regular movers
        local backdrop = shade:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.088, 0.098, 0.111, 0.95)
        -- Border: accent at idle, white on hover
        local brd = CUI.MakeBorder(shade, accR, accG, accB, 0.6)
        shade._brd = brd
        -- Label (always visible, same style as mover labels)
        local nameFs = shade:CreateFontString(nil, "OVERLAY")
        CUI.PrimeFontShadow(nameFs, true)
        nameFs:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        nameFs:SetPoint("CENTER", shade, "CENTER", 0, 0)
        nameFs:SetTextColor(1, 1, 1, 0.75)
        nameFs:SetText(CUI.L(def.label))
        nameFs:SetWordWrap(false)
        shade._nameFs = nameFs
        -- Action text (hidden at idle, fades in on hover)
        local actionText = shade:CreateFontString(nil, "OVERLAY")
        CUI.PrimeFontShadow(actionText, true)
        actionText:SetFont(FONT_PATH, 9 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        actionText:SetPoint("TOP", nameFs, "BOTTOM", 0, -2)
        actionText:SetTextColor(accR, accG, accB, 0.9)
        actionText:SetText(CUI.L("Move via Blizz Edit Mode"))
        actionText:SetAlpha(0)
        shade._actionFs = actionText
        -- Clickable button sized to the action text only
        local actionBtn = CreateFrame("Button", nil, shade)
        actionBtn:SetFrameLevel(shade:GetFrameLevel() + 2)
        actionBtn:SetPoint("TOPLEFT", actionText, "TOPLEFT", -4, 2)
        actionBtn:SetPoint("BOTTOMRIGHT", actionText, "BOTTOMRIGHT", 4, -2)
        actionBtn:Hide()
        -- Hover animation state
        local hoverT = 0
        local hoverTarget = 0
        local animFrame = CreateFrame("Frame")
        local function ApplyHover(t)
            actionText:SetAlpha(t)
            if t > 0.01 then
                actionBtn:Show()
            else
                actionBtn:Hide()
            end
            -- Shift label up to make room for action text
            local yOff = t * 5
            nameFs:SetPoint("CENTER", shade, "CENTER", 0, yOff)
        end
        animFrame:SetScript("OnUpdate", function(self, elapsed)
            local direction = hoverTarget > hoverT and 1 or -1
            hoverT = hoverT + direction * (elapsed / 0.15)
            if (direction == 1 and hoverT >= hoverTarget) or (direction == -1 and hoverT <= hoverTarget) then
                hoverT = hoverTarget
                if hoverT == 0 then self:Hide() end
            end
            ApplyHover(hoverT)
        end)
        animFrame:Hide()
        -- Hover handlers on the overlay frame
        local function OnEnter()
            hoverTarget = 1
            shade._brd:SetColor(1, 1, 1, 0.9)
            animFrame:Show()
        end
        local function OnLeave()
            if actionBtn:IsShown() and actionBtn:IsMouseOver() then return end
            if shade:IsMouseOver() then return end
            hoverTarget = 0
            shade._brd:SetColor(accR, accG, accB, 0.6)
            animFrame:Show()
        end
        shade:SetScript("OnEnter", OnEnter)
        shade:SetScript("OnLeave", OnLeave)
        -- Action button hover: brighten text, keep overlay hovered
        actionBtn:SetScript("OnEnter", function()
            actionText:SetTextColor(1, 1, 1, 1)
            OnEnter()
        end)
        actionBtn:SetScript("OnLeave", function()
            actionText:SetTextColor(accR, accG, accB, 0.9)
            OnLeave()
        end)
        -- Click: close unlock mode, open Blizzard Edit Mode
        actionBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            if EditModeManagerFrame then
                mod.RequestClose(false, function() ShowUIPanel(EditModeManagerFrame) end)
            end
        end)
        shade._forceCollapse = function()
            hoverT = 0
            hoverTarget = 0
            animFrame:Hide()
            ApplyHover(0)
            shade._brd:SetColor(accR, accG, accB, 0.6)
        end
        -- Shift+Right Click temporarily hides this overlay for the current unlock
        -- session (matches the regular mover behavior). The _tempHidden flag is
        -- cleared on the next unlock entry so the overlay reappears then. Purely a
        -- visual toggle on the info overlay -- it never touches the Blizzard frame.
        local function TempHide(_, btnFrame)
            if btnFrame == "RightButton" and IsShiftKeyDown() then
                shade._tempHidden = true
                shade._forceCollapse()
                shade:Hide()
            end
        end
        shade:SetScript("OnMouseUp", TempHide)
        -- The hover action strip (a child button) swallows mouse events over itself,
        -- so wire the same handler there to catch a Shift+Right Click landing on it.
        actionBtn:SetScript("OnMouseUp", TempHide)
        return shade
    end

    local function ShowBlizzOwnedOverlays(hostFrame)
        for _, def in ipairs(BLIZZ_OWNED_OVERLAY_DEFS) do
            local anchor = def.frame()
            if not anchor then
            -- frame doesn't exist at all, skip
            elseif anchor:IsShown() and anchor:GetWidth() > 1 then
                -- Visible frame: anchor directly
                local shade = _blizzOwnedOverlays[def.label]
                if not shade then
                    shade = CreateBlizzOwnedOverlay(def, hostFrame)
                    _blizzOwnedOverlays[def.label] = shade
                end
                -- Same strata as the regular movers (FULLSCREEN_DIALOG) but a lower level
                -- (movers sit at unlockFrame+20), so non-Blizzard overlays always render
                -- above these Blizzard Edit Mode overlays. Still above the dimmer (+1).
                shade:SetFrameStrata("FULLSCREEN_DIALOG")
                shade:SetFrameLevel(hostFrame:GetFrameLevel() + 15)
                shade:ClearAllPoints()
                if def.anchor then
                    def.anchor(shade, anchor)
                else
                    shade:SetAllPoints(anchor)
                end
                shade._forceCollapse()
                shade:Show()
            elseif def.showAlways then
                -- Hidden frame but showAlways: position at frame's location with fallback size
                local shade = _blizzOwnedOverlays[def.label]
                if not shade then
                    shade = CreateBlizzOwnedOverlay(def, hostFrame)
                    _blizzOwnedOverlays[def.label] = shade
                end
                -- FULLSCREEN_DIALOG (below movers at +20, above the dimmer at +1) so
                -- non-Blizzard overlays always render above Blizzard Edit Mode overlays.
                shade:SetFrameStrata("FULLSCREEN_DIALOG")
                shade:SetFrameLevel(hostFrame:GetFrameLevel() + 15)
                shade:ClearAllPoints()
                shade:SetSize(def.fallbackW or 200, def.fallbackH or 40)
                -- Read the frame's current anchor or fall back to bottom center
                local pt, relTo, rpt, ox, oy = anchor:GetPoint(1)
                local yAdj = def.yOffset or 0
                if pt and relTo then
                    shade:SetPoint(pt, relTo, rpt or pt, ox or 0, (oy or 0) + yAdj)
                else
                    shade:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200 + yAdj)
                end
                shade._forceCollapse()
                shade:Show()
            end
        end
    end

    local function HideBlizzOwnedOverlays()
        for _, shade in pairs(_blizzOwnedOverlays) do
            if shade._forceCollapse then shade._forceCollapse() end
            shade:Hide()
        end
    end

    LM.GetAccent, LM.CreateGrid, LM.ClearSnapHighlight, LM.ShowSnapHighlight =
        AccentColor, CreateGrid, DropSnapHighlight, ShowSnapHighlight
    LM.HideAllGuidesAndHighlight, LM.ShowAlignmentGuides, LM.SnapPosition, LM.SelectMover =
        HideAllGuidesAndHighlight, ShowAlignmentGuides, SnapPosition, SelectMover
    LM.DeselectMover, LM.ApplyDarkOverlays, LM.SetupArrowKeyFrame, LM.GetActionBarVisualSize =
        DeselectMover, ApplyDarkOverlays, SetupArrowKeyFrame, GetActionBarVisualSize
    LM.SortMoverFrameLevels, LM.ShowBlizzOwnedOverlays, LM.HideBlizzOwnedOverlays =
        SortMoverFrameLevels, ShowBlizzOwnedOverlays, HideBlizzOwnedOverlays
    LM.FlashSelectHighlight = FlashSelectHighlight
end
