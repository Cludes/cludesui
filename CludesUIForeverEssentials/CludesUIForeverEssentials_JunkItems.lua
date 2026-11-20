if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_JunkItems.lua  (WoW Forever only)
--  Small window listing the cheapest junk stacks in your bags: every stack up
--  to Maximum Quality (gray only by default), and anything marked with the
--  Bags Junk Marker.
--    Ctrl + Left Click  : delete the stack (above Delete Without Confirming: a
--                         second Ctrl + Left Click confirms; Rare and better type DELETE first)
--    Middle Click       : never show this item again (account-wide)
--  Each icon shows its stack's value underneath (vendor, or Auctionator's with
--  Use Auctionator Prices on), cut to whole silver (1g 15s 12c -> 1g 15s).
--  Copper only appears while the value is under 1g.
-------------------------------------------------------------------------------
local _, module = ...
local Pix = CludesUI.PP

local GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant

-- Settings live in CludesUIDB.junkList, beside the shared visibility keys
-- (unset = Always); unset keys read these. Excluded items are account-wide
-- too: CludesUIDB.junkListExcluded holds [itemID] = true.
local DEFAULTS = {
    enabled = false, -- opt-in: this window can delete items
    itemCount = 4, -- 1..MAX_CELLS
    iconSize = 32,
    iconSpacing = 20, -- gap between icons, px
    priceSide = "bottom", -- bottom | top
    auctionPrices = false, -- value stacks at Auctionator's price when it has one
    showFreeSlots = false, -- title reads "Bag Slots - free/total"; off hides the title
    onlyLowBagSpace = false, -- also hidden until fewer bag slots are free than the threshold
    freeSlotThreshold = 5, -- free regular bag slots, 1..100
    maxQuality = 0, -- Enum.ItemQuality: stacks up to this quality list
    oneClickQuality = 0, -- stacks up to this quality (Uncommon at most) delete without asking
}
-- The screen's centre until unlock mode moves it.
local F = module.Feature("junkList", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })
local Get, Read, Enabled = F.Get, F.Read, F.Enabled

-- Layout
local MAX_CELLS = 6
local PRICE_H = 12
local TITLE_H = 24

local RARE = Enum.ItemQuality.Rare
local QUEST_CLASS = Enum.ItemClass.Questitem
local BATTLEPET_CLASS = Enum.ItemClass.Battlepet

local widget, titleFS, emptyFS, probeFS
local cells = {}
-- Made in the main chunk so their handlers bill to this addon, whatever turns
-- the window on (a login or the options page). Neither holds an event while
-- the window is off or hidden.
local watcher = CreateFrame("Frame")
-- Only Show When Bag Space Is Low: a bag watcher of its own, listening while
-- the option is on and the visibility setting lets the window show (shown or
-- not, any bag change can cross the threshold).
local bagSpaceWatcher = CreateFrame("Frame")
local bagWatching = false
local ctrlWatch = CreateFrame("Frame") -- MODIFIER_STATE_CHANGED while a cell is flagged
local isActive = false -- shown, with its events registered
local visRegistered = false -- on the shared visibility dispatcher
local itemInfoOn = false -- GET_ITEM_INFO_RECEIVED registered
local confirmHandle -- the open delete confirmation
local armedCell -- the cell whose stack the next Ctrl + Left Click deletes
local swapCount = 0 -- cells holding a double-click guard
local priceFitW = 0 -- widest price a cell shows in full (its icon plus the spacing, less 2 px)
local lastFree, lastTotal -- the title's counts as last drawn
local auctionOn = false -- Use Auctionator Prices, as the remembered values were priced
local dbHooked = false -- Auctionator's price-update callback registered

-- Per-slot facts for the scanned bags. A pass re-reads only the bags marked
-- dirty (by BAG_UPDATE, or all of them when the window comes back or a bag is
-- swapped), then picks the list from these facts. Settings, exclusions and
-- Junk Marker changes need a new pick but no re-read (Bags asks for its pick
-- through CludesUI._JunkItems.Refresh). recs[bag][slot] lives for the
-- session; scanSlots[bag] = how many slots the last read covered.
local recs, slotsToScan, isStale = {}, {}, {}
local pending = {} -- [itemID] = true: item data not cached yet
local failed = {} -- [itemID] = true: the client said the data will not load
local best, bestN = {}, 0 -- the cheapest listable records, in display order

-- How many stacks the window lists.
local function Limit()
    return Clamp(Get("itemCount"), 1, MAX_CELLS)
