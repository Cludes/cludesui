if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Select.lua
--
--  Pin and Assign selection modes, the Junk Marker and Sell Junk.
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

local BP, GetAccentRGB, GetFont, IsGearItem = Inner.BP, Inner.GetAccentRGB, Inner.GetFont, Inner.IsGearItem
local IsItemPinned, NormalizePinKey = Inner.IsItemPinned, Inner.NormalizePinKey
local SetBagFont, _openItemPanels, PinnedItems = Inner.SetBagFont, Inner._openItemPanels, Inner.PinnedItems
local itemSlots, SetInsetBorderColor = Inner.itemSlots, Inner.SetInsetBorderColor
local GetInsetBorderStyle, SetInsetBorderThickness = Inner.GetInsetBorderStyle, Inner.SetInsetBorderThickness

-------------------------------------------------------------------------------
--  Pin Selection Mode
-------------------------------------------------------------------------------
local EnterPinSelectMode -- forward declaration
local ExitPinSelectMode -- forward declaration
local EnterAssignSelectMode -- forward declaration

-- The "+" look shared by the pin and assign "+" overlays and the Compact
-- display's drop zones (CludesUIBags_Compact.lua): a dimmed button with a
-- "+" that brightens on hover and shows the button's _plusTip.
mod.PIN_PLUS_TIP = "Pin an Item"
mod.ASSIGN_PLUS_TIP = "Assign an item to this category"
do
    local function PlusOnEnter(self)
        self._hover = true
        self.plus:SetTextColor(1, 1, 1, 1)
        CUI.ShowWidgetTooltip(self, self._plusTip)
    end
    local function PlusOnLeave(self)
        self._hover = nil
        self.plus:SetTextColor(1, 1, 1, 0.5)
        CUI.HideWidgetTooltip()
    end
    function mod.CreatePlusButton(hostFrame, tipText)
        local shade = CreateFrame("Button", nil, hostFrame)
        shade.bg = shade:CreateTexture(nil, "BACKGROUND")
        shade.bg:SetAllPoints()
        shade.bg:SetColorTexture(0, 0, 0, 0.4)
        shade.plus = shade:CreateFontString(nil, "OVERLAY")
        shade.plus:SetFont(GetFont(), 18, (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
        shade.plus:SetPoint("CENTER", 0, 0)
        shade.plus:SetText("+")
        shade.plus:SetTextColor(1, 1, 1, 0.5)
        shade._plusTip = tipText
        shade:SetScript("OnEnter", PlusOnEnter)
        shade:SetScript("OnLeave", PlusOnLeave)
        shade:RegisterForDrag("LeftButton")
        return shade
    end
    -- Ends the hover look of a plus button hidden under the mouse (it may get no OnLeave)
    function mod.EndPlusHover(button)
        if button._hover then
            PlusOnLeave(button)
        end
    end
end

-- Pins the item on the cursor (the pin "+" overlay, the Compact Pinned drop
-- zone) and refreshes; returns true when the cursor held an item.
function mod.PinCursorItem()
    -- The third return is the item link: pins are keyed by it (NormalizePinKey)
    local cursorType, itemId, cursorLink = GetCursorInfo()
    if cursorType ~= "item" or not itemId then
        return false
    end
    local isPinned = PinnedItems(true)
    if not isPinned then
        ClearCursor()
        return true
    end
    if not IsItemPinned(isPinned, cursorLink, itemId) then
        isPinned[NormalizePinKey(cursorLink, itemId)] = IsGearItem(cursorLink) and 1 or 999
    end
    ClearCursor()
    CUI_Bags:RefreshInventory()
    return true
end

-- Assigns the item on the cursor to the category catKey (the assign "+"
-- overlay, a Compact drop zone) and refreshes; returns true when it did.
function mod.AssignCursorItem(catKey)
    local cursorType, itemId = GetCursorInfo()
    if cursorType ~= "item" or not itemId or not catKey then
        return false
    end
    CUI_CategoryManager:AssignItem(itemId, catKey)
    ClearCursor()
    CUI_Bags:RefreshInventory()
    return true
end

-- The "+" overlays lie over an empty slot's item button and its overlays (the
-- window's level + 9 to + 15, ns.PinItemButton), so each placement levels them
-- from the window's current level: 100 over a window at level 1
local function OverSlots(shade)
    shade:SetFrameLevel(CUI_Bags:GetFrameLevel() + 99)
    return shade
end

-- Pin "+" overlay: a click-catcher frame placed over a regular empty slot
local function GetOrCreatePinOverlay()
    if CUI_Bags._pinOverlayBtn then
        return OverSlots(CUI_Bags._pinOverlayBtn)
    end
    local shade = mod.CreatePlusButton(CUI_Bags, mod.PIN_PLUS_TIP)
    mod.SizeSlot(shade)
    shade:SetScript("OnReceiveDrag", mod.PinCursorItem)
    shade:SetScript("OnClick", function(self)
        -- Click-to-place also pins
        if mod.PinCursorItem() then
            return
        end
        -- Controller cursor on screen: select mode hit-tests the hidden
        -- pointer, so explain the carry-then-press path instead.
        if CUI.PadCursorShown() then
            CUI.ShowWidgetTooltip(self, CludesUI.L("Pick up an item, then press + to pin it"))
            return
        end
        CUI.HideWidgetTooltip()
        -- Select modes raise the item grid: out of combat only
        if InCombatLockdown() then
            return
        end
        EnterPinSelectMode()
    end)
    shade:Hide()
    CUI_Bags._pinOverlayBtn = shade
    return OverSlots(shade)
end

-- Assign "+" overlay: click/drag an item to assign to a category; pooled so multiple sections can show one simultaneously.
local _assignOverlays = {}
local _assignOverlayIdx = 0

local function GetOrCreateAssignOverlay()
    _assignOverlayIdx = _assignOverlayIdx + 1
    if _assignOverlays[_assignOverlayIdx] then
        return OverSlots(_assignOverlays[_assignOverlayIdx])
    end
    local shade = mod.CreatePlusButton(CUI_Bags, mod.ASSIGN_PLUS_TIP)
    mod.SizeSlot(shade)
    local function DoAssign(self)
        if mod.AssignCursorItem(self._assignCatKey) then
            return
        end
        -- No cursor item: enter assign select mode (like pin select)
        if self._assignCatKey then
            -- Controller cursor on screen: select mode hit-tests the hidden
            -- pointer, so explain the carry-then-press path instead.
            if CUI.PadCursorShown() then
                CUI.ShowWidgetTooltip(
                    self,
                    CludesUI.L("Pick up an item, then press + to add it to this category")
                )
                return
            end
            CUI.HideWidgetTooltip()
            -- Select modes raise the item grid: out of combat only
            if InCombatLockdown() then
                return
            end
            EnterAssignSelectMode(self._assignCatKey)
        end
    end
    shade:SetScript("OnReceiveDrag", DoAssign)
    shade:SetScript("OnClick", DoAssign)
    shade:Hide()
    _assignOverlays[_assignOverlayIdx] = shade
    return OverSlots(shade)
end

local function ResetAssignOverlays()
    for index = 1, _assignOverlayIdx do
        _assignOverlays[index]:Hide()
    end
    _assignOverlayIdx = 0
end

ExitPinSelectMode = function()
    CUI_Bags._pinSelectMode = false
    local castFrame = CUI_Bags._pinCatcher
    if castFrame then
        castFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        castFrame:Hide()
    end
    local shade = CUI_Bags._pinOverlay
    if shade then
        shade:EnableMouse(false)
        if not shade._fadeOut then
            local fg = shade:CreateAnimationGroup()
            local a = fg:CreateAnimation("Alpha")
            a:SetFromAlpha(1)
            a:SetToAlpha(0)
            a:SetDuration(0.15)
            fg:SetScript("OnFinished", function()
                shade:Hide()
                shade:SetAlpha(1)
            end)
            shade._fadeOut = fg
        end
        shade._fadeOut:Play()
    end
    local scrollFrame = CUI_Bags._scrollFrame
    if scrollFrame then
        scrollFrame:SetFrameStrata(CUI_Bags:GetFrameStrata())
    end
end

-- Repaints an open bank (RefreshBank returns while it is closed), so the
-- search filter and Junk Marker changes show in both windows
function mod.RefreshOpenBank()
    local bank = _G.CUI_BankFrame
    if bank then
        bank:RefreshBank()
    end
end

-------------------------------------------------------------------------------
--  Assign Selection Mode: dim the screen, click an item to assign it to a category (mirrors Pin Selection Mode).
-------------------------------------------------------------------------------
local _assignSelectCatKey = nil

local function ExitAssignSelectMode()
    local wasJunk = CUI_Bags._junkMode
    CUI_Bags._assignSelectMode = false
    CUI_Bags._junkMode = nil
    _assignSelectCatKey = nil
    local castFrame = CUI_Bags._assignCatcher
    if castFrame then
        castFrame._clearHover()
        castFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        castFrame:Hide()
    end
    local shade = CUI_Bags._assignOverlay
    if shade then
        shade:EnableMouse(false)
        if not shade:IsVisible() then
            -- Hidden with the bags: nothing to fade out
            if shade._fadeIn then
                shade._fadeIn:Stop()
            end
            shade:Hide()
            shade:SetAlpha(1)
        else
            if not shade._fadeOut then
                local fg = shade:CreateAnimationGroup()
                local a = fg:CreateAnimation("Alpha")
                a:SetFromAlpha(1)
                a:SetToAlpha(0)
                a:SetDuration(0.15)
                fg:SetScript("OnFinished", function()
                    shade:Hide()
                    shade:SetAlpha(1)
                end)
                shade._fadeOut = fg
            end
            shade._fadeOut:Play()
        end
    end
    local scrollFrame = CUI_Bags._scrollFrame
    if scrollFrame then
        scrollFrame:SetFrameStrata(CUI_Bags:GetFrameStrata())
    end
    -- The coin goes back into the header's layer
    local coinTex = wasJunk and CUI_Bags._junkBtn
    if coinTex then
        coinTex:SetFrameStrata(CUI_Bags:GetFrameStrata())
        coinTex:SetFrameLevel(coinTex:GetParent():GetFrameLevel() + 1)
    end
    -- Marks repainted only their own slots: sort them into place now (an open
    -- bank greys and regroups its copies too)
    if wasJunk and CUI_Bags._junkDirty then
        CUI_Bags._junkDirty = nil
        if CUI_Bags:IsShown() then
            CUI_Bags:RefreshInventory()
        end
        mod.RefreshOpenBank()
    end
end

-- Select modes' hit-test: the shown grid slot or list row under the cursor,
-- only over the scroll frame (rows scrolled out of view stay shown under the
-- header, the footer or outside the window; the scroll frame only clips them).
-- Cursor / each button's OWN effective scale: GetRect() is in button units.
function mod.SelectSlotUnderCursor()
    if mod.OfflineUp and mod.OfflineUp() then
        return nil
    end -- an alt's items aren't real slots
    local scrollFrame = CUI_Bags._scrollFrame
    if not (scrollFrame and scrollFrame:IsMouseOver()) then
        return nil
    end
    local rawCx, rawCy = GetCursorPosition()
    local pool = itemSlots
    for _ = 1, 2 do
        for _, button in pairs(pool) do
            if button:IsShown() and button:GetParent():IsShown() then
                local es = button:GetEffectiveScale()
                local cx, cy = rawCx / es, rawCy / es
                local l, b, wid, hgt = button:GetRect()
                if l and b and wid and hgt and cx >= l and cx <= l + wid and cy >= b and cy <= b + hgt then
                    return button
                end
            end
        end
        pool = mod.ListRows
        if not pool then
            break
        end
    end
    return nil
end

-- Mark mode: a mark is per item, so every shown slot holding it repaints
-- (the item ID first: only those slots read the full item info)
function mod.RepaintJunkItem(itemId)
    local pool = itemSlots
    for _ = 1, 2 do
        for _, button in pairs(pool) do
            if button:IsShown() and button:GetParent():IsShown() then
                local bagId, slotBtn = button:GetParent():GetID(), button:GetID()
                if C_Container.GetContainerItemID(bagId, slotBtn) == itemId then
                    local details = C_Container.GetContainerItemInfo(bagId, slotBtn)
                    if details then
                        if button._lvIcon then
                            mod.ListPaintJunk(button, details)
                        else
                            mod.GridPaintJunk(button, details)
                        end
                    end
                end
            end
        end
        pool = mod.ListRows
        if not pool then
            break
        end
    end
end

-- junk: Junk Marker mode -- clicks toggle marks, the mode stays open, and only
-- the bag window dims (the "+" assign dims the whole screen).
EnterAssignSelectMode = function(catKey, junkList)
    if mod.OfflineUp and mod.OfflineUp() then
        return
    end -- nothing live to pick while an alt or bank is up
    CUI_Bags._assignSelectMode = true
    CUI_Bags._junkMode = junkList or nil
    _assignSelectCatKey = catKey

    local cacheKey = junkList and "_assignOverlayBag" or "_assignOverlayFull"
    if not CUI_Bags[cacheKey] then
        local shade = CreateFrame("Frame", nil, junkList and CUI_Bags or UIParent)
        if junkList then
            -- The bag's own strata: the item grid rides the scroll frame, raised
            -- to FULLSCREEN_DIALOG below, so only the bag behind the items dims.
            shade:SetFrameStrata(CUI_Bags:GetFrameStrata())
            shade:SetFrameLevel(CUI_Bags:GetFrameLevel() + 20)
            shade:SetAllPoints(CUI_Bags)
        else
            shade:SetFrameStrata("FULLSCREEN_DIALOG")
            shade:SetFrameLevel(0)
            shade:SetAllPoints(UIParent)
        end
        shade:EnableMouse(true)
        shade.bg = shade:CreateTexture(nil, "BACKGROUND")
        shade.bg:SetAllPoints()
        shade.bg:SetColorTexture(0, 0, 0, 0.6)
        shade:SetScript("OnMouseDown", function()
            ExitAssignSelectMode()
        end)
        -- Escape (and controller Back) ends the mode before closing the bags,
        -- through the escape proxy: the overlay takes no keyboard input
        CludesUI.RegisterEscapeClose(shade, {
            notOwned = true,
            onEscape = function()
                ExitAssignSelectMode()
            end,
        })
        CUI_Bags[cacheKey] = shade
    end
    CUI_Bags._assignOverlay = CUI_Bags[cacheKey]
    local shade = CUI_Bags._assignOverlay
    -- A fade-out still running from a quick exit would hide the dim mid-mode,
    -- and the exit turned its mouse off
    if shade._fadeOut then
        shade._fadeOut:Stop()
    end
    shade:EnableMouse(true)
    shade:SetAlpha(0)
    shade:Show()
    if not shade._fadeIn then
        local fg = shade:CreateAnimationGroup()
        local a = fg:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.15)
        fg:SetScript("OnFinished", function()
            shade:SetAlpha(1)
        end)
        shade._fadeIn = fg
    end
    shade._fadeIn:Play()

    -- Raise scroll frame above overlay
    local scrollFrame = CUI_Bags._scrollFrame
    if scrollFrame then
        scrollFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    end

    local FindBtnUnderCursor = mod.SelectSlotUnderCursor

    -- Click catcher with hover highlight
    if not CUI_Bags._assignCatcher then
        local castFrame = CreateFrame("Frame", nil, UIParent)
        castFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        castFrame:SetFrameLevel(500)
        castFrame:EnableMouse(true)
        -- Combat ends the mode (registered only while it is on)
        castFrame:SetScript("OnEvent", function()
            ExitAssignSelectMode()
        end)

        local hoverOverlay = castFrame:CreateTexture(nil, "OVERLAY")
        hoverOverlay:SetColorTexture(1, 1, 1, 0.4)
        hoverOverlay:Hide()
        local hoveredBtn = nil
        local savedR, savedG, savedB, savedA, savedBrdSize

        local function ClearHover()
            if hoveredBtn then
                if savedR then
                    SetInsetBorderColor(hoveredBtn, savedR, savedG, savedB, savedA)
                end
                if savedBrdSize then
                    SetInsetBorderThickness(hoveredBtn, savedBrdSize)
                end
            end
            hoveredBtn = nil
            savedR = nil
            savedBrdSize = nil
            hoverOverlay:ClearAllPoints()
            hoverOverlay:Hide()
        end
        castFrame._clearHover = ClearHover

        -- Re-tests only when the cursor or the scroll moved, or on a show
        -- (_hoverDirty); the wheel scrolls under a still cursor
        local lastX, lastY, lastScroll
        castFrame:SetScript("OnUpdate", function(self)
            local posX, posY = GetCursorPosition()
            local scrollFrame = CUI_Bags._scrollFrame
            local s = scrollFrame and scrollFrame:GetVerticalScroll() or 0
            if posX == lastX and posY == lastY and s == lastScroll and not self._hoverDirty then
                return
            end
            lastX, lastY, lastScroll = posX, posY, s
            self._hoverDirty = nil
            local button = FindBtnUnderCursor()
            if button == hoveredBtn then
                return
            end
            ClearHover()
            if button and button.icon and button.icon:IsShown() then
                savedR, savedG, savedB, savedA, savedBrdSize = GetInsetBorderStyle(button)
                if savedR then
                    local ar, ag, ab = GetAccentRGB()
                    SetInsetBorderColor(button, ar, ag, ab, 1)
                    local Pix = CUI and CUI.PP
                    local px2 = ((Pix and Pix.mult) or 1) * 2
                    SetInsetBorderThickness(button, px2)
                end
                hoverOverlay:ClearAllPoints()
                hoverOverlay:SetAllPoints(button)
                hoverOverlay:Show()
                hoveredBtn = button
            end
        end)

        castFrame:SetScript("OnMouseDown", function(_, btnFrame)
            if btnFrame == "RightButton" then
                ClearHover()
                ExitAssignSelectMode()
                return
            end
            -- Junk Marker: the close button still closes the bags (the coin
            -- sits above this catcher and takes its own clicks)
            local junkMode = CUI_Bags._junkMode
            if junkMode and CUI_Bags._closeBtn and CUI_Bags._closeBtn:IsMouseOver() then
                ExitAssignSelectMode()
                CUI_Bags._closeBtn:Click()
                return
            end
            local button = FindBtnUnderCursor()
            if button then
                local bagID = button:GetParent():GetID()
                local slotId = button:GetID()
                if bagID and slotId and slotId > 0 then
                    local details = C_Container.GetContainerItemInfo(bagID, slotId)
                    if details and details.itemID and _assignSelectCatKey then
                        if junkMode then
                            -- Only the item's own slots repaint, so nothing moves under
                            -- the cursor; the bag sorts the marks when the mode ends
                            CUI_CategoryManager:ToggleJunk(details.itemID)
                            mod.RepaintJunkItem(details.itemID)
                            CUI_Bags._junkDirty = true
                        else
                            ClearHover()
                            CUI_CategoryManager:AssignItem(details.itemID, _assignSelectCatKey)
                            ExitAssignSelectMode()
                            CUI_Bags:RefreshInventory()
                        end
                        return
                    end
                end
            end
            -- Junk Marker: a click on empty bag space keeps the mode; anywhere
            -- outside the bags, right-click or Esc ends it
            if junkMode and CUI_Bags:IsMouseOver() then
                return
            end
            ClearHover()
            ExitAssignSelectMode()
        end)

        castFrame:SetAllPoints(UIParent)
        castFrame:Hide()
        CUI_Bags._assignCatcher = castFrame
    end
    local castFrame = CUI_Bags._assignCatcher
    castFrame._hoverDirty = true
    castFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    castFrame:Show()
    -- Junk Marker: the coin stays bright above the dim and takes its own
    -- clicks above the catcher (a click on it ends the mode)
    local coinTex = junkList and CUI_Bags._junkBtn
    if coinTex then
        coinTex:SetFrameStrata("FULLSCREEN_DIALOG")
        coinTex:SetFrameLevel(castFrame:GetFrameLevel() + 1)
    end
end

-------------------------------------------------------------------------------
--  Junk Marker: the header coin (mark mode) and Sell Junk (at merchants). Both
--  buttons are built on the first enable; nothing exists while it is off.
-------------------------------------------------------------------------------
do
    local function BuildButtons()
        local headerBar = CUI_Bags._bagsBtn:GetParent()
        -- Placed by SyncHeaderIcons, left of the next shown header icon
        local junkList = CreateFrame("Button", nil, headerBar)
        junkList:SetSize(22, 22)
        -- Our own coin art (the item badge and the Junk category keep the game's
        -- coin). It sits inside a thin margin: drawn 24 px, the coin fills the button
        junkList.icon = junkList:CreateTexture(nil, "OVERLAY")
        junkList.icon:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\gold.png")
        junkList.icon:SetSize(24, 24)
        junkList.icon:SetPoint("CENTER")
        junkList.icon:SetAlpha(0.9)
        junkList:SetScript("OnEnter", function(self)
            self.icon:SetAlpha(1)
            CUI.ShowWidgetTooltip(self, CludesUI.L("Click items to mark or unmark them as junk."))
        end)
        junkList:SetScript("OnLeave", function(self)
            self.icon:SetAlpha(0.9)
            CUI.HideWidgetTooltip()
        end)
        junkList:SetScript("OnClick", function(self)
            CUI.HideWidgetTooltip()
            -- Mark mode on: the coin ends it
            if CUI_Bags._junkMode then
                ExitAssignSelectMode()
                return
            end
            if InCombatLockdown() then
                return
            end
            -- An item on the cursor: mark or unmark that one
            local cursorType, itemId = GetCursorInfo()
            if cursorType == "item" and itemId then
                CUI_CategoryManager:ToggleJunk(itemId)
                ClearCursor()
                CUI_Bags:RefreshInventory()
                mod.RefreshOpenBank()
                return
            end
            -- Controller cursor on screen: mark mode hit-tests the hidden
            -- pointer, so explain the carry-then-press path instead.
            if CUI.PadCursorShown() then
                CUI.ShowWidgetTooltip(
                    self,
                    CludesUI.L("Pick up an item, then press the coin to mark it as junk")
                )
                return
            end
            EnterAssignSelectMode(CUI_CategoryManager.JUNK_KEY, true)
        end)
        -- A double-click is one press: its second click runs this instead of
        -- OnClick, which would end the mode the first click started
        junkList:SetScript("OnDoubleClick", function() end)
        CUI_Bags._junkBtn = junkList

        local sellBtn = CreateFrame("Button", nil, headerBar)
        sellBtn:SetPoint("RIGHT", junkList, "LEFT", -6, 0)
        local backdrop = sellBtn:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.4)
        sellBtn.label = sellBtn:CreateFontString(nil, "OVERLAY")
        SetBagFont(sellBtn.label, 10)
        sellBtn.label:SetPoint("CENTER")
        sellBtn.label:SetText(CludesUI.L("Sell Junk"))
        sellBtn.label:SetTextColor(0.85, 0.82, 0.55)
        -- Sized to its label (translations run longer)
        sellBtn:SetSize(math.max(58, math.ceil(sellBtn.label:GetStringWidth()) + 14), 18)
        sellBtn:SetScript("OnEnter", function(self)
            self.label:SetTextColor(1, 0.96, 0.66)
            CUI.ShowWidgetTooltip(self, CludesUI.L("Sells all your junk items."))
        end)
        sellBtn:SetScript("OnLeave", function(self)
            self.label:SetTextColor(0.85, 0.82, 0.55)
            CUI.HideWidgetTooltip()
        end)
        sellBtn:SetScript("OnClick", function()
            CUI.HideWidgetTooltip()
            CUI_Bags:SellJunk()
        end)
        CUI_Bags._sellJunkBtn = sellBtn
    end

    -- The header's icons (Bag Top Bar Icons), right to left from the search box:
    -- Sort, Show Bags, Quick Actions and the Junk Marker's coin, each shown one left of the next
    -- shown one; Sell Junk sits left of the coin while a merchant is open, and
    -- mark mode ends when the Junk Marker goes off. Hidden icons keep a point (the
    -- bags overview window hangs from Show Bags). Run at header build, by the
    -- options dropdown, on profile changes and on merchant open / close.
    function CUI_Bags:SyncHeaderIcons()
        local bags = self._bagsBtn
        if not bags then
            return
        end
        local profile = BP()
        local previous, gap = self._searchBox, 13
        local sortOn = profile.bagShowSortIcon ~= false
        self._sortBtn:SetShown(sortOn)
        local forever = mod.BagsForever()
        if sortOn or forever then
            previous, gap = self._sortBtn, 6
        end
        local bagsOn = profile.bagShowBagsIcon ~= false
        bags:ClearAllPoints()
        bags:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
        bags:SetShown(bagsOn)
        if bagsOn then
            previous, gap = bags, 6
        else
            CUI_BagsWindow:Hide() -- opened only from Show Bags
        end
        -- Quick Actions (CludesUIBags_QuickActions.lua), off by default
        local quick = mod.SyncQuickActionsIcon(previous, gap)
        if quick then
            previous, gap = quick, 6
        end
        local junkOn = CUI_CategoryManager:IsJunkMarkerEnabled()
        if junkOn and not self._junkBtn then
            BuildButtons()
        end
        if self._junkBtn then
            self._junkBtn:ClearAllPoints()
            self._junkBtn:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
            self._junkBtn:SetShown(junkOn)
            self._sellJunkBtn:SetShown(junkOn and _openItemPanels.merchant == true)
        end
        local edge = previous
        if junkOn and self._junkBtn then
            edge = self._sellJunkBtn:IsShown() and self._sellJunkBtn or self._junkBtn
        end
        -- The leftmost shown icon bounds the search on Forever and the title on CUI.
        if forever then
            local search, headerBar = self._searchBox, bags:GetParent()
            search:ClearAllPoints()
            search:SetPoint("LEFT", headerBar, "TOPLEFT", 45, headerBar._foreverToolsY)
            search:SetPoint("RIGHT", edge, "LEFT", -6, 0)
        end
        if not junkOn and self._junkMode then
            ExitAssignSelectMode()
        end
        if not forever then
            self._hdrEdge = edge
            self:FitHeaderText()
        end
    end

    -- The slots one Sell Junk sweep may sell, gathered once as bag * 1000 + slot
    -- (ids holds each one's itemID): marked or grey junk worth something, outside
    -- WoW Forever's special bags, equipment sets and pins, and not still
    -- refundable (Blizzard's own right-click never sells those without asking, and
    -- a fresh purchase of a marked item would otherwise go unasked). Returns how
    -- many junk items it kept back (the summary counts them as not sold).
    local function GatherJunkSlots(slotList, ids)
        local special = mod.SpecialBags()
        local setGear = CUI_CategoryManager:GetSetGearLookup()
        local isPinned = PinnedItems()
        local keptSet = 0
        for bagId = 0, 5 do
            if not (special and special[bagId]) then
                for slotBtn = 1, C_Container.GetContainerNumSlots(bagId) or 0 do
                    local details = C_Container.GetContainerItemInfo(bagId, slotBtn)
                    if
                        details
                        and details.itemID
                        and CUI_CategoryManager:IsJunk(details.itemID, details.quality)
                    then
                        local keep = details.hasNoValue
                            or setGear[bagId * 1000 + slotBtn]
                            or (isPinned and IsItemPinned(isPinned, details.hyperlink, details.itemID))
                        if not keep then
                            local p = C_Container.GetContainerItemPurchaseInfo(bagId, slotBtn, false)
                            keep = p and p.refundSeconds and p.refundSeconds > 0
                        end
                        if keep then
                            keptSet = keptSet + 1
                        else
                            slotList[#slotList + 1] = bagId * 1000 + slotBtn
                            ids[#ids + 1] = details.itemID
                        end
                    end
                end
            end
        end
        return keptSet
    end

    -- One item every 0.08 s, until the gathered slots run out, the merchant
    -- closes, combat starts or the cursor holds an item (a sale waiting on its
    -- confirmation: press Sell Junk again once it is answered). A sale counts once
    -- its slot has emptied; the summary (what sold, and what was left unsold)
    -- waits for the server to answer the sales in flight, 2 s at most.
    -- force: the caller saw MERCHANT_SHOW, which can run before Bags' own merchant
    -- flag is set.
    function CUI_Bags:SellJunk(force)
        if self._junkSelling or InCombatLockdown() or not (force or _openItemPanels.merchant) then
            return
        end
        self._junkSelling = true
        local slotList, ids, values, sent = {}, {}, {}, {}
        local keptSet = GatherJunkSlots(slotList, ids)
        local index, done = 0, false
        local function Landed(k)
            local itemKey = slotList[k]
            return C_Container.GetContainerItemID(math.floor(itemKey / 1000), itemKey % 1000) ~= ids[k]
        end
        local function InFlight()
            for num = 1, #sent do
                local k = sent[num]
                if not Landed(k) then
                    local itemKey = slotList[k]
                    local details = C_Container.GetContainerItemInfo(math.floor(itemKey / 1000), itemKey % 1000)
                    if details and details.isLocked then
                        return true
                    end
                end
            end
            return false
        end
        -- The summary (the bags repaint from the sales' own BAG_UPDATEs)
        local function Finish()
            if done then
                return
            end
            done = true
            local frame = CUI_Bags._junkSettle
            if frame then
                frame:UnregisterAllEvents()
            end
            CUI_Bags._junkSelling = nil
            local sold, earned = 0, 0
            for num = 1, #sent do
                if Landed(sent[num]) then
                    sold, earned = sold + 1, earned + values[sent[num]]
                end
            end
            -- Not sold: the junk kept back (no sell price, equipment sets, pins,
            -- refundable), and a gathered slot still holding its item (a sale
            -- refused or waiting on its confirmation, or the sweep cut short)
            local leftX = keptSet
            for k = 1, #slotList do
                if not Landed(k) then
                    leftX = leftX + 1
                end
            end
            local tag = CludesUI.COLOR_CODES.BRAND .. "CludesUI:|r "
            if sold > 0 then
                local message = CludesUI.Lf("Sold %1$d junk item(s)", sold)
                if earned > 0 then
                    message = message .. "  " .. C_CurrencyInfo.GetCoinTextureString(earned)
                end
                CludesUI.Print(tag .. message)
            end
            if leftX > 0 then
                CludesUI.Print(tag .. CludesUI.Lf("%d junk item(s) could not be sold.", leftX))
            end
        end
        -- Sales still in flight: finish once the server has answered them (their
        -- slots emptied or unlocked), or after 2 s at the latest
        local function Report()
            if not InFlight() then
                return Finish()
            end
            local frame = CUI_Bags._junkSettle
            if not frame then
                frame = CreateFrame("Frame")
                frame:SetScript("OnEvent", function(self)
                    self._check()
                end)
                CUI_Bags._junkSettle = frame
            end
            frame._check = function()
                if not InFlight() then
                    Finish()
                end
            end
            frame:RegisterEvent("BAG_UPDATE_DELAYED")
            frame:RegisterEvent("ITEM_LOCK_CHANGED")
            C_Timer.After(2, Finish)
        end
        local function step()
            local live = (force or _openItemPanels.merchant)
                and not InCombatLockdown()
                and not CursorHasItem()
            force = nil
            while live and index < #slotList do
                index = index + 1
                local itemKey = slotList[index]
                local bagId, slotBtn = math.floor(itemKey / 1000), itemKey % 1000
                local details = C_Container.GetContainerItemInfo(bagId, slotBtn)
                -- Still the gathered item, and not locked
                if details and details.itemID == ids[index] and not details.isLocked then
                    values[index] = ((details.hyperlink and select(11, GetItemInfo(details.hyperlink))) or 0)
                        * (details.stackCount or 1)
                    sent[#sent + 1] = index
                    C_Container.UseContainerItem(bagId, slotBtn)
                    C_Timer.After(0.08, step)
                    return
                end
            end
            Report()
        end
        step()
    end

    -- Profile switch: the categories (Junk with them) and the header icons follow the new profile
    function CUI_Bags:OnProfileApplied()
        self.InvalidateSetCategories()
        self:SyncHeaderIcons()
        if self:IsShown() then
            self:RefreshInventory()
        end
        mod.RefreshOpenBank()
        CUI_CategoryManager:OnJunkChanged() -- the new profile may switch the Junk Marker
    end
end -- Junk Marker

EnterPinSelectMode = function()
    if mod.OfflineUp and mod.OfflineUp() then
        return
    end
    CUI_Bags._pinSelectMode = true

    -- Dark overlay covers the entire screen including bags
    if not CUI_Bags._pinOverlay then
        local shade = CreateFrame("Frame", nil, UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetFrameLevel(0)
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade.bg = shade:CreateTexture(nil, "BACKGROUND")
        shade.bg:SetAllPoints()
        shade.bg:SetColorTexture(0, 0, 0, 0.6)
        shade:SetScript("OnMouseDown", function()
            ExitPinSelectMode()
        end)
        -- Escape (and controller Back) ends the mode before closing the bags,
        -- through the escape proxy: the overlay takes no keyboard input
        CludesUI.RegisterEscapeClose(shade, {
            notOwned = true,
            onEscape = function()
                ExitPinSelectMode()
            end,
        })
        CUI_Bags._pinOverlay = shade
    end
    local shade = CUI_Bags._pinOverlay
    -- A fade-out still running from a quick exit would hide the dim mid-mode,
    -- and the exit turned its mouse off (clicks outside the grid end the mode)
    if shade._fadeOut then
        shade._fadeOut:Stop()
    end
    shade:EnableMouse(true)
    shade:SetAlpha(0)
    shade:Show()
    if not shade._fadeIn then
        local fg = shade:CreateAnimationGroup()
        local a = fg:CreateAnimation("Alpha")
        a:SetFromAlpha(0)
        a:SetToAlpha(1)
        a:SetDuration(0.15)
        fg:SetScript("OnFinished", function()
            shade:SetAlpha(1)
        end)
        shade._fadeIn = fg
    end
    shade._fadeIn:Play()

    -- Raise the scroll frame above the overlay so item icons are visible
    local scrollFrame = CUI_Bags._scrollFrame
    if scrollFrame then
        scrollFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    end

    local FindBtnUnderCursor = mod.SelectSlotUnderCursor

    -- Click catcher above the raised icons: swallows clicks (items aren't used/equipped), then pins whichever icon was clicked.
    if not CUI_Bags._pinCatcher then
        local castFrame = CreateFrame("Frame", nil, UIParent)
        castFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        castFrame:SetFrameLevel(500)
        castFrame:EnableMouse(true)
        -- Combat ends the mode (registered only while it is on)
        castFrame:SetScript("OnEvent", function()
            ExitPinSelectMode()
        end)

        -- Hover highlight: accent border (2px) + white overlay
        local pinHover = castFrame:CreateTexture(nil, "OVERLAY")
        pinHover:SetColorTexture(1, 1, 1, 0.4)
        pinHover:Hide()
        local pinHoveredBtn = nil
        local pinRed, pinSavedG, pinSavedB, pinSavedA
        local pinSavedBrdSize

        local function ClearPinHover()
            if pinHoveredBtn then
                if pinRed then
                    SetInsetBorderColor(pinHoveredBtn, pinRed, pinSavedG, pinSavedB, pinSavedA)
                end
                if pinSavedBrdSize then
                    SetInsetBorderThickness(pinHoveredBtn, pinSavedBrdSize)
                end
            end
            pinHoveredBtn = nil
            pinRed = nil
            pinSavedBrdSize = nil
            pinHover:ClearAllPoints()
            pinHover:Hide()
        end
        castFrame._clearHover = ClearPinHover

        -- Re-tests only when the cursor or the scroll moved, or on a show or a
        -- bag refresh (_hoverDirty); the wheel scrolls under a still cursor
        local lastX, lastY, lastScroll
        castFrame:SetScript("OnUpdate", function(self)
            local posX, posY = GetCursorPosition()
            local scrollFrame = CUI_Bags._scrollFrame
            local s = scrollFrame and scrollFrame:GetVerticalScroll() or 0
            if posX == lastX and posY == lastY and s == lastScroll and not self._hoverDirty then
                return
            end
            lastX, lastY, lastScroll = posX, posY, s
            self._hoverDirty = nil
            local button = FindBtnUnderCursor()
            if button == pinHoveredBtn then
                return
            end
            ClearPinHover()
            if button and button.icon and button.icon:IsShown() then
                pinRed, pinSavedG, pinSavedB, pinSavedA, pinSavedBrdSize = GetInsetBorderStyle(button)
                if pinRed then
                    local ar, ag, ab = GetAccentRGB()
                    SetInsetBorderColor(button, ar, ag, ab, 1)
                    local Pix = CUI and CUI.PP
                    local px2 = ((Pix and Pix.mult) or 1) * 2
                    SetInsetBorderThickness(button, px2)
                end
                pinHover:ClearAllPoints()
                pinHover:SetAllPoints(button)
                pinHover:Show()
                pinHoveredBtn = button
            end
        end)

        castFrame:SetScript("OnMouseDown", function(_, btnFrame)
            if btnFrame == "RightButton" then
                ClearPinHover()
                ExitPinSelectMode()
                return
            end
            local button = FindBtnUnderCursor()
            if button then
                local bagID = button:GetParent():GetID()
                local slotId = button:GetID()
                if bagID and slotId and slotId > 0 then
                    local details = C_Container.GetContainerItemInfo(bagID, slotId)
                    if details and details.itemID then
                        local isPinned = PinnedItems(true)
                        if not isPinned then
                            ClearPinHover()
                            ExitPinSelectMode()
                            return
                        end
                        local itemLink = C_Container.GetContainerItemLink(bagID, slotId)
                        local pinKey = NormalizePinKey(itemLink, details.itemID)
                        isPinned[pinKey] = (isPinned[pinKey] or 0) + 1
                        ClearPinHover()
                        ExitPinSelectMode()
                        CUI_Bags:RefreshInventory()
                        return
                    end
                end
            end
            ClearPinHover()
            ExitPinSelectMode()
        end)

        castFrame:SetScript("OnHide", function()
            ClearPinHover()
        end)
        CUI_Bags._pinCatcher = castFrame
    end
    -- Position catcher over the scroll frame area
    local scrollFrame = CUI_Bags._scrollFrame
    if scrollFrame and CUI.IS_FOREVER then
        -- WoW Forever: the window can grow while open (fit to content), so the catcher follows the scroll frame.
        CUI_Bags._pinCatcher:ClearAllPoints()
        CUI_Bags._pinCatcher:SetAllPoints(scrollFrame)
    elseif scrollFrame then
        local l, b, wid, hgt = scrollFrame:GetRect()
        if l and b and wid and hgt then
            CUI_Bags._pinCatcher:ClearAllPoints()
            CUI_Bags._pinCatcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            CUI_Bags._pinCatcher:SetSize(wid, hgt)
        end
    end
    CUI_Bags._pinCatcher._hoverDirty = true
    CUI_Bags._pinCatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    CUI_Bags._pinCatcher:Show()
end

Inner.ExitAssignSelectMode, Inner.ExitPinSelectMode = ExitAssignSelectMode, ExitPinSelectMode
Inner.GetOrCreateAssignOverlay = GetOrCreateAssignOverlay
Inner.GetOrCreatePinOverlay, Inner.ResetAssignOverlays = GetOrCreatePinOverlay, ResetAssignOverlays
Inner.broken = false
