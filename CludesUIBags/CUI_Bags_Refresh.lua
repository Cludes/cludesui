if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Refresh.lua
--
--  Category headers, the scroll frame, the resize grip and
--  RefreshInventory for the bags and the reagent bag.
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
local GetItemQualityColor = C_Item.GetItemQualityColor
local CUI = CludesUI
local GetUpgradeTrack = CUI.GetUpgradeTrack

local AbbrevDungeon, BP, GetColumns = Inner.AbbrevDungeon, Inner.BP, Inner.GetColumns
local GetItemLevelAtLocation, IsGearItem = Inner.GetItemLevelAtLocation, Inner.IsGearItem
local IsItemPinned, SetBagFont, SLOT_SIZE = Inner.IsItemPinned, Inner.SetBagFont, Inner.SLOT_SIZE
local SPACING, _pendingResortCats = Inner.SPACING, Inner._pendingResortCats
mod.OnSlotMetrics(function(m)
    SLOT_SIZE, SPACING = m[1], m[2]
end)
local _pendingResortGroups, _slotCategories = Inner._pendingResortGroups, Inner._slotCategories
local AcquireSlotTable, bagSlots = Inner.AcquireSlotTable, Inner.bagSlots
local DetectAndApplySwaps, FOOTER_H = Inner.DetectAndApplySwaps, Inner.FOOTER_H
local PreCacheSortFields, reagentSlots = Inner.PreCacheSortFields, Inner.reagentSlots
local ReleaseAllSlotTables, SaveCategoryOrder = Inner.ReleaseAllSlotTables, Inner.SaveCategoryOrder
local TakeBagSnapshot, UpdatePawnArrow = Inner.TakeBagSnapshot, Inner.UpdatePawnArrow
local VisualSortCompare, UpdateBagMoneyDisplay = Inner.VisualSortCompare, Inner.UpdateBagMoneyDisplay
local UpdateCurrencyDisplays, SCROLLBAR_HIT_W = Inner.UpdateCurrencyDisplays, Inner.SCROLLBAR_HIT_W
local SetInsetBorderColor, GetOrCreateBagSlot = Inner.SetInsetBorderColor, Inner.GetOrCreateBagSlot
local GetOrCreateReagentSlot, PinnedItems = Inner.GetOrCreateReagentSlot, Inner.PinnedItems
local BuildSidebarButtons, GetSidebarWidth = Inner.BuildSidebarButtons, Inner.GetSidebarWidth
local SetGearCatSet, SetPaintedPanelOpen = Inner.SetGearCatSet, Inner.SetPaintedPanelOpen

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
local _anyItemPanelOpen = Inner._anyItemPanelOpen
Inner.anyItemPanelOpenSetters[#Inner.anyItemPanelOpenSetters + 1] = function(val)
    _anyItemPanelOpen = val
end

local _lastCatCounts = {} -- category counts from last full refresh
local _lastTotalCount = 0 -- total item count from last full refresh

-- RefreshInventory's per-item reads. One location is reused for every slot
-- (CreateFromBagAndSlot builds a new mixin table per call). An item link names
-- one exact item, bonus IDs included, so its quality, bind type, gear flag and
-- upgrade track never change: they are kept per link, and only answers given
-- once the item's data is loaded (a quality came back), never an empty track,
-- so a later read can still fill them in. Bounded like the crafted-track memo.
local _slotLoc = ItemLocation:CreateEmpty()
local _linkFacts, _linkFactsN = {}, 0

-------------------------------------------------------------------------------
--  Category header pool (for "All Items" view)
-------------------------------------------------------------------------------
local _catHeaders = {} -- pool of header frames

local function GetOrCreateCatHeader(position)
    if _catHeaders[position] then
        return _catHeaders[position]
    end
    local frame = CreateFrame("Frame", nil, CUI_Bags)
    frame:SetHeight(20)
    frame._label = frame:CreateFontString(nil, "OVERLAY")
    SetBagFont(frame._label, 11)
    frame._label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame._label:SetTextColor(0.7, 0.7, 0.7)
    frame._label:SetJustifyH("LEFT")
    frame._hint = frame:CreateFontString(nil, "OVERLAY")
    SetBagFont(frame._hint, 10)
    frame._hint:SetPoint("LEFT", frame._label, "RIGHT", 4, 0)
    frame._hint:SetTextColor(0.7, 0.7, 0.7, 0.9)
    frame._hint:SetJustifyH("LEFT")
    frame._hint:SetText("")
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    frame._line = frame:CreateTexture(nil, "ARTWORK")
    frame._line:SetHeight(px)
    frame._line:SetPoint("LEFT", frame._hint, "RIGHT", 6, 0)
    frame._line:SetPoint("RIGHT", frame, "RIGHT", -SPACING, 0)
    frame._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    if mod.BagsForever() then
        mod.SetForeverBagSectionColors(frame._label, frame._line)
    end
    _catHeaders[position] = frame
    return frame
end

-- A frame that takes mouse motion is still the mouse focus: it drops every
-- click and item drop on it, and takes hover from the frames beneath (the bag
-- window's drop target), unless it passes them on. Those switches are
-- protected (out of combat only): a frame made in combat takes no mouse until
-- a later paint out of combat turns them on. Returns whether the frame passes
-- clicks on. Shared with the Compact display's labels.
function mod.PassClicks(frame)
    if frame._passClicks or not frame.SetPropagateMouseClicks then
        return true
    end
    if InCombatLockdown() then
        return false
    end
    frame:SetPropagateMouseClicks(true)
    if frame.SetPropagateMouseMotion then
        frame:SetPropagateMouseMotion(true)
    end
    frame._passClicks = true
    return true
end

-- The Pinned / Recent header hint, shown while the header's label is
-- hovered; nil clears it. The hover frame is built with the first hint.
do
    local function HeaderHintOnEnter(self)
        local hint = self:GetParent()._hintText
        if hint then
            CUI.ShowWidgetTooltip(self, hint)
        end
    end
    function mod.SetHeaderHint(heading, textValue)
        heading._hintText = textValue
        local hit = heading._hintHit
        if not hit then
            if not textValue then
                return
            end
            hit = CreateFrame("Frame", nil, heading)
            hit:SetPoint("TOPLEFT", heading._label, "TOPLEFT", 0, 2)
            hit:SetPoint("BOTTOMRIGHT", heading._label, "BOTTOMRIGHT", 0, -2)
            hit:SetScript("OnEnter", HeaderHintOnEnter)
            hit:SetScript("OnLeave", CUI.HideWidgetTooltip)
            -- After the scripts: motion only, never clicks
            hit:SetMouseClickEnabled(false)
            heading._hintHit = hit
        end
        hit:SetMouseMotionEnabled(textValue ~= nil and mod.PassClicks(hit))
    end
end

-- "Clear" link on a Recent Items header, sitting just left of its "Hide" link
-- (or at the header's right edge when there is none, as in the list).
-- Opt-in (bagShowRecentClear, default off): callers gate on the setting, so a
-- user who never enables it never has the button built. Pooled on the header
-- like _hideBtn; hidden by the per-refresh header reset.
local function ShowRecentClearButton(heading, hideBtn)
    if not heading._clearBtn then
        local callback = CreateFrame("Button", nil, heading)
        callback:SetSize(34, 16)
        callback._fs = callback:CreateFontString(nil, "OVERLAY")
        SetBagFont(callback._fs, 9)
        callback._fs:SetAllPoints()
        callback._fs:SetText(CludesUI.L("Clear"))
        callback._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
        callback:SetScript("OnEnter", function(self)
            self._fs:SetTextColor(1, 1, 1, 0.9)
            CUI.ShowWidgetTooltip(self, "Clears the Recent Items list.")
        end)
        callback:SetScript("OnLeave", function(self)
            self._fs:SetTextColor(0.5, 0.5, 0.5, 0.7)
            CUI.HideWidgetTooltip()
        end)
        callback:SetScript("OnClick", function()
            if CUI_Bags.ClearRecentItems then
                CUI_Bags:ClearRecentItems()
            end
        end)
        heading._clearBtn = callback
    end
    heading._clearBtn:ClearAllPoints()
    if hideBtn then
        heading._clearBtn:SetPoint("RIGHT", hideBtn, "LEFT", -6, 0)
    else
        heading._clearBtn:SetPoint("RIGHT", heading, "RIGHT", 0, 0)
    end
    heading._clearBtn:Show()
    return heading._clearBtn
end

-- Indented subheaders under a category (expansion names) for All Items nesting
local _expSubHeaders = {}

local function GetOrCreateExpSubHeader(position)
    if _expSubHeaders[position] then
        return _expSubHeaders[position]
    end
    local frame = CreateFrame("Frame", nil, CUI_Bags)
    frame:SetHeight(16)
    frame._label = frame:CreateFontString(nil, "OVERLAY")
    SetBagFont(frame._label, 9)
    frame._label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame._label:SetTextColor(0.55, 0.55, 0.55)
    frame._label:SetJustifyH("LEFT")
    _expSubHeaders[position] = frame
    return frame
end

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar for item grid
-------------------------------------------------------------------------------
local function CreateBagScrollFrame()
    if CUI_Bags._scrollFrame then
        return
    end

    local sidebarW = GetSidebarWidth()
    local headerH = CUI_Bags.Header:GetHeight() + (mod.ModernStripH and mod.ModernStripH() or 0)
    local scrollInset = mod.BagsForever() and -7 or -1
    CUI_Bags._scrollRightInset = scrollInset

    -- ScrollFrame: fills between header, footer, and sidebar
    local scrollFrame = CreateFrame("ScrollFrame", nil, CUI_Bags)
    scrollFrame:SetPoint("TOPLEFT", CUI_Bags, "TOPLEFT", sidebarW, -(headerH + 1))
    scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bags.Footer, "TOPRIGHT", scrollInset, 0)
    scrollFrame:EnableMouseWheel(true)

    -- Scroll child: tall frame that holds all items
    local childFrame = CreateFrame("Frame", nil, scrollFrame)
    childFrame:SetWidth(scrollFrame:GetWidth())
    childFrame:SetHeight(1) -- updated by RefreshInventory
    childFrame:EnableMouse(false) -- let clicks pass through to item buttons
    scrollFrame:SetScrollChild(childFrame)

    -- Track (always visible)
    local track, thumb, UpdateThumb = mod.AttachGridScrollbar(CUI_Bags, scrollFrame, true, false)
    track:SetPoint("TOPRIGHT", CUI_Bags, "TOPRIGHT", scrollInset, -(headerH + 1))
    track:SetPoint("BOTTOMRIGHT", CUI_Bags.Footer, "TOPRIGHT", scrollInset, 0)

    CUI_Bags._scrollFrame = scrollFrame
    CUI_Bags._scrollChild = childFrame
    CUI_Bags._scrollTrack = track
    CUI_Bags._scrollThumb = thumb
    CUI_Bags._updateThumb = UpdateThumb
end

-------------------------------------------------------------------------------
--  RefreshInventory
-------------------------------------------------------------------------------
-- Shared tail of RefreshInventory (grid and list view): scroll child height,
-- scrollbar, frame size, item count. curY = bottom of the rendered content.
-------------------------------------------------------------------------------
--  Resize grip and lock: the bag and bank windows' bottom-right corner, as on
--  a damage meter window. Unlocked: the open lock with the resize grip right
--  of it; locked: the closed lock alone in the corner, and the window neither
--  resizes nor moves. Clicking the lock toggles it. Dragging the grip steps
--  the width unit (a grid column, or 1px for the list views) and sets the
--  height. While dragging, the edges follow the cursor; the content re-lays
--  out every relayoutStep px (frame._resizing set meanwhile) and the width
--  settles on release. OnUpdate only while a drag is held. Double-click
--  resets the window to its default size. The footer's right-edge text keeps
--  clear of whichever icons show (cfg.inset(px)).
--  cfg: step, relayoutStep (optional, default step), minCols, minH,
--  getCols(), getHeight(), save(cols, h), finish(), savePos(left, top),
--  reset(), inset(px), isLocked(), setLocked(v), hidden() (optional: the
--  window sizes itself, so neither icon shows)
-------------------------------------------------------------------------------
do
    -- Art, alphas and the footer text clearance (the lock alone, or the grip with
    -- the lock beside it), plus the handlers this block adds: one table keeps the
    -- chunk's local count low.
    local GR = {
        RESIZE = "Interface\\AddOns\\CludesUI\\media\\icons\\resize_element.png",
        LOCKED = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-lock-locked.png",
        UNLOCKED = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-lock-unlocked.png",
        A = 0.4,
        HOVER = 0.8,
        LOCK_INSET = 18,
        GRIP_INSET = 36,
    }

    local function GripStop(dragGrip)
        dragGrip:SetScript("OnUpdate", nil)
        if dragGrip._drag then
            dragGrip._drag = nil
            dragGrip:GetParent()._resizing = nil
            dragGrip._cfg.finish()
        end
        dragGrip:SetAlpha(dragGrip:IsMouseOver() and GR.HOVER or GR.A)
    end

    local function GripOnUpdate(dragGrip)
        if not IsMouseButtonDown("LeftButton") then
            GripStop(dragGrip)
            return
        end
        local skinData, conf = dragGrip._drag, dragGrip._cfg
        local cx, cy = GetCursorPosition()
        local es = dragGrip:GetParent():GetEffectiveScale()
        local step = conf.step
        local dx = math.floor(cx / es - skinData.x + 0.5)
        dx = math.max((conf.minCols - skinData.cols) * step, math.min((skinData.maxCols - skinData.cols) * step, dx))
        local cols = skinData.cols + math.floor(dx / step)
        local bucket = math.floor(dx / (conf.relayoutStep or step))
        local hgt = math.floor(skinData.h + (skinData.y - cy / es) + 0.5)
        hgt = math.max(conf.minH, math.min(skinData.maxH, hgt))
        if dx == skinData.lastDX and hgt == skinData.lastH then
            return
        end
        local relayout = bucket ~= skinData.lastBucket
        skinData.lastDX, skinData.lastBucket, skinData.lastH = dx, bucket, hgt
        conf.save(cols, hgt)
        if relayout then
            conf.finish()
        end
        -- After the refresh, which sets the snapped size
        dragGrip:GetParent():SetSize(skinData.frameW + dx, hgt)
    end

    local function GripOnMouseDown(dragGrip, btnFrame)
        if btnFrame ~= "LeftButton" then
            return
        end
        local widget, conf = dragGrip:GetParent(), dragGrip._cfg
        local left, top, right, bottom =
            widget:GetLeft(), widget:GetTop(), widget:GetRight(), widget:GetBottom()
        if not left then
            return
        end
        -- Pin the top-left corner so only the right and bottom edges move
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        conf.savePos(left, top)
        local cx, cy = GetCursorPosition()
        local es = widget:GetEffectiveScale()
        local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale() / es
        local cols, hgt = conf.getCols(), conf.getHeight()
        dragGrip._drag = {
            x = cx / es,
            y = cy / es,
            cols = cols,
            h = hgt,
            lastBucket = 0,
            lastDX = 0,
            lastH = hgt,
            frameW = widget:GetWidth(),
            maxCols = math.max(cols, cols + math.floor((screenW - right) / conf.step)),
            maxH = math.max(hgt, hgt + math.floor(bottom)),
        }
        widget._resizing = true
        -- Keep the hover look while the cursor runs ahead of the snapped edge
        dragGrip:SetAlpha(GR.HOVER)
        dragGrip:SetScript("OnUpdate", GripOnUpdate)
    end

    local function GripReset(dragGrip)
        GripStop(dragGrip)
        dragGrip._cfg.reset()
    end

    local function GripOnEnter(dragGrip)
        dragGrip:SetAlpha(GR.HOVER)
        CUI.ShowWidgetTooltip(dragGrip, CludesUI.L("Drag to resize. Double-click to reset."))
    end

    function GR.GripOnLeave(dragGrip)
        if not dragGrip._drag then
            dragGrip:SetAlpha(GR.A)
        end
        CUI.HideWidgetTooltip()
    end

    function GR.LockTooltip(lockBtn)
        CUI.ShowWidgetTooltip(lockBtn, CludesUI.L(lockBtn._cfg.isLocked() and "Locked" or "Unlocked"))
    end

    function GR.LockOnEnter(lockBtn)
        lockBtn:SetAlpha(GR.HOVER)
        GR.LockTooltip(lockBtn)
    end

    function GR.LockOnLeave(lockBtn)
        lockBtn:SetAlpha(GR.A)
        CUI.HideWidgetTooltip()
    end

    function GR.LockOnClick(lockBtn)
        local conf = lockBtn._cfg
        conf.setLocked(not conf.isLocked())
        mod.UpdateResizeGrip(lockBtn:GetParent(), conf)
        GR.LockTooltip(lockBtn)
    end

    function GR.IconButton(widget, wid, hgt, filePath)
        local b = CreateFrame("Button", nil, widget)
        b:SetSize(wid, hgt)
        b:SetFrameLevel(widget:GetFrameLevel() + 50)
        local texture = b:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetDesaturated(true)
        if filePath then
            texture:SetTexture(filePath)
        end
        b._icon = texture
        b:SetAlpha(GR.A)
        return b
    end

    -- The lock always shows (it also holds the window in place); the grip only
    -- while unlocked and the window does not size itself. Runs on every refresh,
    -- so it repaints only when that state changes.
    function mod.UpdateResizeGrip(widget, conf)
        local dragGrip, lockBtn = widget._resizeGrip, widget._lockBtn
        local locked = conf.isLocked()
        local noGrip = locked or (conf.hidden and conf.hidden()) or false
        if
            lockBtn
            and widget._gripCfg == conf
            and widget._gripLocked == locked
            and widget._gripNoGrip == noGrip
        then
            return
        end
        widget._gripCfg, widget._gripLocked, widget._gripNoGrip = conf, locked, noGrip
        if not lockBtn then
            lockBtn = GR.IconButton(widget, 13, 17)
            lockBtn:SetScript("OnEnter", GR.LockOnEnter)
            lockBtn:SetScript("OnLeave", GR.LockOnLeave)
            lockBtn:SetScript("OnClick", GR.LockOnClick)
            widget._lockBtn = lockBtn
        end
        lockBtn._cfg = conf
        lockBtn._icon:SetTexture(locked and GR.LOCKED or GR.UNLOCKED)
        lockBtn:ClearAllPoints()
        local inset = GR.LOCK_INSET
        if noGrip then
            if dragGrip then
                dragGrip:Hide()
            end
            lockBtn:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -4, 4)
        else
            if not dragGrip then
                dragGrip = GR.IconButton(widget, 18, 18, GR.RESIZE)
                dragGrip:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -2, 2)
                dragGrip:SetScript("OnMouseDown", GripOnMouseDown)
                dragGrip:SetScript("OnMouseUp", GripStop)
                dragGrip:SetScript("OnDoubleClick", GripReset)
                dragGrip:SetScript("OnEnter", GripOnEnter)
                dragGrip:SetScript("OnLeave", GR.GripOnLeave)
                -- Window closed mid-drag: end the drag instead of resuming on reopen
                dragGrip:SetScript("OnHide", GripStop)
                widget._resizeGrip = dragGrip
            end
            if not dragGrip._drag then
                dragGrip._cfg = conf
            end
            dragGrip:Show()
            lockBtn:SetPoint("RIGHT", dragGrip, "LEFT", -2, 0)
            inset = GR.GRIP_INSET
        end
        lockBtn:Show()
        if widget._gripInset ~= inset then
            widget._gripInset = inset
            conf.inset(inset)
        end
    end