end

-------------------------------------------------------------------------------
--  Fonts (the Forever Essentials module font)
-------------------------------------------------------------------------------
local function SetJunkFont(fontStr, size)
    CludesUI.ApplyModuleFont(fontStr, nil, size, "essentials")
end

local function NewText(hostFrame, size, alpha)
    local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
    SetJunkFont(fontStr, size)
    fontStr:SetTextColor(1, 1, 1, alpha or 1)
    return fontStr
end

-------------------------------------------------------------------------------
--  Money text: cut to whole silver, so 1g15s12c reads "1g 15s". Copper only
--  shows while the value is under 1 gold ("15s 12c"). short: the largest coin
--  alone ("1g", "15s"), for a price too wide for its icon's slot.
-------------------------------------------------------------------------------
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local function FormatValue(copperValue, short)
    local g = math.floor(copperValue / 10000)
    local text = math.floor((copperValue % 10000) / 100)
    local c = copperValue % 100
    if g > 0 then
        local result = BreakUpLargeNumbers(g) .. GOLD_ICON
        if text > 0 and not short then
            result = result .. " " .. text .. SILVER_ICON
        end
        return result
    end
    if text > 0 then
        local result = text .. SILVER_ICON
        if c > 0 and not short then
            result = result .. " " .. c .. COPPER_ICON
        end
        return result
    end
    return c .. COPPER_ICON
end

-------------------------------------------------------------------------------
--  Item rules
-------------------------------------------------------------------------------
-- A bag slot's item as this list sees it: its quality and stack value; nil
-- while its item data is not cached yet; false when it must never list (quest
-- items, battle pets, soulbound items with no vendor value, unknown quality).
local function Classify(details)
    local ident = details.itemID
    local _, _, _, _, _, classID = GetItemInfoInstant(ident)
    if classID == QUEST_CLASS or classID == BATTLEPET_CLASS then
        return false
    end
    local itemLink = details.hyperlink
    if itemLink and itemLink:find("|Hbattlepet:", 1, true) then
        return false
    end
    local _, _, itemQuality, _, _, _, _, _, _, _, sell = GetItemInfo(ident)
    if sell == nil then
        return nil
    end
    -- Fail closed: the higher of the slot's and the item's quality, and never an
    -- item that reports neither.
    local q = details.quality
    if q == nil or (itemQuality and itemQuality > q) then
        q = itemQuality
    end
    if q == nil then
        return false
    end
    -- No vendor value still wastes a slot, so it lists (at the top), but not
    -- when soulbound: those are keepers (Hearthstone, Marks of Honor).
    local noValue = details.hasNoValue or sell == 0
    if noValue and details.isBound then
        return false
    end
    return q, noValue and 0 or sell * (details.stackCount or 1)
end

-- Quest items never list, including ones that start a quest (same check as Bags).
local function IsQuestSlot(bagId, slotId)
    local quality = C_Container.GetContainerItemQuestInfo(bagId, slotId)
    return (quality and (quality.isQuestItem or quality.questID)) and true or false
end

local function InEquipmentSet(bagId, slotId)
    return C_Container.GetContainerItemEquipmentSetInfo(bagId, slotId) and true or false
end

-- Anything up to Maximum Quality, and anything marked with the Bags Junk
-- Marker: above Poor, IsJunk reports exactly the marks. cm is nil while Bags
-- is not loaded, and then nothing counts as marked.
local function Listable(q, ident, maxQuality, cm)
    if q <= maxQuality then
        return true
    end
    return cm ~= nil and cm:IsJunk(ident, q) == true
end

-------------------------------------------------------------------------------
--  Bag reads and the list
-------------------------------------------------------------------------------
local function ReadSlot(region)
    region.quality, region.pending, region.quest, region.inSet, region.total = nil, false, nil, nil, nil
    local details = GetContainerItemInfo(region.bag, region.slot)
    local ident = details and details.itemID
    region.id = ident or false
    if not ident then
        return
    end
    region.count, region.icon, region.link = details.stackCount or 1, details.iconFileID, details.hyperlink
    local q, sum = Classify(details)
    if q then
        region.quality, region.vendor, region.bound = q, sum, details.isBound
    elseif q == nil then
        region.pending = true -- its GET_ITEM_INFO_RECEIVED re-reads the bag
    end
end

