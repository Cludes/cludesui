if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Start.lua
--
--  StartAddon, the loader and what CludesUIBags_Grid.lua, _List, _Compact
--  and _Bank read from ns.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local Inner = mod._bagsInternals
-- CludesUIBags.lua or an earlier CUI_Bags_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = CludesUI

local ApplyBagScale, BagsItemUnusable, BP = Inner.ApplyBagScale, Inner.BagsItemUnusable, Inner.BP
local CurrencyOrder, GetAccentRGB = Inner.CurrencyOrder, Inner.GetAccentRGB
local GetCatTitleSize, GetDefaultBagType = Inner.GetCatTitleSize, Inner.GetDefaultBagType
local GetFont, SetBagFont, SLOT_SIZE, SPACING =
    Inner.GetFont, Inner.SetBagFont, Inner.SLOT_SIZE, Inner.SPACING
local ApplySavedOrder = Inner.ApplySavedOrder
local ArmorySlotGroupingEnabled = Inner.ArmorySlotGroupingEnabled
local BuildExpansionBuckets, BuildSlotBuckets = Inner.BuildExpansionBuckets, Inner.BuildSlotBuckets
local GetArmorySlotBucket, IsArmoryGearCategory = Inner.GetArmorySlotBucket, Inner.IsArmoryGearCategory
local IsGearOnlyGroup, itemSlots = Inner.IsGearOnlyGroup, Inner.itemSlots
local MergeDuplicates, PreCacheSortFields = Inner.MergeDuplicates, Inner.PreCacheSortFields
local RegisterPawnIntegration, SetItemPanelOpen = Inner.RegisterPawnIntegration, Inner.SetItemPanelOpen
local UpdatePawnArrow, VisualSortCompare = Inner.UpdatePawnArrow, Inner.VisualSortCompare
local CreateHeader, CreateFooter = Inner.CreateHeader, Inner.CreateFooter
local CreateReagentBagUI, GoldLedger = Inner.CreateReagentBagUI, Inner.GoldLedger
local OnGoldChanged, SyncBagFrameToFooter = Inner.OnGoldChanged, Inner.SyncBagFrameToFooter
local CreateInsetBorder, QUEST_BORDER_COLOR = Inner.CreateInsetBorder, Inner.QUEST_BORDER_COLOR
local SetInsetBorderColor = Inner.SetInsetBorderColor
local SetInsetBorderThickness, _itemDragFrame = Inner.SetInsetBorderThickness, Inner._itemDragFrame
local ExitAssignSelectMode, ExitPinSelectMode = Inner.ExitAssignSelectMode, Inner.ExitPinSelectMode
local GetOrCreateAssignOverlay = Inner.GetOrCreateAssignOverlay
local GetOrCreatePinOverlay = Inner.GetOrCreatePinOverlay
local ResetAssignOverlays, CreateSidebar = Inner.ResetAssignOverlays, Inner.CreateSidebar
local _catHeaders, _expSubHeaders = Inner._catHeaders, Inner._expSubHeaders
local CreateBagScrollFrame = Inner.CreateBagScrollFrame
local GetOrCreateCatHeader = Inner.GetOrCreateCatHeader
local GetOrCreateExpSubHeader = Inner.GetOrCreateExpSubHeader
local ShowRecentClearButton = Inner.ShowRecentClearButton
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
local _anyItemPanelOpen = Inner._anyItemPanelOpen
Inner.anyItemPanelOpenSetters[#Inner.anyItemPanelOpenSetters + 1] = function(val)
    _anyItemPanelOpen = val
end

-- Unmerge state the CURRENT painted layout was built with; the bags OnShow
-- compares against it so a flip while hidden still repaints (closing a
-- mailbox hides both). Written by the earlier files through
-- SetPaintedPanelOpen, read here only.
local _paintedPanelOpen = false
Inner.paintedPanelOpenSetters[#Inner.paintedPanelOpenSetters + 1] = function(val)
    _paintedPanelOpen = val
end

-------------------------------------------------------------------------------
--  StartAddon
-------------------------------------------------------------------------------
local function StartAddon()
    RegisterPawnIntegration()

    -- Apply default view based on setting (DB now available)
    local _dbt = GetDefaultBagType()
    if _dbt == "onebag" then
        SetSelectedCategoryIndex(-1)
    elseif _dbt == "multibag" then
        SetSelectedCategoryIndex(-2)
    end

    GoldLedger.Register("bags", OnGoldChanged)

    -- Position: default 50px from bottom-left, saved position overrides
    if BP().bagsPosition then
        local place = BP().bagsPosition
        CUI_Bags:SetPoint(place.point, UIParent, place.relativePoint, place.x, place.y)
    else
        CUI_Bags:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -50, 50)
    end

    CUI_Bags:SetClampedToScreen(true)
    CUI_Bags:ApplyWindowLayering()
    CUI_Bags:EnableMouse(true)
    CUI_Bags:SetMovable(true)

    -- Bag frame drag: left-drag while unlocked, OnMouseDown/OnUpdate pattern (no RegisterForDrag)
    local _bagDragging = false
    local _bagDragStartCX, _bagDragStartCY = 0, 0
    local _bagDragStartLeft, _bagDragStartTop = 0, 0
    local _bagDragFrame = CreateFrame("Frame")
    _bagDragFrame:Hide()
    _bagDragFrame:SetScript("OnUpdate", function(self)
        if not _bagDragging then
            self:Hide()
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            _bagDragging = false
            self:Hide()
            local leftX, topY = CUI_Bags:GetLeft(), CUI_Bags:GetTop()
            if leftX and topY then
                local Pix = CUI and CUI.PP
                if Pix and Pix.Snap then
                    leftX = Pix.Snap(leftX)
                    topY = Pix.Snap(topY)
                end
                BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = leftX, y = topY }
                CUI_Bags:ClearAllPoints()
                CUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
            end
            return
        end
        local cursorX, cursorY = GetCursorPosition()
        local effScale = CUI_Bags:GetEffectiveScale()
        local newLeft = _bagDragStartLeft + (cursorX / effScale - _bagDragStartCX)
        local newTop = _bagDragStartTop + (cursorY / effScale - _bagDragStartCY)
        CUI_Bags:ClearAllPoints()
        CUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
    CUI_Bags:SetScript("OnMouseDown", function(self, btnFrame)
        self:Raise()
        self:RepinIconLevels()
        -- Locked (the footer's lock icon): the window stays put. Nor does it move
        -- while something is on the cursor: a click on its empty space drops an
        -- item from outside the bags (the OnMouseUp hook below).
        if btnFrame ~= "LeftButton" or BP().bagWindowLocked or GetCursorInfo() then
            return
        end
        local cursorX, cursorY = GetCursorPosition()
        local effScale = self:GetEffectiveScale()
        _bagDragStartCX = cursorX / effScale
        _bagDragStartCY = cursorY / effScale
        _bagDragStartLeft = self:GetLeft()
        _bagDragStartTop = self:GetTop()
        if not _bagDragStartLeft or not _bagDragStartTop then
            return
        end
        _bagDragging = true
        _bagDragFrame:Show()
    end)
    CUI_Bags:SetScript("OnMouseUp", function(_, btnFrame)
        if btnFrame == "LeftButton" and _bagDragging then
            _bagDragging = false
            _bagDragFrame:Hide()
            local leftX, topY = CUI_Bags:GetLeft(), CUI_Bags:GetTop()
            if leftX and topY then
                local Pix = CUI and CUI.PP
                if Pix and Pix.Snap then
                    leftX = Pix.Snap(leftX)
                    topY = Pix.Snap(topY)
                end
                BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = leftX, y = topY }
                CUI_Bags:ClearAllPoints()
                CUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
            end
        end
    end)

    CUI_Bags.bg = CUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 0)
    CUI_Bags.bg:SetAllPoints()
    CUI_Bags.bg:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    CUI_Bags.bg:SetTexCoord(0, 1, 0, 1)

    -- Dark overlay on top of the atlas (25% black)
    CUI_Bags.bgOverlay = CUI_Bags:CreateTexture(nil, "BACKGROUND", nil, 1)
    CUI_Bags.bgOverlay:SetAllPoints()
    CUI_Bags.bgOverlay:SetColorTexture(0, 0, 0, 0.25)

    if
        not mod.SkinForeverBagWindow(CUI_Bags, CUI_Bags.bg, CUI_Bags.bgOverlay, true, true) and CUI.PanelPP
    then
        CUI.PanelPP.CreateBorder(CUI_Bags, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    local PadBagsShown -- controller cursor show edge (defined below)

    -- Blizzard's backpack open/close sounds, played on the frame's show/hide
    -- transitions as Blizzard's container frames do: a Show on an already open
    -- bag fires no OnShow, and the login pre-build never shows the frame.
    CUI_Bags:HookScript("OnShow", function(self)
        self:Raise()
        self:RepinIconLevels()
        PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
        -- Repaint if the unmerge state changed while hidden: the flag-flip refresh is gated on
        -- IsVisible, and closing a mailbox hides bags in the same breath so that repaint is thrown away (costs one boolean compare when already matching).
        -- Same for session unmerge marks: the close that hid the bags wiped
        -- them, so a layout painted with marks must merge again on show.
        if _paintedPanelOpen ~= _anyItemPanelOpen or CUI_Bags._paintedUnmerged then
            CUI_Bags:RefreshInventory()
        end
        -- Controller cursor: scroll aids and the carried-item drop button,
        -- built only once a controller is in use.
        if CUI_Bags._padBuilt or CUI.PadInUse() then
            PadBagsShown()
        end
        -- The one-time "categories can be dragged" tip, until its Okay
        if not CludesUIDB.bagCategoryTipSeen then
            mod.ShowCategoryTip()
        end
    end)

    CUI_Bags:HookScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        CUI_Bags._closeSoundAt = GetTime()
        -- A tip left up without Okay must not come back with the window (in combat too)
        if CUI_Bags._catTip then
            CUI_Bags._catTip:Hide()
        end
        if CUI_Bags._searchBox then
            CUI_Bags._searchBox:SetText("")
            CUI_Bags._searchBox:ClearFocus()
        end
    end)

    -- An item on the cursor that is not from the player's bags (bank withdrawals, mail, etc.).
    local function CursorItemIsExternal()
        if GetCursorInfo() ~= "item" then
            return false
        end
        -- The cursor item's own location is its pickup source: a slot of the
        -- player's bags (bag 0-5, reagent bag included) when it came from them.
        local location = C_Cursor.GetCursorItem()
        if location and location:IsBagAndSlot() then
            local bagId = location:GetBagAndSlot()
            if bagId >= 0 and bagId <= 5 then
                return false
            end
        end
        return true
    end
    -- External item: place in first empty bag slot (same as looting), never in
    -- a WoW Forever special bag.
    local function PlaceExternalCursorItem()
        if not CursorItemIsExternal() then
            return
        end
        local special = mod.SpecialBags()
        for bagId = 0, 4 do
            local slotCount = (special and special[bagId]) and 0 or C_Container.GetContainerNumSlots(bagId)
            for slotId = 1, slotCount do
                if not C_Container.GetContainerItemInfo(bagId, slotId) then
                    C_Container.PickupContainerItem(bagId, slotId)
                    return
                end
            end
        end
    end
    -- Click or drag release on empty bag window space with an item from
    -- outside the bags (bank, mail, ...) on the cursor: it goes to the first
    -- empty bag slot. An item picked up from the bags stays on the cursor.
    CUI_Bags:HookScript("OnMouseUp", function(_, btnFrame)
        if btnFrame == "LeftButton" then
            PlaceExternalCursorItem()
        end
    end)
    CUI_Bags:SetScript("OnReceiveDrag", PlaceExternalCursorItem)

    -- Drop target: while an item from outside the bags is on the cursor, a
    -- catch layer over the item area's empty space takes the same drop and the
    -- window lights its border. The layer sits UNDER the slots, so a drop on a
    -- slot always reaches the slot (stack merges, gear swaps). Whether the
    -- cursor item is from outside is read from its location, cached until the
    -- cursor or an item lock changes; the Compact display's drop zones read the same cache
    -- and follow the same watch. The events are registered only while the
    -- bags are open; everything is built on first use.
    local dropEdge, dropCatcher
    local hoverFrame, hoverCatch = false, false
    local extCache, extrasStale = false, true
    function mod.CursorItemExternalCached()
        if extrasStale then
            extCache = CursorItemIsExternal()
            extrasStale = false
        end
        return extCache
    end
    local function SyncDropBorder()
        local layer = mod.CursorItemExternalCached() and CUI_Bags:IsVisible()
        if layer and not dropCatcher then
            dropCatcher = CreateFrame("Frame", nil, CUI_Bags)
            dropCatcher:Hide()
            dropCatcher:EnableMouse(true)
            dropCatcher:EnableMouseWheel(true)
            dropCatcher:SetScript("OnMouseWheel", function(_, delta)
                local scrollFrame = CUI_Bags._scrollFrame
                local wheel = scrollFrame and scrollFrame:GetScript("OnMouseWheel")
                if wheel then
                    wheel(scrollFrame, delta)
                end
            end)
            dropCatcher:SetScript("OnMouseUp", function(_, btnFrame)
                if btnFrame == "LeftButton" then
                    PlaceExternalCursorItem()
                end
            end)
            dropCatcher:SetScript("OnReceiveDrag", PlaceExternalCursorItem)
            dropCatcher:SetScript("OnEnter", function()
                hoverCatch = true
                SyncDropBorder()
            end)
            dropCatcher:SetScript("OnLeave", function()
                hoverCatch = false
                SyncDropBorder()
            end)
            dropCatcher:SetScript("OnHide", function()
                hoverCatch = false
            end)
        end
        if dropCatcher then
            if layer and not dropCatcher:IsShown() then
                -- Just above the window, under the slots.
                dropCatcher:SetFrameLevel(CUI_Bags:GetFrameLevel() + 1)
                dropCatcher:ClearAllPoints()
                dropCatcher:SetAllPoints(CUI_Bags._scrollFrame)
            end
            dropCatcher:SetShown(layer and true or false)
        end
        local enabled = layer and (hoverFrame or hoverCatch)
        if enabled and not dropEdge then
            dropEdge = CreateFrame("Frame", nil, CUI_Bags)
            dropEdge:SetAllPoints()
            dropEdge:SetFrameLevel(CUI_Bags:GetFrameLevel() + 60)
            dropEdge:EnableMouse(false)
            CreateInsetBorder(dropEdge)
        end
        if not dropEdge then
            return
        end
        if enabled then
            local region, g, bl = GetAccentRGB()
            SetInsetBorderColor(dropEdge, region, g, bl, 1)
        end
        dropEdge:SetShown(enabled and true or false)
    end
    CUI_Bags._syncDropTarget = SyncDropBorder
    CUI_Bags:HookScript("OnEnter", function()
        hoverFrame = true
        SyncDropBorder()
    end)
    CUI_Bags:HookScript("OnLeave", function()
        hoverFrame = false
        SyncDropBorder()
    end)
    local cursorWatcher = CreateFrame("Frame")
    cursorWatcher:SetScript("OnEvent", function(_, eventName)
        extrasStale = true
        -- A lock change only matters with an item on the cursor (the pickup's
        -- source slot locks); sorts lock and unlock slots constantly.
        if eventName == "CURSOR_CHANGED" or GetCursorInfo() == "item" then
            SyncDropBorder()
            -- The Compact display's drop zones (CludesUIBags_Compact.lua)
            mod.CompactZonesSync()
        end
    end)
    CUI_Bags:HookScript("OnShow", function()
        cursorWatcher:RegisterEvent("CURSOR_CHANGED")
        cursorWatcher:RegisterEvent("ITEM_LOCK_CHANGED")
        extrasStale = true
    end)
    CUI_Bags:HookScript("OnHide", function()
        cursorWatcher:UnregisterEvent("CURSOR_CHANGED")
        cursorWatcher:UnregisterEvent("ITEM_LOCK_CHANGED")
        hoverFrame = false
        extrasStale = true
        SyncDropBorder()
    end)

    -- Controller cursor: empty slots take no presses in the All Items and
    -- category views, so an item carried in from the bank or mail gets a
    -- "Place in Bags" footer button. The cursor watch is registered only
    -- while the bags are open with a controller in use.
    local function PadPlaceSync()
        CUI_Bags._padPlaceBtn:SetShown(CursorItemIsExternal())
    end
    local function PadPlaceButton()
        local footerBar = CUI_Bags.Footer
        local widget = CreateFrame("Button", nil, footerBar)
        widget:SetHeight(22)
        widget:SetPoint("BOTTOMLEFT", footerBar, "BOTTOMLEFT", 8, 5)
        widget:SetFrameLevel(footerBar:GetFrameLevel() + 20)
        local backdrop = widget:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        local Pix = CUI and CUI.PP
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(widget, 0.25, 0.25, 0.25, 1)
        end
        local fontStr = widget:CreateFontString(nil, "OVERLAY")
        SetBagFont(fontStr, 11)
        fontStr:SetPoint("CENTER", 0, 0)
        fontStr:SetTextColor(1, 1, 1, 0.9)
        fontStr:SetText(CludesUI.L("Place in Bags"))
        widget:SetWidth(fontStr:GetStringWidth() + 20)
        widget:SetScript("OnEnter", function()
            backdrop:SetColorTexture(0.2, 0.2, 0.2, 1)
        end)
        widget:SetScript("OnLeave", function()
            backdrop:SetColorTexture(0.15, 0.15, 0.15, 1)
        end)
        widget:SetScript("OnClick", function()
            PlaceExternalCursorItem()
        end)
        widget:Hide()
        CUI_Bags._padPlaceBtn = widget
        local watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", PadPlaceSync)
        CUI_Bags._padCursorWatch = watcher
    end
    -- Show edge (gated at the call): scroll aids, sidebar steps, drop button.
    PadBagsShown = function()
        local enabled = CUI.PadInUse()
        CUI_Bags._padBuilt = true
        if CUI_Bags._scrollTrack then
            CUI_Bags._scrollTrack.PadSync(enabled)
        end
        mod.PadSidebarSync(
            CUI_Bags._sidebarHdr,
            CUI_Bags._sidebarSF,
            CUI_Bags._sidebarChild,
            "bagSidebarCollapsed",
            enabled
        )
        local watcher = CUI_Bags._padCursorWatch
        if enabled then
            if not watcher then
                PadPlaceButton()
                watcher = CUI_Bags._padCursorWatch
            end
            watcher:RegisterEvent("CURSOR_CHANGED")
            watcher:RegisterEvent("ITEM_LOCK_CHANGED")
            PadPlaceSync()
        elseif watcher then
            watcher:UnregisterAllEvents()
            CUI_Bags._padPlaceBtn:Hide()
        end
    end

    CreateHeader()
    CreateFooter()
    CreateSidebar()
    CreateBagScrollFrame()
    CreateReagentBagUI()

    -- Bag overview window
    CUI_BagsWindow:SetSize(280, 80)
    CUI_BagsWindow:SetPoint("BOTTOMRIGHT", CUI_Bags._bagsBtn, "TOPRIGHT", 0, 2)
    CUI_BagsWindow:SetFrameStrata(CUI_Bags:GetFrameStrata())
    CUI_BagsWindow:SetToplevel(true)
    -- Toplevel only raises on a click: opening it brings it forward too, over
    -- a panel (Auction House, bank) raised after the bags.
    CUI_BagsWindow:HookScript("OnShow", CUI_BagsWindow.Raise)
    CUI_BagsWindow:EnableMouse(true)
    CUI_BagsWindow.bg = CUI_BagsWindow:CreateTexture(nil, "BACKGROUND")
    CUI_BagsWindow.bg:SetAllPoints()
    CUI_BagsWindow.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if not mod.SkinForeverBagWindow(CUI_BagsWindow, CUI_BagsWindow.bg) and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(CUI_BagsWindow, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end
    CludesUI.RegisterEscapeClose(CUI_BagsWindow)

    CUI_BagsReagent:SetSize(320, 300)
    CUI_BagsReagent:SetPoint("BOTTOMRIGHT", CUI_Bags, "BOTTOMLEFT", -10, 0)
    CUI_BagsReagent:SetFrameStrata(CUI_Bags:GetFrameStrata())
    CUI_BagsReagent:SetToplevel(true)
    CUI_BagsReagent:HookScript("OnShow", function(self)
        self:Raise()
        -- Re-pins the reagent pool too
        CUI_Bags:RepinIconLevels()
    end)
    CUI_BagsReagent:EnableMouse(true)
    CUI_BagsReagent.bg = CUI_BagsReagent:CreateTexture(nil, "BACKGROUND")
    CUI_BagsReagent.bg:SetAllPoints()
    CUI_BagsReagent.bg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    if not mod.SkinForeverBagWindow(CUI_BagsReagent, CUI_BagsReagent.bg, nil, true, true) and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(CUI_BagsReagent, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)
    end

    CUI_BagsReagent:RegisterEvent("BAG_UPDATE")
    CUI_BagsReagent:SetScript("OnEvent", function(self, eventName)
        if eventName == "BAG_UPDATE" then
            local detached = BP().detachReagentBag or false
            if detached and CUI_BagsReagent:IsVisible() then
                CUI_BagsReagent:RefreshInventory()
            end
        end
    end)
    CludesUI.RegisterEscapeClose(CUI_BagsReagent)
    -- The detached reagent bag closed on its own plays the backpack close
    -- sound. Silent when the main bag closed in the same frame (it already
    -- played) or when only its parent hid (its own shown flag is still set).
    CUI_BagsReagent:HookScript("OnHide", function(self)
        if not self:IsShown() and CUI_Bags._closeSoundAt ~= GetTime() then
            PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
        end
    end)

    local OriginalToggleAllBags = ToggleAllBags
    local function CloseBags()
        CUI_Bags:Hide()
        CUI_BagsReagent:Hide()
        if not CludesUIDB then
            CludesUIDB = {}
        end
        CludesUIDB.bagsVisible = false
        -- Controller cursor: keep Blizzard's hidden bag frames closed too.
        if CUI.PadInUse() then
            mod.PadReleaseBlizzBags()
        end
    end
    local function ToggleCUI()
        if CUI_Bags:IsVisible() then
            CloseBags()
        else
            -- Controller cursor: gamepad pointer on at this user-requested
            -- open, as Blizzard's own bag toggle does (one C call when no
            -- gamepad is active).
            if CUI.PadNative() then
                CUI.RaiseGamePadCursor()
                -- WoW Forever: the Gamepad interface style was switched on
                -- since login. Its D-pad cannot reach our bags, so they stay
                -- closed until a reload.
                if CUI.IS_FOREVER and CUI.PadGamepadUI() then
                    mod.PadStyleChanged()
                    return
                end
            end
            ApplyBagScale()
            CUI_Bags:Show()
            CUI_Bags:RefreshInventory()
            if not CludesUIDB then
                CludesUIDB = {}
            end
            -- Seed default pinned items on first ever open
            if not CludesUIDB.bagPinsSeeded then
                CludesUIDB.bagPinsSeeded = true
                if not CludesUIDB.bagPinnedItems then
                    CludesUIDB.bagPinnedItems = {}
                end
                CludesUIDB.bagPinnedItems[6948] = 1 -- Hearthstone
                CludesUIDB.bagPinnedItems[180653] = 1 -- Nomi Snacks
            end
            -- Auto-sort on first ever open
            if not CludesUIDB.bagInitialSortDone and CUI_Bags._doVisualSort then
                CludesUIDB.bagInitialSortDone = true
                CUI_Bags._doVisualSort()
            end
            CludesUIDB.bagsVisible = true
            local detached = BP().detachReagentBag or false
            if detached then
                CUI_BagsReagent:Show()
                CUI_BagsReagent:RefreshInventory()
            end
        end
    end

    local characterBagHooksInstalled = false
    function mod.ToggleBagsWithCharacterFrame()
        if not BP().bagOpenWithCharacter then
            return
        end
        -- WoW Forever's Gamepad interface style: no hooks on Blizzard windows (see the stand-down below).
        if mod.PadUIStandDown() then
            return
        end
        local widget = _G.CharacterFrame
        if not widget then
            return
        end
        if not characterBagHooksInstalled then
            characterBagHooksInstalled = true
            widget:HookScript("OnShow", function()
                if BP().bagOpenWithCharacter and not CUI_Bags:IsVisible() then
                    ToggleCUI()
                end
            end)
            widget:HookScript("OnHide", function()
                if BP().bagOpenWithCharacter and CUI_Bags:IsVisible() then
                    ToggleCUI()
                end
            end)
        end
    end
    mod.ToggleBagsWithCharacterFrame()

    local _lastToggleTime = 0
    local _visibleBeforeToggle = false
    local function SmartToggleBags()
        -- Debounce: Blizzard keybinds can fire both ToggleAllBags and C_Container.ToggleAllBags in the same frame, causing a double-toggle.
        if GetTime() == _lastToggleTime then
            return
        end
        _lastToggleTime = GetTime()
        _visibleBeforeToggle = CUI_Bags:IsVisible()
        local enhancedEnabled = BP().enhancedBags ~= false
        if enhancedEnabled then
            ToggleCUI()
        else
            if OriginalToggleAllBags then
                OriginalToggleAllBags()
            end
        end
    end

    -- WoW Forever with the Gamepad interface style at login: Blizzard's own
    -- bags keep the D-pad navigation, so none of the takeover below runs
    -- (false on retail and for every other Forever player).
    if mod.PadUIStandDown() then
        -- A switch back to another style: the takeover follows a reload.
        local function StyleCheck()
            if not CUI.PadGamepadUI() then
                mod.PadStyleChanged()
            end
        end
        hooksecurefunc("ToggleAllBags", StyleCheck)
        hooksecurefunc("ToggleBackpack", StyleCheck)
    else
        ToggleAllBags = SmartToggleBags
        -- Hook ToggleBackpack/ToggleBag via hooksecurefunc (avoids tainting the global)
        hooksecurefunc("ToggleBackpack", SmartToggleBags)

        -- Hide Blizzard bag frames by reparenting to a hidden container (never write .Show/.Hide onto Blizzard frames -- causes taint).
        local _blizzBagHidden = CreateFrame("Frame")
        _blizzBagHidden:Hide()
        -- The same rect as Blizzard's ContainerFrameContainer (all of UIParent):
        -- UpdateContainerFrameAnchors pins the first open bag to its parent, and a
        -- bag that opens while parented here (the keyring below) keeps that pin
        -- after it is let out, so a rectless container left it with no position.
        _blizzBagHidden:SetAllPoints(UIParent)

        -- WoW Forever's keyring (bag -1) has no place in our bag window, so its
        -- button keeps opening Blizzard's own keyring window: the one bag frame
        -- let back out of the hidden container while it shows.
        local KEYRING = CUI.IS_FOREVER and Enum.BagIndex and Enum.BagIndex.Keyring or nil
        local function IsKeyringFrame(frame)
            return KEYRING ~= nil and frame:IsShown() and frame.MatchesBagID ~= nil and frame:MatchesBagID(KEYRING)
        end

        local function KillBlizzard()
            for i = 1, 13 do
                local frame = _G["ContainerFrame" .. i]
                if frame and not IsKeyringFrame(frame) then
                    frame:SetParent(_blizzBagHidden)
                end
            end
            if ContainerFrameCombinedBags then
                ContainerFrameCombinedBags:SetParent(_blizzBagHidden)
            end
        end
        KillBlizzard()

        local keyringHooked = setmetatable({}, { __mode = "k" })
        hooksecurefunc("ToggleBag", function(ident)
            if KEYRING and ident == KEYRING then
                -- Blizzard just opened or closed it; only an open one comes out.
                local frame = ContainerFrameUtil_GetShownFrameForID
                    and ContainerFrameUtil_GetShownFrameForID(KEYRING)
                if frame then
                    frame:SetParent(ContainerFrameContainer or UIParent)
                    if not keyringHooked[frame] then
                        keyringHooked[frame] = true
                        -- The frames are shared: once closed (its own shown flag
                        -- clear, not just a hidden UI), any bag it shows next stays hidden.
                        frame:HookScript("OnHide", function(self)
                            if not self:IsShown() then
                                self:SetParent(_blizzBagHidden)
                            end
                        end)
                    end
                end
                return
            end
            SmartToggleBags()
        end)

        -- Window that auto-opened the bags (merchant, mail, auction house, ...)
        local bagsOpener
        hooksecurefunc("OpenAllBags", function(widget)
            -- Blizzard's OpenBackpack can call ToggleBackpack first, which already
            -- flipped our window this frame: read its state from before that.
            local wasVisible = CUI_Bags:IsVisible()
            if _lastToggleTime == GetTime() then
                wasVisible = _visibleBeforeToggle
            end
            local isOpen = wasVisible or mod.BagAutoWindowOn("bagAutoOpenWindows", mod.BagAutoWindowKey(widget))
            if isOpen and not CUI_Bags:IsVisible() then
                ToggleCUI()
            elseif not isOpen and CUI_Bags:IsVisible() then
                CloseBags()
            end
            if isOpen and not wasVisible then
                bagsOpener = widget
            end
            KillBlizzard()
        end)
        -- Close with that window; frame is nil for non-window closes
        hooksecurefunc("CloseAllBags", function(widget)
            if not widget or widget ~= bagsOpener then
                return
            end
            bagsOpener = nil
            if
                CUI_Bags:IsShown()
                and mod.BagAutoWindowOn("bagAutoCloseWindows", mod.BagAutoWindowKey(widget))
            then
                CloseBags()
            end
        end)
        -- Closed by hand: a later open is the player's, so it stays open.
        -- Alt-Z also fires OnHide but leaves IsShown true.
        CUI_Bags:HookScript("OnHide", function(self)
            if not self:IsShown() then
                bagsOpener = nil
            end
        end)
    end -- not ns.PadUIStandDown()

    -- Recent Items: session-only tracking (resets on login/reload)
    -- Raised from 12 to 15.
    local RECENT_MAX = 15
    CUI_Bags._recentItems = {} -- itemID -> pickup number (higher = newer; ns.RecentCompare sorts by it)
    CUI_Bags._recentOrder = {} -- ordered list of itemIDs (oldest first)
    CUI_Bags._recentSeq = 0 -- last pickup number handed out
    local _knownItemCounts = {} -- itemID -> highest carried count (bags + worn gear) since the last bank/mail resync
    local _snapshotReady = false

    -- Both are interaction state, not frame visibility -- a third-party bank/mail
    -- addon can hide the stock frame, but the server-tracked interaction stays
    -- accurate. Bank/warband bank contents are only queryable while physically
    -- there (or via a Personal Distance Inhibitor), so unlike mail there's no
    -- way to count them from a distance -- detection just freezes at the bank
    -- instead, the same as it does for mail.
    local function MailOpen()
        return (
            C_PlayerInteractionManager
            and C_PlayerInteractionManager.IsInteractingWithNpcOfType
            and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.MailInfo)
        )
                and true
            or false
    end
    local function BankOpen()
        if not (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType) then
            return false
        end
        local PIT, IsAt = Enum.PlayerInteractionType, C_PlayerInteractionManager.IsInteractingWithNpcOfType
        -- some bankers open the character bank as CharacterBanker
        return (
            IsAt(PIT.Banker)
            or (PIT.CharacterBanker and IsAt(PIT.CharacterBanker))
            or IsAt(PIT.AccountBanker)
        )
                and true
            or false
    end

    -- One total per item across the bags AND worn gear: equipping, taking off
    -- and equipment set swaps only move an item between the two, so its total
    -- holds and nothing re-flags, while loot still raises it. Slots 1-30 are
    -- gear and profession gear, 31-35 the equipped bags; a worn stack (a thrown
    -- weapon stack on WoW Forever) counts by its size. The ammo slot (0) is
    -- skipped: it names a type whose ammo is already counted in the bags.
    local function TallyItemCounts()
        local counts, sequence = {}, {}
        for bagId = 0, 5 do
            local slotCount = C_Container.GetContainerNumSlots(bagId)
            for slotId = 1, slotCount do
                local details = C_Container.GetContainerItemInfo(bagId, slotId)
                if details and details.itemID then
                    if not counts[details.itemID] then
                        sequence[#sequence + 1] = details.itemID
                    end
                    counts[details.itemID] = (counts[details.itemID] or 0) + (details.stackCount or 0)
                end
            end
        end
        for slotId = INVSLOT_FIRST_EQUIPPED, CONTAINER_BAG_OFFSET + NUM_TOTAL_EQUIPPED_BAG_SLOTS do
            local itemId = GetInventoryItemID("player", slotId)
            if itemId then
                if not counts[itemId] then
                    sequence[#sequence + 1] = itemId
                end
                counts[itemId] = (counts[itemId] or 0) + (GetInventoryItemCount("player", slotId) or 1)
            end
        end
        return counts, sequence
    end

    local function SnapshotKnownIDs()
        _knownItemCounts = TallyItemCounts()
        _snapshotReady = true
    end

    -- A rise flags a new pickup; a drop (sold/used/deleted) lowers the known
    -- total so a later re-acquisition below the old peak still registers as
    -- new. Frozen entirely at a bank/warband bank -- depositing and withdrawing
    -- look identical to disposing of and looting, since bag contents are all
    -- this can see. MAIL_CLOSED, BANKFRAME_CLOSED, and
    -- PLAYER_INTERACTION_MANAGER_FRAME_HIDE below silently resync once the
    -- mailbox/bank closes, so none of that traffic falsely flags or evicts
    -- anything.
    --
    -- A mailbox is only half that problem, so it no longer freezes both ways: a
    -- RISE there can only be an item arriving (sending lowers a count, never
    -- raises one), which is what left auction returns landing with no trace.
    -- Drops stay ignored: sent, sold and deleted are indistinguishable.
    local function DetectNewItems()
        if not _snapshotReady or BankOpen() then
            return
        end
        local atMail = MailOpen()
        local counts, sequence = TallyItemCounts()
        for _, itemId in ipairs(sequence) do
            local total = counts[itemId]
            local known = _knownItemCounts[itemId] or 0
            if total > known then
                -- New, or more of a listed item: either way it is the newest now
                local recent, ro = CUI_Bags._recentItems, CUI_Bags._recentOrder
                if recent[itemId] then
                    for i = #ro, 1, -1 do
                        if ro[i] == itemId then
                            table.remove(ro, i)
                            break
                        end
                    end
                end
                CUI_Bags._recentSeq = CUI_Bags._recentSeq + 1
                recent[itemId] = CUI_Bags._recentSeq
                ro[#ro + 1] = itemId
                while #ro > RECENT_MAX do
                    recent[table.remove(ro, 1)] = nil
                end
            end
            if not atMail or total > known then
                _knownItemCounts[itemId] = total
            end
        end
        -- Items gone entirely (sold/used/deleted) no longer appear in `counts`;
        -- drop their known peak too. Worn gear is in `counts`, so an equipped
        -- item keeps its peak and taking it off later re-flags nothing.
        -- Skipped at the mailbox for the same reason drops are ignored above: an item
        -- gone from bags there was as likely posted or sent as disposed of, and
        -- dropping its peak would re-flag it as new the moment it came back.
        if not atMail then
            for itemId in pairs(_knownItemCounts) do
                if not counts[itemId] then
                    _knownItemCounts[itemId] = nil
                end
            end
        end
    end

    -- "Clear" link on the Recent Items headers. Only the tracked set is dropped --
    -- _knownItemCounts already holds each item's current carried total, so nothing
    -- sitting in bags re-flags as new on the next DetectNewItems pass.
    function CUI_Bags:ClearRecentItems()
        wipe(CUI_Bags._recentItems)
        wipe(CUI_Bags._recentOrder)
        if CUI_Bags:IsVisible() then
            CUI_Bags:RefreshInventory()
        end
    end

    C_Timer.After(1, function()
        SnapshotKnownIDs()
    end)

    -- Debounced full refresh: one code path, no stale state. The first paint of a
    -- window stays at 0.1 s. When events kept landing during that window a burst is
    -- under way, so the NEXT windows re-arm on the trailing edge instead (at most
    -- four 0.1 s deferrals): a loot or vendor burst that fires BAG_UPDATE every few
    -- frames rebuilds about twice a second and once more after it settles, instead
    -- of ten times a second for the whole burst. An isolated event is untouched.
    local refreshPending, rerun, refreshDefers, refreshBurst = false, false, 0, false
    CUI_Bags.refreshEnabled = true
    local function FireRefresh()
        if refreshBurst and rerun and refreshDefers < 4 then
            rerun = false
            refreshDefers = refreshDefers + 1
            C_Timer.After(0.1, FireRefresh)
            return
        end
        refreshBurst = rerun
        if CUI_Bags:IsVisible() then
            CUI_Bags:RefreshInventory()
            local detached = BP().detachReagentBag or false
            if detached and CUI_BagsReagent:IsVisible() then
                CUI_BagsReagent:RefreshInventory()
            end
        end
        refreshPending, rerun, refreshDefers = false, false, 0
    end
    local function ScheduleRefresh()
        if not CUI_Bags.refreshEnabled then
            return
        end
        if refreshPending then
            rerun = true
            return
        end
        refreshPending, rerun, refreshDefers = true, false, 0
        C_Timer.After(0.1, FireRefresh)
    end

    CUI_Bags:RegisterEvent("BAG_UPDATE")
    -- Equipping / unequipping a bag: its BAG_UPDATE can land before the slot
    -- counts change; BAG_UPDATE_DELAYED fires once the whole batch settles
    CUI_Bags:RegisterEvent("BAG_UPDATE_DELAYED")
    CUI_Bags:RegisterEvent("ITEM_LOCK_CHANGED")
    CUI_Bags:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    -- A keystone's encoded level changing (downgrade on completion, or on reset)
    -- doesn't reliably fire BAG_UPDATE for its slot, so the keystone level text
    -- painted by RefreshInventory goes stale while bags stay open across the
    -- run -- GameTooltip looks correct because it re-queries fresh on every
    -- hover, independent of our repaint cycle. Force a refresh on these too.
    CUI_Bags:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    CUI_Bags:RegisterEvent("CHALLENGE_MODE_RESET")
    -- Lindormi's NPC-dialogue keystone downgrade is the same in-place encoded-
    -- level change as above, just triggered outside any dungeon run -- neither
    -- CHALLENGE_MODE event applies (both are scoped to an active M+ run's
    -- lifecycle). GOSSIP_CLOSED is the generic "an NPC dialogue just ended"
    -- signal and fires reliably around her interaction; it also fires for every
    -- unrelated NPC gossip close, but ScheduleRefresh below is cheap and gated
    -- on bags being visible, so that's a harmless no-op rather than a real cost.
    CUI_Bags:RegisterEvent("GOSSIP_CLOSED")
    -- Set created/renamed/deleted: rebuild split categories / refresh name labels.
    -- Registered only while a set feature is on: zero event cost when disabled
    -- (merged-mode routing stays correct without it -- the lookup rebuilds per
    -- classify pass; the event only serves the split children and name labels).
    function CUI_Bags.UpdateSetEventRegistration()
        if BP().bagSplitSetGearBySet or BP().bagShowSetGearName == true then
            CUI_Bags:RegisterEvent("EQUIPMENT_SETS_CHANGED")
        else
            CUI_Bags:UnregisterEvent("EQUIPMENT_SETS_CHANGED")
        end
    end
    CUI_Bags.UpdateSetEventRegistration()
    -- Replays a refresh that was deferred during combat (secure-button taint guard).
    CUI_Bags:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Cludes: moved unchanged by the file split
    -- Drives the post-mailbox/bank Recent Items resync (see MailOpen/BankOpen/DetectNewItems above).
    if C_PlayerInteractionManager then
        CUI_Bags:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    end

    -- Panels that move items one bag slot at a time (see SetItemPanelOpen).
    local ITEM_PANEL_EVENTS = {
        -- No MAIL_SHOW: the Inbox never takes items OUT of bags, so unmerging there churns for
        -- nothing -- only Send Mail matters (hooked below). MAIL_CLOSED is a belt against a stuck flag if the frame vanishes without its OnHide running.
        MAIL_CLOSED = { "sendmail", false },
        TRADE_SHOW = { "trade", true },
        TRADE_CLOSED = { "trade", false },
        AUCTION_HOUSE_SHOW = { "auction", true },
        AUCTION_HOUSE_CLOSED = { "auction", false },
        MERCHANT_SHOW = { "merchant", true },
        MERCHANT_CLOSED = { "merchant", false },
        BANKFRAME_OPENED = { "bank", true },
        BANKFRAME_CLOSED = { "bank", false },
        GUILDBANKFRAME_OPENED = { "guildbank", true },
        GUILDBANKFRAME_CLOSED = { "guildbank", false },
    }
    -- pcall belt: RegisterEvent on an unknown event name is a HARD error, and this loop runs
    -- BEFORE the OnEvent wiring below, so one bad name kills StartAddon; a panel lost to a patch rename must degrade to "that panel doesn't unmerge", never a dead bags addon.
    for evt in pairs(ITEM_PANEL_EVENTS) do
        local success = pcall(CUI_Bags.RegisterEvent, CUI_Bags, evt)
        if not success then
            ITEM_PANEL_EVENTS[evt] = nil
        end
    end

    -- Send Mail is driven off the frame, not MAIL_SHOW, so switching tabs inside an open
    -- mailbox flips the state too. Blizzard_MailFrame loads with no LoadOnDemand, so the frame exists by now; the guard is belt.
    local function HookSendMail(widget)
        if not widget or not widget.HookScript then
            return
        end
        local function flip(isOpen)
            if SetItemPanelOpen("sendmail", isOpen) and CUI_Bags:IsVisible() then
                CUI_Bags:RefreshInventory()
            end
        end
        widget:HookScript("OnShow", function()
            flip(true)
        end)
        widget:HookScript("OnHide", function()
            flip(false)
        end)
        -- Already on the Send Mail tab when hooked (/reload with mailbox open): OnShow already fired, so seed from live state.
        if widget:IsShown() then
            flip(true)
        end
    end
    HookSendMail(_G.SendMailFrame)

    -- The saved slot size before the pool is built (out of combat only): a first
    -- bag open in combat could not resize the slots for the whole fight.
    mod.ApplySlotMetrics()
    -- Pre-warm the secure item-button pool out of combat: a ContainerFrameItemButtonTemplate created
    -- in lockdown is tainted (UseContainerItem() blocked in M+/Delves), so build every button we could
    -- need up front and let RefreshInventory only position/show clean ones. Slots the loading-screen
    -- pass already built are skipped; in lockdown this builds nothing and combat end tops it up.
    CUI_Bags:WarmSlotPool()

    -- Seed this character's tracked currencies from Blizzard's on first load
    if CludesUIDB and C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
        -- Only seed when this character's table is empty: first install, a
        -- fresh profile, or a character whose legacy seed was empty too.
        local coroutineObj = CurrencyOrder()
        local hasAny = false
        if coroutineObj then
            for _ in pairs(coroutineObj) do
                hasAny = true
                break
            end
        end
        if coroutineObj and not hasAny then
            local sequence = 0
            for i = 1, 20 do
                local details = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not details then
                    break
                end
                sequence = sequence + 1
                coroutineObj[details.currencyTypesID] = sequence
            end
        end
    end

    -- Snapshot Blizzard's tracked currencies so we can diff on change.
    local _lastBlizzSet = {}
    local function ReadBlizzSet()
        local cfg = {}
        if C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo then
            for i = 1, 20 do
                local details = C_CurrencyInfo.GetBackpackCurrencyInfo(i)
                if not details then
                    break
                end
                cfg[details.currencyTypesID] = true
            end
        end
        return cfg
    end
    _lastBlizzSet = ReadBlizzSet()

    -- Sync our currency list with Blizzard's currency tab: newly checked added, newly
    -- unchecked removed. Currencies added through our dropdown (never in Blizzard's set) are untouched.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("TokenFrame.OnTokenWatchChanged", function()
            if not CludesUIDB then
                return
            end
            local coroutineObj = CurrencyOrder()
            if not coroutineObj then
                return
            end
            local blizzSet = ReadBlizzSet()
            for containerId in pairs(blizzSet) do
                if not coroutineObj[containerId] then
                    local maxOrder = 0
                    for _, ord in pairs(coroutineObj) do
                        if type(ord) == "number" and ord > maxOrder then
                            maxOrder = ord
                        end
                    end
                    coroutineObj[containerId] = maxOrder + 1
                end
            end
            -- Remove currencies that were in Blizzard's set before but aren't now
            for containerId in pairs(_lastBlizzSet) do
                if not blizzSet[containerId] then
                    coroutineObj[containerId] = nil
                end
            end
            _lastBlizzSet = blizzSet
            if CUI_Bags:IsVisible() then
                SyncBagFrameToFooter()
            end
            CludesUI:RefreshPage()
        end, CUI_Bags)
    end

    -- DetectNewItems: one deferred pass per BAG_UPDATE burst, on the next
    -- frame. Same-frame dedupe alone stranded misses: the first event of a
    -- loot burst can tally before every bag involved is readable, and the
    -- skipped duplicates never re-ran the scan -- an item consumed before the
    -- next bag change (KP studies, planted seeds, learned cosmetics) was then
    -- missed forever. The deferred flush scans once, with the burst settled.
    local _detectQueued = false
    local function _DetectFlush()
        _detectQueued = false
        DetectNewItems()
    end

    CUI_Bags:SetScript("OnEvent", function(self, eventName, interactionType)
        if eventName == "PLAYER_REGEN_ENABLED" then
            -- Combat ended: build any slot the combat guard refused (a /reload in combat, a bag
            -- that grew while locked), shown or not, so the next fight opens a full grid; then
            -- replay any refresh deferred during combat.
            if CUI_Bags._poolShort then
                CUI_Bags._poolShort = nil
                CUI_Bags:WarmSlotPool()
            end
            if CUI_Bags._refreshPendingCombat then
                CUI_Bags._refreshPendingCombat = nil
                if CUI_Bags:IsVisible() then
                    CUI_Bags:RefreshInventory()
                end
                if CUI_BagsReagent:IsVisible() and CUI_BagsReagent.RefreshInventory then
                    CUI_BagsReagent:RefreshInventory()
                end
            end
            return
        end
        if eventName == "MAIL_CLOSED" or eventName == "BANKFRAME_CLOSED" then
            -- Legacy belt, doesn't reliably fire on retail; the interaction-
            -- manager HIDE below is the live driver. Settle first: mail's own
            -- delivery, or a bank auto-deposit, can still be landing items just
            -- after close -- and hold detection down through the settle window
            -- too (_snapshotReady gates DetectNewItems), or those in-flight
            -- items would flag against the stale frozen baselines the moment
            -- the interaction check reads closed.
            _snapshotReady = false
            C_Timer.After(0.5, SnapshotKnownIDs)
            -- No return: falls through to the ITEM_PANEL_EVENTS handling below.
        end
        if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
            if
                interactionType == Enum.PlayerInteractionType.MailInfo
                or interactionType == Enum.PlayerInteractionType.Banker
                or interactionType == Enum.PlayerInteractionType.CharacterBanker
                or interactionType == Enum.PlayerInteractionType.AccountBanker
            then
                -- Same settle-window hold as the legacy branch above.
                _snapshotReady = false
                C_Timer.After(0.5, SnapshotKnownIDs)
            end
            return
        end
        local panelFrame = ITEM_PANEL_EVENTS[eventName]
        if panelFrame then
            -- Tracked even while bags are hidden: the panel that opens them (OpenAllBags) can fire in either order with this event.
            if SetItemPanelOpen(panelFrame[1], panelFrame[2]) and CUI_Bags:IsVisible() then
                CUI_Bags:RefreshInventory()
            end
            -- Sell Junk shows with the merchant (only once the Junk Marker built it)
            if panelFrame[1] == "merchant" and CUI_Bags._junkBtn then
                CUI_Bags:SyncHeaderIcons()
            end
            return
        end
        if eventName == "EQUIPMENT_SETS_CHANGED" then
            -- Invalidate even while hidden: the next open must not classify with
            -- categories built from the old set list.
            CUI_Bags.InvalidateSetCategories()
            if CUI_Bags:IsVisible() then
                ScheduleRefresh()
            end
            return
        end
        if
            eventName == "CHALLENGE_MODE_COMPLETED"
            or eventName == "CHALLENGE_MODE_RESET"
            or eventName == "GOSSIP_CLOSED"
        then
            -- A keystone downgrade here doesn't need a hidden-side invalidation:
            -- the next manual open already forces a full RefreshInventory
            -- (ToggleCUI). This only matters while bags are already visible.
            if CUI_Bags:IsVisible() then
                ScheduleRefresh()
            end
            return
        end
        if eventName == "BAG_UPDATE" and CUI_Bags.refreshEnabled ~= false and not _detectQueued then
            _detectQueued = true
            C_Timer.After(0, _DetectFlush)
        end
        if not CUI_Bags:IsVisible() then
            return
        end
        if eventName == "BAG_UPDATE" or eventName == "BAG_UPDATE_DELAYED" then
            if eventName == "BAG_UPDATE_DELAYED" then
                -- Equipped bag icons settle with the batch (bag equip / unequip)
                if CUI_BagsWindow:IsVisible() then
                    CUI_BagsWindow:RefreshBags()
                end
                -- A refresh the batch's own BAG_UPDATE armed already lands after
                -- it; re-arming would mark every single change as a burst.
                if refreshPending then
                    return
                end
            end
            if not CUI_Bags.refreshEnabled then
                return
            end
            if CUI_Bags._unlockSort then
                CUI_Bags._unlockSort()
            end
            ScheduleRefresh()
        elseif eventName == "ITEM_LOCK_CHANGED" then
            if not CUI_Bags.refreshEnabled then
                return
            end
            if CUI_Bags._unlockSort then
                CUI_Bags._unlockSort()
            end
            ScheduleRefresh()
        elseif eventName == "CURRENCY_DISPLAY_UPDATE" then
            SyncBagFrameToFooter()
        end
    end)

    CUI_Bags:HookScript("OnHide", function()
        CUI_BagsWindow:Hide()
        -- Controller cursor: the carried-item watch lives only while the bags are open.
        local watcher = CUI_Bags._padCursorWatch
        if watcher then
            watcher:UnregisterAllEvents()
            CUI_Bags._padPlaceBtn:Hide()
        end
        -- The select modes (pin, assign, Junk Marker) end with the bags: their
        -- click catchers cover the screen (a real close only, not a hidden UI)
        if not CUI_Bags:IsShown() then
            if CUI_Bags._pinSelectMode then
                ExitPinSelectMode()
            end
            if CUI_Bags._assignSelectMode then
                ExitAssignSelectMode()
            end
        end
        -- Controller cursor: a Back press or a bank close hides the bags
        -- alone, so the detached reagent window goes with them.
        if CUI.PadInUse() and not CUI_Bags:IsShown() then
            CUI_BagsReagent:Hide()
        end
    end)

    CludesUI.RegisterEscapeClose(CUI_Bags)
end

-------------------------------------------------------------------------------
--  Loader
-------------------------------------------------------------------------------
-- Per loading-screen event, the most the combat-reload pool pass may take (ms). The pass
-- runs in this frame's own handler (its own script budget); whatever it leaves is built at
-- PLAYER_ENTERING_WORLD, still behind the loading screen, then at combat end.
local WINDOW_WARM_MS = 40
local function ReleaseStaleSortMute()
    CludesUI.ReleaseStaleHold("Sound_EnableSFX", "CludesUIBags")
end
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, eventName)
    if eventName == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        CUI_Bags:WarmSlotPool(WINDOW_WARM_MS)
        return
    end
    self:UnregisterEvent("PLAYER_LOGIN")
    -- The sort's sound effects mute, when a session ended with it held (a
    -- reload mid-sort): no sort runs at login, so it goes back, only while the
    -- sound effects still read the mute. Out of combat (some CVars cannot
    -- change in combat): a reload in combat waits for its end.
    if InCombatLockdown() then
        mod.CombatQueue.Defer("staleSortMute", ReleaseStaleSortMute)
    else
        ReleaseStaleSortMute()
    end
    -- Scheduled first, so nothing in the pass below can stop the module from starting.
    C_Timer.After(0.5, function()
        StartAddon()
        CUI_Bags:Hide()
        CUI_BagsReagent:Hide()
    end)
    -- A /reload in combat: the 0.5s start lands after the loading screen, in lockdown, where
    -- the combat guard refuses every slot and the bags would open empty all fight. Timers do
    -- not run during the loading screen, so build the pool here, in it. The guard is
    -- untouched: if it refuses here too, nothing is built and combat end builds the pool.
    -- Normal logins skip this and keep the 0.5s pre-warm.
    local inCombat = UnitAffectingCombat("player")
    if not (issecretvalue and issecretvalue(inCombat)) and inCombat then
        if not CUI_Bags:WarmSlotPool(WINDOW_WARM_MS) and not InCombatLockdown() then
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
end)

