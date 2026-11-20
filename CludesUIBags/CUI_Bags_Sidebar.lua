if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Sidebar.lua
--
--  The sidebar: drag-to-reorder, CreateSidebar, the category context
--  menu and BuildSidebarButtons.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local GetItemInfo = C_Item.GetItemInfo
local CUI = CludesUI

local BP, GetAccentRGB, GetDefaultBagType = Inner.BP, Inner.GetAccentRGB, Inner.GetDefaultBagType
local GetFont, IsItemPinned, NormalizePinKey = Inner.GetFont, Inner.IsItemPinned, Inner.NormalizePinKey
local SetBagFont, ClearGroupOrder = Inner.SetBagFont, Inner.ClearGroupOrder
local ResortAfterGroupChange, SIDEBAR_BTN_H = Inner.ResortAfterGroupChange, Inner.SIDEBAR_BTN_H
local SIDEBAR_ICON_SIZE, SIDEBAR_INDENT = Inner.SIDEBAR_ICON_SIZE, Inner.SIDEBAR_INDENT
local SIDEBAR_PAD, SIDEBAR_W_COLLAPSED = Inner.SIDEBAR_PAD, Inner.SIDEBAR_W_COLLAPSED
local SIDEBAR_W_EXPANDED, PinnedItems = Inner.SIDEBAR_W_EXPANDED, Inner.PinnedItems
local SetSelectedCategoryIndex = Inner.SetSelectedCategoryIndex
local SetSelectedGroupName = Inner.SetSelectedGroupName

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = Inner.selectedCategoryIndex
Inner.categoryIndexSetters[#Inner.categoryIndexSetters + 1] = function(val)
    selectedCategoryIndex = val
end
local selectedGroupName
Inner.groupNameSetters[#Inner.groupNameSetters + 1] = function(val)
    selectedGroupName = val
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local _sidebarBtns = {} -- array of sidebar button frames

-- 0 while collapsed under Hide Sidebar Icons When Collapsed (default off): the
-- sidebar hides and its expand arrow sits left of the window title.
-- fixed views up top: all items, onebag, multibag, plus bank when offline bank is on
local function FixedViewCount()
    return (mod.Offline and mod.Offline.Enabled()) and 4 or 3
end

local function GetSidebarWidth()
    -- The Modern display has no sidebar: its chip strip picks the view
    if CUI_Bags.IsModernMode and CUI_Bags.IsModernMode() then
        return 0
    end
    local p = BP()
    if not p.bagSidebarCollapsed then
        return SIDEBAR_W_EXPANDED
    end
    return p.bagHideSidebarIconsCollapsed == true and 0 or SIDEBAR_W_COLLAPSED
end

-- The item grid starts after the full width, including the window rim.
local function GetSidebarContentWidth(sideBar)
    return math.max(0, GetSidebarWidth() - sideBar._leftInset)
end

-------------------------------------------------------------------------------
--  Sidebar drag-to-reorder (iOS-style: ghost + insert line + source fade)
-------------------------------------------------------------------------------
local _dragGhost -- floating ghost frame (scaled 0.5x, 70% opacity)
local _dragFromCatIdx -- category index being dragged (1-based into bagCategoryDefs)
local _dragSourceBtn -- the button frame being dragged (to restore alpha)
local _dragInsertLine -- accent-colored insertion line
local _dragGroupHL -- accent-colored group highlight overlay
local _dragLastTarget -- last computed insert target (avoid redundant updates)
local _dragLastMode -- "above", "below", "group"
local _dragLastBtn -- last target button (avoid redundant updates)
local _dragDropMode -- current drop mode for StopSidebarDrag
local _dragDropTarget -- current drop target catIdx
local _dragTargetIsHeader -- true when resolved target came from a group header button
local _dragInsertGroup -- group name when insert position is inside a group

local function EnsureDragGhost()
    if _dragGhost then
        return _dragGhost
    end
    local ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(SIDEBAR_W_EXPANDED, SIDEBAR_BTN_H)
    ghost:SetAlpha(0.7)
    ghost:SetScale(0.5)
    ghost:EnableMouse(false)
    ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.bg:SetAllPoints()
    ghost.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
    ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ghost.label = ghost:CreateFontString(nil, "OVERLAY")
    SetBagFont(ghost.label, 11)
    ghost.label:SetPoint("LEFT", ghost.icon, "RIGHT", 6, 0)
    ghost.label:SetTextColor(1, 1, 1)
    ghost:Hide()
    _dragGhost = ghost
    return ghost
end

local function EnsureInsertLine()
    if _dragInsertLine then
        return _dragInsertLine
    end
    local sideBar = CUI_Bags._sidebar
    if not sideBar then
        return nil
    end
    local eg = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
    local rowLine = sideBar:CreateTexture(nil, "OVERLAY", nil, 7)
    rowLine:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    rowLine:SetHeight(px * 2)
    rowLine:Hide()
    _dragInsertLine = rowLine
    return rowLine
end

local function EnsureGroupHighlight()
    if _dragGroupHL then
        return _dragGroupHL
    end
    local sideBar = CUI_Bags._sidebar
    if not sideBar then
        return nil
    end
    local eg = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
    local highlight = CreateFrame("Frame", nil, sideBar)
    highlight:SetFrameLevel(sideBar:GetFrameLevel() + 10)
    highlight.bg = highlight:CreateTexture(nil, "OVERLAY", nil, 6)
    highlight.bg:SetAllPoints()
    highlight.bg:SetColorTexture(eg.r, eg.g, eg.b, 0.15)
    -- Accent border
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local function MakeLine(point1, rel1, point2, rel2, wid, hgt)
        local t = highlight:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(eg.r, eg.g, eg.b, 0.6)
        t:SetPoint(point1, highlight, rel1, 0, 0)
        t:SetPoint(point2, highlight, rel2, 0, 0)
        if wid then
            t:SetWidth(wid)
        end
        if hgt then
            t:SetHeight(hgt)
        end
        return t
    end
    MakeLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, px)
    MakeLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, px)
    MakeLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", px, nil)
    MakeLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", px, nil)
    highlight:Hide()
    _dragGroupHL = highlight
    return highlight
end

-- Compute insert position from cursor Y relative to visible sidebar buttons (skips hidden/empty categories).
local function ComputeDropTarget()
    local sideBar = CUI_Bags._sidebar
    if not sideBar then
        return nil
    end
    local scale = sideBar:GetEffectiveScale()
    local _, rowY = GetCursorPosition()
    local sidebarTop = sideBar:GetTop() * scale
    local localY = (sidebarTop - rowY) / scale

    -- offset past the sidebar header and the fixed views
    localY = localY - 24 - FixedViewCount() * (SIDEBAR_BTN_H + SIDEBAR_PAD)

    if localY < 0 then
        return 1
    end

    -- Walk visible category buttons to find which slot the cursor is over
    local categories = CUI_CategoryManager:GetCategories()
    local visIdx = 0
    local lastVisibleCatIdx = 1
    for i = 1, #categories do
        local anyShown = false
        for _, button in ipairs(_sidebarBtns) do
            if button:IsShown() and button._catIdx == i then
                anyShown = true
                break
            end
        end
        if anyShown then
            visIdx = visIdx + 1
            lastVisibleCatIdx = i
            local slotTop = (visIdx - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD)
            local slotMid = slotTop + (SIDEBAR_BTN_H + SIDEBAR_PAD) / 2
            if localY < slotMid then
                return i
            end
        end
    end
    return lastVisibleCatIdx
end