end -- resize grip

local _bagGripCfg = {
    step = SLOT_SIZE + SPACING,
    minCols = 8,
    minH = 300,
    getCols = function()
        return BP().bagColumns or 12
    end,
    getHeight = function()
        return math.floor(CUI_Bags:GetHeight() + 0.5)
    end,
    save = function(cols, hgt)
        BP().bagColumns, BP().bagHeight = cols, hgt
        if CUI_Bags._updateThumb then
            CUI_Bags._updateThumb()
        end
    end,
    finish = function()
        CUI_Bags:RefreshInventory()
    end,
    savePos = function(left, top)
        BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }
    end,
    reset = function()
        local p = BP()
        p.bagColumns, p.bagHeight, p.bagListWidth = nil, nil, nil
        CUI_Bags:RefreshInventory()
    end,
    -- The gold display sits in the footer's bottom-right corner
    inset = Inner.PositionBagMoney,
    isLocked = function()
        return BP().bagWindowLocked == true
    end,
    setLocked = function(val)
        BP().bagWindowLocked = val and true or false
    end,
    -- Auto-Size owns the window size
    hidden = function()
        return CUI_Bags.AutoSizeOn()
    end,
}

-- List display: free width (rows have no cell grid), saved in pixels. It keeps
-- the default slot pitch: the slot sliders are for Grid and Compact
local LIST_PITCH = 38
local _bagListGripCfg = setmetatable({
    step = 1,
    relayoutStep = LIST_PITCH,
    minCols = 300,
    getCols = function()
        return BP().bagListWidth or GetColumns() * LIST_PITCH
    end,
    save = function(wid, hgt)
        BP().bagListWidth, BP().bagHeight = wid, hgt
        if CUI_Bags._updateThumb then
            CUI_Bags._updateThumb()
        end
    end,
}, { __index = _bagGripCfg })
-- a new slot size: grow-only widths start over, and the detached reagent
-- window and bag bar lay out again (the main refresh does the rest)
mod.OnSlotMetrics(function(m)
    _bagGripCfg.step = m[1] + m[2]
    _bagGripCfg.minCols = math.max(1, math.ceil(8 * 38 / (m[1] + m[2])))
    CUI_Bags._compactCols, CUI_Bags._compactW = nil, nil
    CUI_Bags._asCols, CUI_Bags._asMaxGridW, CUI_Bags._asMaxH = nil, nil, nil
    if CUI_BagsReagent:IsShown() and CUI_BagsReagent.RefreshInventory then
        CUI_BagsReagent:RefreshInventory()
    end
    if CUI_BagsWindow:IsShown() and CUI_BagsWindow.RefreshBags then
        CUI_BagsWindow:RefreshBags()
    end
end)