-- Regular bags only: the reagent bag and specialty bags (quiver, ammo pouch,
-- soul bag) hold things this delete list must never offer. A family of 0 is
-- a general-purpose bag (the backpack included).
local function ReadBag(bagId)
    isStale[bagId] = nil
    local _, family = GetContainerNumFreeSlots(bagId)
    local num = (family == 0) and GetContainerNumSlots(bagId) or 0
    slotsToScan[bagId] = num
    local entries = recs[bagId]
    if not entries then
        entries = {}
        recs[bagId] = entries
    end
    for slotId = 1, num do
        local region = entries[slotId]
        if not region then
            region = { bag = bagId, slot = slotId }
            entries[slotId] = region
        end
        ReadSlot(region)
    end
end

local function DirtyAll()
    for bagId = 0, NUM_BAG_SLOTS do
        isStale[bagId] = true
    end
end

-- An item finished loading: re-read the bags it sits in.
local function DirtyHolders(ident)
    for bagId = 0, NUM_BAG_SLOTS do
        local entries = recs[bagId]
        for slotId = 1, slotsToScan[bagId] or 0 do
            local region = entries[slotId]
            if region.pending and region.id == ident then
                isStale[bagId] = true
                break
            end
        end
    end
end

-- A set edit or new prices fire no bag update: drop that remembered fact instead.
local function Forget(key)
    for bagId = 0, NUM_BAG_SLOTS do
        local entries = recs[bagId]
        for slotId = 1, slotsToScan[bagId] or 0 do
            entries[slotId][key] = nil
        end
    end
end

-- Soulbound stacks cannot be auctioned: they keep their vendor value.
local function StackValue(region)
    local each = auctionOn and not region.bound and region.link and module.AuctionPrice(region.link)
    return each and each * region.count or region.vendor
end

-- Cheapest first; ties keep bag order.
local function Better(a, b)
    if a.total ~= b.total then
        return a.total < b.total
    end
    if a.bag ~= b.bag then
        return a.bag < b.bag
    end
    return a.slot < b.slot
end

-- Inserts r into the fixed best-N list holding n entries; returns the new count.
local function Offer(region, num, cap)
    if num < cap then
        num = num + 1
    elseif not Better(region, best[num]) then
        return num
    end
    local index = num
    while index > 1 and Better(region, best[index - 1]) do
        best[index] = best[index - 1]
        index = index - 1
    end
    best[index] = region
    return num
end

-- Picks the cheapest listable stacks from the read facts. The quest and set
-- checks and the value run only for items that would otherwise list, once per
-- read (set membership again after a set edit, the value after new prices).
local function Select(cap)
    local maxQuality = Get("maxQuality")
    local cm = _G.CUI_CategoryManager
    local excludedItems = CludesUIDB.junkListExcluded
    wipe(pending)
    local num = 0
    for bagId = 0, NUM_BAG_SLOTS do
        local entries = recs[bagId]
        for slotId = 1, slotsToScan[bagId] or 0 do
            local region = entries[slotId]
            local ident, q = region.id, region.quality
            if region.pending then
                if not failed[ident] then
                    pending[ident] = true
                end
            elseif q and not (excludedItems and excludedItems[ident]) and Listable(q, ident, maxQuality, cm) then
                if region.quest == nil then
                    region.quest = IsQuestSlot(bagId, slotId)
                end
                if not region.quest then
                    if region.inSet == nil then
                        region.inSet = InEquipmentSet(bagId, slotId)
                    end
                    if not region.inSet then
                        if region.total == nil then
                            region.total = StackValue(region)
                        end
                        num = Offer(region, num, cap)
                    end
                end
            end
        end
    end
    for index = num + 1, bestN do
        best[index] = nil
    end
    bestN = num
end

-------------------------------------------------------------------------------
--  Double-click guard: when a pass puts a different stack in the cell under the
--  cursor while Ctrl is held, that cell refuses Ctrl + Left Click until the
--  cursor enters it again or Ctrl is let go, so the second click of a double
--  click never deletes a stack the player has not seen.
-------------------------------------------------------------------------------
local function ClearSwapFlags()
    if swapCount == 0 then
        return
    end
    for index = 1, #cells do
        cells[index].swapped = nil
    end
    swapCount = 0
    ctrlWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
end

local function OnModifierChanged()
    if not IsControlKeyDown() then
        ClearSwapFlags()
    end
end
ctrlWatch:SetScript("OnEvent", OnModifierChanged)

local function FlagSwap(junkCell)
    if junkCell.swapped then
        return
    end
    junkCell.swapped = true
    swapCount = swapCount + 1
    if swapCount == 1 then
        ctrlWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
    end