-- Compute drop zone: which button the cursor is over and which zone (above/group/below).
-- Returns: targetCatIdx, mode ("above", "below", "group"), targetBtn
local function ComputeDropZone()
    -- Sidebar buttons carry the sidebar's effective scale, so divide the cursor by that
    -- (not UIParent's) to match btn:GetTop()/GetBottom() -- UIParent math picks the wrong row at scale != 100%. Mirrors ComputeDropTarget above.
    local sideBar = CUI_Bags._sidebar
    local scale = (sideBar and sideBar:GetEffectiveScale()) or UIParent:GetEffectiveScale()
    local _, rowY = GetCursorPosition()
    local cursorY = rowY / scale

    local GROUP_ZONE = 4 -- pixels from center that count as "group" zone

    -- Walk visible sidebar buttons to find which one cursor is over
    for _, button in ipairs(_sidebarBtns) do
        if button:IsShown() and button._catIdx and button._catIdx > 0 then
            local topY = button:GetTop()
            local bot = button:GetBottom()
            if topY and bot and cursorY <= topY and cursorY >= bot then
                local mid = (topY + bot) / 2
                local distFromMid = math.abs(cursorY - mid)
                if distFromMid <= GROUP_ZONE then
                    return button._catIdx, "group", button
                elseif cursorY > mid then
                    return button._catIdx, "above", button
                else
                    return button._catIdx, "below", button
                end
            end
        end
    end
    -- Fallback: find nearest category button by Y distance
    local bestIdx, bestDist, bestBtn, bestMode = 1, math.huge, nil, "above"
    for _, button in ipairs(_sidebarBtns) do
        if button:IsShown() and button._catIdx and button._catIdx > 0 then
            local topY = button:GetTop()
            local bot = button:GetBottom()
            if topY and bot then
                local mid = (topY + bot) / 2
                local dist = math.abs(cursorY - mid)
                if dist < bestDist then
                    bestDist = dist
                    bestIdx = button._catIdx
                    bestBtn = button
                    bestMode = cursorY > mid and "above" or "below"
                end
            end
        end
    end
    return bestIdx, bestMode, bestBtn
end

-- Compute insert line Y position for a given category target index
local function GetInsertLineY(targetCatIdx)
    -- offset: header (24) plus the fixed views
    local topOffset = 24 + FixedViewCount() * (SIDEBAR_BTN_H + SIDEBAR_PAD)
    local shownSlot = 0
    local categories = CUI_CategoryManager:GetCategories()
    for i = 1, #categories do
        local anyShown = false
        for _, button in ipairs(_sidebarBtns) do
            if button:IsShown() and button._catIdx == i then
                anyShown = true
                break
            end
        end
        if anyShown then
            shownSlot = shownSlot + 1
            if i == targetCatIdx then
                return -topOffset - ((shownSlot - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD))
            end
        end
    end
    return -topOffset - (shownSlot * (SIDEBAR_BTN_H + SIDEBAR_PAD))
end

local StartSidebarDrag -- forward declaration (defined below)

-- Shared drag-detect frame for sidebar buttons (hidden when not dragging)
local _sidebarDragDetect = CreateFrame("Frame")
_sidebarDragDetect:Hide()
_sidebarDragDetect._btn = nil
_sidebarDragDetect:SetScript("OnUpdate", function(self)
    local button = self._btn
    if not button or not button._dragPending then
        self:Hide()
        return
    end
    local _, rowY = GetCursorPosition()
    if math.abs(rowY - (button._dragStartY or rowY)) > 4 then
        button._dragPending = false
        button._didDrag = true
        self:Hide()
        StartSidebarDrag(button, button._catIdx, button._catName, button._catIcon, button._catIsAtlas)
    end
end)

local _dragUpdateFrame = CreateFrame("Frame")
_dragUpdateFrame:Hide()
_dragUpdateFrame:SetScript("OnUpdate", function()
    if not _dragFromCatIdx then
        _dragUpdateFrame:Hide()
        return
    end

    local dragShadow = _dragGhost
    if dragShadow and dragShadow:IsShown() then
        local cx, rowY = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        local gs = dragShadow:GetScale() or 1
        dragShadow:ClearAllPoints()
        dragShadow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / (sc * gs), rowY / (sc * gs))
    end

    local goal, modeName, goalButton = ComputeDropZone()

    if goal ~= _dragLastTarget or modeName ~= _dragLastMode or goalButton ~= _dragLastBtn then
        _dragLastTarget = goal
        _dragLastMode = modeName
        _dragLastBtn = goalButton
        local rowLine = EnsureInsertLine()
        local highlight = EnsureGroupHighlight()

        -- Don't group with self
        if modeName == "group" and goal == _dragFromCatIdx then
            modeName = "above"
        end

        local categories = CUI_CategoryManager:GetCategories()

        -- Block drops onto/above special entries (Pinned Items, Recent Items) -- nothing drags above the divider,
        -- and nothing lands among the virtual categories at the tail.
        local targetCatCheck = categories[goal]
        if
            targetCatCheck
            and (targetCatCheck.isPinned or targetCatCheck.isRecent or targetCatCheck.isVirtual)
        then
            rowLine:Hide()
            highlight:Hide()
            _dragDropMode = nil
            _dragDropTarget = nil
            return
        end
        -- Can't group with or from a noGroup category (e.g. Reagent Bag)
        if modeName == "group" and categories[goal] and categories[goal].noGroup then
            modeName = "below"
        end
        if modeName == "group" and categories[_dragFromCatIdx] and categories[_dragFromCatIdx].noGroup then
            modeName = "above"
        end

        local fromCat = categories[_dragFromCatIdx]
        local targetCat = categories[goal]
        -- Can't group with a grouped member (but CAN group with a group header to join that group)
        if
            modeName == "group"
            and targetCat
            and targetCat.groupName
            and not (goalButton and goalButton._isGroupHeader)
        then
            modeName = "above"
        end
        -- Can't group something already in a group with an ungrouped category (would nest groups)
        if
            modeName == "group"
            and fromCat
            and fromCat.groupName
            and not (goalButton and goalButton._isGroupHeader)
        then
            modeName = "above"
        end

        if modeName == "group" and goalButton then
            if rowLine then
                rowLine:Hide()
            end
            highlight:ClearAllPoints()
            highlight:SetPoint("TOPLEFT", goalButton, "TOPLEFT", 2, 0)
            highlight:SetPoint("BOTTOMRIGHT", goalButton, "BOTTOMRIGHT", -2, 0)
            highlight:Show()
            _dragDropMode = "group"
            _dragDropTarget = goal
        else
            if highlight then
                highlight:Hide()
            end
            _dragDropMode = "insert"

            -- Resolve actual target index: "above N" = N, "below N" = N+1
            -- Exception: "below header" = same gap as "above first member" = N (not N+1)
            local resolvedTarget = goal
            if modeName == "below" then
                if goalButton and goalButton._isGroupHeader then
                    resolvedTarget = goal
                else
                    resolvedTarget = goal + 1
                end
            end

            -- Set children are a contiguous runtime block re-anchored on rebuild:
            -- an insert between them would not actually land there, so suppress
            -- the line instead of promising a position the drop can't keep.
            if goalButton and goalButton._isEquipSet then
                if rowLine then
                    rowLine:Hide()
                end
                _dragDropTarget = nil
                _dragInsertGroup = nil
                return
            end

            -- Determine if insert position is inside a group
            local inGroup = nil
            local fromNoGroup = categories[_dragFromCatIdx] and categories[_dragFromCatIdx].noGroup
            local posInGroup = goalButton
                and targetCat
                and targetCat.groupName
                and (goalButton._isGroupMember or (goalButton._isGroupHeader and modeName == "below"))
            if posInGroup then
                if fromNoGroup then
                    -- noGroup categories can't enter groups; suppress line entirely
                    if rowLine then
                        rowLine:Hide()
                    end
                    _dragDropTarget = nil
                    _dragInsertGroup = nil
                    return
                end
                inGroup = targetCat.groupName
            end

            -- No-op check: skip if same position AND group membership isn't changing
            local fromCatGroup = categories[_dragFromCatIdx] and categories[_dragFromCatIdx].groupName
            local groupChanges = (inGroup or false) ~= (fromCatGroup or false)
            local isNoOp = not groupChanges
                and (resolvedTarget == _dragFromCatIdx or resolvedTarget == _dragFromCatIdx + 1)

            if isNoOp then
                if rowLine then
                    rowLine:Hide()
                end
                _dragDropTarget = nil
                _dragInsertGroup = nil
            else
                _dragDropTarget = resolvedTarget
                _dragTargetIsHeader = goalButton and goalButton._isGroupHeader or false
                _dragInsertGroup = inGroup

                if goal and rowLine then
                    -- Position line in the gap between buttons (centered in SIDEBAR_PAD)
                    local gapOff = math.floor(SIDEBAR_PAD / 2)
                    local leftOff = inGroup and (4 + SIDEBAR_INDENT) or 4
                    if modeName == "below" and goalButton then
                        rowLine:ClearAllPoints()
                        rowLine:SetPoint("TOPLEFT", goalButton, "BOTTOMLEFT", leftOff, -gapOff)
                        rowLine:SetPoint("TOPRIGHT", goalButton, "BOTTOMRIGHT", -4, -gapOff)
                    elseif goalButton then
                        rowLine:ClearAllPoints()
                        rowLine:SetPoint("TOPLEFT", goalButton, "TOPLEFT", leftOff, gapOff)
                        rowLine:SetPoint("TOPRIGHT", goalButton, "TOPRIGHT", -4, gapOff)
                    else
                        local sideBar = CUI_Bags._sidebar
                        local lineY = GetInsertLineY(goal)
                        rowLine:ClearAllPoints()
                        rowLine:SetPoint("TOPLEFT", sideBar, "TOPLEFT", leftOff, lineY)
                        rowLine:SetPoint("TOPRIGHT", sideBar, "TOPRIGHT", -4, lineY)
                    end
                    rowLine:Show()
                end
            end
        end
    end
end)

StartSidebarDrag = function(btnSelf, catIndex, catName, catIcon, catIsAtlas)
    _dragFromCatIdx = catIndex
    _dragSourceBtn = btnSelf
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil

    local dragShadow = EnsureDragGhost()
    dragShadow:SetSize(btnSelf:GetWidth(), SIDEBAR_BTN_H)
    if catIsAtlas then
        dragShadow.icon:SetAtlas(catIcon or "")
        dragShadow.icon:SetTexCoord(0, 1, 0, 1)
    else
        dragShadow.icon:SetTexture(CludesUI.ClientIcon(catIcon or 134400))
        dragShadow.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    dragShadow.label:SetText(catName or "?")
    local navCollapsed = BP().bagSidebarCollapsed
    mod.AnchorBagSidebarIcon(dragShadow.icon, navCollapsed and mod.BagsForever(), 8)
    if navCollapsed then
        dragShadow.label:Hide()
    else
        dragShadow.label:Show()
    end
    dragShadow:Show()

    -- Source button: fade to 30% (iOS lift effect)
    btnSelf:SetAlpha(0.3)

    EnsureInsertLine()
    _dragUpdateFrame:Show()
end