local function FormatSlots(used, sum, reagent, format)
    if format == "free" then
        if reagent then
            return CludesUI.Lf("%d Reagent slots free", sum - used)
        end
        return CludesUI.Lf("%d Slots free", sum - used)
    elseif format == "free_total" then
        if reagent then
            return CludesUI.Lf("%d / %d Reagent slots free", sum - used, sum)
        end
        return CludesUI.Lf("%d / %d Slots free", sum - used, sum)
    end
    if reagent then
        return CludesUI.Lf("%d / %d Reagent slots", used, sum)
    end
    return CludesUI.Lf("%d / %d Slots", used, sum)
end

local function FinishRefresh(
    curY,
    gridContentW,
    sidebarW,
    bagUsed,
    bagTotal,
    reagUsed,
    reagTotal,
    totalCount
)
    -- In combat the sort button's lock depends on the view just painted.
    if InCombatLockdown() and CUI_Bags._applySortEnabled then
        CUI_Bags._applySortEnabled()
    end
    local scrollFrame, childFrame = CUI_Bags._scrollFrame, CUI_Bags._scrollChild
    local headerH = CUI_Bags.Header:GetHeight() + (mod.ModernStripH and mod.ModernStripH() or 0)
    local contentH = math.abs(curY) + 10
    if childFrame then
        childFrame:SetHeight(contentH)
    end

    -- Update scroll frame position + thumb (deferred one frame so layout updates scrollRange)
    if scrollFrame then
        scrollFrame:SetVerticalScroll(
            math.min(scrollFrame:GetVerticalScroll(), scrollFrame:GetVerticalScrollRange())
        )
    end
    C_Timer.After(0, function()
        if CUI_Bags._updateThumb then
            CUI_Bags._updateThumb()
        end
    end)

    -- Update scroll track left position to match sidebar
    if CUI_Bags._scrollTrack then
        CUI_Bags._scrollTrack:ClearAllPoints()
        local scrollInset = CUI_Bags._scrollRightInset
        CUI_Bags._scrollTrack:SetPoint("TOPRIGHT", CUI_Bags, "TOPRIGHT", scrollInset, -(headerH + 1))
        CUI_Bags._scrollTrack:SetPoint("BOTTOMRIGHT", CUI_Bags.Footer, "TOPRIGHT", scrollInset, 0)
    end

    -- 6. Size frame. Default: fixed height, dynamic width. Auto-size: height grows to fit content
    -- (no vertical scroll), width follows column count; both track a running max while open (never shrink mid-session), floored at FIXED_H and capped at the screen.
    -- WoW Forever, and Auto-Size with the Compact display: height fits the content on that running max, with no FIXED_H floor (see below).
    local FIXED_H = 650
    -- Resize grip height: the whole window, footer inside it (so a footer
    -- re-wrap never moves the bottom edge)
    local userH = BP().bagHeight
    local fullW = sidebarW + gridContentW
    local autoSize = CUI_Bags.AutoSizeOn()
    if autoSize then
        CUI_Bags._asMaxGridW = math.max(CUI_Bags._asMaxGridW or 0, gridContentW)
        fullW = sidebarW + CUI_Bags._asMaxGridW
    end
    local currencyFooterH = UpdateCurrencyDisplays(fullW) or FOOTER_H

    -- A grip-set height overrides WoW Forever's grow-only content fit (Auto-Size hides the grip)
    if autoSize or (CUI.IS_FOREVER and not userH) then
        local sc = CUI_Bags:GetScale()
        if not sc or sc <= 0 then
            sc = 1
        end
        local maxH = (UIParent:GetHeight() / sc) * 0.95
        local fitH = contentH + headerH + currencyFooterH + 2
        local neededH
        if CUI.IS_FOREVER or CUI_Bags.IsCompactMode() then
            -- Fit the content instead of flooring at FIXED_H (WoW Forever bags hold far fewer slots, and the Compact
            -- display packs them tight), never shorter than the category list; on WoW Forever without Auto-Size the
            -- normal height stays the cap (taller content scrolls).
            if not autoSize then
                maxH = math.min(maxH, FIXED_H + currencyFooterH - FOOTER_H)
            end
            local sbHdr, sbChild = CUI_Bags._sidebarHdr, CUI_Bags._sidebarChild
            local sbH = headerH
                + currencyFooterH
                + (sbHdr and sbHdr:GetHeight() or 0)
                + (sbChild and sbChild:GetHeight() or 0)
            -- A hidden sidebar (collapsed, no icon strip) sets no floor
            if sidebarW == 0 then
                sbH = 0
            end
            neededH = math.min(math.max(fitH, sbH), maxH)
        else
            -- Cap at the screen first, then floor at FIXED_H so the window is never smaller than normal (even on short screens).
            neededH = math.max(FIXED_H, math.min(fitH, maxH))
        end
        CUI_Bags._asMaxH = math.max(CUI_Bags._asMaxH or 0, neededH)
        CUI_Bags:SetWidth(fullW)
        CUI_Bags:SetHeight(CUI_Bags._asMaxH)
    else
        CUI_Bags:SetWidth(fullW)
        CUI_Bags:SetHeight(userH or (FIXED_H + currencyFooterH - FOOTER_H))
    end

    if CUI_Bags.Header and CUI_Bags.Header.itemCount then
        -- Optional capacity formats count physical slots, not filtered items.
        local format = BP().bagSlotCountFormat
        local separate = not CludesUI.IS_FOREVER and BP().bagSeparateReagentSlots == true
        local countLabel
        if
            not separate
            and format ~= "free"
            and format ~= "free_total"
            and selectedCategoryIndex ~= 0
            and selectedCategoryIndex ~= -1
            and selectedCategoryIndex ~= -2
        then
            countLabel = CludesUI.Lf("%d Items", totalCount)
        elseif separate then
            countLabel = FormatSlots(bagUsed, bagTotal, false, format)
            if reagTotal > 0 then
                countLabel = countLabel .. "\n" .. FormatSlots(reagUsed, reagTotal, true, format)
            end
        else
            countLabel = FormatSlots(bagUsed + reagUsed, bagTotal + reagTotal, false, format)
        end
        CUI_Bags.Header.itemCount:SetText(countLabel)
    end

    UpdateBagMoneyDisplay()
    mod.ApplyWindowBackground(CUI_Bags.bg, CUI_Bags.bgOverlay)
    -- View may have changed under a held item (catch layer on / off)
    if CUI_Bags._syncDropTarget and GetCursorInfo() == "item" then
        CUI_Bags._syncDropTarget()
    end
    mod.UpdateResizeGrip(CUI_Bags, CUI_Bags.IsListMode() and _bagListGripCfg or _bagGripCfg)
    -- the offline bank panel goes over the items (bank picked, or an alt)
    if mod.OfflinePanel then
        mod.OfflinePanel(sidebarW)
    end