-------------------------------------------------------------------------------
--  Shared with CludesUIBags_Grid.lua (loads after this file)
-------------------------------------------------------------------------------
function mod.GetSelection()
    return selectedCategoryIndex, selectedGroupName
end
function mod.SetSelection(position, set)
    SetSelectedCategoryIndex(position)
    SetSelectedGroupName(set)
end
mod.SLOT_SIZE, mod.SPACING = SLOT_SIZE, SPACING
mod.itemSlots = itemSlots
mod.itemDragFrame = _itemDragFrame
mod.catHeaders = _catHeaders
mod.expSubHeaders = _expSubHeaders
mod.QUEST_BORDER_COLOR = QUEST_BORDER_COLOR
mod.BagsItemUnusable = BagsItemUnusable
mod.GetFont = GetFont
mod.GetCatTitleSize = GetCatTitleSize
mod.SetInsetBorderThickness = SetInsetBorderThickness
mod.UpdatePawnArrow = UpdatePawnArrow
mod.PreCacheSortFields = PreCacheSortFields
-- Recent Items order in every view: newest pickup first (pickup numbers in
-- CUI_Bags._recentItems), the bag position breaking ties within one item
function mod.RecentCompare(a, b)
    local rec = CUI_Bags._recentItems
    local ra = (a.info and rec[a.info.itemID]) or 0
    local rb = (b.info and rec[b.info.itemID]) or 0
    if ra ~= rb then
        return ra > rb
    end
    if a.bag ~= b.bag then
        return a.bag < b.bag
    end
    return a.slot < b.slot
end
mod.VisualSortCompare = VisualSortCompare
mod.MergeDuplicates = MergeDuplicates
mod.ApplySavedOrder = ApplySavedOrder
mod.BuildExpansionBuckets = BuildExpansionBuckets
mod.BuildSlotBuckets = BuildSlotBuckets
mod.GetArmorySlotBucket = GetArmorySlotBucket
mod.ArmorySlotGroupingEnabled = ArmorySlotGroupingEnabled
mod.IsArmoryGearCategory = IsArmoryGearCategory
mod.IsGearOnlyGroup = IsGearOnlyGroup
mod.GetOrCreateCatHeader = GetOrCreateCatHeader
mod.GetOrCreateExpSubHeader = GetOrCreateExpSubHeader
mod.ShowRecentClearButton = ShowRecentClearButton
mod.GetOrCreatePinOverlay = GetOrCreatePinOverlay
mod.GetOrCreateAssignOverlay = GetOrCreateAssignOverlay
mod.ResetAssignOverlays = ResetAssignOverlays

-- The start values the copies were built from: nothing may read them again.
Inner._anyItemPanelOpen, Inner.selectedCategoryIndex = nil, nil
Inner.broken = false