local function StopSidebarDrag()
    if not _dragFromCatIdx then
        return
    end

    if _dragSourceBtn then
        _dragSourceBtn:SetAlpha(1)
    end

    -- Capture selected category by reference so we can re-find its index after reorder
    local categories = CUI_CategoryManager:GetCategories()
    local selectedCatRef = (selectedCategoryIndex > 0) and categories[selectedCategoryIndex] or nil
    local savedGroupName = selectedGroupName

    local fromCat = categories[_dragFromCatIdx]
    local sourceGroup = fromCat and fromCat.groupName
    local isHeader = _dragSourceBtn and _dragSourceBtn._isGroupHeader
    local dropMode = _dragDropMode
    local dropTarget = _dragDropTarget

    if dropMode == "group" and dropTarget and dropTarget ~= _dragFromCatIdx then
        -- GROUP MODE: merge dragged category with target
        local targetCat = categories[dropTarget]
        local destGroup = targetCat and targetCat.groupName

        if targetCat then
            -- Group-to-group is always allowed (old group may disband, that's fine)
            if sourceGroup then
                CUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                ClearGroupOrder(sourceGroup)
            end

            if destGroup then
                -- Move to bottom of group
                local groupMembers = CUI_CategoryManager:GetGroupMembers(destGroup)
                local lastMemberIdx = groupMembers[#groupMembers]
                local fromIdx
                for i, category in ipairs(categories) do
                    if category == fromCat then
                        fromIdx = i
                        break
                    end
                end
                if fromIdx and lastMemberIdx then
                    local dest = lastMemberIdx + 1
                    if dest > #categories + 1 then
                        dest = #categories + 1
                    end
                    if fromIdx ~= dest then
                        CUI_CategoryManager:ReorderCategory(fromIdx, dest)
                    end
                end
                -- Add to group (already in position); re-find index after the move
                for i, category in ipairs(categories) do
                    if category == fromCat then
                        CUI_CategoryManager:AddToGroup(i, destGroup)
                        break
                    end
                end
            else
                -- Create new group: move dragged category to right after target first
                local fromIdx
                for i, category in ipairs(categories) do
                    if category == fromCat then
                        fromIdx = i
                        break
                    end
                end
                local curTargetIdx
                for i, category in ipairs(categories) do
                    if category == targetCat then
                        curTargetIdx = i
                        break
                    end
                end
                if fromIdx and curTargetIdx and fromIdx ~= curTargetIdx then
                    -- Place after target so target stays first in the new group
                    local dest = curTargetIdx + 1
                    if dest > #categories then
                        dest = #categories
                    end
                    CUI_CategoryManager:ReorderCategory(fromIdx, dest)
                end
                -- Re-find indices after move
                local idx1, idx2
                for i, category in ipairs(categories) do
                    if category == targetCat then
                        idx1 = i
                    end
                    if category == fromCat then
                        idx2 = i
                    end
                end
                if idx1 and idx2 then
                    CUI_CategoryManager:GroupCategories({ idx1, idx2 })
                end
            end
        end
    elseif dropMode == "insert" and dropTarget then
        local goal = dropTarget

        local fromGroupName = fromCat and fromCat.groupName
        local dropGroupChanges = (_dragInsertGroup or false) ~= (fromGroupName or false)
        if goal ~= _dragFromCatIdx or dropGroupChanges then
            if isHeader and sourceGroup then
                -- Group header drag: move ALL members as a block, using raw dropTarget (not the -1 adjusted target).
                local dropRaw = dropTarget
                local memberList = CUI_CategoryManager:GetGroupMembers(sourceGroup)
                local minIdx = memberList[1]
                local blockSize = #memberList
                if dropRaw < minIdx or dropRaw > minIdx + blockSize - 1 then
                    local removed = {}
                    for m = #memberList, 1, -1 do
                        removed[#removed + 1] = table.remove(categories, memberList[m])
                    end
                    local ordered = {}
                    for region = #removed, 1, -1 do
                        ordered[#ordered + 1] = removed[region]
                    end
                    local insertAt
                    if dropRaw > minIdx then
                        insertAt = dropRaw - blockSize
                    else
                        insertAt = dropRaw
                    end
                    if insertAt < 1 then
                        insertAt = 1
                    end
                    if insertAt > #categories + 1 then
                        insertAt = #categories + 1
                    end
                    -- Virtual categories stay the tail and Junk stays last (as in ReorderCategory)
                    local last = CUI_CategoryManager:GetSavedCount()
                    if insertAt > last + 1 then
                        insertAt = last + 1
                    end
                    if categories[last] and categories[last].isJunk and insertAt > last then
                        insertAt = last
                    end
                    for b = #ordered, 1, -1 do
                        table.insert(categories, insertAt, ordered[b])
                    end
                    -- Persist the block move; without this it reverts on the next
                    -- rebuild (equip-set groups rebuild on every set change).
                    CUI_CategoryManager:SaveState()
                end
            elseif sourceGroup then
                -- Grouped member dragged to insert position
                local memberList = CUI_CategoryManager:GetGroupMembers(sourceGroup)
                local minIdx, maxIdx = memberList[1], memberList[#memberList]

                local inGroup = (_dragInsertGroup == sourceGroup)
                    or (not _dragInsertGroup and goal >= minIdx and goal <= maxIdx)
                if inGroup and goal ~= _dragFromCatIdx then
                    -- Check if trying to move above the group (target == minIdx from the header button, not the first member)
                    if
                        goal == minIdx
                        and _dragFromCatIdx ~= minIdx
                        and #memberList >= 2
                        and _dragTargetIsHeader
                    then
                        -- Ungroup and place above the group
                        CUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(sourceGroup)
                        local newIdx
                        for i, category in ipairs(categories) do
                            if category == fromCat then
                                newIdx = i
                                break
                            end
                        end
                        if newIdx then
                            CUI_CategoryManager:ReorderCategory(newIdx, minIdx)
                        end
                    else
                        -- Normal intra-group reorder
                        CUI_CategoryManager:ReorderCategory(_dragFromCatIdx, goal)
                    end
                    if not CUI_CategoryManager:IsGroupNameCustom(sourceGroup) then
                        CUI_CategoryManager:RegenerateGroupName(sourceGroup)
                    end
                else
                    -- Drag out of group
                    if #memberList >= 1 then
                        CUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(sourceGroup)
                        -- Re-find index after ungroup may have shifted things
                        local newIdx
                        for i, category in ipairs(categories) do
                            if category == fromCat then
                                newIdx = i
                                break
                            end
                        end
                        if newIdx then
                            -- Check if destination is inside another group -- auto-join it
                            local destGroup = _dragInsertGroup
                            if destGroup == sourceGroup then
                                destGroup = nil
                            end
                            if destGroup then
                                CUI_CategoryManager:ReorderCategory(newIdx, goal)
                                -- Re-find after move
                                for i, category in ipairs(categories) do
                                    if category == fromCat then
                                        CUI_CategoryManager:AddToGroup(i, destGroup)
                                        break
                                    end
                                end
                                if not CUI_CategoryManager:IsGroupNameCustom(destGroup) then
                                    CUI_CategoryManager:RegenerateGroupName(destGroup)
                                end
                            else
                                CUI_CategoryManager:ReorderCategory(newIdx, goal)
                            end
                        end
                    end
                end
            else
                -- Check if insert position is inside a group -- auto-join that group
                local destGroup = _dragInsertGroup
                if destGroup then
                    CUI_CategoryManager:ReorderCategory(_dragFromCatIdx, goal)
                    for i, category in ipairs(categories) do
                        if category == fromCat then
                            CUI_CategoryManager:AddToGroup(i, destGroup)
                            break
                        end
                    end
                    if not CUI_CategoryManager:IsGroupNameCustom(destGroup) then
                        CUI_CategoryManager:RegenerateGroupName(destGroup)
                    end
                else
                    CUI_CategoryManager:ReorderCategory(_dragFromCatIdx, goal)
                end
            end
        end
    end

    -- Re-sort any categories affected by group membership changes
    local newFromCat = nil
    for i, category in ipairs(categories) do
        if category == fromCat then
            newFromCat = category
            break
        end
    end
    local fromGroup = sourceGroup
    local toGroup = newFromCat and newFromCat.groupName
    if fromGroup ~= toGroup then
        local resortCats = {}
        -- Find the moved category's current index
        for i, category in ipairs(categories) do
            if category == fromCat then
                resortCats[#resortCats + 1] = i
                break
            end
        end
        if fromGroup then
            local oldMembers = CUI_CategoryManager:GetGroupMembers(fromGroup)
            if oldMembers then
                for _, mi in ipairs(oldMembers) do
                    resortCats[#resortCats + 1] = mi
                end
            end
        end
        if toGroup then
            local newMembers = CUI_CategoryManager:GetGroupMembers(toGroup)
            if newMembers then
                for _, mi in ipairs(newMembers) do
                    resortCats[#resortCats + 1] = mi
                end
            end
        end
        ResortAfterGroupChange(resortCats, toGroup or fromGroup)
        if fromGroup and toGroup and fromGroup ~= toGroup then
            ResortAfterGroupChange({}, fromGroup)
        end
    end

    -- Restore selection by reference (index may have shifted during reorder)
    if selectedCatRef then
        for i, category in ipairs(categories) do
            if category == selectedCatRef then
                SetSelectedCategoryIndex(i)
                break
            end
        end
    end
    SetSelectedGroupName(savedGroupName)

    _dragFromCatIdx = nil
    _dragSourceBtn = nil
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil
    _dragTargetIsHeader = nil
    _dragInsertGroup = nil
    _dragUpdateFrame:Hide()
    if _dragGhost then
        _dragGhost:Hide()
    end
    if _dragInsertLine then
        _dragInsertLine:Hide()
    end
    if _dragGroupHL then
        _dragGroupHL:Hide()
    end
    if CUI_Bags._unlockSort then
        CUI_Bags._unlockSort()
    end
    CUI_Bags:RefreshInventory()
end

local function CreateSidebar()
    if CUI_Bags._sidebar then
        return
    end

    local forever = mod.BagsForever()
    local inset = forever and mod.ForeverBagSidebarInset(CUI_Bags) or 0
    local sideBar = CreateFrame("Frame", nil, CUI_Bags)
    sideBar._leftInset = inset
    local width = GetSidebarContentWidth(sideBar)
    sideBar:SetPoint("TOPLEFT", CUI_Bags, "TOPLEFT", inset, -CUI_Bags.Header:GetHeight())
    sideBar:SetPoint("BOTTOMLEFT", CUI_Bags.Footer, "TOPLEFT", inset, 0)
    sideBar:SetWidth(width)
    sideBar.bg = sideBar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sideBar.bg:SetAllPoints()
    sideBar.bg:SetColorTexture(0, 0, 0, 0.25)

    -- Right-edge separator
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    sideBar.sep = sideBar:CreateTexture(nil, "ARTWORK")
    sideBar.sep:SetWidth(px)
    sideBar.sep:SetPoint("TOPRIGHT", sideBar, "TOPRIGHT", 0, 0)
    sideBar.sep:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", 0, 0)
    sideBar.sep:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Sidebar header: "Categories" label + collapse arrow
    local sidebarHdr, collapseBtn, UpdateCollapseArrow =
        mod.CreateSidebarHeader(sideBar, CludesUI.L("Categories"), "bagSidebarCollapsed")

    -- The expand arrow left of the window title, shown while a collapsed
    -- sidebar hides (Hide Sidebar Icons When Collapsed; BuildSidebarButtons)
    local expandArrow = mod.SidebarArrowButton(CUI_Bags.Header, "Expand Sidebar")
    expandArrow:SetPoint("LEFT", CUI_Bags.Header, "LEFT", 8, 0)
    if forever then
        sideBar.bg:SetColorTexture(0.10, 0.065, 0.035, 0.45)
        sideBar.sep:SetColorTexture(0.45, 0.33, 0.21, 0.85)
        expandArrow:ClearAllPoints()
        expandArrow:SetPoint("LEFT", CUI_Bags.Header, "TOPLEFT", 39, CUI_Bags.Header._foreverControlsY)
    end
    expandArrow._icon:SetRotation(math.pi)
    expandArrow:Hide()

    local function ToggleSidebar()
        local center = CUI_Bags:GetCenter()
        local screenW = UIParent:GetWidth()
        local onRightSide = center and screenW and (center > screenW / 2)
        local oldRight = onRightSide and CUI_Bags:GetRight() or nil
        local oldTop = onRightSide and CUI_Bags:GetTop() or nil

        BP().bagSidebarCollapsed = not BP().bagSidebarCollapsed
        UpdateCollapseArrow()
        sideBar:SetWidth(GetSidebarContentWidth(sideBar))
        CUI_Bags:RefreshInventory()

        if onRightSide and oldRight and oldTop then
            local leftX = oldRight - CUI_Bags:GetWidth()
            CUI_Bags:ClearAllPoints()
            CUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, oldTop)
            BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = leftX, y = oldTop }
        end
    end
    collapseBtn:SetScript("OnClick", ToggleSidebar)
    expandArrow:SetScript("OnClick", function()
        CUI.HideWidgetTooltip()
        ToggleSidebar()
    end)

    -- Sidebar scroll frame (below header, above footer)
    local sidebarSF = CreateFrame("ScrollFrame", nil, sideBar)
    sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
    sidebarSF:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", 0, 0)
    sidebarSF:EnableMouseWheel(true)
    local sideChild = CreateFrame("Frame", nil, sidebarSF)
    sideChild:SetWidth(width)
    sidebarSF:SetScrollChild(sideChild)

    local SIDEBAR_SCROLL_STEP = 28
    sidebarSF:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = sideChild:GetHeight() - self:GetHeight()
        if maxScroll <= 0 then
            return
        end
        local current = self:GetVerticalScroll()
        local newVal = math.max(0, math.min(maxScroll, current - delta * SIDEBAR_SCROLL_STEP))
        self:SetVerticalScroll(newVal)
    end)

    CUI_Bags._sidebar = sideBar
    CUI_Bags._sidebarHdr = sidebarHdr
    CUI_Bags._sidebarSF = sidebarSF
    CUI_Bags._sidebarChild = sideChild
    CUI_Bags._collapseBtn = collapseBtn
    CUI_Bags._titleArrow = expandArrow
end

-- One-time tip on the sidebar's categories: they can be dragged to reorder.
-- New users only (an account that ran Bags before it starts with it seen:
-- bags_category_tip_existing_seen_v1 in CludesUI_Migration.lua). Shown
-- whenever the bags open with the sidebar showing, until its Okay is
-- clicked (CludesUIDB.bagCategoryTipSeen); a sidebar that hides takes it
-- down until the next time. Its arrow points at the first category that can
-- be dragged (past the fixed views and the unmovable Pinned / Recent rows),
-- re-anchored on every sidebar build. It never first shows in combat (the box
-- takes the mouse over the grid), and it waits while its row is scrolled out
-- of the list's view.
function mod.ShowCategoryTip()
    if CludesUIDB.bagCategoryTipSeen then
        return
    end
    local sideBar, scrollFrame = CUI_Bags._sidebar, CUI_Bags._sidebarSF
    if not (sideBar and sideBar:IsShown() and CUI_Bags:IsShown()) then
        return
    end
    local tipText = CUI_Bags._catTip
    if InCombatLockdown() and not (tipText and tipText:IsShown()) then
        return
    end
    if not CUI_Bags._catTipScrollHooked then
        CUI_Bags._catTipScrollHooked = true
        scrollFrame:HookScript("OnVerticalScroll", function()
            if not CludesUIDB.bagCategoryTipSeen then
                mod.ShowCategoryTip()
            end
        end)
    end
    local goal
    for i = 1, #_sidebarBtns do
        local b = _sidebarBtns[i]
        if b:IsShown() and (b._catIdx or 0) >= 1 and not b._noMove then
            goal = b
            break
        end
    end
    if not goal then
        return
    end
    local _, rowY = goal:GetCenter()
    local topY, bottom = scrollFrame:GetTop(), scrollFrame:GetBottom()
    if not (rowY and topY and bottom and rowY <= topY and rowY >= bottom) then
        if tipText then
            tipText:Hide()
        end
        return
    end
    if not tipText then
        -- The panel tips' metrics (the CDM tip's), the height fitted to the text
        tipText = CludesUI.BuildTipCallout(CUI_Bags, {
            width = 250,
            arrow = "left",
            text = CludesUI.L("Categories can be dragged\nto reorder them."),
            strata = false,
            level = CUI_Bags:GetFrameLevel() + 60,
            font = CUI.GetFontPath("bags"),
            fontSize = 12,
            spacing = 4,
            textTop = 15,
            gap = 12,
            btnBottom = 12,
            onOkay = function()
                CludesUIDB.bagCategoryTipSeen = true
            end,
        })
        CUI_Bags._catTip = tipText
    end
    -- Drawn at the options panel's density (GetPopupScale on UIParent: one unit
    -- = one physical pixel x Window Scale) whatever the bag window's and the
    -- UI's scale, so it matches the panel's tips; built with PanelPP for that.
    tipText:SetScale(UIParent:GetEffectiveScale() * CludesUI.GetPopupScale() / CUI_Bags:GetEffectiveScale())
    tipText:ClearAllPoints()
    tipText:SetPoint("LEFT", goal, "RIGHT", 12, 0)
    if not tipText:IsShown() then
        CludesUI.ShowTipCallout(tipText)
    end
end

-- Controller cursor: a pad has no middle click and no drag, so while one is in
-- use the category menu also offers unpinning, removing assigned items and
-- moving the entry one place up or down. A move runs the drag's own drop
-- path (StopSidebarDrag) with the neighbour the sidebar shows.
local function PadCategoryEntries(root, button, category, catIndex, isGroupHeader, isGroupMember)
    local rowList = {}

    -- Pinned Items: every pinned item in the bags, once per pin key.
    if category.isPinned then
        local pinned = PinnedItems()
        local seen
        for bag = 0, 5 do
            for slot = 1, (pinned and C_Container.GetContainerNumSlots(bag) or 0) do
                local details = C_Container.GetContainerItemInfo(bag, slot)
                local itemLink = details and details.itemID and C_Container.GetContainerItemLink(bag, slot)
                if details and details.itemID and IsItemPinned(pinned, itemLink, details.itemID) then
                    local key = NormalizePinKey(itemLink, details.itemID)
                    seen = seen or {}
                    if key and not seen[key] then
                        seen[key] = true
                        local itemId = details.itemID
                        rowList[#rowList + 1] = {
                            text = itemLink or tostring(itemId),
                            fn = function()
                                local p = PinnedItems(true)
                                if p then
                                    p[key] = nil
                                    p[itemId] = nil
                                end
                                CUI_Bags:RefreshInventory()
                            end,
                        }
                    end
                end
            end
        end
        rowList.title = CludesUI.L("Unpin Item")
    -- A category items can be assigned to: every item assigned to it.
    elseif not isGroupHeader and CUI_CategoryManager:CanAssignToCategory(catIndex) then
        local assignments = CludesUIDB and CludesUIDB.bagItemAssignments
        local catKey = category._defaultName
        if assignments and catKey then
            for itemId, aKey in pairs(assignments) do
                if aKey == catKey then
                    local name, itemLink = GetItemInfo(itemId)
                    rowList[#rowList + 1] = {
                        text = itemLink or name or ("item:" .. itemId),
                        sort = name or "",
                        fn = function()
                            CUI_CategoryManager:UnassignItem(itemId)
                            CUI_Bags:RefreshInventory()
                        end,
                    }
                end
            end
            table.sort(rowList, function(a, b)
                return a.sort < b.sort
            end)
        end
        rowList.title = CludesUI.L("Remove Assigned Item")
    end

    -- Move Up / Move Down against the neighbouring sidebar rows.
    local me
    for i = 1, #_sidebarBtns do
        if _sidebarBtns[i] == button and button:IsShown() then
            me = i
            break
        end
    end
    local function Row(jdx)
        local b = _sidebarBtns[jdx]
        if b and b:IsShown() then
            return b
        end
    end
    local upTarget, downTarget, moveGroup
    -- Junk stays last: it never moves (ReorderCategory keeps the rest above it)
    if me and not category.noMove and not button._noMove and not category.isJunk then
        local set = category.groupName
        if isGroupMember and set then
            -- Within its own group only (set children are skipped).
            local jdx = me - 1
            while Row(jdx) and Row(jdx)._isEquipSet do
                jdx = jdx - 1
            end
            local rowRec = Row(jdx)
            if rowRec and rowRec._isGroupMember and rowRec._groupName == set then
                upTarget = rowRec._catIdx
            end
            jdx = me + 1
            while Row(jdx) and Row(jdx)._isEquipSet do
                jdx = jdx + 1
            end
            rowRec = Row(jdx)
            if rowRec and rowRec._isGroupMember and rowRec._groupName == set then
                downTarget = rowRec._catIdx + 1
            end
            moveGroup = set
        else
            -- A plain category, or a group header moving its whole block past
            -- the neighbouring entry (a whole group counts as one entry).
            local jdx = me - 1
            while Row(jdx) and (Row(jdx)._isEquipSet or Row(jdx)._isGroupMember) do
                jdx = jdx - 1
            end
            local rowRec = Row(jdx)
            if rowRec and rowRec._catIdx > 0 and not rowRec._noMove then
                upTarget = rowRec._catIdx
            end
            jdx = me + 1
            while
                Row(jdx)
                and (
                    Row(jdx)._isEquipSet
                    or (isGroupHeader and Row(jdx)._isGroupMember and Row(jdx)._groupName == set)
                )
            do
                jdx = jdx + 1
            end
            rowRec = Row(jdx)
            if rowRec and rowRec._catIdx > 0 and not rowRec._noMove then
                if rowRec._isGroupHeader and rowRec._groupName then
                    local memberList = CUI_CategoryManager:GetGroupMembers(rowRec._groupName)
                    if #memberList > 0 then
                        downTarget = memberList[#memberList] + 1
                    end
                else
                    local nextCat = CUI_CategoryManager:GetCategories()[rowRec._catIdx]
                    if not (nextCat and nextCat.isJunk) then
                        downTarget = rowRec._catIdx + 1
                    end
                end
            end
        end
    end
    local function Move(goal)
        -- The sidebar may have been rebuilt while the menu was open: act only
        -- when the same row still shows the same category.
        if
            CUI_CategoryManager:GetCategories()[catIndex] ~= category
            or button._catIdx ~= catIndex
            or not button:IsShown()
            or (button._isGroupHeader or false) ~= (isGroupHeader or false)
        then
            return
        end
        _dragFromCatIdx = catIndex
        _dragSourceBtn = button
        _dragDropMode = "insert"
        _dragDropTarget = goal
        _dragInsertGroup = moveGroup
        _dragTargetIsHeader = false
        StopSidebarDrag()
    end

    if #rowList == 0 and not upTarget and not downTarget then
        return
    end
    root:CreateDivider()
    if upTarget then
        root:CreateButton(CludesUI.L("Move Up"), function()
            Move(upTarget)
        end)
    end
    if downTarget then
        root:CreateButton(CludesUI.L("Move Down"), function()
            Move(downTarget)
        end)
    end
    if #rowList > 0 then
        local sub = root:CreateButton(rowList.title)
        -- A long list scrolls inside the menu instead of running off screen.
        if #rowList > 20 then
            sub:SetScrollMode(20 * 20)
        end
        for _, region in ipairs(rowList) do
            sub:CreateButton(region.text, region.fn)
        end
    end
end

-- Show context menu for grouping categories
local function ShowCategoryContextMenu(button, catIndex, isGroupHeader, isGroupMember)
    local categories = CUI_CategoryManager:GetCategories()
    local category = categories[catIndex]
    if not category then
        return
    end
    -- Set children and virtual categories have no menu actions (rename/group/hide all N/A): no empty menu
    if category.isEquipSet or category.isVirtual then
        return
    end

    MenuUtil.CreateContextMenu(button, function(_, menu)
        local ownGroup = category.groupName

        if not BP().bagHiddenInAllItems then
            BP().bagHiddenInAllItems = {}
        end
        local hiddenSet = BP().bagHiddenInAllItems

        if isGroupHeader and ownGroup then
            menu:CreateButton(CludesUI.L("Rename"), function()
                if not CUI.ShowInputPopup then
                    return
                end
                CUI:ShowInputPopup({
                    title = "Rename Group",
                    message = CludesUI.L("Enter a new name for this group:"),
                    placeholder = CUI_CategoryManager:GroupDisplayName(ownGroup),
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(renamed)
                        renamed = renamed and strtrim(renamed) or ""
                        if renamed == "" or renamed == ownGroup then
                            return
                        end
                        CUI_CategoryManager:RenameGroup(ownGroup, renamed)
                        CUI_CategoryManager:SetGroupNameCustom(renamed, true)
                        if selectedGroupName == ownGroup then
                            SetSelectedGroupName(renamed)
                        end
                        CUI_Bags:RefreshInventory()
                    end,
                })
            end)
            menu:CreateButton(CludesUI.L("Disband Group"), function()
                ClearGroupOrder(ownGroup)
                CUI_CategoryManager:DisbandGroup(ownGroup)
                if selectedGroupName == ownGroup then
                    SetSelectedGroupName(nil)
                    SetSelectedCategoryIndex(0)
                end
                CUI_Bags:RefreshInventory()
            end)
            local groupHidden = hiddenSet[ownGroup]
            menu:CreateButton(
                groupHidden and CludesUI.L("Show in All Items") or CludesUI.L("Hide in All Items"),
                function()
                    hiddenSet[ownGroup] = not groupHidden or nil
                    CUI_Bags:RefreshInventory()
                end
            )
        elseif isGroupMember and ownGroup then
            menu:CreateButton(CludesUI.L("Rename"), function()
                if not CUI.ShowInputPopup then
                    return
                end
                CUI:ShowInputPopup({
                    title = "Rename Category",
                    message = CludesUI.Lf('Enter a new name for "%1$s":', category.name),
                    placeholder = category.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(renamed)
                        renamed = renamed and strtrim(renamed) or ""
                        if renamed == "" or renamed == category.name then
                            return
                        end
                        CUI_CategoryManager:RenameCategory(catIndex, renamed)
                        CUI_Bags:RefreshInventory()
                    end,
                })
            end)
            menu:CreateButton(CludesUI.Lf("Ungroup %1$s", category.name), function()
                ClearGroupOrder(ownGroup)
                CUI_CategoryManager:UngroupCategory(catIndex)
                CUI_Bags:RefreshInventory()
            end)
        else
            -- Equip-set categories are named by the set; renames would not persist
            if not category.isEquipSet then
                menu:CreateButton(CludesUI.L("Rename"), function()
                    if not CUI.ShowInputPopup then
                        return
                    end
                    CUI:ShowInputPopup({
                        title = "Rename Category",
                        message = CludesUI.Lf('Enter a new name for "%1$s":', category.name),
                        placeholder = category.name,
                        confirmText = "Rename",
                        cancelText = "Cancel",
                        onConfirm = function(renamed)
                            renamed = renamed and strtrim(renamed) or ""
                            if renamed == "" or renamed == category.name then
                                return
                            end
                            CUI_CategoryManager:RenameCategory(catIndex, renamed)
                            CUI_Bags:RefreshInventory()
                        end,
                    })
                end)
            end

            if not category.noGroup then
                local groupSub = menu:CreateButton(CludesUI.L("Create Group With"))
                local hasOptions = false
                for ci, other in ipairs(categories) do
                    if ci ~= catIndex and not other.groupName and not other.noGroup then
                        hasOptions = true
                        groupSub:CreateButton(other.name, function()
                            CUI_CategoryManager:GroupCategories({ catIndex, ci })
                            CUI_Bags:RefreshInventory()
                        end)
                    end
                end

                local groupNames = CUI_CategoryManager:GetGroupNames()
                if #groupNames > 0 then
                    local addSub = menu:CreateButton(CludesUI.L("Add to Group"))
                    for _, gn in ipairs(groupNames) do
                        addSub:CreateButton(CUI_CategoryManager:GroupDisplayName(gn), function()
                            CUI_CategoryManager:AddToGroup(catIndex, gn)
                            CUI_Bags:RefreshInventory()
                        end)
                    end
                end
            end

            -- Equip-set children don't render standalone in All Items (they fold
            -- into their anchor's section), so hide/show doesn't apply to them.
            if not category.noMove and not category.isEquipSet then
                local catKey = category._defaultName
                local catHidden = hiddenSet[catKey]
                menu:CreateButton(
                    catHidden and CludesUI.L("Show in All Items") or CludesUI.L("Hide in All Items"),
                    function()
                        hiddenSet[catKey] = not catHidden or nil
                        CUI_Bags:RefreshInventory()
                    end
                )
            end
        end

        -- Controller cursor: unpin / remove / move entries (no middle click or drag on a pad).
        if CUI.PadInUse() then
            PadCategoryEntries(menu, button, category, catIndex, isGroupHeader, isGroupMember)
        end
    end)
end

local function BuildSidebarButtons(categoryCounts, totalCount)
    local sideBar = CUI_Bags._sidebar
    if not sideBar then
        return
    end
    local navCollapsed = BP().bagSidebarCollapsed
    local sidebarW = GetSidebarContentWidth(sideBar)
    sideBar:SetWidth(sidebarW)
    -- A collapsed sidebar with no icon strip hides; its expand arrow sits left
    -- of the window title meanwhile (the tip on the categories waits for it)
    local hidden = sidebarW == 0
    -- Modern: no sidebar to expand again, so no expand arrow by the title
    local modern = CUI_Bags.IsModernMode and CUI_Bags.IsModernMode() == true
    if CUI_Bags._sidebarHidden ~= hidden then
        CUI_Bags._sidebarHidden = hidden
        sideBar:SetShown(not hidden)
        local heading = CUI_Bags.Header
        CUI_Bags._titleArrow:SetShown(hidden and not modern)
        if not mod.BagsForever() then
            heading.title:ClearAllPoints()
            heading.title:SetPoint("LEFT", heading, "LEFT", (hidden and not modern) and 24 or 8, 0)
        end
        if hidden and CUI_Bags._catTip then
            CUI_Bags._catTip:Hide()
        end
    end
    -- Nothing to paint on a hidden sidebar: un-hiding comes back through here
    if hidden then
        if modern and mod.BuildModernChips then
            mod.BuildModernChips(categoryCounts, totalCount)
        end
        return
    end

    if CUI_Bags._sidebarHdr then
        if navCollapsed then
            CUI_Bags._sidebarHdr._label:Hide()
        else
            CUI_Bags._sidebarHdr._label:Show()
        end
    end

    local categories = CUI_CategoryManager and CUI_CategoryManager:GetCategories() or {}

    -- Build display list: { catIdx, name, icon, count, isGroupHeader, groupName, indent }
    local shownList = {}
    -- Three fixed views; the configured default type first, then canonical order.
    local _fixedViews = {
        all = { catIdx = 0, name = CludesUI.L("All Items"), icon = 133633, count = totalCount },
        onebag = { catIdx = -1, name = CludesUI.L("OneBag"), icon = 133634, count = totalCount },
        multibag = { catIdx = -2, name = CludesUI.L("MultiBag"), icon = 133635, count = totalCount },
    }
    local _dbt = GetDefaultBagType()
    shownList[#shownList + 1] = _fixedViews[_dbt] or _fixedViews.all
    for _, _k in ipairs({ "all", "onebag", "multibag" }) do
        if _k ~= _dbt then
            shownList[#shownList + 1] = _fixedViews[_k]
        end
    end
    -- bank: the offline bank view
    if FixedViewCount() == 4 then
        shownList[#shownList + 1] = { catIdx = -3, name = CludesUI.L("Bank"), icon = 133784 }
    end

    -- Split-mode set children: rendered nested under the "Item Set Gear" anchor
    -- wherever it sits (plain or inside a group), skipped by the main loop.
    -- Scan gated on split mode: zero extra work while it's off.
    local setMembers, setMemberTotal = nil, 0
    if BP().bagSplitSetGearBySet then
        for i, c in ipairs(categories) do
            if c.isEquipSet then
                setMembers = setMembers or {}
                setMembers[#setMembers + 1] = i
                setMemberTotal = setMemberTotal + (categoryCounts and categoryCounts[i] or 0)
            end
        end
    end
    local function EmitSetChildren(level)
        if not setMembers or navCollapsed then
            return
        end
        for _, sci in ipairs(setMembers) do
            local sc = categories[sci]
            shownList[#shownList + 1] = {
                catIdx = sci,
                name = sc.name,
                icon = sc.icon or 134400,
                count = categoryCounts and categoryCounts[sci] or 0,
                indent = level,
                isEquipSet = true,
            }
        end
    end
    local function IsSetAnchor(c)
        return c and c.isSetGear and not c.isEquipSet
    end

    local renderedGroups = {}
    for ci, category in ipairs(categories) do
        if category.groupName then
            if not renderedGroups[category.groupName] then
                renderedGroups[category.groupName] = true
                -- Group header: sum counts of all members (+ set children on the anchor)
                local memberList = CUI_CategoryManager:GetGroupMembers(category.groupName)
                local groupCount = 0
                for _, mi in ipairs(memberList) do
                    groupCount = groupCount + (categoryCounts and categoryCounts[mi] or 0)
                    if IsSetAnchor(categories[mi]) then
                        groupCount = groupCount + setMemberTotal
                    end
                end
                -- Use first member's icon for group
                local firstCat = categories[memberList[1]]
                local groupIcon = firstCat and firstCat.icon or 134400
                local groupIsAtlas = firstCat and firstCat.isAtlas
                -- Check if any member is user-created (keep group visible if so)
                local groupHasUserCreated = false
                for _, mi in ipairs(memberList) do
                    if categories[mi] and categories[mi].isUserCreated then
                        groupHasUserCreated = true
                        break
                    end
                end
                shownList[#shownList + 1] = {
                    catIdx = memberList[1],
                    name = CUI_CategoryManager:GroupDisplayName(category.groupName),
                    icon = groupIcon,
                    isAtlas = groupIsAtlas,
                    count = groupCount,
                    isGroupHeader = true,
                    groupName = category.groupName,
                    isUserCreated = groupHasUserCreated,
                }
                -- Indented members (hidden when collapsed)
                if not navCollapsed then
                    for _, mi in ipairs(memberList) do
                        local mc = categories[mi]
                        local anchor = IsSetAnchor(mc)
                        shownList[#shownList + 1] = {
                            catIdx = mi,
                            name = mc.name,
                            icon = mc.icon or 134400,
                            isAtlas = mc.isAtlas,
                            count = (categoryCounts and categoryCounts[mi] or 0)
                                + (anchor and setMemberTotal or 0),
                            indent = true,
                            groupName = category.groupName,
                            isGroupMember = true,
                            isUserCreated = mc.isUserCreated,
                        }
                        -- Set children: third level under a grouped anchor
                        if anchor then
                            EmitSetChildren(2)
                        end
                    end
                end
            end
        elseif category.isEquipSet then
            -- Emitted by EmitSetChildren under the anchor
        else
            local anchor = IsSetAnchor(category)
            local total = (categoryCounts and categoryCounts[ci] or 0) + (anchor and setMemberTotal or 0)
            local isUserCreated = not category.isCatchAll and (not category.types or #category.types == 0)
            -- Skip Pinned/Recent Items if disabled
            if category.isPinned and BP().bagShowPinnedItems == false then
                -- skip
            elseif category.isRecent and BP().bagShowRecentItems == false then
                -- skip
            else
                shownList[#shownList + 1] = {
                    catIdx = ci,
                    name = category.name,
                    icon = category.icon or 134400,
                    isAtlas = category.isAtlas,
                    count = total,
                    noMove = category.noMove,
                    isPinned = category.isPinned,
                    isRecent = category.isRecent,
                    isUserCreated = category.isUserCreated,
                    isVirtual = category.isVirtual,
                }
                if anchor then
                    EmitSetChildren(1)
                end
            end
        end
    end

    -- Hide empty categories (sidebar-only visual, does not affect grouping)
    local hideEmpty = BP().bagHideEmptyCategories ~= false
    if hideEmpty then
        local filtered = {}
        for _, record in ipairs(shownList) do
            local keep = true
            if record.count == 0 then
                -- Always keep: All Items, OneBag, noMove (Pinned/Recent), user-created
                -- (virtual categories are noMove too, but hide when empty)
                if
                    record.catIdx >= 1
                    and (not record.noMove or record.isVirtual)
                    and not record.isUserCreated
                then
                    if record.isGroupHeader then
                        -- Hide group header if all members are 0
                        keep = false
                    elseif record.isGroupMember then
                        keep = false
                    else
                        keep = false
                    end
                end
            end
            if keep then
                filtered[#filtered + 1] = record
            end
        end
        shownList = filtered
    end

    for i = 1, #shownList do
        if not _sidebarBtns[i] then
            local button = CreateFrame("Button", nil, CUI_Bags._sidebarChild or sideBar)
            button:SetHeight(SIDEBAR_BTN_H)
            button._indicator = button:CreateTexture(nil, "OVERLAY")
            local Pix = CUI and CUI.PP
            local px = (Pix and Pix.mult) or 1
            button._indicator:SetWidth(px * 2)
            button._indicator:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            button._indicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
            button._bg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
            button._bg:SetAllPoints()
            button._bg:SetColorTexture(1, 1, 1, 0)
            button._icon = button:CreateTexture(nil, "ARTWORK")
            button._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            button._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button._label = button:CreateFontString(nil, "OVERLAY")
            SetBagFont(button._label, 11)
            button._label:SetJustifyH("LEFT")
            button._label:SetWordWrap(false)
            button._label:SetPoint("LEFT", button._icon, "RIGHT", 6, 0)
            button._label:SetPoint("RIGHT", button, "RIGHT", -30, 0)
            button._count = button:CreateFontString(nil, "OVERLAY")
            SetBagFont(button._count, 10)
            button._count:SetJustifyH("RIGHT")
            button._count:SetTextColor(0.5, 0.5, 0.5)
            button._count:SetPoint("RIGHT", button, "RIGHT", -6, 0)

            button:SetScript("OnEnter", function(self)
                if _dragFromCatIdx then
                    return
                end
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (
                        not self._isGroupHeader
                        and self._catIdx == selectedCategoryIndex
                        and not selectedGroupName
                    )
                if not isSel then
                    self._bg:SetColorTexture(1, 1, 1, 0.06)
                end
                if BP().bagSidebarCollapsed and CUI.ShowWidgetTooltip then
                    CUI.ShowWidgetTooltip(
                        self,
                        (self._catName or "?") .. (self._catCount and (" (" .. self._catCount .. ")") or "")
                    )
                end
            end)
            button:SetScript("OnLeave", function(self)
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (
                        not self._isGroupHeader
                        and self._catIdx == selectedCategoryIndex
                        and not selectedGroupName
                    )
                if not isSel then
                    self._bg:SetColorTexture(1, 1, 1, 0)
                end
                CUI.HideWidgetTooltip()
            end)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:SetScript("OnClick", function(self, btnFrame)
                if btnFrame == "RightButton" then
                    if self._catIdx > 0 then
                        ShowCategoryContextMenu(self, self._catIdx, self._isGroupHeader, self._isGroupMember)
                    end
                    return
                end
                -- Drag-to-sidebar: if the cursor holds an item, assign it to this category
                if self._catIdx and self._catIdx > 0 then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and cursorItemID then
                        if CUI_CategoryManager and CUI_CategoryManager:CanAssignToCategory(self._catIdx) then
                            local categories = CUI_CategoryManager:GetCategories()
                            local category = categories[self._catIdx]
                            if category then
                                CUI_CategoryManager:AssignItem(cursorItemID, category._defaultName)
                                ClearCursor()
                                CUI_Bags:RefreshInventory()
                                return
                            end
                        end
                    end
                end
                if self._didDrag then
                    self._didDrag = false
                    return
                end
                if self._isGroupHeader and self._groupName then
                    SetSelectedGroupName(self._groupName)
                    SetSelectedCategoryIndex(0)
                elseif self._isGroupMember and self._groupName then
                    SetSelectedGroupName(nil)
                    SetSelectedCategoryIndex(self._catIdx)
                else
                    SetSelectedGroupName(nil)
                    SetSelectedCategoryIndex(self._catIdx)
                end
                if CUI_Bags._scrollFrame then
                    CUI_Bags._scrollFrame:SetVerticalScroll(0)
                end
                CUI_Bags:RefreshInventory()
            end)
            button:SetScript("OnMouseDown", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then
                    return
                end
                -- Equip-set cats and Junk: ReorderCategory rejects them; don't start the drag either
                if self._catIdx <= 0 or self._noMove or self._isEquipSet then
                    return
                end
                local dragCat = CUI_CategoryManager:GetCategories()[self._catIdx]
                if dragCat and dragCat.isJunk then
                    return
                end
                self._didDrag = false
                local _, startY = GetCursorPosition()
                self._dragStartY = startY
                self._dragPending = true
                _sidebarDragDetect._btn = self
                _sidebarDragDetect:Show()
            end)
            button:SetScript("OnMouseUp", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then
                    return
                end
                self._dragPending = false
                _sidebarDragDetect:Hide()
                if self._didDrag then
                    StopSidebarDrag()
                end
            end)

            _sidebarBtns[i] = button
        end
    end

    for i = #shownList + 1, #_sidebarBtns do
        _sidebarBtns[i]:Hide()
    end

    local sideChild = CUI_Bags._sidebarChild

    -- Separator line between All Items/OneBag and categories
    if not sideBar._catDivider then
        local Pix = CUI and CUI.PP
        local px = (Pix and Pix.mult) or 1
        local div = (sideChild or sideBar):CreateTexture(nil, "ARTWORK")
        div:SetHeight(px)
        div:SetColorTexture(0.2, 0.2, 0.2, 1)
        sideBar._catDivider = div
    end

    -- Position and populate (buttons go in the scroll child)
    if sideChild then
        sideChild:SetWidth(sidebarW)
    end
    local posY = 0
    local ar, ag, ab = GetAccentRGB()
    local INDENT = SIDEBAR_INDENT

    for i, record in ipairs(shownList) do
        local button = _sidebarBtns[i]
        local isSelected
        if record.isGroupHeader then
            isSelected = (record.groupName == selectedGroupName)
        else
            isSelected = (not selectedGroupName and record.catIdx == selectedCategoryIndex)
        end

        button._catIdx = record.catIdx
        button._catName = record.name
        button._catIcon = record.icon
        button._catIsAtlas = record.isAtlas
        button._catCount = record.count
        button._isGroupHeader = record.isGroupHeader or false
        button._isGroupMember = record.isGroupMember or false
        button._groupName = record.groupName
        button._noMove = record.noMove or false
        button._isEquipSet = record.isEquipSet or false
        button._isPinned = record.isPinned or false

        button:SetParent(sideChild or sideBar)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", sideChild or sideBar, "TOPLEFT", 0, posY)
        button:SetWidth(sidebarW)

        -- entry.indent: true = 1 level (legacy group members), or a number of levels
        local indentLv = (record.indent == true and 1) or record.indent or 0
        local leftPad = (indentLv ~= 0 and not navCollapsed) and (8 + INDENT * indentLv) or 8
        mod.AnchorBagSidebarIcon(button._icon, navCollapsed, leftPad)
        if record.isAtlas then
            button._icon:SetAtlas(record.icon)
            button._icon:SetTexCoord(0, 1, 0, 1)
        else
            -- Through the client icon map: a default the Forever client
            -- cannot draw takes its vanilla-era stand-in there.
            button._icon:SetTexture(CludesUI.ClientIcon(record.icon))
            button._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        button._icon:SetAlpha(isSelected and 1 or 0.75)
        -- Smaller icon for indented members
        if record.indent then
            button._icon:SetSize(SIDEBAR_ICON_SIZE - 2, SIDEBAR_ICON_SIZE - 2)
        else
            button._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        end

        if navCollapsed then
            button._label:Hide()
            button._count:Hide()
        else
            button._label:Show()
            button._label:SetText(record.name)
            button._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)

            button._count:Show()
            button._count:SetText(record.count and tostring(record.count) or "")
        end

        if isSelected then
            button._indicator:SetColorTexture(ar, ag, ab, 1)
            button._indicator:Show()
            button._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            button._indicator:Hide()
            button._bg:SetColorTexture(1, 1, 1, 0)
        end

        button:Show()
        posY = posY - SIDEBAR_BTN_H - SIDEBAR_PAD

        -- Divider after the last special entry (Pinned or Recent)
        local isLastSpecial = record.isPinned or record.isRecent
        local nextEntry = shownList[i + 1]
        local nextIsRegular = nextEntry and not nextEntry.isPinned and not nextEntry.isRecent
        if isLastSpecial and nextIsRegular and sideBar._catDivider then
            posY = posY - 4 -- spacing above line
            local div = sideBar._catDivider
            div:SetParent(sideChild or sideBar)
            div:ClearAllPoints()
            local inset = math.floor(sidebarW * 0.08)
            div:SetPoint("TOPLEFT", sideChild or sideBar, "TOPLEFT", inset, posY)
            div:SetPoint("TOPRIGHT", sideChild or sideBar, "TOPRIGHT", -inset, posY)
            div:Show()
            posY = posY - (div:GetHeight() or 1) - 4 -- spacing below line
        end
    end

    -- "+Add Category" button at the bottom of the sidebar
    local hideAddCat = BP().bagHideAddCategory
    if not navCollapsed and not hideAddCat then
        if not sideBar._addCatBtn then
            local button = CreateFrame("Button", nil, sideChild or sideBar)
            button:SetHeight(SIDEBAR_BTN_H)
            button._bg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
            button._bg:SetAllPoints()
            button._bg:SetColorTexture(1, 1, 1, 0)
            button._icon = button:CreateTexture(nil, "ARTWORK")
            button._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            button._icon:SetPoint("LEFT", button, "LEFT", 8, 0)
            button._icon:SetTexture(134400)
            button._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button._icon:SetAlpha(0.5)
            button._label = button:CreateFontString(nil, "OVERLAY")
            SetBagFont(button._label, 11)
            button._label:SetJustifyH("LEFT")
            button._label:SetWordWrap(false)
            button._label:SetPoint("LEFT", button._icon, "RIGHT", 6, 0)
            button._label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
            button._label:SetText(CludesUI.L("Add Category"))
            button._label:SetTextColor(1, 1, 1, 0.4)
            button:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0.06)
                self._label:SetTextColor(1, 1, 1, 0.8)
                self._icon:SetAlpha(0.8)
            end)
            button:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0)
                self._label:SetTextColor(1, 1, 1, 0.4)
                self._icon:SetAlpha(0.5)
            end)
            button:SetScript("OnClick", function(self)
                local dialog = CUI_Bags._newCatPopup
                if dialog and dialog:IsShown() then
                    dialog:Hide()
                    return
                end
                if not dialog then
                    dialog = CreateFrame("Frame", nil, CUI_Bags)
                    dialog:SetFrameStrata("DIALOG")
                    dialog:SetSize(240, 230)
                    dialog:EnableMouse(true)
                    local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
                    backdrop:SetAllPoints()
                    backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                    local Pix = CUI and CUI.PP
                    if Pix and Pix.CreateBorder then
                        Pix.CreateBorder(dialog, 0.2, 0.2, 0.2, 1)
                    end

                    local title = dialog:CreateFontString(nil, "OVERLAY")
                    SetBagFont(title, 13)
                    title:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, -10)
                    title:SetTextColor(1, 1, 1, 0.9)
                    title:SetText(CludesUI.L("New Custom Category"))

                    local editField = CreateFrame("EditBox", nil, dialog)
                    editField:SetSize(220, 22)
                    editField:SetPoint("TOPLEFT", dialog, "TOPLEFT", 10, -30)
                    editField:SetAutoFocus(false)
                    editField:SetFont(GetFont(), 12, "")
                    editField:SetTextColor(1, 1, 1, 1)
                    editField:SetTextInsets(6, 6, 0, 0)
                    editField:SetMaxLetters(30)
                    local ebBg = editField:CreateTexture(nil, "BACKGROUND")
                    ebBg:SetAllPoints()
                    ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if Pix and Pix.CreateBorder then
                        Pix.CreateBorder(editField, 0.15, 0.15, 0.15, 1)
                    end
                    editField:SetScript("OnEscapePressed", function(s)
                        s:ClearFocus()
                    end)
                    editField:SetScript("OnEnterPressed", function(s)
                        s:ClearFocus()
                    end)
                    dialog._nameEB = editField

                    local iconLbl = dialog:CreateFontString(nil, "OVERLAY")
                    SetBagFont(iconLbl, 11)
                    iconLbl:SetPoint("TOPLEFT", editField, "BOTTOMLEFT", 0, -8)
                    iconLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    iconLbl:SetText(CludesUI.L("Icon:"))

                    -- Forever does not include the newer icon files used by the
                    -- Midnight picker. Keep its choices to long-standing client
                    -- icons, including a profession icon.
                    local ICON_IDS = CUI_CLIENT_FOREVER
                            and {
                                134400,
                                132996,
                                136240,
                                136241,
                                136242,
                                136244,
                                136245,
                                136246,
                                136247,
                                136248,
                                136249,
                                132485,
                                132640,
                                134332,
                            }
                        or {
                            7514178,
                            7548926,
                            7427980,
                            7548966,
                            2143125,
                            6025441,
                            7451177,
                            7548901,
                            7501337,
                            7704166,
                            7549083,
                            7549010,
                            7136579,
                            7549012,
                        }
                    dialog._iconIDs = ICON_IDS
                    local ICON_SZ = 28
                    local ICON_PAD = 4
                    local ICONS_PER_ROW = 7
                    local iconBtns = {}
                    dialog._selectedIcon = ICON_IDS[1]
                    dialog._customMode = false

                    local ar, ag, ab = GetAccentRGB()
                    local edgePx = (Pix and Pix.mult or 1) * 2

                    -- Helper: update selection highlight across grid + custom
                    local function UpdateSelection()
                        for _, ob in ipairs(iconBtns) do
                            ob._border:Hide()
                        end
                        if dialog._customBorder then
                            dialog._customBorder:Hide()
                        end
                        if dialog._customMode then
                            if dialog._customBorder then
                                dialog._customBorder:Show()
                            end
                        else
                            for _, ob in ipairs(iconBtns) do
                                if ob._iconID == dialog._selectedIcon then
                                    ob._border:Show()
                                    break
                                end
                            end
                        end
                    end
                    dialog._updateSelection = UpdateSelection

                    for position, iconID in ipairs(ICON_IDS) do
                        local iconBtn = CreateFrame("Button", nil, dialog)
                        iconBtn:SetSize(ICON_SZ, ICON_SZ)
                        local colour = (position - 1) % ICONS_PER_ROW
                        local row = math.floor((position - 1) / ICONS_PER_ROW)
                        iconBtn:SetPoint(
                            "TOPLEFT",
                            iconLbl,
                            "BOTTOMLEFT",
                            colour * (ICON_SZ + ICON_PAD),
                            -(4 + row * (ICON_SZ + ICON_PAD))
                        )
                        local texture = iconBtn:CreateTexture(nil, "ARTWORK")
                        texture:SetAllPoints()
                        texture:SetTexture(iconID)
                        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        iconBtn._tex = texture
                        iconBtn._iconID = iconID
                        -- Accent-colored 2px border for selection
                        local iconEdge = CreateFrame("Frame", nil, iconBtn)
                        iconEdge:SetPoint("TOPLEFT", -edgePx, edgePx)
                        iconEdge:SetPoint("BOTTOMRIGHT", edgePx, -edgePx)
                        iconEdge:SetFrameLevel(iconBtn:GetFrameLevel() + 2)
                        local bTop = iconEdge:CreateTexture(nil, "OVERLAY")
                        bTop:SetColorTexture(ar, ag, ab, 1)
                        bTop:SetPoint("TOPLEFT")
                        bTop:SetPoint("TOPRIGHT")
                        bTop:SetHeight(edgePx)
                        local bBot = iconEdge:CreateTexture(nil, "OVERLAY")
                        bBot:SetColorTexture(ar, ag, ab, 1)
                        bBot:SetPoint("BOTTOMLEFT")
                        bBot:SetPoint("BOTTOMRIGHT")
                        bBot:SetHeight(edgePx)
                        local bLeft = iconEdge:CreateTexture(nil, "OVERLAY")
                        bLeft:SetColorTexture(ar, ag, ab, 1)
                        bLeft:SetPoint("TOPLEFT")
                        bLeft:SetPoint("BOTTOMLEFT")
                        bLeft:SetWidth(edgePx)
                        local bRight = iconEdge:CreateTexture(nil, "OVERLAY")
                        bRight:SetColorTexture(ar, ag, ab, 1)
                        bRight:SetPoint("TOPRIGHT")
                        bRight:SetPoint("BOTTOMRIGHT")
                        bRight:SetWidth(edgePx)
                        iconEdge:Hide()
                        iconBtn._border = iconEdge
                        iconBtn:SetScript("OnClick", function(s)
                            dialog._selectedIcon = s._iconID
                            dialog._customMode = false
                            dialog._prevTex:SetTexture(s._iconID)
                            UpdateSelection()
                        end)
                        iconBtn:SetScript("OnEnter", function(s)
                            s._tex:SetAlpha(1)
                        end)
                        iconBtn:SetScript("OnLeave", function(s)
                            s._tex:SetAlpha(0.85)
                        end)
                        iconBtn._tex:SetAlpha(0.85)
                        iconBtns[position] = iconBtn
                    end
                    dialog._iconBtns = iconBtns

                    -- Custom icon ID label + preview + editbox
                    local lastRow = math.ceil(#ICON_IDS / ICONS_PER_ROW)
                    local customLbl = dialog:CreateFontString(nil, "OVERLAY")
                    SetBagFont(customLbl, 11)
                    customLbl:SetPoint(
                        "TOPLEFT",
                        iconLbl,
                        "BOTTOMLEFT",
                        0,
                        -(4 + lastRow * (ICON_SZ + ICON_PAD) + 6)
                    )
                    customLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    customLbl:SetText(CludesUI.L("Custom Icon ID:"))

                    local preview = CreateFrame("Frame", nil, dialog)
                    preview:SetSize(22, 22)
                    preview:SetPoint("TOPLEFT", customLbl, "BOTTOMLEFT", 0, -4)
                    local prevTex = preview:CreateTexture(nil, "ARTWORK")
                    prevTex:SetAllPoints()
                    prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    prevTex:SetTexture(ICON_IDS[1])
                    dialog._prevTex = prevTex
                    -- Accent border on the preview (for custom mode)
                    local cBorder = CreateFrame("Frame", nil, preview)
                    cBorder:SetPoint("TOPLEFT", -edgePx, edgePx)
                    cBorder:SetPoint("BOTTOMRIGHT", edgePx, -edgePx)
                    cBorder:SetFrameLevel(preview:GetFrameLevel() + 2)
                    local cbTop = cBorder:CreateTexture(nil, "OVERLAY")
                    cbTop:SetColorTexture(ar, ag, ab, 1)
                    cbTop:SetPoint("TOPLEFT")
                    cbTop:SetPoint("TOPRIGHT")
                    cbTop:SetHeight(edgePx)
                    local cbBot = cBorder:CreateTexture(nil, "OVERLAY")
                    cbBot:SetColorTexture(ar, ag, ab, 1)
                    cbBot:SetPoint("BOTTOMLEFT")
                    cbBot:SetPoint("BOTTOMRIGHT")
                    cbBot:SetHeight(edgePx)
                    local cbLeft = cBorder:CreateTexture(nil, "OVERLAY")
                    cbLeft:SetColorTexture(ar, ag, ab, 1)
                    cbLeft:SetPoint("TOPLEFT")
                    cbLeft:SetPoint("BOTTOMLEFT")
                    cbLeft:SetWidth(edgePx)
                    local cbRight = cBorder:CreateTexture(nil, "OVERLAY")
                    cbRight:SetColorTexture(ar, ag, ab, 1)
                    cbRight:SetPoint("TOPRIGHT")
                    cbRight:SetPoint("BOTTOMRIGHT")
                    cbRight:SetWidth(edgePx)
                    cBorder:Hide()
                    dialog._customBorder = cBorder

                    local customField = CreateFrame("EditBox", nil, dialog)
                    customField:SetSize(80, 22)
                    customField:SetPoint("LEFT", preview, "RIGHT", 8, 0)
                    customField:SetAutoFocus(false)
                    customField:SetFont(GetFont(), 11, "")
                    customField:SetTextColor(1, 1, 1, 1)
                    customField:SetTextInsets(4, 4, 0, 0)
                    customField:SetNumeric(true)
                    local cBg = customField:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints()
                    cBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if Pix and Pix.CreateBorder then
                        Pix.CreateBorder(customField, 0.15, 0.15, 0.15, 1)
                    end
                    customField:SetScript("OnEscapePressed", function(s)
                        s:ClearFocus()
                    end)
                    customField:SetScript("OnEnterPressed", function(s)
                        s:ClearFocus()
                    end)
                    customField:SetScript("OnTextChanged", function(s)
                        local txt = s:GetText()
                        local ident = tonumber(txt)
                        if txt and txt ~= "" and ident and ident > 0 then
                            dialog._selectedIcon = ident
                            dialog._customMode = true
                            prevTex:SetTexture(ident)
                        else
                            dialog._customMode = false
                        end
                        UpdateSelection()
                    end)
                    dialog._customEB = customField

                    local createBtn = CreateFrame("Button", nil, dialog)
                    createBtn:SetSize(220, 26)
                    createBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 10, 10)
                    local cBtnBg = createBtn:CreateTexture(nil, "BACKGROUND")
                    cBtnBg:SetAllPoints()
                    cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1)
                    if Pix and Pix.CreateBorder then
                        Pix.CreateBorder(createBtn, 0.25, 0.25, 0.25, 1)
                    end
                    local cBtnLbl = createBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(cBtnLbl, 12)
                    cBtnLbl:SetPoint("CENTER")
                    cBtnLbl:SetTextColor(1, 1, 1, 0.9)
                    cBtnLbl:SetText(CludesUI.L("Create"))
                    createBtn:SetScript("OnEnter", function()
                        cBtnBg:SetColorTexture(0.2, 0.2, 0.2, 1)
                    end)
                    createBtn:SetScript("OnLeave", function()
                        cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1)
                    end)
                    -- Red flash validation for empty fields
                    local function MakeFlashBorder(hostFrame)
                        local fallback = CreateFrame("Frame", nil, hostFrame)
                        fallback:SetPoint("TOPLEFT", -1, 1)
                        fallback:SetPoint("BOTTOMRIGHT", 1, -1)
                        fallback:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
                        local edges = {}
                        local function MakeEdge(p1, p2, isHoriz)
                            local t = fallback:CreateTexture(nil, "OVERLAY")
                            t:SetColorTexture(0.9, 0.15, 0.15, 0)
                            if isHoriz then
                                t:SetPoint(p1)
                                t:SetPoint(p2)
                                t:SetHeight(1)
                            else
                                t:SetPoint(p1)
                                t:SetPoint(p2)
                                t:SetWidth(1)
                            end
                            edges[#edges + 1] = t
                        end
                        MakeEdge("TOPLEFT", "TOPRIGHT", true)
                        MakeEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
                        MakeEdge("TOPLEFT", "BOTTOMLEFT", false)
                        MakeEdge("TOPRIGHT", "BOTTOMRIGHT", false)
                        fallback._edges = edges
                        fallback._elapsed = 0
                        fallback._active = false
                        fallback:SetScript("OnUpdate", function(self, dt)
                            if not self._active then
                                self:Hide()
                                return
                            end
                            self._elapsed = self._elapsed + dt
                            if self._elapsed >= 0.7 then
                                self._active = false
                                for _, e in ipairs(self._edges) do
                                    e:SetColorTexture(0.9, 0.15, 0.15, 0)
                                end
                                self:Hide()
                                return
                            end
                            local t = self._elapsed / 0.7
                            local a = 0.7 * (1 - t)
                            for _, e in ipairs(self._edges) do
                                e:SetColorTexture(0.9, 0.15, 0.15, a)
                            end
                        end)
                        fallback:Hide()
                        fallback.Flash = function(self)
                            self._elapsed = 0
                            self._active = true
                            for _, e in ipairs(self._edges) do
                                e:SetColorTexture(0.9, 0.15, 0.15, 0.7)
                            end
                            self:Show()
                        end
                        return fallback
                    end
                    local nameFlash = MakeFlashBorder(editField)
                    dialog._nameFlash = nameFlash

                    createBtn:SetScript("OnClick", function()
                        local name = dialog._nameEB:GetText()
                        if not name or name == "" then
                            dialog._nameFlash:Flash()
                            dialog._nameEB:SetFocus()
                            return
                        end
                        local iconTex = dialog._selectedIcon or 134400
                        local position = CUI_CategoryManager:AddCustomCategory(name)
                        if position then
                            local categories = CUI_CategoryManager:GetCategories()
                            if categories[position] then
                                categories[position].icon = iconTex
                                categories[position].isAtlas = nil
                            end
                            CUI_CategoryManager:SaveState()
                        end
                        dialog:Hide()
                        CUI_Bags:RefreshInventory()
                    end)

                    -- EnableKeyboard and SetPropagateKeyboardInput are protected in
                    -- combat: the popup takes the keyboard as it shows out of combat
                    -- (below) and stands aside in it, keys reaching the game.
                    dialog:SetScript("OnKeyDown", function(s, key)
                        if InCombatLockdown() then
                            return
                        end
                        if key == "ESCAPE" then
                            s:Hide()
                            s:SetPropagateKeyboardInput(false)
                        else
                            s:SetPropagateKeyboardInput(true)
                        end
                    end)
                    -- Controller cursor: Cancel finds Add Category, which toggles the popup closed.
                    if CUI.PadCP() then
                        dialog.CloseButton = self
                    end

                    CUI_Bags._newCatPopup = dialog
                end
                dialog._nameEB:SetText("")
                dialog._customEB:SetText("")
                dialog._selectedIcon = dialog._iconIDs[1]
                dialog._customMode = false
                dialog._prevTex:SetTexture(dialog._iconIDs[1])
                dialog._updateSelection()
                dialog:ClearAllPoints()
                dialog:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 4, 0)
                if not InCombatLockdown() then
                    dialog:EnableKeyboard(true)
                    dialog:SetPropagateKeyboardInput(true)
                end
                dialog:Show()
                dialog._nameEB:SetFocus()
            end)
            sideBar._addCatBtn = button
        end
        local addBtn = sideBar._addCatBtn
        addBtn:SetParent(sideChild or sideBar)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", sideChild or sideBar, "TOPLEFT", 0, posY - 4)
        addBtn:SetWidth(sidebarW)
        addBtn:Show()
        posY = posY - SIDEBAR_BTN_H - 4
    elseif sideBar._addCatBtn then
        sideBar._addCatBtn:Hide()
    end

    if sideChild then
        sideChild:SetHeight(math.abs(posY) + 4)
    end

    -- The one-time "categories can be dragged" tip follows its category row
    if not CludesUIDB.bagCategoryTipSeen then
        mod.ShowCategoryTip()
    end
end

Inner.BuildSidebarButtons, Inner.CreateSidebar = BuildSidebarButtons, CreateSidebar
Inner.GetSidebarWidth = GetSidebarWidth
Inner.broken = false