end

local function UnflagSwap(junkCell)
    if not junkCell.swapped then
        return
    end
    junkCell.swapped = nil
    swapCount = swapCount - 1
    if swapCount == 0 then
        ctrlWatch:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
end

-------------------------------------------------------------------------------
--  Passes
-------------------------------------------------------------------------------
local Refresh -- forward

-- Every pass goes through here: any number of triggers in one frame (bag
-- updates, item loads, settings, an exclude, a Junk Marker change) collapse
-- into a single Refresh.
local refreshQueued = false
local function RunQueuedRefresh()
    refreshQueued = false
    Refresh()
end
local function RequestRefresh()
    if refreshQueued or not isActive then
        return
    end
    refreshQueued = true
    C_Timer.After(0, RunQueuedRefresh)
end

-------------------------------------------------------------------------------
--  Delete and exclude
-------------------------------------------------------------------------------
-- The slot still holds the stack the player chose and it still qualifies: same
-- item and count, not locked, no better than the quality they saw, and still no
-- quest item, battle pet, keeper or equipment-set item.
local function StillJunk(bagId, slotId, ident, count, maxQuality)
    local details = GetContainerItemInfo(bagId, slotId)
    if not details or details.itemID ~= ident or details.isLocked or (details.stackCount or 1) ~= count then
        return false
    end
    local q = Classify(details)
    if not q or q > maxQuality then
        return false
    end
    return not IsQuestSlot(bagId, slotId) and not InEquipmentSet(bagId, slotId)
end

-- DeleteCursorItem needs a hardware event, and the game refuses it from a
-- confirmation popup's click: this runs only inside the stack's own Ctrl +
-- Left Click. Never in combat or with anything already on the cursor.
local function DeleteStack(bagId, slotId, ident, count, maxQuality)
    if InCombatLockdown() or GetCursorInfo() then
        return
    end
    if not StillJunk(bagId, slotId, ident, count, maxQuality) then
        return
    end
    C_Container.PickupContainerItem(bagId, slotId)
    local kind, cursorID = GetCursorInfo()
    if kind == "item" and cursorID == ident then
        DeleteCursorItem()
    elseif CursorHasItem() then
        ClearCursor()
    end
end

local ShowCellTooltip -- forward (Cells)

local function CloseConfirm()
    if not confirmHandle then
        return
    end
    CludesUI:CloseConfirmPopup(confirmHandle)
    confirmHandle = nil
    if not armedCell then
        watcher:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
end

-- A stack that must be confirmed is armed first (white and green stacks above
-- Delete Without Confirming by their first Ctrl + Left Click, Rare and better by
-- the typed confirmation); the next Ctrl + Left Click on it deletes. Arming
-- holds for ARM_SECS and for that stack only: a change to the cell, combat or
-- the time running out ends it.
local ARM_SECS = 6

local function Disarm()
    local junkCell = armedCell
    if not junkCell then
        return
    end
    armedCell = nil
    junkCell.armedUntil = nil
    junkCell._arm:Hide()
    if not confirmHandle then
        watcher:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    if GameTooltip:IsOwned(junkCell) then
        ShowCellTooltip(junkCell)
    end
end

local function Arm(junkCell)
    Disarm()
    armedCell = junkCell
    local untilT = GetTime() + ARM_SECS
    junkCell.armedUntil = untilT
    junkCell._arm:Show()
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    if GameTooltip:IsOwned(junkCell) then
        ShowCellTooltip(junkCell)
    end
    C_Timer.After(ARM_SECS, function()
        if armedCell == junkCell and junkCell.armedUntil == untilT then
            Disarm()
        end
    end)
end

