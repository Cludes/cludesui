if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\LivePreview_Options.lua
--  Cooldown Manager options: the interactive bar preview in the content header
--  of the CDM Bars page (BuildCDMLivePreview). Definitions only; the shared
--  helpers come from ns._CDMO_OptEnv (filled by CUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end -- module disabled: no options page

-- The options page pool (CludesUI_FramePool.lua): a frame made under a pool
-- host (a reused header) is handed out again reset to fresh; anywhere else this
-- is the plain CreateFrame. The drag ghost is one kept frame for the session.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolGen = CludesUI._Pool.Kept, CludesUI._Pool.Gen

--- Build the live CDM bar preview in the content header (interactive)
local function BuildCDMLivePreview(hostFrame, yOff)
    local environ = mod._CDMO_OptEnv
    local _cdmActivePreviewOn, DB, FONT_PATH, GetCDMOptOutline =
        environ._cdmActivePreviewOn, environ.DB, environ.FONT_PATH, environ.GetCDMOptOutline
    local NormalizeToBase, optionState, Pix, Refresh =
        environ.NormalizeToBase, environ.optState, environ.PP, environ.Refresh
    local RefreshCDPreview, ResolveIconArt, ResolveToLive, SelectedCDMBar =
        environ.RefreshCDPreview, environ.ResolveIconArt, environ.ResolveToLive, environ.SelectedCDMBar
    local SetPVFont, StartActiveStatePreview, StopActiveStatePreview, UpdateCDMPreviewAndResize =
        environ.SetPVFont,
        environ.StartActiveStatePreview,
        environ.StopActiveStatePreview,
        environ.UpdateCDMPreviewAndResize
    local profile = DB()
    if not profile or not profile.cdmBars then
        return 0
    end

    local barInfo = SelectedCDMBar()
    if not barInfo then
        return 0
    end

    local barId = barInfo.key
    local PAD = CludesUI.CONTENT_PAD or 10

    -- Create preview container scale to match real in-game icon sizes
    local previewScale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    local localParentW = (hostFrame:GetWidth() - PAD * 2) / previewScale
    local initH = (barInfo.iconSize or 36) + 10

    -- Max visible height for the preview area (in parent-space pixels)
    local PREVIEW_MAX_H = 200

    -- Wrapper frame at parent scale; holds the scroll frame and scrollbar
    local wrapper = CreateFrame("Frame", nil, hostFrame)
    wrapper:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", PAD, yOff)
    wrapper:SetSize(hostFrame:GetWidth() - PAD * 2, PREVIEW_MAX_H)
    wrapper:SetClipsChildren(true)

    local popFrame = CreateFrame("Frame", nil, hostFrame)
    popFrame:SetClipsChildren(false)
    popFrame:SetScale(previewScale)
    popFrame:SetSize(localParentW, initH)

    local scrollFrame = CreateFrame("ScrollFrame", nil, wrapper)
    scrollFrame:SetAllPoints()
    scrollFrame:SetScrollChild(popFrame)
    scrollFrame:EnableMouseWheel(true)

    local UpdatePVThumb = CludesUI.AttachSmoothScrollbar(scrollFrame, {
        step = 40,
        thumbMin = 20,
        trackParent = wrapper,
        topInset = 2,
        level = 5,
        panelWheel = true,
    })

    -- Store refs for height management after Update()
    popFrame._wrapper = wrapper
    popFrame._scrollFrame = scrollFrame
    popFrame._previewScale = previewScale
    popFrame._PREVIEW_MAX_H = PREVIEW_MAX_H
    popFrame._updatePVThumb = UpdatePVThumb

    -- Pixel-snap helper for the preview's effective scale
    local function Snap(val)
        local s = popFrame:GetEffectiveScale()
        return math.floor(val * s + 0.5) / s
    end

    -- Bar background texture (shown when barBgEnabled)
    local pvBarBg = popFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    pvBarBg:SetColorTexture(0, 0, 0, 0.4) -- default; updated in refresh
    if pvBarBg.SetSnapToPixelGrid then
        pvBarBg:SetSnapToPixelGrid(false)
        pvBarBg:SetTexelSnappingBias(0)
    end
    pvBarBg:Hide()

    -- Interactive preview icon slots
    local MAX_PREVIEW_ICONS = 30
    local slotList = {}

    -- Display-only dedupe for buff bars. assignedSpells can hold a LEGACY  -- cui-style: allow comment-budget
    -- duplicate: the SAME tracked buff stored under two different spell ids (e.g.
    -- its spellID and one of its linkedSpellIDs). They are NOT base/override
    -- variants -- the link is that both ids resolve to the same Blizzard
    -- cooldownID. BOTH ids must stay in the data (routing depends on them), so
    -- collapse them in the PREVIEW only: one slot per cooldownID, remembering which
    -- assignedSpells index/indices each slot covers (for edit + remove). With no
    -- dupes this is the raw list 1:1. spellID -> cooldownID depends only on
    -- talents, so it is stable per spec: build ONCE per spec from the static
    -- category sets (spellID + overrideSpellID + linkedSpellIDs, covering buffs
    -- currently down) and reuse across refreshes. Private local fed ONLY into the
    -- dedupe -- nothing writes assignedSpells, the route map, or live frames, and
    -- the scan never runs during gameplay (pf.Update only runs with options open).
    local _buffIdToCd, _buffIdToCdSpec = nil, nil
    local function GetBuffIdToCdid()
        local specKey = (mod.GetActiveSpecKey and mod.GetActiveSpecKey()) or "?"
        if _buffIdToCdSpec == specKey then
            return _buffIdToCd
        end
        _buffIdToCdSpec = specKey
        local map
        local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        if gcs and getCdInfo then
            -- 0-8 covers every Midnight CooldownViewerCategory value; the
            -- Hidden pseudo-categories are negative and excluded by the range.
            for category = 0, 8 do
                local ids = gcs(category, true)
                if ids then
                    for _, cdID in ipairs(ids) do
                        local details = getCdInfo(cdID)
                        if details then
                            map = map or {}
                            if type(details.spellID) == "number" and details.spellID > 0 then
                                map[details.spellID] = cdID
                            end
                            if type(details.overrideSpellID) == "number" and details.overrideSpellID > 0 then
                                map[details.overrideSpellID] = cdID
                            end
                            if details.linkedSpellIDs then
                                for _, l in ipairs(details.linkedSpellIDs) do
                                    if type(l) == "number" and l > 0 then
                                        map[l] = cdID
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        _buffIdToCd = map
        return map
    end

    local function BuildBuffDisplayDedup(raw)
        local idToCd = GetBuffIdToCdid()
        local dispList, dispGroups, slotOf = {}, {}, {}
        for rawIdx = 1, #raw do
            local spellRef = raw[rawIdx]
            -- Group by cooldownID when the id maps to a tracked buff; otherwise the
            -- entry stands alone (its own slot, keyed by the spell id).
            local cd = idToCd and idToCd[spellRef]
            local key = cd or ("s" .. tostring(spellRef))
            local at = slotOf[key]
            if at then
                local g = dispGroups[at]
                g[#g + 1] = rawIdx
            else
                dispList[#dispList + 1] = spellRef
                dispGroups[#dispList] = { rawIdx }
                slotOf[key] = #dispList
            end
        end
        return dispList, dispGroups
    end

    -- Preview display index -> underlying assignedSpells index for buff bars
    -- that collapsed a duplicate (identity when there are no dupes / not a buff bar).
    local function BuffDataIdx(displayIdx)
        local g = popFrame._buffDispGroups and popFrame._buffDispGroups[displayIdx]
        return (g and g[1]) or displayIdx
    end

    -- Drag state
    local dragSlot, dragIdx, dragGhost
    local dropIdx = nil
    local lastInsertIdx = nil
    local dragMode = nil -- "swap" or "insert"
    local swapIdx = nil -- index of icon being swapped with
    local dragEndTime = 0 -- GetTime() when drag finished, suppresses OnClick

    local function EnsureDragGhost()
        if dragGhost then
            return dragGhost
        end
        -- One ghost frame for the session, dressed again by the first drag of
        -- each preview build.
        local g = PoolKept(optionState, "cdmDragGhost", "Frame", UIParent)
        g:SetFrameStrata("TOOLTIP")
        g:SetSize(36, 36)
        g:SetAlpha(0.7)
        local texture = g:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        g._icon = texture
        g:Hide()
        dragGhost = g
        return g
    end

    -- Insertion line indicator (accent line between icons; horizontal on a vertical bar)
    local dropLine = popFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    local accentGreen = CludesUI.CLUDES_GREEN
    dropLine:SetColorTexture(accentGreen.r, accentGreen.g, accentGreen.b, 0.9)
    dropLine:SetWidth(2)
    dropLine:Hide()

    -- Two preview slots stacked in one column (a vertical bar: same X, one per row)
    local function StackedSlots(a, b)
        return a
            and b
            and a._baseX
            and b._baseX
            and a._baseY
            and b._baseY
            and math.abs(a._baseX - b._baseX) < 1
            and math.abs(a._baseY - b._baseY) >= 1
    end

    -- Animation: each slot has _targetOffX, _currentOffX (and _targetOffY, _currentOffY on a
    -- vertical bar); lerped inside drag OnUpdate
    local ANIM_SPEED = 48
    local animRunning = false

    local function StopAnimTicker()
        animRunning = false
    end

    local function StartAnimTicker()
        animRunning = true
    end

    local function TickAnimation(dt)
        if not animRunning then
            return
        end
        local allDone = true
        for i = 1, MAX_PREVIEW_ICONS do
            local s = slotList[i]
            if s and s._targetOffX and s._currentOffX then
                local diff = s._targetOffX - s._currentOffX
                if math.abs(diff) < 0.3 then
                    s._currentOffX = s._targetOffX
                else
                    s._currentOffX = s._currentOffX + diff * math.min(ANIM_SPEED * dt, 1)
                    allDone = false
                end
                local curY = s._currentOffY or 0
                local diffY = (s._targetOffY or 0) - curY
                if math.abs(diffY) < 0.3 then
                    curY = s._targetOffY or 0
                else
                    curY = curY + diffY * math.min(ANIM_SPEED * dt, 1)
                    allDone = false
                end
                s._currentOffY = curY
                if s._baseX then
                    s:ClearAllPoints()
                    Pix.Point(s, "TOPLEFT", popFrame, "TOPLEFT", s._baseX + s._currentOffX, s._baseY + curY)
                end
            end
        end
        if allDone then
            animRunning = false
        end
    end

    local function ClearInsertIndicator()
        dropLine:Hide()
        dropIdx = nil
        lastInsertIdx = nil
        -- Clear swap highlight
        if swapIdx then
            local cfg = slotList[swapIdx]
            if cfg and cfg._hlBrd then
                cfg._hlBrd:Hide()
            end
            swapIdx = nil
        end
        dragMode = nil
        -- Reset all slot offsets (snap, no animation)
        StopAnimTicker()
        for i = 1, MAX_PREVIEW_ICONS do
            local s = slotList[i]
            if s and s._baseX then
                s._targetOffX = 0
                s._currentOffX = 0
                s._targetOffY = nil
                s._currentOffY = nil
                s:ClearAllPoints()
                Pix.Point(s, "TOPLEFT", popFrame, "TOPLEFT", s._baseX, s._baseY)
            end
        end
    end

    --- Find drag target: swap (centered on icon) or insert (between icons)
    --- Returns mode ("swap"/"insert"), targetIdx
    --- cx, cy are in screen units (GetCursorPosition / UIParent:GetEffectiveScale)
    local function FindDragTarget(cx, cy, slotTotal, sourceIdx)
        local edge = SelectedCDMBar()
        if not edge then
            return nil, nil
        end
        local iconSz = edge.iconSize or 36
        -- Match the preview render: width-matched bars use a fixed icon size.
        if CludesUI.GetWidthMatchTarget and CludesUI.GetWidthMatchTarget("CDM_" .. edge.key) then
            iconSz = 36
        end
        local gap = edge.spacing or 2
        -- Preview always renders left-to-right regardless of bar growDirection,
        -- so drag logic must also use left-to-right ordering.
        local growLeft = false

        -- Convert cursor from screen units to pf-local units
        local pfES = popFrame:GetEffectiveScale()
        local uiES = UIParent:GetEffectiveScale()
        local rawCX = cx * uiES
        local rawCY = cy * uiES
        local rawPfL = popFrame:GetLeft() * pfES
        local rawPfT = popFrame:GetTop() * pfES
        local localX = (rawCX - rawPfL) / pfES
        local localY = -((rawPfT - rawCY) / pfES)

        -- A vertical bar stacks its icons in columns, so there the cursor's height
        -- inside an icon picks the drop (top part above it, bottom part below it,
        -- the middle swaps), in the column nearest the cursor. The preview lays each
        -- column out top-down in index order.
        if StackedSlots(slotList[1], slotList[2]) then
            local colX, colDist
            for i = 1, slotTotal do
                local s = slotList[i]
                if s and s:IsShown() and s._baseX then
                    local d = math.abs(localX - (s._baseX + iconSz / 2))
                    if not colDist or d < colDist then
                        colX, colDist = s._baseX, d
                    end
                end
            end
            if not colX or colDist > iconSz then
                return nil, nil
            end
            -- Each icon's band reaches half the spacing past its edges (+1 so rounding
            -- leaves no seam; an overlap resolves to the same insert either way).
            local pad = gap * 0.5 + 1
            local firstIdx, lastIdx
            for i = 1, slotTotal do
                local s = slotList[i]
                if s and s:IsShown() and s._baseX and math.abs(s._baseX - colX) < 1 then
                    firstIdx = firstIdx or i
                    lastIdx = i
                    local height = s:GetHeight()
                    local topY = s._baseY
                    if localY <= topY + pad and localY > topY - height - pad then
                        local midY = topY - height / 2
                        local isBlank = not s._icon or not s._icon:GetTexture()
                        if i ~= sourceIdx and math.abs(localY - midY) < height * (isBlank and 0.45 or 0.2) then
                            return "swap", i
                        end
                        return "insert", (localY > midY) and i or (i + 1)
                    end
                end
            end
            if not firstIdx then
                return nil, nil
            end
            if localY > slotList[firstIdx]._baseY then
                return "insert", firstIdx
            end
            return "insert", lastIdx + 1
        end

        -- Group slots into rows by _baseY
        local bestRowStart, bestRowEnd, bestRowDist = 1, slotTotal, math.huge
        local rowsByY = {}
        for i = 1, slotTotal do
            local s = slotList[i]
            if s and s:IsShown() and s._baseY then
                local yKey = math.floor(s._baseY * 10 + 0.5)
                if not rowsByY[yKey] then
                    rowsByY[yKey] = { y = s._baseY, startIdx = i, endIdx = i }
                else
                    rowsByY[yKey].endIdx = i
                end
            end
        end
        for _, line in pairs(rowsByY) do
            local rowCenterY = line.y - iconSz / 2
            local d = math.abs(localY - rowCenterY)
            if d < bestRowDist then
                bestRowDist = d
                bestRowStart = line.startIdx
                bestRowEnd = line.endIdx
            end
        end

        -- Check Y range
        local refSlot = slotList[bestRowStart]
        if not refSlot or not refSlot:IsShown() or not refSlot._baseY then
            return nil, nil
        end
        if localY > refSlot._baseY + iconSz * 0.5 or localY < refSlot._baseY - iconSz * 1.5 then
            return nil, nil
        end

        -- Build a list of slots in this row sorted by visual X (left to right on screen).
        -- With growLeft, slot indices are reversed relative to screen X order.
        local rowSlots = {}
        for i = bestRowStart, bestRowEnd do
            local s = slotList[i]
            if s and s:IsShown() and s._baseX then
                rowSlots[#rowSlots + 1] = { slot = s, idx = i }
            end
        end
        -- Sort by _baseX ascending (left to right on screen)
        table.sort(rowSlots, function(lhs, rhs)
            return lhs.slot._baseX < rhs.slot._baseX
        end)

        local swapZone = iconSz * 0.2
        local blankSwapZone = iconSz * 0.45

        -- If cursor is before the leftmost slot on screen, insert at the logical start of that side
        local firstEntry = rowSlots[1]
        if firstEntry and localX < firstEntry.slot._baseX - gap * 0.5 then
            if growLeft then
                return "insert", firstEntry.idx + 1
            else
                return "insert", firstEntry.idx
            end
        end

        for vi = 1, #rowSlots do
            local record = rowSlots[vi]
            local cfg = record.slot
            local i = record.idx
            local slotL = cfg._baseX
            local slotR = slotL + iconSz
            local slotCX = slotL + iconSz / 2
            local isBlank = not cfg._icon or not cfg._icon:GetTexture()
            local zone = isBlank and blankSwapZone or swapZone
            if localX >= slotL - gap * 0.5 and localX < slotR + gap * 0.5 then
                if i ~= sourceIdx and math.abs(localX - slotCX) < zone then
                    return "swap", i
                elseif localX < slotCX then
                    -- Cursor in the left half of this slot: insert before it logically
                    if growLeft then
                        return "insert", i + 1
                    else
                        return "insert", i
                    end
                else
                    -- Cursor in the right half of this slot: insert after it logically
                    if growLeft then
                        return "insert", i
                    else
                        return "insert", i + 1
                    end
                end
            end
        end

        -- Past the rightmost slot on screen: insert at the logical end of that side
        local lastEntry = rowSlots[#rowSlots]
        if lastEntry then
            if growLeft then
                return "insert", lastEntry.idx
            else
                return "insert", lastEntry.idx + 1
            end
        end
        return "insert", bestRowEnd + 1
    end

    --- Apply visual feedback for drag: shift icons for insert, highlight for swap
    local function ApplyDragFeedback(mode, goalIdx, sourceIdx, slotTotal)
        local edge = SelectedCDMBar()
        -- Preview always renders left-to-right; drag feedback must match.
        local growLeft = false

        if mode == "swap" then
            dropLine:Hide()
            if swapIdx and swapIdx ~= goalIdx then
                local cfg = slotList[swapIdx]
                if cfg and cfg._hlBrd then
                    cfg._hlBrd:Hide()
                end
            end
            if lastInsertIdx then
                for i = 1, slotTotal do
                    local s = slotList[i]
                    if s and s._baseX then
                        s._targetOffX = 0
                        if not s._currentOffX then
                            s._currentOffX = 0
                        end
                        s._targetOffY = 0
                        if i ~= sourceIdx then
                            s:SetAlpha(1)
                        end
                    end
                end
                StartAnimTicker()
                lastInsertIdx = nil
            end
            swapIdx = goalIdx
            local cfg = slotList[goalIdx]
            if cfg and cfg._hlBrd then
                cfg._hlBrd:Show()
            end
            return
        end

        -- Insert mode: clear swap highlight first
        if swapIdx then
            local cfg = slotList[swapIdx]
            if cfg and cfg._hlBrd then
                cfg._hlBrd:Hide()
            end
            swapIdx = nil
        end

        if goalIdx == lastInsertIdx then
            return
        end
        lastInsertIdx = goalIdx

        if not edge then
            return
        end
        local iconSz = edge.iconSize or 36
        -- Match the preview render: width-matched bars use a fixed icon size.
        if CludesUI.GetWidthMatchTarget and CludesUI.GetWidthMatchTarget("CDM_" .. edge.key) then
            iconSz = 36
        end
        local gap = edge.spacing or 2
        local nudge = math.floor((iconSz + gap) * 0.15)

        -- With growLeft, higher index = further left on screen.
        -- Flip nudge direction so slots shift away from the gap correctly.
        local shiftTowardEnd = nudge
        local shiftTowardStart = -nudge
        if growLeft then
            shiftTowardEnd = -nudge
            shiftTowardStart = nudge
        end

        -- Determine which row the target belongs to (by _baseY).
        -- Only shift slots on that row; other rows stay still.
        local targetRowY = nil
        if goalIdx >= 1 and goalIdx <= slotTotal then
            local ts = slotList[goalIdx]
            if ts and ts._baseY then
                targetRowY = ts._baseY
            end
        end
        -- Fallback: check the slot just before targetIdx (insert at end of row)
        if not targetRowY and goalIdx > 1 and goalIdx - 1 <= slotTotal then
            local ts = slotList[goalIdx - 1]
            if ts and ts._baseY then
                targetRowY = ts._baseY
            end
        end

        for i = 1, slotTotal do
            local s = slotList[i]
            if not s or not s._baseX then
                if s then
                    s:SetAlpha(i == sourceIdx and 0.3 or 1)
                end
            elseif i == sourceIdx then
                s:SetAlpha(0.3)
                s._targetOffX = 0
                if not s._currentOffX then
                    s._currentOffX = 0
                end
            else
                -- Only shift slots on the same row as the target
                local onTargetRow = targetRowY and s._baseY and math.abs(s._baseY - targetRowY) < 1
                if not onTargetRow then
                    s._targetOffX = 0
                    if not s._currentOffX then
                        s._currentOffX = 0
                    end
                    s:SetAlpha(1)
                else
                    local virtualPos = i
                    if i > sourceIdx then
                        virtualPos = i - 1
                    end
                    local virtualInsert = goalIdx
                    if goalIdx > sourceIdx then
                        virtualInsert = goalIdx - 1
                    end

                    local offX = 0
                    if virtualPos >= virtualInsert then
                        offX = shiftTowardEnd
                    else
                        offX = shiftTowardStart
                    end

                    s._targetOffX = offX
                    if not s._currentOffX then
                        s._currentOffX = 0
                    end
                    s:SetAlpha(1)
                end
            end
        end
        -- A vertical bar stacks its icons (same X, one per row, so the row shift above
        -- moves only the target): the gap opens up and down within its column instead.
        local first, second = slotList[1], slotList[2]
        if StackedSlots(first, second) then
            -- Later slots sit further along the column (down, or up on a bar growing up).
            local towardEndY = (second._baseY < first._baseY) and -nudge or nudge
            -- The target's column; past the last slot, the last slot's (as the row code above).
            local ts = slotList[(goalIdx <= slotTotal) and goalIdx or (goalIdx - 1)]
            local colX = ts and ts._baseX
            local virtualInsert = goalIdx
            if goalIdx > sourceIdx then
                virtualInsert = goalIdx - 1
            end
            for i = 1, slotTotal do
                local s = slotList[i]
                if s and s._baseX then
                    s._targetOffX = 0
                    if not s._currentOffX then
                        s._currentOffX = 0
                    end
                    if i == sourceIdx then
                        s:SetAlpha(0.3)
                        s._targetOffY = 0
                    else
                        s:SetAlpha(1)
                        if colX and math.abs(s._baseX - colX) < 1 then
                            local virtualPos = i
                            if i > sourceIdx then
                                virtualPos = i - 1
                            end
                            s._targetOffY = (virtualPos >= virtualInsert) and towardEndY or -towardEndY
                        else
                            s._targetOffY = 0
                        end
                    end
                elseif s then
                    s:SetAlpha(i == sourceIdx and 0.3 or 1)
                end
            end
        end

        StartAnimTicker()

        -- Position the insertion line between the two logical neighbors
        if goalIdx and goalIdx >= 1 then
            local iconSz2 = iconSz
            local prevSlot, nextSlot -- screen-left, screen-right
            if growLeft then
                -- With growLeft, slot targetIdx is to the right on screen, slot targetIdx-1 is to the left
                if goalIdx > 1 and goalIdx <= slotTotal then
                    nextSlot = slotList[goalIdx]
                    prevSlot = slotList[goalIdx - 1]
                    if goalIdx == sourceIdx and goalIdx + 1 <= slotTotal then
                        nextSlot = slotList[goalIdx + 1]
                    elseif goalIdx - 1 == sourceIdx and goalIdx - 2 >= 1 then
                        prevSlot = slotList[goalIdx - 2]
                    end
                elseif goalIdx <= 1 then
                    nextSlot = slotList[1]
                elseif goalIdx > slotTotal then
                    prevSlot = slotList[slotTotal]
                end
            else
                if goalIdx > 1 and goalIdx <= slotTotal then
                    prevSlot = slotList[goalIdx - 1]
                    nextSlot = slotList[goalIdx]
                    if goalIdx - 1 == sourceIdx and goalIdx - 2 >= 1 then
                        prevSlot = slotList[goalIdx - 2]
                    elseif goalIdx == sourceIdx and goalIdx + 1 <= slotTotal then
                        nextSlot = slotList[goalIdx + 1]
                    end
                elseif goalIdx <= 1 then
                    nextSlot = slotList[1]
                elseif goalIdx > slotTotal and slotTotal > 0 then
                    prevSlot = slotList[slotTotal]
                end
            end

            -- A vertical bar stacks its icons in columns: there the line runs across the
            -- gap between the neighbors instead of down through an icon. Between two
            -- columns it sits above the next column's first icon, where that column opens.
            local stacked = StackedSlots(slotList[1], slotList[2])

            local lineX, lineY
            if stacked then
                local gap = math.floor(gap / 2) + 1
                if
                    prevSlot
                    and prevSlot:IsShown()
                    and prevSlot._baseX
                    and nextSlot
                    and nextSlot:IsShown()
                    and nextSlot._baseX
                    and StackedSlots(prevSlot, nextSlot)
                then
                    local max, lower = prevSlot, nextSlot
                    if lower._baseY > max._baseY then
                        max, lower = lower, max
                    end
                    -- Centered in the gap the icons are opening (their shifted positions; the
                    -- drawn height, which a cropped icon shape makes shorter than the size).
                    lineX = max._baseX
                    lineY = (
                        (max._baseY + (max._targetOffY or 0) - max:GetHeight())
                        + (lower._baseY + (lower._targetOffY or 0))
                    ) / 2
                elseif nextSlot and nextSlot:IsShown() and nextSlot._baseX then
                    lineX = nextSlot._baseX
                    lineY = nextSlot._baseY + (nextSlot._targetOffY or 0) + gap
                elseif prevSlot and prevSlot:IsShown() and prevSlot._baseX then
                    lineX = prevSlot._baseX
                    lineY = prevSlot._baseY + (prevSlot._targetOffY or 0) - prevSlot:GetHeight() - gap
                end
            elseif
                prevSlot
                and prevSlot:IsShown()
                and prevSlot._baseX
                and nextSlot
                and nextSlot:IsShown()
                and nextSlot._baseX
            then
                local leftRight = prevSlot._baseX + iconSz2 - nudge
                local rightLeft = nextSlot._baseX + nudge
                lineX = (leftRight + rightLeft) / 2
                lineY = nextSlot._baseY
            elseif nextSlot and nextSlot:IsShown() and nextSlot._baseX then
                lineX = nextSlot._baseX + nudge - math.floor(gap / 2) - 1
                lineY = nextSlot._baseY
            elseif prevSlot and prevSlot:IsShown() and prevSlot._baseX then
                lineX = prevSlot._baseX + iconSz2 - nudge + math.floor(gap / 2) + 1
                lineY = prevSlot._baseY
            end

            if lineX and lineY then
                dropLine:ClearAllPoints()
                if stacked then
                    dropLine:SetHeight(2)
                    Pix.Point(dropLine, "LEFT", popFrame, "TOPLEFT", lineX, lineY)
                    Pix.Point(dropLine, "RIGHT", popFrame, "TOPLEFT", lineX + iconSz2, lineY)
                else
                    -- As tall as the icons are drawn (a cropped shape is shorter than the size).
                    local ref = nextSlot or prevSlot
                    local lineH = (ref and ref:GetHeight()) or iconSz2
                    dropLine:SetWidth(2)
                    Pix.Point(dropLine, "TOP", popFrame, "TOPLEFT", lineX, lineY)
                    Pix.Point(dropLine, "BOTTOM", popFrame, "TOPLEFT", lineX, lineY - lineH)
                end
                dropLine:Show()
            else
                dropLine:Hide()
            end
        else
            dropLine:Hide()
        end
    end

    -- Hover tooltip above an icon: the spell (or item) it shows, then the
    -- click hint wherever a click opens its settings (the OnClick rules
    -- below: no settings on a custom aura bar, for a custom item on the
    -- default buffs bar, or while a Spec Override is being edited).
    local function ShowSlotTip(slotFrame)
        local name
        if slotFrame._previewSpellID then
            name = (slotFrame._previewArtID and C_Spell.GetSpellName(slotFrame._previewArtID))
                or C_Spell.GetSpellName(slotFrame._previewSpellID)
        elseif slotFrame._previewTipItemID then
            name = C_Item.GetItemNameByID(slotFrame._previewTipItemID)
        end
        if not name then
            return
        end
        if slotFrame._previewBlizzHidden then
            name = name
                .. "\n"
                .. CludesUI.Lf(
                    "Blizzard's Cooldown Manager has this in %1$s, so it does not show in game. Open Blizzard CDM and move it to %2$s or %3$s.",
                    COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR,
                    COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL,
                    COOLDOWN_VIEWER_SETTINGS_CATEGORY_UTILITY
                )
        end
        local edge = SelectedCDMBar()
        if
            edge
            and edge.barType ~= "custom_buff"
            and not (edge.key == "buffs" and slotFrame._previewItemID)
            and not CludesUI.SpecOverrides_EditSessionActive()
        then
            name = name .. "\n" .. CludesUI.L("Click spell for alert settings")
        end
        CludesUI.ShowWidgetTooltip(slotFrame, name)
    end

    local function CreatePreviewSlot(position)
        local slotFrame = CreateFrame("Button", nil, popFrame)
        -- A reused header hands this slot out again for a new build: what the
        -- live icon passes cached on its previous dress (shape and stock style
        -- frames, the keybind badge) went with that dress, so they start anew.
        mod._ecmeFC[slotFrame] = nil
        slotFrame:SetSize(1, 1)
        slotFrame:RegisterForClicks("LeftButtonUp", "RightButtonDown", "MiddleButtonDown")
        -- Expand hit area so small icons are easier to click/drag
        slotFrame:SetHitRectInsets(-6, -6, -6, -6)
        slotFrame:Hide()

        local sBg = slotFrame:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if sBg.SetSnapToPixelGrid then
            sBg:SetSnapToPixelGrid(false)
            sBg:SetTexelSnappingBias(0)
        end
        slotFrame._bg = sBg

        local sIcon = slotFrame:CreateTexture(nil, "ARTWORK")
        sIcon:SetAllPoints()
        if sIcon.SetSnapToPixelGrid then
            sIcon:SetSnapToPixelGrid(false)
            sIcon:SetTexelSnappingBias(0)
        end
        slotFrame._icon = sIcon
        slotFrame._tex = sIcon -- alias for shape system compatibility

        local sEdges = {}
        local Pix = CludesUI and CludesUI.PP
        if Pix then
            Pix.CreateBorder(slotFrame, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end
        slotFrame._edges = sEdges -- empty; borders managed by PP

        -- Hosted-buff marker border: gold (same color as the buff "+" add button), same 2px
        -- geometry as the hover highlight, always ON for buff icons hosted on this CD/utility
        -- bar so they read apart from the cooldowns at a glance. Level +1 -- UNDER the hover highlight (+2), so hovering still shows the accent border on top.
        local slotPP = CludesUI and CludesUI.PP
        local slotHostCont = CreateFrame("Frame", nil, slotFrame)
        slotHostCont:SetAllPoints()
        slotHostCont:SetFrameLevel(slotFrame:GetFrameLevel() + 1)
        local hostBrd = slotPP and slotPP.CreateBorder(slotHostCont, 1, 0.82, 0.25, 1, 2, "OVERLAY", 7)
        if hostBrd then
            hostBrd:Hide()
        end
        slotFrame._hostBrd = hostBrd
        -- Hover highlight (2px accent border, child container avoids conflict with existing PP border)
        local accentGreen = CludesUI.CLUDES_GREEN
        local slotHlCont = CreateFrame("Frame", nil, slotFrame)
        slotHlCont:SetAllPoints()
        slotHlCont:SetFrameLevel(slotFrame:GetFrameLevel() + 2)
        local slotBrd = slotPP and slotPP.CreateBorder(slotHlCont, accentGreen.r, accentGreen.g, accentGreen.b, 1, 2, "OVERLAY", 7)
        if slotBrd then
            slotBrd:Hide()
        end
        slotFrame._hlBrd = slotBrd
        -- Text overlay (renders above border)
        local pvTextOvr = CreateFrame("Frame", nil, slotFrame)
        pvTextOvr:SetAllPoints(slotFrame)
        -- +5: the keybind badge sits two levels under this overlay (+3/+4),
        -- above the slot border (+1) and the hosted-buff marker (+2).
        pvTextOvr:SetFrameLevel(slotFrame:GetFrameLevel() + 5)
        pvTextOvr:EnableMouse(false)
        slotFrame._pvTextOverlay = pvTextOvr

        slotFrame._stackText = pvTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(slotFrame._stackText, FONT_PATH, 11)
        slotFrame._stackText:SetPoint("BOTTOMRIGHT", pvTextOvr, "BOTTOMRIGHT", 0, 2)
        slotFrame._stackText:SetJustifyH("RIGHT")
        slotFrame._stackText:Hide()
        local stackTxt = slotFrame._stackText

        -- Keybind text (mirrors _keybindText on real CDM icons)
        local kbTxt = pvTextOvr:CreateFontString(nil, "OVERLAY")
        mod.CdmForgetKeybindBadge(kbTxt)
        SetPVFont(kbTxt, FONT_PATH, 9)
        kbTxt:SetPoint("TOPLEFT", pvTextOvr, "TOPLEFT", 2, -2)
        kbTxt:SetJustifyH("LEFT")
        kbTxt:Hide()
        slotFrame._keybindText = kbTxt

        slotFrame:SetScript("OnEnter", function()
            if dragSlot then
                return
            end
            local bdHov = SelectedCDMBar()
            -- Custom shapes: tint the shape border instead of square edges
            if slotFrame._shapeBorder and slotFrame._shapeBorder:IsShown() then
                slotFrame._shapeBorder:SetVertexColor(accentGreen.r, accentGreen.g, accentGreen.b, 1)
            else
                if slotBrd then
                    slotBrd:Show()
                end
            end
            ShowSlotTip(slotFrame)
        end)
        slotFrame:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
            if dragSlot then
                return
            end
            local bdHov = SelectedCDMBar()
            if slotFrame._shapeBorder and slotFrame._shapeBorder:IsShown() then
                if slotFrame._previewHostedBuff then
                    -- Hosted buff: restore the persistent gold tint, not
                    -- the bar border color.
                    slotFrame._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
                else
                    local bR, bG, bB = 0, 0, 0
                    if bdHov then
                        bR, bG, bB = bdHov.borderR or 0, bdHov.borderG or 0, bdHov.borderB or 0
                        if bdHov.borderClassColor then
                            local _, classTok = UnitClass("player")
                            if classTok then
                                local classColor = RAID_CLASS_COLORS[classTok]
                                if classColor then
                                    bR, bG, bB = classColor.r, classColor.g, classColor.b
                                end
                            end
                        end
                    end
                    slotFrame._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                end
            else
                if slotBrd then
                    slotBrd:Hide()
                end
            end
        end)

        slotFrame._slotIdx = position

        -- Right-click: spell picker to replace; Middle-click: remove
        -- Default buff bar: no interaction (Blizzard controls the list)
        slotFrame:SetScript("OnClick", function(self, btnFrame)
            if GetTime() - dragEndTime < 0.2 then
                return
            end
            CludesUI.HideWidgetTooltip()
            local edge = SelectedCDMBar()
            if not edge then
                return
            end
            local isDefaultBuffs = (edge.key == "buffs")

            if btnFrame == "MiddleButton" then
                local si = self._slotIdx
                -- A per-icon settings dropdown may be open (anchored to this or
                -- another slot). A remove reshuffles the preview slots, so any
                -- open dropdown is about to point at the wrong spell -- close it.
                if optionState._spellPickerMenu and optionState._spellPickerMenu:IsShown() then
                    optionState._spellPickerMenu:Hide()
                end
                if isDefaultBuffs then
                    -- Custom item slot (negative -itemID marker): remove it
                    -- directly. slotIndex maps to the mixed preview list, so
                    -- key off the marker, not assignedSpells[si].
                    if self._previewItemID then
                        mod.RemoveSpellFromBar(edge.key, -self._previewItemID)
                        if mod.RebuildSpellRouteMap then
                            mod.RebuildSpellRouteMap()
                        end
                        if mod.QueueReanchor then
                            mod.QueueReanchor()
                        end
                        RefreshCDPreview()
                        return
                    end
                    -- Main buffs bar: only injected custom/preset buffs can be deleted
                    -- (Blizzard-tracked buffs are managed in Blizzard's CDM). Remove by spellID since slotIndex maps to the mixed preview list (Blizzard buffs + customs), not assignedSpells.
                    local spellRef = self._previewSpellID
                    if not spellRef then
                        return
                    end
                    local sdMid = mod.GetBarSpellData(edge.key)
                    local isInj = sdMid
                        and (
                            (sdMid.spellDurations and (sdMid.spellDurations[spellRef] or 0) > 0)
                            or (sdMid.customSpellIDs and sdMid.customSpellIDs[spellRef])
                        )
                    if not isInj then
                        return
                    end
                    mod.RemoveSpellFromBar(edge.key, spellRef)
                    if sdMid.spellDurations then
                        sdMid.spellDurations[spellRef] = nil
                    end
                    if mod.RebuildSpellRouteMap then
                        mod.RebuildSpellRouteMap()
                    end
                    if mod.QueueReanchor then
                        mod.QueueReanchor()
                    end
                    RefreshCDPreview()
                    return
                end
                local sdMid = mod.CDMO_EnsureAssignedSpells(edge.key)
                if not sdMid or not sdMid.assignedSpells then
                    return
                end
                local tbl = sdMid.assignedSpells
                -- Remove every assignedSpells entry collapsed into this preview slot. A legacy
                -- duplicate buff maps >1 stored id to one slot; a normal slot maps exactly one (plain remove). Highest index first keeps the lower indices valid across removes.
                local grp = (popFrame._buffDispGroups and popFrame._buffDispGroups[si]) or { si }
                local sequence = {}
                for _, value in ipairs(grp) do
                    sequence[#sequence + 1] = value
                end
                table.sort(sequence, function(lhs, rhs)
                    return lhs > rhs
                end)
                local removedAny = false
                for _, position in ipairs(sequence) do
                    if tbl[position] and tbl[position] ~= 0 then
                        mod.RemoveTrackedSpell(edge.key, position)
                        removedAny = true
                    end
                end
                if not removedAny then
                    return
                end
                RefreshCDPreview()
            elseif btnFrame == "RightButton" or btnFrame == "LeftButton" then
                local si = self._slotIdx
                -- Custom item slots (default buffs bar) have no per-icon settings and don't
                -- map to assignedSpells[si]; middle-click removes them. Ignore left/right-click to avoid a mis-indexed settings menu.
                if isDefaultBuffs and self._previewItemID then
                    return
                end
                -- Translate the preview slot to its underlying assignedSpells index (identity
                -- unless this buff slot collapsed a duplicate).
                local dataIdx = BuffDataIdx(si)
                -- A slot is configurable if it maps to an assignedSpells entry OR (default
                -- buffs bar mirror) exposes a live spellID. The per-icon settings menu keys off whichever is present.
                local sdClick = mod.GetBarSpellData(edge.key)
                local hasAssigned = sdClick
                    and sdClick.assignedSpells
                    and sdClick.assignedSpells[dataIdx]
                    and sdClick.assignedSpells[dataIdx] ~= 0
                if not hasAssigned and not self._previewSpellID then
                    return
                end

                -- Show remove-only dropdown (per-icon settings + Remove)
                mod.CDMO_ShowSpellPicker(self, edge.key, dataIdx, {}, function()
                    -- onSelect unused -- remove is handled inside ShowSpellPicker
                end, true) -- removeOnly flag
            end
        end)

        -- Manual drag detection: bypasses WoW's large built-in drag threshold
        local DRAG_THRESHOLD = 3 -- pixels of mouse movement before drag starts
        local pendingDragSlot, pendingStartX, pendingStartY

        -- After a drag ends, refresh hover highlights based on current cursor position
        local function RefreshHoverHighlight()
            local edge = SelectedCDMBar()
            local bR, bG, bB = 0, 0, 0
            if edge then
                bR, bG, bB = edge.borderR or 0, edge.borderG or 0, edge.borderB or 0
                if edge.borderClassColor then
                    local _, classTok = UnitClass("player")
                    if classTok then
                        local classColor = RAID_CLASS_COLORS[classTok]
                        if classColor then
                            bR, bG, bB = classColor.r, classColor.g, classColor.b
                        end
                    end
                end
            end
            for i = 1, MAX_PREVIEW_ICONS do
                local s = slotList[i]
                if s then
                    local hovered = s:IsShown() and s:IsMouseOver()
                    local hasShape = s._shapeBorder and s._shapeBorder:IsShown()
                    if hasShape then
                        if hovered then
                            s._shapeBorder:SetVertexColor(accentGreen.r, accentGreen.g, accentGreen.b, 1)
                        else
                            s._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                        end
                    elseif s._hlBrd then
                        if hovered then
                            s._hlBrd:Show()
                        else
                            s._hlBrd:Hide()
                        end
                    end
                end
            end
        end

        -- Drop handler: called when mouse is released during a drag
        local function FinishDrag()
            if not dragSlot then
                return
            end
            local self = dragSlot
            local edge = SelectedCDMBar()
            if dragGhost then
                dragGhost:Hide()
            end
            self:SetAlpha(1)
            self:SetFrameLevel(popFrame:GetFrameLevel() + 1)
            local didChange = false
            if dropIdx and edge then
                local oldPos = {}
                for i = 1, MAX_PREVIEW_ICONS do
                    local s = slotList[i]
                    if s and s:IsShown() and s._baseX then
                        local texture = s._icon and s._icon:GetTexture()
                        if texture then
                            oldPos[texture] = s._baseX + (s._currentOffX or 0)
                        end
                    end
                end

                -- Default buffs bar reorders a dedicated display-order array (canon ids)
                -- instead of assignedSpells, which it shares with routing/custom injection. Seed it from the rendered order on the first drag so index-based moves line up with the preview.
                local isDefBuffs = (edge.key == "buffs")
                if isDefBuffs then
                    local sdBuf = mod.GetBarSpellData("buffs")
                    if sdBuf and not (sdBuf.buffDisplayOrder and #sdBuf.buffDisplayOrder > 0) then
                        local snap = popFrame._buffTrackedOrder
                        if snap and #snap > 0 then
                            local copy = {}
                            for i = 1, #snap do
                                copy[i] = snap[i]
                            end
                            sdBuf.buffDisplayOrder = copy
                        end
                    end
                end
                -- Resolved index refuses the commit when out of range (drag snaps back, no
                -- write). Cd-claimed collided-buff slots carry a real assignedSpells index (a cd-claim marker, see ns.CdClaimMarker) same as any other entry, so no special-casing needed here.
                local function SafeDataIdx(dispIdx)
                    local di = BuffDataIdx(dispIdx)
                    local sdChk = mod.GetBarSpellData and mod.GetBarSpellData(edge.key)
                    local num = sdChk and sdChk.assignedSpells and #sdChk.assignedSpells or 0
                    if di < 1 or di > num then
                        return nil
                    end
                    return di
                end
                if dragMode == "swap" then
                    if dropIdx ~= dragIdx then
                        if isDefBuffs then
                            -- Slot -> stable-key translation: buffDisplayOrder
                            -- keeps absent (talent-gapped) keys in place, so
                            -- slot indices cannot address it directly.
                            local sk = popFrame._buffSlotKeys
                            if
                                sk
                                and mod.SwapBuffDisplayKeys
                                and mod.SwapBuffDisplayKeys(sk[dragIdx], sk[dropIdx])
                            then
                                didChange = true
                            end
                        else
                            local a, b = SafeDataIdx(dragIdx), SafeDataIdx(dropIdx)
                            if a and b then
                                mod.SwapTrackedSpells(edge.key, a, b)
                                didChange = true
                            end
                        end
                    end
                else
                    local toIdx = dropIdx
                    if toIdx > dragIdx then
                        toIdx = toIdx - 1
                    end
                    if toIdx ~= dragIdx then
                        if isDefBuffs then
                            local sk = popFrame._buffSlotKeys
                            if sk and mod.MoveBuffDisplayKey then
                                -- Final rendered position toIdx = insert before
                                -- the key at toIdx among the OTHER rendered keys
                                -- (nil past the end = append after everything).
                                local rk, num = {}, 0
                                for i = 1, #sk do
                                    if i ~= dragIdx then
                                        num = num + 1
                                        rk[num] = sk[i]
                                    end
                                end
                                if mod.MoveBuffDisplayKey(sk[dragIdx], rk[toIdx]) then
                                    didChange = true
                                end
                            end
                        else
                            local a, b = SafeDataIdx(dragIdx), SafeDataIdx(toIdx)
                            if a and b then
                                mod.MoveTrackedSpell(edge.key, a, b)
                                didChange = true
                            end
                        end
                    end
                end

                if didChange then
                    local droppedIdx
                    if dragMode == "swap" then
                        droppedIdx = dropIdx
                    else
                        local toIdx = dropIdx
                        if toIdx > dragIdx then
                            toIdx = toIdx - 1
                        end
                        droppedIdx = toIdx
                    end

                    dropLine:Hide()
                    if swapIdx then
                        local sw = slotList[swapIdx]
                        if sw and sw._hlBrd then
                            sw._hlBrd:Hide()
                        end
                        swapIdx = nil
                    end

                    for i = 1, MAX_PREVIEW_ICONS do
                        local cfg = slotList[i]
                        if cfg then
                            cfg._targetOffX = nil
                            cfg._currentOffX = nil
                            cfg._targetOffY = nil
                            cfg._currentOffY = nil
                        end
                    end
                    animRunning = false

                    Refresh()
                    if popFrame.Update then
                        popFrame:Update()
                    end
                    UpdateCDMPreviewAndResize()

                    for i = 1, MAX_PREVIEW_ICONS do
                        local s = slotList[i]
                        if s and s:IsShown() and s._baseX then
                            if i == droppedIdx then
                                s._currentOffX = 0
                                s._targetOffX = 0
                            else
                                local texture = s._icon and s._icon:GetTexture()
                                if texture and oldPos[texture] then
                                    local diff = oldPos[texture] - s._baseX
                                    if math.abs(diff) > 0.5 then
                                        s._currentOffX = diff
                                        s._targetOffX = 0
                                    else
                                        s._currentOffX = 0
                                        s._targetOffX = 0
                                    end
                                else
                                    s._currentOffX = 0
                                    s._targetOffX = 0
                                end
                            end
                        end
                    end
                    animRunning = true
                    popFrame:SetScript("OnUpdate", function(_, elapsed)
                        TickAnimation(elapsed)
                        if not animRunning then
                            popFrame:SetScript("OnUpdate", nil)
                        end
                    end)
                    dragSlot = nil
                    dragIdx = nil
                    dropIdx = nil
                    dragMode = nil
                    dragEndTime = GetTime()
                    RefreshHoverHighlight()
                    return
                end
            end
            ClearInsertIndicator()
            dragSlot = nil
            dragIdx = nil
            dropIdx = nil
            dragMode = nil
            dragEndTime = GetTime()
            popFrame:SetScript("OnUpdate", nil)
            RefreshHoverHighlight()
        end

        local function BeginDrag(self)
            local edge = SelectedCDMBar()
            if not edge then
                return
            end
            local sdDrag = mod.GetBarSpellData(edge.key)
            local si = self._slotIdx
            if edge.key == "buffs" then
                -- Default bar: a slot is draggable if it renders a buff
                -- (_previewSpellID / a rendered stable key). buffDisplayOrder
                -- is NOT indexed by slot -- it keeps absent keys in place.
                if
                    not self._previewSpellID and not (popFrame._buffSlotKeys and popFrame._buffSlotKeys[si])
                then
                    return
                end
            else
                local tbl = sdDrag and sdDrag.assignedSpells or {}
                local di = BuffDataIdx(si)
                if not tbl[di] or tbl[di] == 0 then
                    return
                end
            end
            dragSlot = self
            dragIdx = si
            CludesUI.HideWidgetTooltip()
            -- Clear hover highlight on the dragged slot
            if self._shapeBorder and self._shapeBorder:IsShown() then
                local bd2 = SelectedCDMBar()
                local bR2, bG2, bB2 = 0, 0, 0
                if bd2 then
                    bR2, bG2, bB2 = bd2.borderR or 0, bd2.borderG or 0, bd2.borderB or 0
                    if bd2.borderClassColor then
                        local _, classTok = UnitClass("player")
                        if classTok then
                            local classColor = RAID_CLASS_COLORS[classTok]
                            if classColor then
                                bR2, bG2, bB2 = classColor.r, classColor.g, classColor.b
                            end
                        end
                    end
                end
                self._shapeBorder:SetVertexColor(bR2, bG2, bB2, 1)
            elseif self._hlBrd then
                self._hlBrd:Hide()
            end
            local ghost = EnsureDragGhost()
            local iSz = edge.iconSize or 36
            ghost:SetSize(iSz, iSz)
            ghost._icon:SetTexture(self._icon:GetTexture())
            local zm = edge.iconZoom or 0.08
            ghost._icon:SetTexCoord(zm, 1 - zm, zm, 1 - zm)
            ghost:SetScale(0.5)
            ghost:Show()
            self:SetAlpha(0.3)
            self:SetFrameLevel(popFrame:GetFrameLevel())
            -- Start cursor tracking + mouse-up detection
            popFrame:SetScript("OnUpdate", function(_, elapsed)
                -- Detect mouse release
                if not IsMouseButtonDown("LeftButton") then
                    popFrame:SetScript("OnUpdate", nil)
                    FinishDrag()
                    return
                end
                if not dragGhost or not dragGhost:IsShown() then
                    return
                end
                local curX, curY = GetCursorPosition()
                local uiScale = UIParent:GetEffectiveScale()
                curX, curY = curX / uiScale, curY / uiScale
                local gs = dragGhost:GetScale() or 1
                dragGhost:ClearAllPoints()
                dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", curX / gs, curY / gs)
                TickAnimation(elapsed)
                local tBd = SelectedCDMBar()
                local tCount = 0
                if tBd then
                    local sdT = mod.GetBarSpellData(tBd.key)
                    if tBd.key == "buffs" then
                        -- Rendered slot count, NOT #buffDisplayOrder: the stored
                        -- order keeps absent keys and can exceed what is shown.
                        if popFrame._buffSlotKeys then
                            tCount = #popFrame._buffSlotKeys
                        end
                    elseif sdT and sdT.assignedSpells then
                        tCount = #sdT.assignedSpells
                    end
                end
                local visCount = popFrame._gridSlots or tCount
                local newMode, newTarget = FindDragTarget(curX, curY, visCount, dragIdx)
                if newMode and newTarget then
                    local isNoop = false
                    if newMode == "insert" then
                        local effTo = newTarget
                        if effTo > dragIdx then
                            effTo = effTo - 1
                        end
                        if effTo == dragIdx then
                            isNoop = true
                        end
                    elseif newMode == "swap" and newTarget == dragIdx then
                        isNoop = true
                    end
                    if isNoop then
                        ClearInsertIndicator()
                    else
                        dragMode = newMode
                        ApplyDragFeedback(newMode, newTarget, dragIdx, visCount)
                        dropIdx = newTarget
                    end
                else
                    ClearInsertIndicator()
                end
            end)
        end

        slotFrame:SetScript("OnMouseDown", function(self, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            -- Buff-family drag-reorder: extra/custom buff bars reorder via
            -- assignedSpells (1:1 preview), the default buffs bar via its
            -- dedicated buffDisplayOrder (stable cooldownID-keyed, reconciled
            -- from the live viewer pool). Only FocusKick stays locked -- its
            -- icon order is driven by nameplate state, not user order.
            local bdDrag = SelectedCDMBar()
            if bdDrag and bdDrag.key == mod.FOCUSKICK_BAR_KEY then
                return
            end
            local curX, curY = GetCursorPosition()
            pendingDragSlot = self
            pendingStartX = curX
            pendingStartY = curY
            -- Use a lightweight OnUpdate to detect threshold
            self:SetScript("OnUpdate", function()
                if not pendingDragSlot then
                    self:SetScript("OnUpdate", nil)
                    return
                end
                local nx, ny = GetCursorPosition()
                local dx = nx - pendingStartX
                local dy = ny - pendingStartY
                if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
                    local s = pendingDragSlot
                    pendingDragSlot = nil
                    self:SetScript("OnUpdate", nil)
                    BeginDrag(s)
                end
            end)
        end)

        slotFrame:SetScript("OnMouseUp", function(self, btnFrame)
            if btnFrame == "LeftButton" and pendingDragSlot then
                -- Mouse released before threshold not a drag, let OnClick handle it
                pendingDragSlot = nil
                self:SetScript("OnUpdate", nil)
            end
        end)

        return slotFrame
    end

    for i = 1, MAX_PREVIEW_ICONS do
        slotList[i] = CreatePreviewSlot(i)
    end

    -- "+" button to add new spells
    local addBtn = CreateFrame("Button", nil, popFrame)
    Pix.Size(addBtn, 36, 36)
    addBtn:Hide()
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
    if addBg.SetSnapToPixelGrid then
        addBg:SetSnapToPixelGrid(false)
        addBg:SetTexelSnappingBias(0)
    end
    if Pix then
        Pix.CreateBorder(addBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7)
    end
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
    addLbl:SetPoint("CENTER", 0, 1)
    addLbl:SetText("+")

    -- Hover highlight for add button (2px accent border, same as slots)
    local accentGreen = CludesUI.CLUDES_GREEN
    local addHlCont = CreateFrame("Frame", nil, addBtn)
    addHlCont:SetAllPoints()
    addHlCont:SetFrameLevel(addBtn:GetFrameLevel() + 1)
    local addPP = CludesUI and CludesUI.PP
    local addBrd = addPP and addPP.CreateBorder(addHlCont, accentGreen.r, accentGreen.g, accentGreen.b, 1, 2, "OVERLAY", 7)
    if addBrd then
        addBrd:Hide()
    end

    addBtn:SetScript("OnEnter", function()
        local accR, accG, accB = CludesUI.GetAccentColor()
        addLbl:SetTextColor(accR, accG, accB, 1)
        if addBrd then
            addBrd:Show()
        end
        if CludesUI.ShowWidgetTooltip then
            -- This same button adds buffs on buff-family bars, so the tip
            -- follows the selected bar rather than hard-coding CD/Utility.
            local bdHov = SelectedCDMBar()
            local tipText
            if bdHov and mod.IsBarBuffFamily(bdHov) then
                tipText = "Add a Buff Spell"
            else
                tipText = "Add a CD/Utility Spell"
            end
            CludesUI.ShowWidgetTooltip(addBtn, CludesUI.L(tipText))
        end
    end)
    addBtn:SetScript("OnLeave", function()
        local accR, accG, accB = CludesUI.GetAccentColor()
        addLbl:SetTextColor(accR, accG, accB, 0.6)
        if addBrd then
            addBrd:Hide()
        end
        CludesUI.HideWidgetTooltip()
    end)
    addBtn:SetScript("OnClick", function(self)
        local edge = SelectedCDMBar()
        if not edge then
            return
        end

        -- Shared post-add finalization for ALL families (buff + CD/util). Forces an
        -- immediate reanchor so source bars (where the spell got auto-removed from) re-render without waiting for the throttled queue. Then schedules a +0.05s preview refresh.
        local function FinalizeAdd()
            if mod.CollectAndReanchor then
                mod.CollectAndReanchor()
            end
            -- pf's own pass only while it is still this build's preview (a
            -- reused header dresses the frame again for a new build); the
            -- current preview is updated either way.
            local pfGen = PoolGen(popFrame)
            C_Timer.After(0.05, function()
                if mod.CDMApplyVisibility then
                    mod.CDMApplyVisibility()
                end
                if PoolGen(popFrame) == pfGen and popFrame.Update then
                    popFrame:Update()
                end
                UpdateCDMPreviewAndResize()
            end)
        end

        if mod.IsBarBuffFamily(edge) then
            -- Buff bars use ShowBuffBarPicker (walks the BuffIcon viewer pool). Click routes
            -- AddTrackedSpell -- the family sweep removes the spell from every other buff-family bar (including the ghost hidden bar, the "unhide" step) before claiming it for bd.key.
            mod.CDMO_ShowBuffBarPicker(self, edge.key, function(newSpellID, newCdID)
                if newSpellID then
                    -- Collided pair (two viewer slots, one shared spellID) or tracked trinket row:
                    -- claim by cooldownID so each slot is addable on its own. Other buffs keep the sid path -- spellID identity survives talent swaps, cooldownIDs drift.
                    if mod.ClaimBuffByCdID(newSpellID, newCdID) then
                        mod.AddTrackedBuffByCdID(edge.key, newCdID, newSpellID)
                    else
                        mod.AddTrackedSpell(edge.key, newSpellID)
                    end
                end
                FinalizeAdd()
            end)
        else
            -- CD/utility bars use ShowSpellPicker.
            local sdAdd = mod.CDMO_EnsureAssignedSpells(edge.key)
            local excl = {}
            local _FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
            if sdAdd and sdAdd.assignedSpells then
                for _, spellRef in ipairs(sdAdd.assignedSpells) do
                    excl[spellRef] = true
                    -- Also exclude override forms so transformed spells
                    -- (e.g. Lay on Hands 633 -> 471195) are recognized.
                    if _FindOvr and spellRef > 0 then
                        local ovr = _FindOvr(spellRef)
                        if ovr and ovr > 0 then
                            excl[ovr] = true
                        end
                    end
                end
            end
            mod.CDMO_ShowSpellPicker(self, edge.key, nil, excl, function(newSpellID, isExtra)
                mod.AddTrackedSpell(edge.key, newSpellID, isExtra)
                FinalizeAdd()
            end)
        end
    end)

    -- Second "+" button: add a BUFF to this CD/utility bar (buff-family bars keep the single
    -- "+" above). A buff placed here renders as a regular CD/utility icon whose gold Active
    -- State is driven by its aura. Gold-tinted so it reads apart from the standard add button; shown for CD/util only.
    local BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B = 1, 0.82, 0.25
    local addBuffBtn = CreateFrame("Button", nil, popFrame)
    Pix.Size(addBuffBtn, 36, 36)
    addBuffBtn:Hide()
    local buffAddBg = addBuffBtn:CreateTexture(nil, "BACKGROUND")
    buffAddBg:SetAllPoints()
    buffAddBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
    if buffAddBg.SetSnapToPixelGrid then
        buffAddBg:SetSnapToPixelGrid(false)
        buffAddBg:SetTexelSnappingBias(0)
    end
    -- Resting border matches the standard add button (neutral gray, not gold) -- the gold "+" glyph alone marks this as the buff-add button.
    if Pix then
        Pix.CreateBorder(addBuffBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7)
    end
    local buffAddLbl = addBuffBtn:CreateFontString(nil, "OVERLAY")
    buffAddLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
    buffAddLbl:SetPoint("CENTER", 0, 1)
    buffAddLbl:SetText("+")
    buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)

    local buffAddHlCont = CreateFrame("Frame", nil, addBuffBtn)
    buffAddHlCont:SetAllPoints()
    buffAddHlCont:SetFrameLevel(addBuffBtn:GetFrameLevel() + 1)
    local buffAddBrd = CludesUI
        and CludesUI.PP
        and CludesUI.PP.CreateBorder(buffAddHlCont, BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1, 2, "OVERLAY", 7)
    if buffAddBrd then
        buffAddBrd:Hide()
    end

    addBuffBtn:SetScript("OnEnter", function()
        buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1)
        if buffAddBrd then
            buffAddBrd:Show()
        end
        CludesUI.ShowWidgetTooltip(addBuffBtn, CludesUI.L("Add a Buff Spell"))
    end)
    addBuffBtn:SetScript("OnLeave", function()
        buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)
        if buffAddBrd then
            buffAddBrd:Hide()
        end
        CludesUI.HideWidgetTooltip()
    end)
    addBuffBtn:SetScript("OnClick", function(self)
        local edge = SelectedCDMBar()
        if not edge then
            return
        end
        -- CD/utility bars only (defensive: the button is hidden elsewhere).
        if mod.IsBarBuffFamily(edge) or edge.barType == "custom_buff" then
            return
        end
        mod.CDMO_ShowBuffToCDPicker(self, edge.key, function()
            if mod.CollectAndReanchor then
                mod.CollectAndReanchor()
            end
            -- The buff-mirror walk (10Hz) binds to the freshly-created icon on
            -- its own next tick; no re-arm needed. pf's own pass only while it
            -- is still this build's preview (as in FinalizeAdd).
            local pfGen = PoolGen(popFrame)
            C_Timer.After(0.05, function()
                if mod.CDMApplyVisibility then
                    mod.CDMApplyVisibility()
                end
                if PoolGen(popFrame) == pfGen and popFrame.Update then
                    popFrame:Update()
                end
                UpdateCDMPreviewAndResize()
            end)
        end)
    end)

    -- Update: mirrors tracked spells with interactive slots
    popFrame.Update = function(self)
        local edge = SelectedCDMBar()
        if not edge then
            for i = 1, MAX_PREVIEW_ICONS do
                slotList[i]:Hide()
            end
            addBtn:Hide()
            addBuffBtn:Hide()
            self:SetHeight(1)
            return
        end

        local iconPx = edge.iconSize or 36
        -- Width-matched bars derive their real icon size from the matched target, so
        -- bd.iconSize (the disabled Icon Scale value) is ignored at runtime. Show a neutral fixed size in the preview rather than the stale scale value.
        if CludesUI.GetWidthMatchTarget and CludesUI.GetWidthMatchTarget("CDM_" .. edge.key) then
            iconPx = 36
        end
        local iconHeight = iconPx
        local pvShape = edge.iconShape or "none"
        if pvShape == "cropped" then
            iconHeight = math.floor(iconPx * mod.CdmCropFactor(edge) + 0.5)
        end
        local gap = edge.spacing or 2
        local zoom = edge.iconZoom or 0.08
        local grow = edge.growDirection or "RIGHT"
        local numRows = edge.numRows or 1
        if numRows < 1 then
            numRows = 1
        end

        local isBuffBar = mod.IsBarBuffFamily(edge)
        local isCustomBuffBar = (edge.barType == "custom_buff")
        local isFocusKick = (edge.key == "focuskick")

        -- All bars read from assignedSpells (user intent). The DEFAULT buff bar enumerates
        -- the viewer pool directly so the preview shows every tracked buff regardless of active state, minus spells diverted to other buff-family bars.
        local isTracked
        -- Parallel to `tracked` for the default buffs bar: the stable viewer cooldownID for
        -- each Blizzard-tracked buff (nil for custom/injected entries). Per-icon buff settings MUST key off the cooldownID-derived stable spellID, never the live aura GetSpellID (secret/variant-drift).
        local trackedCd
        popFrame._buffDispGroups = nil
        popFrame._buffSlotKeys = nil
        if edge.key == "buffs" then
            if mod.ReconcileBuffDisplayOrder then
                mod.ReconcileBuffDisplayOrder()
            end
            local entries = mod.CollectDefaultBuffTrackEntries and mod.CollectDefaultBuffTrackEntries() or {}
            isTracked = {}
            trackedCd = {}
            local sdBuf = mod.GetBarSpellData("buffs")
            local sequence = sdBuf and sdBuf.buffDisplayOrder
            local byKey = {}
            for _, entry in ipairs(entries) do
                byKey[entry.key] = entry
            end
            local finalKeys = {}
            if sequence and #sequence > 0 then
                for _, key in ipairs(sequence) do
                    finalKeys[#finalKeys + 1] = key
                end
            else
                for _, entry in ipairs(entries) do
                    finalKeys[#finalKeys + 1] = entry.key
                end
            end
            -- Rendered slot i <-> stable key map for the drag/reorder code: absent
            -- (talent-gapped) keys stay in buffDisplayOrder but render no slot, so slot indices cannot address the array directly.
            local slotKeys = {}
            for _, key in ipairs(finalKeys) do
                local e = byKey[key]
                if e then
                    isTracked[#isTracked + 1] = e.sid
                    trackedCd[#isTracked] = e.cdID
                    slotKeys[#isTracked] = key
                end
            end
            popFrame._buffSlotKeys = slotKeys
            local snap = {}
            for i = 1, #finalKeys do
                snap[i] = finalKeys[i]
            end
            popFrame._buffTrackedOrder = snap
        else
            local sdUpd = mod.CDMO_EnsureAssignedSpells(edge.key)
            local raw = sdUpd and sdUpd.assignedSpells or {}
            if isBuffBar then
                -- Collapse legacy duplicate buff ids in the PREVIEW only (stored data is left
                -- intact so routing is untouched).
                isTracked, popFrame._buffDispGroups = BuildBuffDisplayDedup(raw)
                -- Resolve cooldownID-level claims (collided buffs tracked by slot, a cd-claim
                -- marker embedded in assignedSpells -- see ns.CdClaimMarker) to their display
                -- sid IN PLACE, at the marker's own position in `tracked`, so the claim's
                -- preview slot -- and therefore its drag/reorder position -- falls directly out of its assignedSpells index, same as any other entry.
                for i = 1, #isTracked do
                    local cdID = mod.CdClaimMarkerToCdID(isTracked[i])
                    if cdID then
                        local cdSpellId = mod._cdmCleanSidByCDID and mod._cdmCleanSidByCDID[cdID]
                        if not (type(cdSpellId) == "number" and cdSpellId > 0) then
                            -- Clean cache not primed yet (fresh login, buff
                            -- active since): fall back to cooldownInfo. Each
                            -- field is vetted on its own -- never `or`-chain
                            -- possibly-secret values (truthiness taints).
                            local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local details = getCdInfo and getCdInfo(cdID)
                            local raw2 = details and details.overrideSpellID
                            if
                                not (
                                    type(raw2) == "number"
                                    and not (issecretvalue and issecretvalue(raw2))
                                    and raw2 > 0
                                )
                            then
                                raw2 = details and details.spellID
                            end
                            if
                                type(raw2) == "number"
                                and not (issecretvalue and issecretvalue(raw2))
                                and raw2 > 0
                            then
                                cdSpellId = raw2
                            end
                        end
                        if type(cdSpellId) == "number" and cdSpellId > 0 then
                            isTracked[i] = cdSpellId
                            trackedCd = trackedCd or {}
                            trackedCd[i] = cdID
                        end
                    end
                end
            else
                isTracked = raw
            end
        end
        -- Tracked-but-unlearned spells (assigned or materialized) render
        -- desaturated so it's obvious they aren't currently talented.
        -- CD/utility bars only: buff-family lists come from live pools
        -- (always learned), and custom-buff / focuskick ids are arbitrary
        -- spell ids IsPlayerSpell can't vouch for.
        local unlearnedSet
        -- Talent Conditions (same CD/utility gate): assigned id -> "on" (conditions
        -- hold) / "off" (not met: renders dimmed like an unlearned spell, so it can
        -- still be right-clicked). nil for non-users.
        local tcSet
        -- WoW Forever: a learned assigned spell Blizzard's Cooldown Manager keeps
        -- in Not Displayed by default (ns.CDMDefaultHiddenSet) draws nothing in
        -- game until shown there; it renders dimmed and its tooltip says why.
        local blizzHiddenSet
        if
            edge.key ~= "buffs"
            and not isBuffBar
            and not isCustomBuffBar
            and not isFocusKick
            and IsPlayerSpell
        then
            if mod._cdmAnyTalentCond then
                tcSet = mod.TalentCondPreviewSet(edge.key, isTracked)
            end
            local sdUn = mod.GetBarSpellData(edge.key)
            local customUn = sdUn and sdUn.customSpellIDs
            local cdursUn = sdUn and sdUn.customSpellDurations
            local sdursUn = sdUn and sdUn.spellDurations
            local groupsUn = sdUn and sdUn.customSpellGroups
            local racialsUn = mod._myRacialsSet
            local dh
            for _, ident in ipairs(isTracked) do
                if
                    type(ident) == "number"
                    and ident > 0
                    and not (customUn and customUn[ident])
                    and not (racialsUn and racialsUn[ident])
                    and not (cdursUn and cdursUn[ident])
                    and not (sdursUn and sdursUn[ident])
                    and not (groupsUn and groupsUn[ident])
                    and not (mod.CDM_AuraIconKeeps and mod.CDM_AuraIconKeeps(ident))
                then
                    if
                        not (
                            IsPlayerSpell(ident)
                            or IsPlayerSpell(NormalizeToBase(ident))
                            or IsPlayerSpell(ResolveToLive(ident))
                        )
                    then
                        unlearnedSet = unlearnedSet or {}
                        unlearnedSet[ident] = true
                    else
                        if dh == nil then
                            dh = mod.CDMDefaultHiddenSet() or false
                        end
                        if dh and mod.CDMIsDefaultHidden(dh, ident) then
                            blizzHiddenSet = blizzHiddenSet or {}
                            blizzHiddenSet[ident] = true
                        end
                    end
                end
            end
        end
        -- WoW Forever: a stored spell this client cannot see (not known
        -- and not listed anywhere in its Cooldown Manager catalogue: a
        -- retail-only spell a retail layout carried in) keeps its place in
        -- the store but gets no preview slot. The display groups map every
        -- remaining slot back onto its assignedSpells index (drag, remove
        -- and the per-icon menu read them). Same exemptions as the
        -- unlearned test above; the catalogue set is built only once a
        -- candidate shows up.
        if
            CludesUI.IS_FOREVER
            and edge.key ~= "buffs"
            and not isBuffBar
            and not isCustomBuffBar
            and not isFocusKick
        then
            local sdFv = mod.GetBarSpellData(edge.key)
            local customFv = sdFv and sdFv.customSpellIDs
            local cdursFv = sdFv and sdFv.customSpellDurations
            local sdursFv = sdFv and sdFv.spellDurations
            local groupsFv = sdFv and sdFv.customSpellGroups
            local racialsFv = mod._myRacialsSet
            local known = C_SpellBook.IsSpellKnown
            local listedFv, keptFv, dispFv
            for i = 1, #isTracked do
                local ident = isTracked[i]
                local unseen = false
                if
                    type(ident) == "number"
                    and ident > 0
                    and not (customFv and customFv[ident])
                    and not (racialsFv and racialsFv[ident])
                    and not (cdursFv and cdursFv[ident])
                    and not (sdursFv and sdursFv[ident])
                    and not (groupsFv and groupsFv[ident])
                    and not (mod.CDM_AuraIconKeeps and mod.CDM_AuraIconKeeps(ident))
                then
                    local base, live = NormalizeToBase(ident), ResolveToLive(ident)
                    if not (known(ident) or known(base) or known(live)) then
                        if listedFv == nil then
                            listedFv = mod.CDMForeverListedSet() or false
                        end
                        unseen = listedFv and not (listedFv[ident] or listedFv[base] or listedFv[live])
                            or false
                    end
                end
                if unseen then
                    if not keptFv then
                        -- First cut: the kept list starts with the slots before it.
                        keptFv, dispFv = {}, {}
                        for jdx = 1, i - 1 do
                            keptFv[jdx] = isTracked[jdx]
                            dispFv[jdx] = { jdx }
                        end
                    end
                elseif keptFv then
                    keptFv[#keptFv + 1] = ident
                    dispFv[#keptFv] = { i }
                end
            end
            if keptFv then
                isTracked, popFrame._buffDispGroups = keptFv, dispFv
            end
        end
        local total = #isTracked

        -- Use the same stride logic as the runtime (ComputeTopRowStride).
        -- Top and Bottom custom-row overrides are mutually exclusive; the
        -- Bottom override is the flip (pick the bottom count, top gets rest).
        local step, topRowCount
        local customTop
        if numRows == 2 then
            if edge.customTopRowEnabled and edge.topRowCount and edge.topRowCount > 0 then
                customTop = math.min(edge.topRowCount, total)
            elseif edge.customBottomRowEnabled and edge.bottomRowCount and edge.bottomRowCount > 0 then
                customTop = total - math.min(edge.bottomRowCount, total)
            end
        end
        if customTop ~= nil then
            if customTop < 0 then
                customTop = 0
            end
            topRowCount = customTop
            local bottomCount = total - topRowCount
            if bottomCount <= 0 or topRowCount <= 0 then
                -- Match the runtime: collapse to one row until BOTH rows hold
                -- an icon. This also keeps the "+" button on the single row.
                numRows = 1
                topRowCount = total
                step = math.max(total, 1)
            else
                step = math.max(topRowCount, bottomCount)
            end
        else
            step = math.ceil(total / numRows)
            if step < 1 then
                step = 1
            end
            topRowCount = total - (numRows - 1) * step
            if topRowCount < 0 then
                topRowCount = 0
            end
        end
        local gridSlots = (total > 0) and (step * numRows) or 0
        self._stride = step
        self._numRows = numRows
        self._gridSlots = gridSlots

        local bottomRowCount = total - topRowCount
        if bottomRowCount < 0 then
            bottomRowCount = 0
        end

        -- Per-row icon count for centering
        local function RowIconCount(line)
            if line == 0 then
                return topRowCount
            end
            return bottomRowCount
        end

        -- Mirror the live bar's visual row order: with reversed row growth the base
        -- (first data) row renders on the bottom/right (see ns.CDMRowsReversed /
        -- LayoutCDMBar). Data-row logic (RowIconCount, slot indices, drag mapping)
        -- keeps data rows; only the perpendicular placement offset flips.
        local pvReversed = mod.CDMRowsReversed and mod.CDMRowsReversed(edge) or false

        -- Total dimensions: spell grid + 1 extra slot for the "+" button
        local isVert = (grow == "DOWN" or grow == "UP")
        local totalW, totalH
        if isVert then
            local totalCols = numRows + 1
            totalW = (totalCols * iconPx) + ((totalCols - 1) * gap)
            totalH = (step * iconHeight) + ((step - 1) * gap)
        else
            local totalCols = step + 1
            totalW = (totalCols * iconPx) + ((totalCols - 1) * gap)
            totalH = (numRows * iconHeight) + ((numRows - 1) * gap)
        end

        -- CDM preview: no scale-to-fit -- SetClipsChildren on the content
        -- header clips any overflow so icon scale remains accurate.
        local curParentW = (hostFrame:GetWidth() - PAD * 2) / previewScale
        if curParentW > 0 then
            self:SetWidth(curParentW)
        end
        local startX = math.floor((curParentW - totalW) / 2)
        local startY = -5

        -- Position helper: places frame at grid position (col, row).
        -- Center any row that has fewer icons than stride. `row` is the
        -- DATA row; the visual row flips when pvReversed.
        local function PosAtGrid(widget, col, line)
            Pix.Size(widget, iconPx, iconHeight)
            widget:ClearAllPoints()
            local rowCount = RowIconCount(line)
            local rowHasLess = (rowCount > 0 and rowCount < step)
            local vRow = pvReversed and (numRows - 1 - line) or line
            local rowOffset = 0
            if isVert then
                if rowHasLess then
                    rowOffset = math.floor((step - rowCount) * (iconHeight + gap) / 2)
                end
                local px = startX + vRow * (iconPx + gap)
                local py = startY - col * (iconHeight + gap) - rowOffset
                Pix.Point(widget, "TOPLEFT", self, "TOPLEFT", px, py)
                widget._baseX = px
                widget._baseY = py
            else
                if rowHasLess then
                    rowOffset = math.floor((step - rowCount) * (iconPx + gap) / 2)
                end
                local px = startX + col * (iconPx + gap) + rowOffset
                local py = startY - vRow * (iconHeight + gap)
                Pix.Point(widget, "TOPLEFT", self, "TOPLEFT", px, py)
                widget._baseX = px
                widget._baseY = py
            end
        end

        -- Border color
        local bR, bG, bB = edge.borderR or 0, edge.borderG or 0, edge.borderB or 0
        if edge.borderClassColor then
            local _, classTok = UnitClass("player")
            if classTok then
                local classColor = RAID_CLASS_COLORS[classTok]
                if classColor then
                    bR, bG, bB = classColor.r, classColor.g, classColor.b
                end
            end
        end

        local shape = edge.iconShape or "none"

        -- Layout: fill bottom-up. Icons 1..topRowCount go to top row (row 0),
        -- remaining icons fill rows 1..numRows-1 (full bottom rows).
        for i = 1, math.min(gridSlots, MAX_PREVIEW_ICONS) do
            local slotFrame = slotList[i]
            slotFrame._slotIdx = i
            -- The assignedSpells indices this slot covers (a legacy-duplicate
            -- buff slot covers >1); nil when nothing was collapsed. Used by the
            -- settings popup's "Remove Spell" so it clears the whole duplicate.
            slotFrame._dataGroup = popFrame._buffDispGroups and popFrame._buffDispGroups[i] or nil

            -- Map sequential index to bottom-up grid position
            local col, line
            if i <= topRowCount then
                col = i - 1
                line = 0
            else
                local bottomIdx = i - topRowCount - 1
                col = bottomIdx % step
                line = 1 + math.floor(bottomIdx / step)
            end
            PosAtGrid(slotFrame, col, line)

            if i <= total then
                -- Spell slot
                local ident = isTracked[i]
                slotFrame._previewSpellID = nil -- reset each update
                slotFrame._previewCdID = trackedCd and trackedCd[i] or nil
                slotFrame._previewItemID = nil
                slotFrame._previewHostedBuff = nil
                slotFrame._previewIsEmptySlot = nil
                -- What the hover tooltip names: the spell whose art shows, or the item.
                slotFrame._previewArtID = nil
                slotFrame._previewTipItemID = nil
                slotFrame._previewBlizzHidden = nil
                if ident then
                    local texture
                    local cdClaim = mod.CdClaimMarkerToCdID and mod.CdClaimMarkerToCdID(ident)
                    local hostedSid = not cdClaim
                        and mod.HostedBuffMarkerToSpell
                        and mod.HostedBuffMarkerToSpell(ident)
                    if cdClaim then
                        -- Cd-claimed slot (a collided pair, e.g. Diabolist
                        -- Demonic Art vs Diabolic Ritual, or a tracked trinket
                        -- row; a buff bar's unresolved claim lands here too).
                        -- On a CD/util bar `tracked` ALIASES sd.assignedSpells (the buff-bar
                        -- branch above builds a fresh dedup list), so resolve
                        -- the marker to a display sid IN THIS RENDER STEP
                        -- ONLY -- never write back into `id`/`tracked[i]`
                        -- (that corrupts the saved marker). Same clean-cache
                        -- + cooldownInfo fallback as the buff-bar preview.
                        local cdSpellId = mod._cdmCleanSidByCDID and mod._cdmCleanSidByCDID[cdClaim]
                        if not (type(cdSpellId) == "number" and cdSpellId > 0) then
                            local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local details = getCdInfo and getCdInfo(cdClaim)
                            local raw2 = details and details.overrideSpellID
                            if
                                not (
                                    type(raw2) == "number"
                                    and not (issecretvalue and issecretvalue(raw2))
                                    and raw2 > 0
                                )
                            then
                                raw2 = details and details.spellID
                            end
                            if
                                type(raw2) == "number"
                                and not (issecretvalue and issecretvalue(raw2))
                                and raw2 > 0
                            then
                                cdSpellId = raw2
                            end
                        end
                        if type(cdSpellId) == "number" and cdSpellId > 0 then
                            local displayID = ResolveIconArt(cdSpellId, cdClaim)
                            texture = C_Spell.GetSpellTexture(displayID)
                            if not texture and displayID ~= cdSpellId then
                                texture = C_Spell.GetSpellTexture(cdSpellId)
                            end
                            slotFrame._previewSpellID = cdSpellId
                            slotFrame._previewArtID = displayID
                            slotFrame._previewCdID = cdClaim
                            slotFrame._previewHostedBuff = true
                        else
                            -- Tracked trinket row with its buff down reads no
                            -- spellID: show the item worn in that slot.
                            local getCdInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local details = getCdInfo and getCdInfo(cdClaim)
                            local eqSlot = details and details.equipSlot
                            if type(eqSlot) == "number" and not issecretvalue(eqSlot) then
                                local itemId = GetInventoryItemID("player", eqSlot)
                                texture = itemId and C_Item.GetItemIconByID(itemId) or nil
                                slotFrame._previewTipItemID = itemId
                            end
                        end
                    elseif hostedSid then
                        -- Hosted-buff marker: previews as its spell, flagged so
                        -- the per-icon menu takes the buff branch while the same
                        -- id's cooldown slot keeps the cd/util one.
                        local displayID = ResolveIconArt(hostedSid)
                        texture = C_Spell.GetSpellTexture(displayID)
                        if not texture and displayID ~= hostedSid then
                            texture = C_Spell.GetSpellTexture(hostedSid)
                        end
                        slotFrame._previewSpellID = hostedSid
                        slotFrame._previewArtID = displayID
                        slotFrame._previewHostedBuff = true
                    elseif mod.IsEmptySlotMarker(ident) then
                        -- Empty Slot: blank placeholder, no icon/tooltip identity.
                        slotFrame._previewIsEmptySlot = true
                    elseif ident <= -100 then
                        -- On-use bag item: negated itemID. The art and the item the
                        -- live icon shows (a resolved potion variant, or Blizzard's
                        -- own row's art), so the preview matches the bar in game.
                        local dispID
                        texture, dispID = mod.ItemEntryPreview(edge.key, ident)
                        slotFrame._previewItemID = -ident
                        slotFrame._previewTipItemID = dispID or -ident
                    elseif ident < 0 then
                        -- Trinket slot: get icon from equipped item
                        local itemId = GetInventoryItemID("player", -ident)
                        texture = itemId and C_Item.GetItemIconByID(itemId) or nil
                        slotFrame._previewTipItemID = itemId
                    else
                        -- Resolve to live override for texture lookup.
                        local displayID = ResolveIconArt(ident, slotFrame._previewCdID)
                        texture = C_Spell.GetSpellTexture(displayID)
                        if not texture and displayID ~= ident then
                            texture = C_Spell.GetSpellTexture(ident)
                        end
                        slotFrame._previewSpellID = ident
                        slotFrame._previewArtID = displayID
                        slotFrame._previewBlizzHidden = blizzHiddenSet and blizzHiddenSet[ident] or nil
                    end
                    if texture then
                        slotFrame._icon:SetTexture(texture)
                        slotFrame._icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                        local pvUnlearned = (unlearnedSet and unlearnedSet[ident])
                            or (tcSet and tcSet[ident] == "off")
                            or (blizzHiddenSet and blizzHiddenSet[ident])
                            or false
                        slotFrame._icon:SetDesaturated(pvUnlearned)
                        slotFrame._icon:SetAlpha(pvUnlearned and 0.55 or 1)
                    else
                        slotFrame._icon:SetTexture(nil)
                    end
                else
                    slotFrame._icon:SetTexture(nil)
                end
            else
                -- Blank slot (empty grid filler)
                slotFrame._icon:SetTexture(nil)
                slotFrame._previewSpellID = nil
                slotFrame._previewBlizzHidden = nil
                slotFrame._previewCdID = nil
                slotFrame._previewItemID = nil
                slotFrame._previewHostedBuff = nil
                slotFrame._previewIsEmptySlot = nil
                slotFrame._previewArtID = nil
                slotFrame._previewTipItemID = nil
            end

            local bSz = edge.borderSize or 1
            -- The art inset follows an exact Solid size (borderSizePx) so the border keeps sitting outside the art here.
            local bTex = edge.borderTexture or "solid"
            local bPx = CludesUI.BorderPx(edge.borderSizePx, bSz, bTex)
            if bPx and bTex == "solid" then
                bSz = bPx
            end
            slotFrame._icon:ClearAllPoints()
            Pix.Point(slotFrame._icon, "TOPLEFT", slotFrame, "TOPLEFT", bSz, -bSz)
            Pix.Point(slotFrame._icon, "BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", -bSz, bSz)
            slotFrame._icon:Show()

            if Pix.GetBorders(slotFrame) then
                Pix.SetBorderColor(slotFrame, bR, bG, bB, 1)
                Pix.SetBorderSize(slotFrame, bSz)
            end
            slotFrame._bg:SetColorTexture(edge.bgR or 0.08, edge.bgG or 0.08, edge.bgB or 0.08, edge.bgA or 0.6)
            if slotFrame._bg.SetSnapToPixelGrid then
                slotFrame._bg:SetSnapToPixelGrid(false)
                slotFrame._bg:SetTexelSnappingBias(0)
            end

            mod.ApplyShapeToCDMIcon(slotFrame, shape, edge)
            -- Blizzard Style: no CUI border or background; the live art pass
            -- adds the viewer's rounded mask and ring to the slot exactly as
            -- it does to a bar's own icons. The preview's overlays (text,
            -- hover and hosted-buff borders, glow) move above the ring, at
            -- the levels their live counterparts use.
            if CludesUI.BlizzStyle.Get("cdmicons") and mod.CdmApplyBlizzIconArt then
                if Pix.GetBorders(slotFrame) then
                    Pix.HideBorder(slotFrame)
                end
                slotFrame._bg:Hide()
                mod.CdmApplyBlizzIconArt(slotFrame)
                local lvl = slotFrame:GetFrameLevel()
                if slotFrame._pvTextOverlay then
                    slotFrame._pvTextOverlay:SetFrameLevel(lvl + 23)
                end
                if slotFrame._hlBrd then
                    slotFrame._hlBrd:GetParent():SetFrameLevel(lvl + 17)
                end
                if slotFrame._hostBrd then
                    slotFrame._hostBrd:GetParent():SetFrameLevel(lvl + 16)
                end
                if slotFrame._glowOverlay then
                    slotFrame._glowOverlay:SetFrameLevel(lvl + 16)
                end
            end
            -- Talent Conditions corner mark (built on first use; slots are shared across bars, so always
            -- repainted once it exists). After the style pass: it sits just under the text overlay's level.
            if tcSet or slotFrame._tcMark then
                mod.PaintTalentCondMark(slotFrame, tcSet and i <= total and tcSet[isTracked[i]] or nil)
            end
            -- For custom shapes, ensure the square highlight border stays hidden
            -- (ApplyShapeToCDMIcon hides the slot's own PP border but not _hlBrd)
            -- (Blizzard Style forces shape none, whatever the profile carries.)
            if
                slotFrame._hlBrd
                and shape ~= "square"
                and shape ~= "csquare"
                and shape ~= "none"
                and not CludesUI.BlizzStyle.Get("cdmicons")
            then
                slotFrame._hlBrd:Hide()
            end
            -- Hosted-buff gold border: always on for a buff icon hosted on
            -- this CD/utility bar. Square-family shapes use the dedicated
            -- gold strips; masked shapes tint the shape border instead
            -- (their square strips are hidden, like the hover highlight).
            if slotFrame._hostBrd then
                if slotFrame._previewHostedBuff and not (slotFrame._shapeBorder and slotFrame._shapeBorder:IsShown()) then
                    slotFrame._hostBrd:Show()
                else
                    slotFrame._hostBrd:Hide()
                end
            end
            if slotFrame._previewHostedBuff and slotFrame._shapeBorder and slotFrame._shapeBorder:IsShown() then
                slotFrame._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
            end

            -- Stack count preview text
            if slotFrame._stackText then
                if i <= total then
                    -- Show charge count for charge-based spells (default: on)
                    -- Match real bar styling exactly (RefreshCDMIconAppearance)
                    local scFont = mod.GetCDMFont and mod.GetCDMFont() or FONT_PATH
                    local scSize = edge.stackCountSize or 11
                    local scR = edge.stackCountR or 1
                    local scG = edge.stackCountG or 1
                    local scB = edge.stackCountB or 1
                    local scX = edge.stackCountX or 0
                    local scY = edge.stackCountY or 0
                    local scPoint = edge.stackCountPosition or "bottomright"
                    if scPoint == "bottomleft" then
                        scPoint = "BOTTOMLEFT"
                        scY = scY + 2
                    elseif scPoint == "bottom" then
                        scPoint = "BOTTOM"
                        scY = scY + 2
                    elseif scPoint == "topright" then
                        scPoint = "TOPRIGHT"
                    elseif scPoint == "top" then
                        scPoint = "TOP"
                    elseif scPoint == "topleft" then
                        scPoint = "TOPLEFT"
                    elseif scPoint == "center" then
                        scPoint = "CENTER"
                    elseif scPoint == "left" then
                        scPoint = "LEFT"
                    elseif scPoint == "right" then
                        scPoint = "RIGHT"
                    else
                        scPoint = "BOTTOMRIGHT"
                        scY = scY + 2
                    end
                    CludesUI.ApplyIconTextFont(slotFrame._stackText, scFont, scSize, "cdm")
                    slotFrame._stackText:SetTextColor(scR, scG, scB)
                    slotFrame._stackText:ClearAllPoints()
                    slotFrame._stackText:SetPoint(scPoint, slotFrame, scPoint, scX, scY)
                    local spellRef = slotFrame._previewSpellID
                    local chargeInfo = spellRef
                        and C_Spell.GetSpellCharges
                        and C_Spell.GetSpellCharges(spellRef)
                    local maxC = chargeInfo and chargeInfo.maxCharges
                    -- A custom CD/utility spell CUI draws itself has no Blizzard charge
                    -- frame: the live icon shows a count only with its Show Charges
                    -- opt-in, so match it. A Blizzard-tracked one draws Blizzard's frame.
                    local sdSc = spellRef
                        and not isBuffBar
                        and not isCustomBuffBar
                        and mod.GetBarSpellData(edge.key)
                    local showC = edge.showCharges ~= false
                    if
                        sdSc
                        and sdSc.customSpellIDs
                        and sdSc.customSpellIDs[spellRef]
                        and not mod.IsCDMTrackedCooldown(spellRef)
                    then
                        showC = (sdSc.customSpellForceCount and sdSc.customSpellForceCount[spellRef]) or false
                    end
                    if showC and maxC and maxC > 1 then
                        slotFrame._stackText:SetText(tostring(maxC))
                        slotFrame._stackText:Show()
                    elseif slotFrame._previewItemID and (edge.showItemCount ~= false) then
                        -- Preset potions/healthstones: fake item count so users can
                        -- preview and style the count text (mirrors charge preview).
                        slotFrame._stackText:SetText("5")
                        slotFrame._stackText:Show()
                    else
                        slotFrame._stackText:Hide()
                    end
                else
                    slotFrame._stackText:Hide()
                end
            end

            -- Use the live renderer so font, anchors and badge alpha agree.
            if slotFrame._keybindText then
                mod.StyleCDMKeybind(slotFrame._keybindText, edge, slotFrame, 1, FONT_PATH)
                local spellRef = slotFrame._previewSpellID
                if edge.showKeybind and spellRef then
                    -- The live icons' lookup: id, override, base, then name.
                    local key = mod.ResolveCDMKeybind(spellRef)
                    if key then
                        slotFrame._keybindText:SetText(key)
                        slotFrame._keybindText:Show()
                    else
                        slotFrame._keybindText:Hide()
                    end
                else
                    slotFrame._keybindText:Hide()
                end
                -- StyleCDMKeybind above already styled the badge: visibility only.
                mod.ShowCDMKeybindBadge(slotFrame._keybindText, edge)
            end

            if i <= total then
                slotFrame:Show()
            else
                slotFrame:Hide()
            end
        end

        for i = gridSlots + 1, MAX_PREVIEW_ICONS do
            slotList[i]:Hide()
        end

        -- "+" button: placed right after the last icon on the bottom row (always full,
        -- or the only row). For empty bars (count=0), the "+" is the only visible element.
        local addPx, addPy
        if total == 0 then
            -- No spells: center the "+" button alone
            addPx = math.floor((curParentW - iconPx) / 2)
            addPy = startY
        elseif isVert then
            -- Vertical: "+" goes in the next column to the right, at the bottom
            addPx = startX + numRows * (iconPx + gap)
            addPy = startY - (step - 1) * (iconHeight + gap)
        else
            -- Horizontal: "+" goes right after the last column on the bottom row
            local lastRow = numRows - 1
            addPx = startX + step * (iconPx + gap)
            addPy = startY - lastRow * (iconHeight + gap)
        end
        Pix.Size(addBtn, iconPx, iconHeight)
        addBtn:ClearAllPoints()
        Pix.Point(addBtn, "TOPLEFT", self, "TOPLEFT", addPx, addPy)
        if Pix.GetBorders(addBtn) then
            Pix.SetBorderSize(addBtn, 1)
        end
        local accR, accG, accB = CludesUI.GetAccentColor()

        addLbl:SetTextColor(accR, accG, accB, 0.6)
        addBtn:Show()

        -- Second "+" (buff) button sits one slot right of the standard "+", on CD/utility bars only (buff-family/custom_buff/focuskick bars track buffs their own way).
        if not isBuffBar and not isCustomBuffBar and not isFocusKick then
            Pix.Size(addBuffBtn, iconPx, iconHeight)
            addBuffBtn:ClearAllPoints()
            Pix.Point(addBuffBtn, "TOPLEFT", self, "TOPLEFT", addPx + iconPx + gap, addPy)
            if Pix.GetBorders(addBuffBtn) then
                Pix.SetBorderSize(addBuffBtn, 1)
            end
            addBuffBtn:Show()
        else
            addBuffBtn:Hide()
        end

        -- Bar background covers spell grid only (not the + column)
        local spellW, spellH
        if isVert then
            spellW = (numRows * iconPx) + ((numRows - 1) * gap)
            spellH = (step * iconHeight) + ((step - 1) * gap)
        else
            spellW = (step * iconPx) + ((step - 1) * gap)
            spellH = totalH
        end
        if edge.barBgEnabled then
            pvBarBg:ClearAllPoints()
            pvBarBg:SetPoint("TOPLEFT", startX, startY)
            pvBarBg:SetPoint("BOTTOMRIGHT", popFrame, "TOPLEFT", startX + spellW, startY - spellH)
            pvBarBg:SetColorTexture(edge.barBgR or 0, edge.barBgG or 0, edge.barBgB or 0, edge.barBgA or 0.5)
            if pvBarBg.SetSnapToPixelGrid then
                pvBarBg:SetSnapToPixelGrid(false)
                pvBarBg:SetTexelSnappingBias(0)
            end
            pvBarBg:Show()
        else
            pvBarBg:Hide()
        end

        self:SetAlpha(1)

        -- Buff bar info text
        if not self._buffInfoText then
            local infoFS = self:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            infoFS:SetJustifyH("CENTER")
            infoFS:SetWordWrap(true)
            infoFS:SetTextColor(0.6, 0.6, 0.6, 0.9)
            self._buffInfoText = infoFS
        end
        -- Reorder/per-icon hint shown directly below the preview icons. Buff bars and
        -- CD/utility bars get different wording; FocusKick has its own info text instead and is not user-reorderable.
        if not self._reorderHintText then
            local rowHeight = self:CreateFontString(nil, "OVERLAY")
            rowHeight:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            rowHeight:SetJustifyH("CENTER")
            rowHeight:SetWordWrap(true)
            rowHeight:SetTextColor(0.62, 0.62, 0.62, 0.9)
            self._reorderHintText = rowHeight
        end
        local function ShowReorderHint(textValue)
            -- Override editing sessions: the per-icon menu is Remove Spell only.
            if CludesUI.SpecOverrides_EditSessionActive() then
                textValue =
                    "Drag to Reorder. Click to remove spells. Per-spell settings are not part of the override system."
            end
            local rowHeight = self._reorderHintText
            rowHeight:SetText(CludesUI.L(textValue))
            rowHeight:ClearAllPoints()
            rowHeight:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
            rowHeight:SetWidth(self:GetWidth() - 20)
            rowHeight:Show()
            self:SetHeight(totalH + 10 + rowHeight:GetStringHeight() + 20)
        end

        if isBuffBar then
            if self._buffInfoText then
                self._buffInfoText:Hide()
            end
            if self._buffInfoClick then
                self._buffInfoClick:Hide()
            end
            -- Hide any stale hidden rows
            if self._hiddenRows then
                for _, hr in ipairs(self._hiddenRows) do
                    hr:Hide()
                end
            end
            if self._hiddenHeader then
                self._hiddenHeader:Hide()
            end
            if self._focusKickInfoText then
                self._focusKickInfoText:Hide()
            end
            ShowReorderHint(
                "Drag to Reorder. Click to override display settings and add custom effects per icon."
            )
        elseif isFocusKick then
            if self._buffInfoText then
                self._buffInfoText:Hide()
            end
            if self._buffInfoClick then
                self._buffInfoClick:Hide()
            end
            if self._reorderHintText then
                self._reorderHintText:Hide()
            end
            if not self._focusKickInfoText then
                local kickText = self:CreateFontString(nil, "OVERLAY")
                kickText:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                kickText:SetJustifyH("CENTER")
                kickText:SetWordWrap(true)
                kickText:SetTextColor(1, 1, 1, 1)
                self._focusKickInfoText = kickText
            end
            local kickText = self._focusKickInfoText
            -- Wording must track the "Show on Target" toggle -- otherwise this text keeps promising focus-tracking even when the bar is configured to follow the current target instead.
            local fkMain
            if edge.focusKickUseTarget then
                fkMain = CludesUI.L("This bar will always be attached to your current target's nameplate")
            else
                fkMain = CludesUI.L("This bar will always be attached to your focus target's nameplate")
            end
            -- Second, dimmer line: points sound-only users at the setup that needs no icon.
            kickText:SetText(
                fkMain
                    .. "\n"
                    .. CludesUI.COLOR_CODES.DIM
                    .. CludesUI.L(
                        "Want only the cast sound? Leave this bar empty and set Interrupt Spell below."
                    )
                    .. "|r"
            )
            kickText:ClearAllPoints()
            kickText:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
            kickText:SetWidth(self:GetWidth() - 20)
            kickText:Show()
            self:SetHeight(totalH + 10 + kickText:GetStringHeight() + 20)
        else
            if self._buffInfoText then
                self._buffInfoText:Hide()
            end
            if self._buffInfoClick then
                self._buffInfoClick:Hide()
            end
            if self._focusKickInfoText then
                self._focusKickInfoText:Hide()
            end
            ShowReorderHint(
                "Drag to Reorder. Click to add custom glows, active/cooldown state effects and more."
            )
        end

        -- Resize wrapper to min(content, max) and toggle scrollbar
        local parentH = self:GetHeight() * (self._previewScale or 1)
        local maxH = self._PREVIEW_MAX_H or 200
        if parentH > maxH then
            -- Add bottom padding so info text is fully visible when scrolled down
            self:SetHeight(self:GetHeight() + 30)
            -- If the cap would slice into the icon grid itself, snap the viewport to
            -- a whole row instead -- cropping into the hint text below is harmless,
            -- cropping an icon row in half isn't.
            local stackRows = isVert and step or numRows
            local topInset = 5
            local rowStep = iconHeight + gap
            local gridBottomLocal = topInset + stackRows * iconHeight + (stackRows - 1) * gap
            if gridBottomLocal * self._previewScale > maxH then
                local visibleRows = math.max(
                    1,
                    math.floor((maxH / self._previewScale - topInset + gap) / rowStep + 0.001)
                )
                visibleRows = math.min(visibleRows, stackRows)
                local cappedLocalH = topInset + visibleRows * iconHeight + (visibleRows - 1) * gap
                self._wrapper:SetHeight(math.min(maxH, cappedLocalH * self._previewScale))
            else
                self._wrapper:SetHeight(maxH)
            end
        else
            self._wrapper:SetHeight(parentH)
            if self._scrollFrame then
                self._scrollFrame:SetVerticalScroll(0)
            end
        end
        if self._updatePVThumb then
            self._updatePVThumb()
        end

        -- Restart active state preview on first icon if toggled on
        if _cdmActivePreviewOn then
            StopActiveStatePreview()
            StartActiveStatePreview()
        end
    end

    popFrame._previewSlots = slotList
    optionState._cdmPreview = popFrame
    popFrame:Update()
    -- This module's own header preview slot (its readers: the CDM options and
    -- the reanchor's preview pass); the shared slot is still written for the
    -- readers that have not moved to their own.
    CludesUI._cdmHeaderPreview = popFrame
    CludesUI._contentHeaderPreview = popFrame
    -- Start active state preview if toggled on
    if _cdmActivePreviewOn then
        StartActiveStatePreview()
    end
    -- Return wrapper height (already capped by Update's resize logic)
    return wrapper:GetHeight()
end

-- Used by BarsPage_Options.lua
mod.CDMO_BuildCDMLivePreview = BuildCDMLivePreview