end

function CUI_Bags:RefreshInventory()
    if not CUI_Bags:IsVisible() then
        return
    end
    mod.ApplySlotMetrics()

    -- A select mode's hover box sits on a button this refresh may refill: put
    -- that button's border back now and re-test the hover after
    local hoverCatcher = CUI_Bags._assignCatcher
    if hoverCatcher and hoverCatcher:IsShown() then
        hoverCatcher._clearHover()
        hoverCatcher._hoverDirty = true
    end
    hoverCatcher = CUI_Bags._pinCatcher
    if hoverCatcher and hoverCatcher:IsShown() then
        hoverCatcher._clearHover()
        hoverCatcher._hoverDirty = true
    end

    -- Refreshing during combat (bags opened mid-fight in M+/Delves) is safe: moving already-created
    -- buttons taints nothing; only CREATING a secure ContainerFrameItemButtonTemplate in lockdown
    -- poisons it (UseContainerItem() -> ADDON_ACTION_FORBIDDEN). GetOrCreateSlot returns nil in combat (pre-warmed pool makes this rare); PLAYER_REGEN_ENABLED replays a full refresh for anything skipped.
    if InCombatLockdown() then
        CUI_Bags._refreshPendingCombat = true
    end

    -- Category indices shift when the list rebuilds (split-mode set categories
    -- come and go); rebuilt below on first IsGearCategory call, so never stale.
    SetGearCatSet(nil)

    C_NewItems.ClearAll()

    -- 1. Gather items from all bags (0-4 + reagent bag 5)
    ReleaseAllSlotTables()
    local scanItems = {}
    local emptySlots = {}
    local bagUsed, bagTotal = 0, 0
    local reagUsed, reagTotal = 0, 0
    local special = mod.SpecialBags()

    for bag = 0, 5 do
        local slotCount = C_Container.GetContainerNumSlots(bag)
        local restricted = special and special[bag]
        if bag == 5 then
            reagTotal = slotCount
        elseif not restricted then
            bagTotal = bagTotal + slotCount
        end
        for slot = 1, slotCount do
            local details = C_Container.GetContainerItemInfo(bag, slot)
            if details then
                if bag == 5 then
                    reagUsed = reagUsed + 1
                elseif not restricted then
                    bagUsed = bagUsed + 1
                end
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                local skinData = AcquireSlotTable()
                skinData.bag = bag
                skinData.slot = slot
                skinData.info = details
                skinData.itemLink = itemLink
                CUI_Bags.ApplyBindKeyword(details, bag, slot)
                -- Pre-cache per-item data for RenderButton (zero API calls at render time)
                if itemLink then
                    local linkInfo = _linkFacts[itemLink]
                    local quality, bindType, isGear
                    if linkInfo then
                        quality, bindType, isGear = linkInfo.q, linkInfo.bindType, linkInfo.isGear
                    else
                        local _
                        _, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)
                        isGear = IsGearItem(itemLink)
                        if quality ~= nil then
                            if _linkFactsN >= 4000 then
                                wipe(_linkFacts)
                                _linkFactsN = 0
                            end
                            linkInfo = { q = quality, bindType = bindType, isGear = isGear }
                            _linkFacts[itemLink] = linkInfo
                            _linkFactsN = _linkFactsN + 1
                        end
                    end
                    _slotLoc:SetBagAndSlot(bag, slot)
                    local loc = _slotLoc
                    -- Slot-grouping fields (_equipSlot/_classID/_subclassID) are NOT
                    -- pre-cached here: GetArmorySlotBucket fetches them lazily, only
                    -- for gear items and only while Group Gear by Slot is on, so the
                    -- feature costs nothing on the refresh path when disabled.
                    skinData._giQuality = quality
                    skinData._giBindType = bindType
                    -- Track rank + cooldown: only for types that need them
                    skinData._isGear = isGear
                    -- The List view's iLvl column always needs the real level
                    skinData._giIlvl = isGear
                            and (BP().showItemlevelInBags ~= false or CUI_Bags.IsListMode())
                            and GetItemLevelAtLocation(loc, itemLink)
                        or nil
                    -- Upgrade tracks: the grid's item level colour and rank; the
                    -- List view only while its Track column shows or sorts.
                    if
                        isGear
                        and GetUpgradeTrack
                        and (not CUI_Bags.IsListMode() or mod.ListUsesColumn("track"))
                    then
                        local trackText, trackColor
                        if linkInfo and linkInfo.trackText then
                            trackText, trackColor = linkInfo.trackText, linkInfo.trackColor
                        else
                            trackText, trackColor = GetUpgradeTrack(itemLink)
                            if linkInfo and trackText and trackText ~= "" then
                                linkInfo.trackText, linkInfo.trackColor = trackText, trackColor
                            end
                        end
                        if trackText and trackText ~= "" then
                            skinData._giTrackRank = trackText
                            skinData._giTrackColor = trackColor
                        elseif
                            skinData._giIlvl and not (BP().itemlevelUseCustomColor and BP().itemlevelCustomColor)
                        then
                            skinData._giTrackColor = CUI.GetCraftedTrackColor(itemLink)
                        end
                    end
                    -- Warbound check (warbank dim overlay) + WuE bind check (gear only, when bind-type text is enabled).
                    if loc and C_Item.DoesItemExist(loc) then
                        if C_Bank and C_Bank.IsItemAllowedInBankType then
                            skinData._isWarbound = C_Bank.IsItemAllowedInBankType(Enum.BankType.Account, loc)
                        end
                        if isGear and not details.isBound and BP().bagDisplayBindType then
                            skinData._isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                        end
                    end
                    -- Keystone data (rare, fast string match gates the API calls)
                    if details.itemID == 180653 or itemLink:find("keystone:", 1, true) then
                        local ksMap, ksLvl = itemLink:match("keystone:[^:]*:(%d+):(%d+)")
                        if ksLvl then
                            skinData._ksLevel = ksLvl
                            skinData._ksAbbrev = AbbrevDungeon(tonumber(ksMap))
                            local success, color =
                                pcall(C_ChallengeMode.GetKeystoneLevelRarityColor, tonumber(ksLvl))
                            if success and color then
                                skinData._ksR = color.r
                                skinData._ksG = color.g
                                skinData._ksB = color.b
                            end
                        end
                    end
                    -- Cooldown (any item can have a cooldown: trinkets, consumables, toys, etc.)
                    local cdStart, cdDur, cdEnable = C_Container.GetContainerItemCooldown(bag, slot)
                    if cdEnable and cdEnable ~= 0 and cdStart > 0 and cdDur > 0 then
                        skinData._cdStart = cdStart
                        skinData._cdDuration = cdDur
                    end
                    -- _isQuest (any quest item, incl. active objectives + starters) drives the gold
                    -- border; _isQuestStarter (questID set but inactive) is Blizzard's "!" and drives the corner marker.
                    skinData._isQuest, skinData._isQuestStarter = mod.GetSlotQuestFlags(bag, slot)
                end
                scanItems[#scanItems + 1] = skinData
            else
                local skinData = AcquireSlotTable()
                skinData.bag = bag
                skinData.slot = slot
                emptySlots[#emptySlots + 1] = skinData
            end
        end
    end

    -- 1b. Detect manual item swaps and update saved visual order
    local isAllItems = selectedCategoryIndex == 0 and not selectedGroupName
    local swapDetected = DetectAndApplySwaps(scanItems, isAllItems)
    TakeBagSnapshot(scanItems)

    -- Show blocked-swap tooltip in category/group views (not All Items, not OneBag)
    if swapDetected and not isAllItems and selectedCategoryIndex ~= -1 and selectedCategoryIndex ~= -2 then
        if CUI.ShowWidgetTooltip then
            -- Controller cursor: the pointer may be hidden, so anchor to the window.
            CUI.ShowWidgetTooltip(
                CUI_Bags,
                "Positions can only be changed\nin the All Items, OneBag, or MultiBag views",
                (not CUI.PadInUse()) and { anchor = "cursor" } or nil
            )
            C_Timer.After(3, function()
                CUI.HideWidgetTooltip()
            end)
        end
    end

    -- 2. Classify all items and get counts
    local categoryCounts, totalCount = CUI_CategoryManager:ClassifyAll(scanItems)

    -- 2a. Snapshot slot->category mapping for partial refresh
    wipe(_slotCategories)
    for _, payload in ipairs(scanItems) do
        if payload.categoryIndex and payload.bag and payload.slot then
            _slotCategories[payload.bag * 1000 + payload.slot] = payload.categoryIndex
        end
    end

    -- 2b. Compute display-only counts for pinned and recent items
    local recentCatIdx, pinnedCatIdx
    do
        local cats = CUI_CategoryManager:GetCategories()
        for i, category in ipairs(cats) do
            if category.isRecent then
                recentCatIdx = i
            end
            if category.isPinned then
                pinnedCatIdx = i
            end
        end
    end
    local showPinned = BP().bagShowPinnedItems ~= false
    local pinnedSet = PinnedItems()
    local hidePinned = BP().bagHidePinnedInCategories == true
    -- Dim Items in OneBag/MultiBag: in those views (-1 / -2), while the Pinned
    -- Items quickview shows there, a pinned item is drawn dimmed in its bag
    -- section (the slot and row painters skip the quickview's own copy).
    local dimPinned = (selectedCategoryIndex == -1 or selectedCategoryIndex == -2)
        and BP().bagPinnedInOneBag ~= false
        and BP().bagDimPinnedInOneBag == true
    if pinnedCatIdx and pinnedSet and showPinned then
        local pinnedCount = 0
        for _, payload in ipairs(scanItems) do
            if
                payload.info
                and payload.info.itemID
                and IsItemPinned(pinnedSet, payload.itemLink, payload.info.itemID)
            then
                pinnedCount = pinnedCount + 1
                if dimPinned then
                    payload._pinDim = true
                end
                if hidePinned then
                    -- Keep the category for sorting and gear/stack handling.
                    payload._pinnedOnly = true
                    local ci = payload.categoryIndex
                    if ci then
                        categoryCounts[ci] = categoryCounts[ci] - 1
                    end
                end
            end
        end
        categoryCounts[pinnedCatIdx] = pinnedCount
    end
    local recentCount = 0
    local showRecent = BP().bagShowRecentItems ~= false
    if recentCatIdx and CUI_Bags._recentItems and showRecent then
        for _, payload in ipairs(scanItems) do
            if
                not payload._pinnedOnly
                and payload.info
                and payload.info.itemID
                and CUI_Bags._recentItems[payload.info.itemID]
            then
                recentCount = recentCount + 1
            end
        end
        categoryCounts[recentCatIdx] = recentCount
    end

    -- 2c. viewing an alt: the sidebar counts their bags instead
    local altView = mod.OfflineAlt and mod.OfflineAlt()
    if altView then
        categoryCounts, totalCount = mod.OfflineCounts()
    end
    -- an alt or the offline bank view: its panel takes the item area
    local offlineUp = altView
        or (mod.Offline and mod.Offline.Enabled() and selectedCategoryIndex == mod.OFFLINE_BANK_VIEW)

    -- 3. Update sidebar
    BuildSidebarButtons(categoryCounts, totalCount)

    -- Cache counts for partial refresh
    _lastCatCounts = categoryCounts
    _lastTotalCount = totalCount

    -- 4. Filter items by selected category/group + search
    local isRecentView = recentCatIdx and selectedCategoryIndex == recentCatIdx
    local isPinnedView = pinnedCatIdx and selectedCategoryIndex == pinnedCatIdx
    local filterSet = nil -- nil = show all
    do
        local cats = CUI_CategoryManager:GetCategories()
        -- The "Item Set Gear" anchor view (and any group holding it) folds in the
        -- split-mode set children, which hold the actual items.
        local function AddSetChildren(anchorIdx)
            if not BP().bagSplitSetGearBySet then
                return
            end
            if not (cats[anchorIdx] and cats[anchorIdx].isSetGear and not cats[anchorIdx].isEquipSet) then
                return
            end
            for i, c in ipairs(cats) do
                if c.isEquipSet then
                    filterSet[i] = true
                end
            end
        end
        if selectedGroupName then
            filterSet = {}
            local groupMembers = CUI_CategoryManager:GetGroupMembers(selectedGroupName)
            for _, mi in ipairs(groupMembers) do
                filterSet[mi] = true
                AddSetChildren(mi)
            end
        elseif selectedCategoryIndex > 0 and not isRecentView and not isPinnedView then
            filterSet = { [selectedCategoryIndex] = true }
            AddSetChildren(selectedCategoryIndex)
        end
    end

    local displayItems = {}
    for _, payload in ipairs(scanItems) do
        local show = true
        if offlineUp then
            show = false -- the offline panel covers these
        elseif isRecentView then
            show = payload.info
                and payload.info.itemID
                and CUI_Bags._recentItems
                and CUI_Bags._recentItems[payload.info.itemID]
        elseif isPinnedView then
            show = payload.info
                and payload.info.itemID
                and pinnedSet
                and IsItemPinned(pinnedSet, payload.itemLink, payload.info.itemID)
        elseif filterSet then
            show = payload.categoryIndex and filterSet[payload.categoryIndex]
        end
        if payload._pinnedOnly and (isRecentView or filterSet) then
            show = false
        end
        if show and payload.info and payload.info.isFiltered then
            show = false
        end
        if show then
            displayItems[#displayItems + 1] = payload
        end
    end

    -- 4b. Pending resort: sort + save order for categories invalidated by group changes (reuses already-scanned tempItems, no bag re-scan).
    if next(_pendingResortCats) or next(_pendingResortGroups) then
        local cats = CUI_CategoryManager:GetCategories()
        local itemsByCat = {}
        for _, payload in ipairs(scanItems) do
            local ci = payload.categoryIndex
            if ci then
                if not itemsByCat[ci] then
                    itemsByCat[ci] = {}
                end
                itemsByCat[ci][#itemsByCat[ci] + 1] = payload
            end
        end
        for ci in pairs(_pendingResortCats) do
            local itemList = itemsByCat[ci] or {}
            if #itemList > 1 then
                PreCacheSortFields(itemList)
                table.sort(itemList, VisualSortCompare)
            end
            SaveCategoryOrder(ci, itemList)
        end
        for gn in pairs(_pendingResortGroups) do
            local groupMembers = CUI_CategoryManager:GetGroupMembers(gn)
            if groupMembers and #groupMembers > 0 then
                local merged = {}
                for _, mi in ipairs(groupMembers) do
                    for _, payload in ipairs(itemsByCat[mi] or {}) do
                        merged[#merged + 1] = payload
                    end
                end
                if #merged > 1 then
                    PreCacheSortFields(merged)
                    table.sort(merged, VisualSortCompare)
                end
                SaveCategoryOrder(gn, merged)
            end
        end
        wipe(_pendingResortCats)
        wipe(_pendingResortGroups)
    end

    -- OneBag gives each WoW Forever special bag a section of its own.
    local spBags = 0
    if special then
        for _ in pairs(special) do
            spBags = spBags + 1
        end
    end

    -- Auto-size: pick a column count keeping the window near its base shape (columns grow
    -- ~sqrt of slot count) while fitting the active tab. Grows only, never shrinks while open
    -- (running max in _asCols, reset on close); HEIGHT follows rendered content up to the screen cap. Decided BEFORE GetColumns() so the grid renders at this count.
    if CUI_Bags.AutoSizeOn() then
        local baseCols = BP().bagColumns or 12
        -- tuned at the default 38 px pitch, scaled to the current one
        local pitch = SLOT_SIZE + SPACING
        local BASE_ROWS = 15 * 38 / pitch -- rows visible at the base (FIXED_H) height
        local HDR = 0.74 * 38 / pitch -- section-header height in slot-row units (~28/38)
        -- Slot count (n) + section-header count (S) for the active tab. Headers add HEIGHT
        -- but not WIDTH, so they MUST fold into the estimate or a header-heavy tab (All Items with many categories) grows taller than wide.
        local num, S
        if selectedCategoryIndex > 0 and not selectedGroupName then
            num = (categoryCounts and categoryCounts[selectedCategoryIndex]) or #scanItems
            -- The anchor view folds in its set children's items; count them too
            if BP().bagSplitSetGearBySet then
                local szCats = CUI_CategoryManager:GetCategories()
                local selCat = szCats[selectedCategoryIndex]
                if selCat and selCat.isSetGear and not selCat.isEquipSet and categoryCounts then
                    for i, c in ipairs(szCats) do
                        if c.isEquipSet then
                            num = num + (categoryCounts[i] or 0)
                        end
                    end
                end
            end
            S = 1
        elseif selectedCategoryIndex == 0 and not selectedGroupName then
            -- All Items: one section per non-empty category
            num = #scanItems + #emptySlots
            S = 0
            if categoryCounts then
                -- Set children fold into their anchor's section: count them as one
                local sizeCats = BP().bagSplitSetGearBySet and CUI_CategoryManager:GetCategories() or nil
                local hasSetChild = false
                for i, c in pairs(categoryCounts) do
                    if c and c > 0 then
                        if sizeCats and sizeCats[i] and sizeCats[i].isEquipSet then
                            hasSetChild = true
                        else
                            S = S + 1
                        end
                    end
                end
                if hasSetChild then
                    S = S + 1
                end
            end
            if S < 1 then
                S = 1
            end
        elseif selectedCategoryIndex == -2 then
            -- MultiBag: one section per bag that has slots (+ reagent)
            num = #scanItems + #emptySlots
            S = 0
            for bag = 0, 5 do
                if C_Container.GetContainerNumSlots(bag) > 0 then
                    S = S + 1
                end
            end
            if S < 1 then
                S = 1
            end
        else
            -- OneBag / group view: a few sections (pinned/recent/main/reagent,
            -- plus OneBag's special bags)
            num = #scanItems + #emptySlots
            S = 3 + (selectedCategoryIndex == -1 and spBags or 0)
        end
        num = math.max(num, 1)
        -- Compact: no header rows; each block's gap and part-filled last row
        -- (about a cell) and the label bands are folded into the cell count
        -- as an estimate
        if CUI_Bags.IsCompactMode() then
            num = (num + S - 1) * (1 + mod.CompactBandHeight() / (SLOT_SIZE + SPACING))
            S = 0
        end
        local ideal = baseCols
        -- Only grow when the tab won't fit at the base column count.
        if math.ceil(num / baseCols) + math.ceil(HDR * S) > BASE_ROWS then
            -- Cols such that item+header rows keep the base rows:cols slope (grow together):
            -- solve A*cols^2 - HDR*S*cols - n = 0, where A = BASE_ROWS/baseCols.
            local A = BASE_ROWS / baseCols
            local hs = HDR * S
            ideal = math.ceil((hs + math.sqrt(hs * hs + 4 * A * num)) / (2 * A))
        end
        local sbW = GetSidebarWidth()
        local sc = CUI_Bags:GetScale()
        if not sc or sc <= 0 then
            sc = 1
        end
        local maxGridW = (UIParent:GetWidth() / sc) * 0.95 - sbW - 30
        local maxCols = math.max(baseCols, math.floor(maxGridW / (SLOT_SIZE + SPACING)))
        if ideal < baseCols then
            ideal = baseCols
        end
        if ideal > maxCols then
            ideal = maxCols
        end
        CUI_Bags._asCols = math.max(CUI_Bags._asCols or baseCols, ideal)
    end

    local columns = GetColumns()
    local sidebarW = GetSidebarWidth()
    local headerH = CUI_Bags.Header:GetHeight() + (mod.ModernStripH and mod.ModernStripH() or 0)
    local gridPadX = 10
    local gridW = columns * (SLOT_SIZE + SPACING)
    -- List rows take the grip-set width (List has no Auto-Size), by default the default pitch's
    if CUI_Bags.IsListMode() then
        gridW = BP().bagListWidth or columns * LIST_PITCH
    end
    local scrollbarPad = SCROLLBAR_HIT_W + 2

    -- Update scroll frame left edge to track sidebar width
    local scrollFrame = CUI_Bags._scrollFrame
    local childFrame = CUI_Bags._scrollChild
    if scrollFrame then
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", CUI_Bags, "TOPLEFT", sidebarW, -(headerH + 1))
        scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bags.Footer, "TOPRIGHT", CUI_Bags._scrollRightInset, 0)
    end
    if childFrame then
        childFrame:SetWidth(gridW + gridPadX * 2 + scrollbarPad)
    end

    -- Both views below paint with the current panel state, merging or not
    -- (slot views and an unmerged list never reach MergeDuplicates)
    SetPaintedPanelOpen(_anyItemPanelOpen)

    -- no live items laid out under the offline panel (select modes would hit them)
    local liveItems, liveEmpty = scanItems, emptySlots
    if offlineUp then
        liveItems, liveEmpty = {}, {}
    end

    -- List display (latched per session): rows replace the grid; the column
    -- header bar takes the top of the scroll area
    if CUI_Bags.IsListMode() and scrollFrame then
        local listH, colHdrH = mod.RenderListView(displayItems, {
            -- Left / Right Gap: space between the list area edges and the rows
            rowW = math.max(
                100,
                gridW + gridPadX * 2 + scrollbarPad - (BP().bagListGapL or 15) - (BP().bagListGapR or 23)
            ),
            startX = BP().bagListGapL or 15,
            leftX = sidebarW,
            topY = -(headerH + 1),
            allItems = isAllItems,
            slotView = (selectedCategoryIndex == -1 and "one")
                or (selectedCategoryIndex == -2 and "multi")
                or nil,
            -- Same rule as the grid's Recent Items section
            recent = (
                showRecent and (isAllItems or (selectedCategoryIndex < 0 and BP().bagRecentInOneBag == true))
            )
                    and CUI_Bags._recentItems
                or nil,
            -- The Recent Items tab: its items in one newest-first section
            recentOnly = isRecentView or nil,
            -- Empty rows only when nothing is search-filtered out
            emptySlots = (#displayItems == #liveItems) and liveEmpty or nil,
            -- Same rule as the grid's Pinned Items section
            pinned = (
                showPinned
                and (isAllItems or (selectedCategoryIndex < 0 and BP().bagPinnedInOneBag ~= false))
            )
                    and pinnedSet
                or nil,
        })
        scrollFrame:SetPoint("TOPLEFT", CUI_Bags, "TOPLEFT", sidebarW, -(headerH + 1 + colHdrH))
        FinishRefresh(
            -(listH + colHdrH),
            gridW + gridPadX * 2 + scrollbarPad + 2,
            sidebarW,
            bagUsed,
            bagTotal,
            reagUsed,
            reagTotal,
            totalCount
        )
        return
    end

    local curY = mod.RenderGridView(
        liveItems,
        displayItems,
        liveEmpty,
        childFrame,
        columns,
        gridW,
        gridPadX,
        showPinned,
        pinnedSet
    )

    -- Compact: the window drops the remainder its widest band leaves short of
    -- the columns, less than a cell (ns.CompactBagsContentW). While open it
    -- only grows back, so a refresh never pulls the edge in under the cursor;
    -- a new column count, or a close, starts over.
    if CUI_Bags.IsCompactMode() then
        local wid = mod.CompactBagsContentW()
        if wid and wid < gridW then
            if CUI_Bags._compactCols ~= columns then
                CUI_Bags._compactCols, CUI_Bags._compactW = columns, wid
            elseif wid > (CUI_Bags._compactW or 0) then
                CUI_Bags._compactW = wid
            end
            gridW = CUI_Bags._compactW
        else
            CUI_Bags._compactCols, CUI_Bags._compactW = columns, gridW
        end
        if childFrame then
            childFrame:SetWidth(gridW + gridPadX * 2 + scrollbarPad)
        end
    end

    FinishRefresh(
        curY,
        gridW + gridPadX * 2 + scrollbarPad + 2,
        sidebarW,
        bagUsed,
        bagTotal,
        reagUsed,
        reagTotal,
        totalCount
    )
end

-------------------------------------------------------------------------------
--  Reagent Bag Refresh
-------------------------------------------------------------------------------
function CUI_BagsReagent:RefreshInventory()
    if not CUI_BagsReagent:IsVisible() then
        return
    end
    -- Same secure-button rule as CUI_Bags:RefreshInventory: viewing in combat is fine, creating is not (GetOrCreateReagentSlot refuses); mark pending so combat-end tops up.
    if InCombatLockdown() then
        CUI_Bags._refreshPendingCombat = true
    end
    local scanItems = {}
    local slotCount = C_Container.GetContainerNumSlots(5)
    if slotCount > 0 then
        for slot = 1, slotCount do
            local details = C_Container.GetContainerItemInfo(5, slot)
            scanItems[#scanItems + 1] = { bag = 5, slot = slot, info = details }
        end
    end

    for _, button in pairs(reagentSlots) do
        button:GetParent():Hide()
    end

    local startX, startY = 15, -45
    local REAGENT_COLUMNS = 4
    for i, payload in ipairs(scanItems) do
        local button = GetOrCreateReagentSlot(i)
        if button then -- nil during combat (avoids minting tainted secure buttons)
            local hostFrame = button:GetParent()
            hostFrame:ClearAllPoints()
            hostFrame:Show()
            button:Show()
            button:SetID(payload.slot)
            hostFrame:SetID(payload.bag)
            local itemLink = payload.info and C_Container.GetContainerItemLink(payload.bag, payload.slot)

            if not payload.info then
                button:SetItemButtonTexture(nil)
                button:SetItemButtonCount(0)
                SetItemButtonDesaturated(button, false)
                if button.icon then
                    button.icon:Hide()
                end
                if button.ItemLevelText then
                    button.ItemLevelText:SetText("")
                end
                SetInsetBorderColor(button, 0.25, 0.25, 0.25, 1)
                if button._fvSlotBorder then
                    mod.SetForeverSlotQuestBorder(button, false)
                end
            else
                if button.icon then
                    button.icon:Show()
                end
                mod.SetSlotIcon(button, payload.info.iconFileID)
                button:SetItemButtonCount(payload.info.stackCount)
                SetItemButtonDesaturated(button, payload.info.isLocked)
                local filtered = payload.info.isFiltered
                button:SetAlpha(filtered and 0.2 or 1)
                if button._textOverlay then
                    button._textOverlay:SetAlpha(filtered and 0.2 or 1)
                end

                if button.ItemLevelText and payload.info.itemID then
                    local showItemlevel = BP().showItemlevelInBags ~= false
                    if showItemlevel then
                        if itemLink then
                            local _, _, quality = GetItemInfo(itemLink)
                            if IsGearItem(itemLink) then
                                local loc = ItemLocation:CreateFromBagAndSlot(payload.bag, payload.slot)
                                local level = GetItemLevelAtLocation(loc, itemLink)
                                local fontStr = BP().itemlevelFontSize or 12
                                button.ItemLevelText:SetFont(
                                    STANDARD_TEXT_FONT,
                                    fontStr,
                                    (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
                                )
                                button.ItemLevelText:SetText(level or "")
                                local red, green, blue
                                if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                                    red, green, blue =
                                        BP().itemlevelCustomColor.r,
                                        BP().itemlevelCustomColor.g,
                                        BP().itemlevelCustomColor.b
                                else
                                    red, green, blue = GetItemQualityColor(quality or 1)
                                end
                                button.ItemLevelText:SetTextColor(red, green, blue, 1)
                            else
                                button.ItemLevelText:SetText("")
                            end
                        else
                            button.ItemLevelText:SetText("")
                        end
                    else
                        button.ItemLevelText:SetText("")
                    end
                end

                local red, green, blue = mod.QualityBorderColor(payload.info.quality or 1)
                SetInsetBorderColor(button, red, green, blue, 1)
                if button._fvSlotBorder then
                    mod.SetForeverSlotQuestBorder(button, mod.GetSlotQuestFlags(payload.bag, payload.slot))
                end
            end
            UpdatePawnArrow(button, itemLink)
            if next(CUI_Bags.itemOverlayIcons) ~= nil then
                payload.itemLink = itemLink
                CUI_Bags.RunItemOverlays(button, payload)
            end
            -- Tooltip requery after the slot re-assignment (see RenderButton).
            if GameTooltip:IsOwned(button) then
                if payload.info and button.UpdateTooltip then
                    button:UpdateTooltip()
                else
                    GameTooltip:Hide()
                end
            end

            local colour = (i - 1) % REAGENT_COLUMNS
            local row = math.floor((i - 1) / REAGENT_COLUMNS)
            hostFrame:SetPoint(
                "TOPLEFT",
                startX + (colour * (SLOT_SIZE + SPACING)),
                startY - (row * (SLOT_SIZE + SPACING))
            )
        end
    end

    CUI_BagsReagent:SetWidth((REAGENT_COLUMNS * (SLOT_SIZE + SPACING)) + 30)
    CUI_BagsReagent:SetHeight(
        math.abs(startY) + (math.ceil(#scanItems / REAGENT_COLUMNS) * (SLOT_SIZE + SPACING)) + 40
    )
end

function CUI_BagsWindow:RefreshBags()
    if not CUI_BagsWindow:IsVisible() then
        return
    end
    for _, button in pairs(bagSlots) do
        button:GetParent():Hide()
    end
    local startX, startY = 10, -10
    local BAG_COLUMNS = 6
    for i = 0, 5 do
        local displayIdx = i + 1
        local button = GetOrCreateBagSlot(displayIdx)
        local hostFrame = button:GetParent()
        button:SetID(i)
        hostFrame:Show()
        local invID = C_Container.ContainerIDToInventoryID(i)
        local texture = GetInventoryItemTexture("player", invID)
        local quality = GetInventoryItemQuality("player", invID) or 0
        local free = C_Container.GetContainerNumFreeSlots(i)
        local sum = C_Container.GetContainerNumSlots(i)
        if i == 0 then
            button.icon:SetTexture(133633)
        elseif texture then
            button.icon:SetTexture(texture)
        else
            button.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        end
        if sum > 0 then
            button.Count:SetText(free)
            button.Count:Show()
        else
            button.Count:Hide()
        end
        local bdrR, bdrG, bdrB = 0.25, 0.25, 0.25
        if quality > 0 then
            bdrR, bdrG, bdrB = mod.QualityBorderColor(quality)
        end
        SetInsetBorderColor(button, bdrR, bdrG, bdrB, 1)
        button._bdrR, button._bdrG, button._bdrB = bdrR, bdrG, bdrB

        -- Blizzard's bag bar order: backpack on the right, reagent bag on the left
        hostFrame:ClearAllPoints()
        hostFrame:SetPoint(
            "TOPLEFT",
            CUI_BagsWindow,
            "TOPLEFT",
            startX + ((BAG_COLUMNS - 1 - i) * (SLOT_SIZE + SPACING)),
            startY
        )
    end
    CUI_BagsWindow:SetSize((BAG_COLUMNS * (SLOT_SIZE + SPACING)) + 15, SLOT_SIZE + 20)
end

Inner._catHeaders, Inner._expSubHeaders = _catHeaders, _expSubHeaders
Inner.CreateBagScrollFrame, Inner.GetOrCreateCatHeader = CreateBagScrollFrame, GetOrCreateCatHeader
Inner.GetOrCreateExpSubHeader = GetOrCreateExpSubHeader
Inner.ShowRecentClearButton = ShowRecentClearButton
Inner.broken = false