-- Rare or better also needs the delete word typed, as the game's own delete
-- does; confirming arms the stack for its final Ctrl + Left Click.
local function AskDelete(junkCell)
    CloseConfirm()
    local bagId, slotId, ident, count, q = junkCell.bag, junkCell.slot, junkCell.id, junkCell.count, junkCell.quality
    local labelText = count > 1 and (junkCell.link .. " x" .. count) or junkCell.link
    local handle
    handle = CludesUI:ShowConfirmPopup({
        title = CludesUI.L("Delete Junk Item"),
        message = DELETE_ITEM:format(labelText) .. "\n\n" .. CludesUI.L(
            "Then Ctrl + Left Click the item again to delete it."
        ),
        confirmText = DELETE,
        cancelText = CANCEL,
        typeToConfirm = DELETE_ITEM_CONFIRM_STRING,
        onConfirm = function()
            if confirmHandle ~= handle then
                return
            end
            CloseConfirm()
            if junkCell.id == ident and junkCell.bag == bagId and junkCell.slot == slotId and junkCell.count == count then
                Arm(junkCell)
            end
        end,
        onCancel = function()
            if confirmHandle == handle then
                CloseConfirm()
            end
        end,
    })
    confirmHandle = handle
    -- Closed at combat start: the popup's key handling is restricted in combat.
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function Exclude(ident)
    local excludedItems = CludesUIDB.junkListExcluded
    if not excludedItems then
        excludedItems = {}
        CludesUIDB.junkListExcluded = excludedItems
    end
    excludedItems[ident] = true
    RequestRefresh()
end

-------------------------------------------------------------------------------
--  Cells
-------------------------------------------------------------------------------
ShowCellTooltip = function(junkCell)
    GameTooltip:SetOwner(junkCell, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(junkCell.bag, junkCell.slot)
    GameTooltip:AddLine(" ")
    -- No deletes in combat: the hint greys out there.
    if InCombatLockdown() then
        GameTooltip:AddLine(CludesUI.L("Ctrl + Left Click: delete"), 0.5, 0.5, 0.5)
    elseif armedCell == junkCell then
        GameTooltip:AddLine(CludesUI.L("Ctrl + Left Click again to delete"), 1, 0.15, 0.15)
    else
        GameTooltip:AddLine(CludesUI.L("Ctrl + Left Click: delete"), 1, 0.3, 0.3)
    end
    GameTooltip:AddLine(CludesUI.L("Middle Click: never show this item"), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function OnCellClick(self, btnFrame)
    local ident = self.id
    if not ident then
        return
    end
    if btnFrame == "MiddleButton" then
        Exclude(ident)
        return
    end
    if btnFrame ~= "LeftButton" or not IsControlKeyDown() then
        return
    end
    if self.swapped or InCombatLockdown() or GetCursorInfo() then
        return
    end
    local q = self.quality
    -- Rare and better always need the typed confirmation, whatever the setting says.
    if
        (q < RARE and q <= Get("oneClickQuality"))
        or (armedCell == self and GetTime() <= (self.armedUntil or 0))
    then
        Disarm()
        DeleteStack(self.bag, self.slot, ident, self.count, q)
    elseif q >= RARE then
        AskDelete(self)
    else
        Arm(self)
    end
end

local function OnCellEnter(self)
    UnflagSwap(self)
    if self.id then
        ShowCellTooltip(self)
    end
end

local function OnCellLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function AcquireCell(index)
    local b = cells[index]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, widget)
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", OnCellClick)
    b:SetScript("OnEnter", OnCellEnter)
    b:SetScript("OnLeave", OnCellLeave)
    b:Hide()

    b._icon = b:CreateTexture(nil, "ARTWORK")
    b._icon:SetAllPoints()
    b._icon:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
    -- Red wash while the stack is armed for its confirming click.
    b._arm = b:CreateTexture(nil, "OVERLAY", nil, 6)
    b._arm:SetAllPoints()
    b._arm:SetColorTexture(1, 0.1, 0.1, 0.45)
    b._arm:Hide()
    Pix.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 7)

    b._count = b:CreateFontString(nil, "OVERLAY")
    CludesUI.ApplyIconTextFont(b._count, CludesUI.GetFontPath("essentials"), 11, "essentials")
    b._count:SetTextColor(1, 1, 1, 1)
    b._count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)

    b._price = NewText(b, 10)

    cells[index] = b
    return b
end

-- Repaints one cell only where its stack changed.
local function PaintCell(junkCell, region)
    if not region then
        if junkCell.id then
            if armedCell == junkCell then
                Disarm()
            end
            if GameTooltip:IsOwned(junkCell) then
                GameTooltip:Hide()
            end
            UnflagSwap(junkCell)
            junkCell.id = nil
            junkCell:Hide()
        end
        return
    end
    local moved = region.id ~= junkCell.id or region.bag ~= junkCell.bag or region.slot ~= junkCell.slot
    local changed = moved or region.count ~= junkCell.count
    -- An armed stack that left the cell (or changed size) is not the one confirmed.
    if changed and armedCell == junkCell then
        Disarm()
    end
    if region.count ~= junkCell.count then
        junkCell._count:SetText(region.count > 1 and region.count or "")
    end
    if region.icon ~= junkCell.icon then
        junkCell._icon:SetTexture(region.icon)
    end
    -- A price wider than its slot shows its largest coin alone, so prices never collide.
    if region.total ~= junkCell.total or junkCell.fitW ~= priceFitW then
        local fontStr = junkCell._price
        fontStr:SetText(FormatValue(region.total))
        if fontStr:GetStringWidth() > priceFitW then
            fontStr:SetText(FormatValue(region.total, true))
        end
        junkCell.fitW = priceFitW
    end
    -- A different stack under the cursor while Ctrl is held: see the double-click guard.
    if moved and junkCell.id and IsControlKeyDown() and junkCell:IsMouseOver() then
        FlagSwap(junkCell)
    end
    junkCell.id, junkCell.bag, junkCell.slot, junkCell.count = region.id, region.bag, region.slot, region.count
    junkCell.icon, junkCell.total, junkCell.quality, junkCell.link = region.icon, region.total, region.quality, region.link
    if not junkCell:IsShown() then
        junkCell:Show()
    end
    if changed and GameTooltip:IsOwned(junkCell) then
        ShowCellTooltip(junkCell)
    end
end

-------------------------------------------------------------------------------
--  Layout
-------------------------------------------------------------------------------
-- The centre snaps to the pixel grid for the window's size.
local function ApplyPosition()
    F.Place(widget, true)
end

-- Width of the widest title, measured once ("Bag Slots - 888/888"), so the window
-- does not change width as the counts do.
local titleW = 0
local function TitleWidth()
    if titleW == 0 then
        probeFS:SetFormattedText(CludesUI.L("Bag Slots - %d/%d"), 888, 888)
        local wid = probeFS:GetStringWidth() or 0
        if wid >= 1 then
            titleW = math.ceil(wid)
        end
    end
    return titleW
end

-- The window is its content, with no margin (it draws no art): the row of icons
-- (or the title, when it is shown and wider), the title row when shown, then
-- the icons and their prices. Icon Spacing is the gap between icons.
local function WindowSize(cap)
    local iconSize = Get("iconSize")
    local rowW = cap * iconSize + (cap - 1) * Get("iconSpacing")
    local titled = Get("showFreeSlots") and true or false
    local wid = titled and math.max(rowW, TitleWidth()) or rowW
    return Pix.Snap(wid), Pix.Snap((titled and TITLE_H or 0) + iconSize + 3 + PRICE_H), rowW
end

local lay = {} -- the geometry last applied
local function Layout(cap)
    local iconSize = Get("iconSize")
    local pitch = iconSize + Get("iconSpacing")
    local topY = Get("priceSide") == "top"
    local titled = Get("showFreeSlots") and true or false
    local mult = Pix.mult -- the pixel grid the size and the centre snap to (moves with the UI scale)
    if
        iconSize == lay.icon
        and pitch == lay.pitch
        and topY == lay.top
        and cap == lay.limit
        and titled == lay.titled
        and mult == lay.mult
    then
        return
    end
    lay.icon, lay.pitch, lay.top, lay.limit, lay.titled, lay.mult = iconSize, pitch, topY, cap, titled, mult
    -- each price may use its icon's width plus the spacing (less 2 px of air) before it is shortened
    priceFitW = pitch - 2
    local wid, hgt, rowW = WindowSize(cap)
    widget:SetSize(wid, hgt)
    -- The row centred in the window (wider only for the title).
    local x0 = math.floor((wid - rowW) / 2 + 0.5)
    local titleH = titled and TITLE_H or 0
    local y0 = -(titleH + (topY and (PRICE_H + 3) or 0))
    for index = 1, cap do
        local junkCell = AcquireCell(index)
        junkCell:SetSize(iconSize, iconSize)
        junkCell:ClearAllPoints()
        junkCell:SetPoint("TOPLEFT", widget, "TOPLEFT", x0 + (index - 1) * pitch, y0)
        junkCell._price:ClearAllPoints()
        if topY then
            junkCell._price:SetPoint("BOTTOM", junkCell, "TOP", 0, 3)
        else
            junkCell._price:SetPoint("TOP", junkCell, "BOTTOM", 0, -3)
        end
    end
    emptyFS:ClearAllPoints()
    emptyFS:SetPoint("CENTER", widget, "CENTER", 0, -titleH / 2)
    -- The centre snap follows the size; Unlock Mode owns the spot while it is open.
    if not CludesUI._unlockActive then
        ApplyPosition()
    end
end

local function CountBagSlots()
    -- Same bags the list reads: regular bags only.
    local free, sum = 0, 0
    for bagId = 0, NUM_BAG_SLOTS do
        local numFree, family = GetContainerNumFreeSlots(bagId)
        if family == 0 then
            free = free + (numFree or 0)
            sum = sum + GetContainerNumSlots(bagId)
        end
    end
    return free, sum
end

local function UpdateTitle()
    if not Get("showFreeSlots") then
        titleFS:Hide()
        return
    end
    local free, sum = CountBagSlots()
    if free ~= lastFree or sum ~= lastTotal then
        lastFree, lastTotal = free, sum
        titleFS:SetFormattedText(CludesUI.L("Bag Slots - %d/%d"), free, sum)
    end
    titleFS:Show()
end

-------------------------------------------------------------------------------
--  Events and the window
-------------------------------------------------------------------------------
local function OnEvent(_, evt, arg1, arg2)
    if evt == "BAG_UPDATE" then
        if arg1 and arg1 >= 0 and arg1 <= NUM_BAG_SLOTS then
            isStale[arg1] = true
        end
        return -- BAG_UPDATE_DELAYED ends the burst
    elseif evt == "PLAYER_REGEN_DISABLED" then
        CloseConfirm()
        Disarm()
        return
    elseif evt == "GET_ITEM_INFO_RECEIVED" then
        if not pending[arg1] then
            return
        end
        pending[arg1] = nil
        if arg2 == false then
            failed[arg1] = true
        else
            DirtyHolders(arg1)
        end
    elseif evt == "BAG_UPDATE_DELAYED" then
        CloseConfirm() -- the stack a confirmation names may have moved
    elseif evt == "BAG_CONTAINER_UPDATE" then
        DirtyAll()
    elseif evt == "EQUIPMENT_SETS_CHANGED" then
        Forget("inSet")
    end
    RequestRefresh()
end
watcher:SetScript("OnEvent", OnEvent)

local function BuildFrame()
    if widget then
        return
    end
    widget = CreateFrame("Frame", "CludesUIJunkList", UIParent)
    widget:SetFrameStrata("MEDIUM")
    widget:SetClampedToScreen(true)
    widget:Hide()

    -- No window art: the title row, icons and prices. Nothing but the cells
    -- takes the mouse, so the window is click-through; moving it is Unlock
    -- Mode's job.
    local hdrBg = CreateFrame("Frame", nil, widget)
    hdrBg:SetPoint("TOPLEFT")
    hdrBg:SetPoint("TOPRIGHT")
    hdrBg:SetHeight(TITLE_H)

    titleFS = NewText(widget, 11)
    titleFS:SetPoint("LEFT", hdrBg, "LEFT", 0, 0)

    -- Empty frame over the header row; kept because the title may not draw
    -- without it on WoW Forever.
    local hdrCover = CreateFrame("Frame", nil, widget)
    hdrCover:SetPoint("TOPLEFT", hdrBg, "TOPLEFT")
    hdrCover:SetPoint("BOTTOMRIGHT", hdrBg, "BOTTOMRIGHT")

    emptyFS = NewText(widget, 11, 0.5)
    emptyFS:SetText(CludesUI.L("No junk items"))

    -- measures the widest title (TitleWidth)
    probeFS = NewText(widget, 11)
    probeFS:Hide()
end

-------------------------------------------------------------------------------
--  Auctionator prices: a scan that updates them re-prices the list. The API
--  has no unregister, so the callback is registered once and checks the option.
-------------------------------------------------------------------------------
local function OnPricesUpdated()
    if not (auctionOn and isActive) then
        return
    end
    Forget("total")
    RequestRefresh()
end

local function HookPriceUpdates()
    local api = module.AuctionAPI()
    if not (api and api.RegisterForDBUpdate) then
        return
    end
    dbHooked = true
    pcall(api.RegisterForDBUpdate, "CludesUI", OnPricesUpdated)
end

-------------------------------------------------------------------------------
--  Refresh: re-read the dirty bags, pick the list, repaint what changed
-------------------------------------------------------------------------------
Refresh = function()
    if not isActive then
        return
    end
    local ah = Get("auctionPrices") == true
    if ah ~= auctionOn then
        auctionOn = ah
        Forget("total")
    end
    if ah and not dbHooked then
        HookPriceUpdates()
    end
    for bagId = 0, NUM_BAG_SLOTS do
        if isStale[bagId] then
            ReadBag(bagId)
        end
    end
    local cap = Limit()
    Select(cap)
    Layout(cap)
    for index = 1, #cells do
        PaintCell(cells[index], best[index])
    end
    UpdateTitle()
    emptyFS:SetShown(bestN == 0)
    -- GET_ITEM_INFO_RECEIVED only while an item is still loading.
    local wanted = next(pending) ~= nil
    if wanted ~= itemInfoOn then
        itemInfoOn = wanted
        if wanted then
            watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else
            watcher:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
    end
    widget:Show()
end

-------------------------------------------------------------------------------
--  Visibility and settings
-------------------------------------------------------------------------------
-- Active = shown, with its events registered. While enabled but hidden by the
-- visibility setting it costs only that setting's check.
local function SetActive(on)
    if on == isActive then
        return
    end
    isActive = on
    if on then
        watcher:RegisterEvent("BAG_UPDATE")
        watcher:RegisterEvent("BAG_UPDATE_DELAYED")
        watcher:RegisterEvent("BAG_CONTAINER_UPDATE")
        watcher:RegisterEvent("EQUIPMENT_SETS_CHANGED")
        DirtyAll() -- nothing was watched while inactive
        RequestRefresh()
        return
    end
    CloseConfirm()
    watcher:UnregisterAllEvents()
    itemInfoOn = false
    wipe(pending)
    ClearSwapFlags()
    for index = 1, #cells do
        if GameTooltip:IsOwned(cells[index]) then
            GameTooltip:Hide()
        end
    end
    widget:Hide()
end

-- The shared visibility setting: re-checked by the visibility dispatcher on its
-- own edges (combat, group, zone...) and after every settings change.
local function UpdateVisibility()
    local show = (widget and Enabled() and CludesUI.EvalVisibility(Read()) == true) and true or false
    local watching = show and Get("onlyLowBagSpace") == true
    if watching ~= bagWatching then
        bagWatching = watching
        if watching then
            bagSpaceWatcher:RegisterEvent("BAG_UPDATE_DELAYED")
            bagSpaceWatcher:RegisterEvent("BAG_CONTAINER_UPDATE")
        else
            bagSpaceWatcher:UnregisterAllEvents()
        end
    end
    if watching then
        show = CountBagSlots() < Get("freeSlotThreshold")
    end
    SetActive(show)
end
bagSpaceWatcher:SetScript("OnEvent", UpdateVisibility)

local function Apply()
    if Enabled() then
        BuildFrame()
        if not visRegistered then
            visRegistered = true
            CludesUI.RegisterVisibilityUpdater(UpdateVisibility)
        end
        -- Sized and placed even while the visibility setting hides it, so Unlock
        -- Mode always has a mover to show. The fonts may have changed: the title
        -- is measured again and every price fitted again.
        titleW = 0
        wipe(lay)
        for index = 1, #cells do
            cells[index].fitW = nil
        end
        Layout(Limit())
        if not CludesUI._unlockActive then
            ApplyPosition()
        end
    elseif visRegistered then
        visRegistered = false
        CludesUI.UnregisterVisibilityUpdater(UpdateVisibility)
    end
    UpdateVisibility()
    RequestRefresh() -- settings may change what lists and how it looks
end

-- Entry points for the options page and Bags.
CludesUI._JunkItems = {
    Get = Get,
    Read = Read,
    Cfg = F.Cfg,
    Apply = Apply,
    -- Every item middle-clicked away can list again.
    ClearExclusions = function()
        CludesUIDB.junkListExcluded = nil
        RequestRefresh()
    end,
    -- Bags: a Junk Marker mark came or went, or the marker was switched. Does
    -- nothing while the window is inactive (coming back re-reads every bag).
    Refresh = RequestRefresh,
}

F.Start(Apply, {
    key = "CUI_JunkList",
    label = "Junk Items",
    order = 729,
    -- Apply builds and lays out the window whenever it is on.
    frame = function()
        return widget
    end,
    -- Follows Items Shown, the icon settings and Show Empty Bag Slots, so
    -- unlock mode moves the window but never resizes it.
    size = function()
        if widget then
            return widget:GetWidth(), widget:GetHeight()
        end
        local iconSize, num = Get("iconSize"), Limit()
        return num * iconSize + (num - 1) * Get("iconSpacing"), iconSize + 3 + PRICE_H
    end,
    snap = true,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
