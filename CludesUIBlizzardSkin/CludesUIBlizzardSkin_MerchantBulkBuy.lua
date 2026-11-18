if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_MerchantBulkBuy.lua
--  Merchant Bulk Buy (opt-in, CludesUIDB.merchantBulkBuy): a shift-click on
--  a vendor item opens a quantity window (CludesUI.CreateQuantityDialog) in
--  place of Blizzard's split popup (an item sold one at a time, which gets no
--  popup, opens it from the click alone) and buys any amount, one purchase of
--  at most GetMerchantItemMaxStack at a time, the next sent once the bags show
--  the last.
--  The hooks install on the first enable and return at once while off; events
--  are registered only while the window or a purchase confirm is up or a run
--  is going. A purchase paid in a limited currency keeps Blizzard's popup and
--  its own prompt, and so does everything under WoW Forever's Gamepad
--  interface style (CludesUI.StackSplitFor).
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local Skin = mod.WSkin
if not Skin then
    return
end

local CUI = CludesUI
local Theme = Skin.Theme
local floor, min, max = math.floor, math.min, math.max
local band = bit.band
local MAX_COSTS = MAX_ITEM_COST or 3

local BAGS = { BACKPACK_CONTAINER }
for bag = 1, NUM_BAG_SLOTS do
    BAGS[#BAGS + 1] = bag
end
local REAGENT_BAG = Enum.BagIndex and Enum.BagIndex.ReagentBag
if REAGENT_BAG then
    BAGS[#BAGS + 1] = REAGENT_BAG
end

local events = CreateFrame("Frame")
local dialog, job, hooked
local confirm -- the open purchase confirm's handle (CUI:ShowConfirmPopup)
local costParts = {} -- CostText's pieces, reused
local limits = {} -- MaxBundles' breakdown, read by the button tooltips
local TIP_OPTS = { justify = "LEFT" }

local function Enabled()
    return CludesUIDB and CludesUIDB.merchantBulkBuy == true
end

-- Free room for the item in the bags it may go into: empty slots in bags of
-- its family (a quiver takes only arrows, a soul bag only shards), the reagent
-- bag for reagents, and what its own partial stacks still hold (also returned
-- on its own).
local function BagRoom(itemId, stackSize)
    local family = C_Item.GetItemFamily(itemId) or 0
    local isReagent = select(17, C_Item.GetItemInfo(itemId))
    local room, partial = 0, 0
    for _, bag in ipairs(BAGS) do
        local fits
        if bag == REAGENT_BAG then
            fits = isReagent
        else
            local _, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
            fits = not bagFamily or bagFamily == 0 or band(bagFamily, family) ~= 0
        end
        if fits then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local ident = C_Container.GetContainerItemID(bag, slot)
                if not ident then
                    room = room + stackSize
                elseif ident == itemId then
                    local details = C_Container.GetContainerItemInfo(bag, slot)
                    local free = max(stackSize - (details and details.stackCount or stackSize), 0)
                    room = room + free
                    partial = partial + free
                end
            end
        end
    end
    return room, partial
end

-- The most whole purchases the bags, the stock, the gold and every item or
-- currency cost allow. Each limit goes into limits for the tooltips: fit,
-- afford (math.huge for a free item) and stock (-1 for unlimited) in
-- purchases, partial in items.
local function MaxBundles(index, details, itemId, step, stackSize)
    local room, partial = BagRoom(itemId, stackSize)
    local fit = floor(min(room, 999999) / step)
    local afford = math.huge
    if details.price > 0 then
        afford = floor(GetMoney() / details.price)
    end
    for idx = 1, MAX_COSTS do
        local _, value, itemLink, currencyName = GetMerchantItemCostItem(index, idx)
        if itemLink and value and value > 0 then
            local have
            if currencyName then
                local c = C_CurrencyInfo.GetCurrencyInfoFromLink(itemLink)
                have = c and c.quantity
            else
                have = C_Item.GetItemCount(itemLink, false, false, true)
            end
            if have then
                afford = min(afford, floor(have / value))
            end
        end
    end
    local num = min(fit, afford)
    if details.numAvailable >= 0 then
        num = min(num, details.numAvailable)
    end
    limits.fit, limits.afford, limits.stock, limits.partial = fit, afford, details.numAvailable, partial
    return max(num, 0)
end

local function CostText(index, details, bundles)
    local parts = costParts
    wipe(parts)
    if details.price > 0 then
        parts[#parts + 1] = C_CurrencyInfo.GetCoinTextureString(details.price * bundles)
    end
    for idx = 1, MAX_COSTS do
        local texture, value = GetMerchantItemCostItem(index, idx)
        if texture and value and value > 0 then
            parts[#parts + 1] = (value * bundles) .. " |T" .. texture .. ":0|t"
        end
    end
    return table.concat(parts, "  ")
end

-- A purchase paid in a limited currency: Blizzard confirms it with its own
-- prompt, which says when it is the last one you can make.
local function LimitedCurrencyCost(index)
    if (GetMerchantItemCostInfo(index) or 0) ~= 1 then
        return false
    end
    local _, _, itemLink = GetMerchantItemCostItem(index, 1)
    local limited = C_Item.GetLimitedCurrencyItemInfo
    return itemLink ~= nil and limited ~= nil and limited(itemLink) ~= nil
end

local function SyncEvents()
    if job or confirm or (dialog and dialog:IsShown()) then
        events:RegisterEvent("MERCHANT_CLOSED")
    else
        events:UnregisterEvent("MERCHANT_CLOSED")
    end
    if job then
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("UI_ERROR_MESSAGE")
    else
        events:UnregisterEvent("BAG_UPDATE_DELAYED")
        events:UnregisterEvent("UI_ERROR_MESSAGE")
    end
end

-- Ends the run. One that ends short (a red error, full bags, the merchant
-- closed, a new order) says how far it got.
local function StopJob()
    local jdx = job
    job = nil
    SyncEvents()
    if not jdx then
        return
    end
    local got = C_Item.GetItemCount(jdx.itemID) - jdx.base
    if got < jdx.target then
        CUI.Print(CludesUI.Lf("Bulk Buy stopped after %1$d of %2$d.", max(got, 0), jdx.target))
    end
end

-- Sends the next purchase once the bags show the last one; stops on a drop
-- in the count, at the target, or when the merchant no longer sells the item.
local function StepJob()
    local jdx = job
    if not jdx then
        return
    end
    local total = C_Item.GetItemCount(jdx.itemID)
    if total < jdx.last then
        StopJob()
        return
    end
    jdx.last = total
    local got = total - jdx.base
    if got < jdx.issued then
        return
    end
    local num = floor(min(jdx.chunk, jdx.target - got) / jdx.step) * jdx.step
    if num <= 0 or GetMerchantItemID(jdx.index) ~= jdx.itemID then
        StopJob()
        return
    end
    jdx.issued = got + num
    BuyMerchantItem(jdx.index, num)
end

-- One order at a time: a new one ends the run still going (and says so).
local function StartJob(index, itemId, qty, step, chunk)
    if job then
        StopJob()
    end
    if GetMerchantItemID(index) ~= itemId then
        return
    end
    local total = C_Item.GetItemCount(itemId)
    job = {
        index = index,
        itemID = itemId,
        target = qty,
        step = step,
        chunk = chunk,
        base = total,
        last = total,
        issued = 0,
    }
    SyncEvents()
    StepJob()
end

-- The window's onChange: the total for the amount, Buy only with one to buy.
local function ShowCost(qty)
    local skinData = dialog
    skinData._extra:SetText(CludesUI.Lf("Total: %s", CostText(skinData._index, skinData._info, qty / skinData._step)))
    local buy = skinData._buttons.buy
    buy:SetEnabled(qty > 0)
    buy:SetAlpha(qty > 0 and 1 or 0.3)
end

-- Re-reads the item after a merchant repaint (paging, the Buyback tab, stock
-- or money changes) and closes the window once its button moved on.
local function Refresh()
    local skinData = dialog
    local index, ownerFrame = skinData._index, skinData._owner
    local details = (MerchantFrame.selectedTab or 1) == 1 and C_MerchantFrame.GetItemInfo(index)
    if
        not details
        or GetMerchantItemID(index) ~= skinData._itemID
        or not ownerFrame:IsVisible()
        or ownerFrame:GetID() ~= index
    then
        skinData:Hide()
        return
    end
    skinData._info = details
    local step = max(details.stackCount, 1)
    skinData:SetRange(step, MaxBundles(index, details, skinData._itemID, step, skinData._stackSize) * step, skinData._chunk)
    if skinData._eb:HasFocus() and skinData._eb:GetNumber() <= skinData._max then
        ShowCost(skinData:Current())
    else
        skinData:SetValue(skinData:Current())
    end
end

local function DoBuy()
    local skinData = dialog
    local qty = skinData:Current()
    local index, itemId, step, chunk, details = skinData._index, skinData._itemID, skinData._step, skinData._chunk, skinData._info
    skinData:Hide()
    if qty < step then
        return
    end
    local bundles = qty / step
    local function start()
        confirm = nil
        StartJob(index, itemId, qty, step, chunk)
    end
    if details.hasExtendedCost or details.price * bundles >= (MERCHANT_HIGH_PRICE_COST or 1500000) then
        local msg = CludesUI.Lf(
            "Buy %1$d x %2$s for %3$s?",
            qty,
            GetMerchantItemLink(index) or details.name or "",
            CostText(index, details, bundles)
        )
        if not C_MerchantFrame.IsMerchantItemRefundable(index) then
            msg = msg .. "\n\n" .. CludesUI.L("This purchase is not refundable.")
        end
        confirm = CUI:ShowConfirmPopup({
            title = "Bulk Buy",
            message = msg,
            confirmText = "Buy",
            cancelText = "Cancel",
            onConfirm = start,
            onCancel = function()
                confirm = nil
                SyncEvents()
            end,
        })
        SyncEvents()
    else
        start()
    end
end

-- Enter and Buy: a typed amount that is not a whole number of purchases first
-- snaps to one, so the box shows what is bought.
local function BuyOrSnap()
    local q = dialog:Current()
    if q ~= dialog._eb:GetNumber() then
        dialog:SetValue(q)
        return
    end
    DoBuy()
end

-- +1 Stack: up to the next full stack, at least one more purchase.
local function NextStack()
    local skinData = dialog
    local current = skinData:Current()
    local num = (floor(current / skinData._stackSize) + 1) * skinData._stackSize
    if floor(num / skinData._step) * skinData._step <= current then
        num = current + skinData._step
    end
    return num
end

-- The accent, read on every use (it can change at any time).
local function Accent(s)
    local ACC = CUI.CLUDES_GREEN
    return CUI.ColorText(s, ACC.r, ACC.g, ACC.b)
end

-- A Max tooltip amount: purchases shown in items, in the accent when it is the limit.
local function LimitAmount(bundles, topY)
    local s = tostring(bundles * dialog._step)
    return bundles == topY and Accent(s) or s
end

-- Max's tooltip: what the bags, the money and the stock each allow.
local function MaxTip()
    local skinData, lim = dialog, limits
    local topY = floor(skinData._max / skinData._step)
    local t = CludesUI.Lf("You can buy: %s", Accent(skinData._max))
        .. "\n"
        .. CludesUI.Lf("You can fit: %s", LimitAmount(lim.fit, topY))
    if lim.afford ~= math.huge then
        t = t .. "\n" .. CludesUI.Lf("You can afford: %s", LimitAmount(lim.afford, topY))
    end
    if lim.stock >= 0 then
        t = t .. "\n" .. CludesUI.Lf("Vendor has: %s", LimitAmount(lim.stock, topY))
    end
    return t
end

-- +1 Stack's tooltip: where a click takes the amount, the stack size, and the
-- room left in the partial stacks already in the bags.
local function StackTip()
    local skinData = dialog
    local num = floor(min(NextStack(), skinData._max) / skinData._step) * skinData._step
    local t = CludesUI.Lf("+1 Stack goes to: %s", Accent(max(num, 0)))
        .. "\n"
        .. CludesUI.Lf("Stack size: %d", skinData._stackSize)
    if limits.partial > 0 then
        t = t .. "\n" .. CludesUI.Lf("Room in partial stacks: %d", limits.partial)
    end
    return t
end

local function AddStack(button)
    dialog:SetValue(NextStack())
    -- The tooltip under the cursor follows the new amount.
    if button:IsMouseOver() then
        CUI.ShowWidgetTooltip(button, StackTip, TIP_OPTS)
    end
end

-- Blizzard Skins+' look on the shared quantity window: the theme's surface,
-- border, close button and edit box, popup buttons in the theme's font.
local SKIN = {
    frame = function(skinData)
        Skin.SolidTex(skinData, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, 1):SetAllPoints()
        Skin.AddBorder(skinData)
    end,
    font = function(fontStr, size)
        Skin.Font(fontStr, nil, nil, nil, size)
    end,
    button = function(hostFrame, wid, hgt, labelText)
        local button = CUI.MakePopupButton(
            hostFrame,
            "CENTER",
            hostFrame,
            "CENTER",
            0,
            0,
            1,
            1,
            1,
            0.7,
            1,
            1,
            1,
            0.9,
            1,
            1,
            1,
            0.5,
            1,
            1,
            1,
            0.6,
            true
        )
        button:SetSize(wid, hgt)
        button:ClearAllPoints()
        Skin.Font(button._lbl, nil, nil, nil, 12)
        button._lbl:SetText(labelText)
        return button
    end,
    editBox = function(editField)
        editField:SetFont(Theme.fontPath, 12, Theme.fontFlag or "")
        Skin.EditBox(editField)
    end,
    close = function(close)
        close:SetSize(18, 18)
        close:SetPoint("TOPRIGHT", close:GetParent(), "TOPRIGHT", -4, -5)
        Skin.CloseButton(close)
    end,
}

local function CreateDialog()
    if not Theme.fontPath then
        Skin.ResolveTheme()
    end
    return CUI.CreateQuantityDialog({
        name = "CUI_MerchantBulkBuyFrame",
        width = 232,
        height = 121,
        title = CludesUI.L("Bulk Buy"),
        editWidth = 64,
        maxLetters = 6,
        extraLine = true,
        skin = SKIN,
        onChange = ShowCost,
        onEnter = BuyOrSnap,
        onShow = SyncEvents,
        onHide = SyncEvents,
        buttons = {
            {
                key = "stack",
                label = CludesUI.L("+1 Stack"),
                width = 66,
                height = 27,
                point = "BOTTOMLEFT",
                onClick = AddStack,
                tooltip = StackTip,
                tooltipOpts = TIP_OPTS,
            },
            {
                key = "max",
                label = CludesUI.L("Max"),
                width = 66,
                height = 27,
                point = "BOTTOM",
                onClick = function()
                    dialog:SetValue(dialog._max)
                end,
                tooltip = MaxTip,
                tooltipOpts = TIP_OPTS,
            },
            {
                key = "buy",
                label = CludesUI.L("Buy"),
                width = 66,
                height = 27,
                point = "BOTTOMRIGHT",
                onClick = BuyOrSnap,
                primary = true,
            },
        },
    })
end

local function Validate()
    if dialog and dialog:IsShown() then
        Refresh()
    end
end
-- Merchant repaints come in bursts: one refresh per frame while the window shows.
local refreshSoon = Skin.Debounce(Validate)

-- A shift-click on an item sold one at a time, unless it went into a focused
-- edit box (not the window's own) as a link.
local function SingleBuyClick(index)
    local focus = GetCurrentKeyBoardFocus()
    return (MerchantFrame.selectedTab or 1) == 1
        and IsModifiedClick("SPLITSTACK")
        and GetMerchantItemMaxStack(index) == 1
        and (not focus or (dialog ~= nil and focus == dialog._eb))
        and not CUI.PadGamepadUI()
end

local function TakeOver(btnFrame)
    if not Enabled() then
        return
    end
    local index = btnFrame:GetID()
    local split = CUI.StackSplitFor(btnFrame)
    if not split and not (index and SingleBuyClick(index)) then
        return
    end
    local itemId = index and GetMerchantItemID(index)
    local details = itemId and C_MerchantFrame.GetItemInfo(index)
    if not details or details.currencyID or LimitedCurrencyCost(index) then
        return
    end
    if split then
        CUI.TakeStackSplit()
    end
    dialog = dialog or CreateDialog()
    local step = max(details.stackCount, 1)
    dialog._owner, dialog._index, dialog._itemID = btnFrame, index, itemId
    local maxStack = GetMerchantItemMaxStack(index)
    dialog._chunk = max(floor((maxStack or step) / step) * step, step)
    -- An item not loaded yet reads no stack size: one purchase's cap stands in.
    dialog._stackSize = max(C_Item.GetItemMaxStackSizeByID(itemId) or maxStack or step, 1)
    dialog._eb:SetText(tostring(step))
    -- Buy wears the accent, read on every open (it can change at any time).
    local button = dialog._buttons
    local ACC = CUI.CLUDES_GREEN
    button.buy._setColors(
        ACC.r,
        ACC.g,
        ACC.b,
        0.9,
        ACC.r,
        ACC.g,
        ACC.b,
        1,
        ACC.r,
        ACC.g,
        ACC.b,
        0.9,
        ACC.r,
        ACC.g,
        ACC.b,
        1
    )
    button.buy._resetAnim()
    button.max._resetAnim()
    button.stack._resetAnim()
    dialog:Open(btnFrame)
    Refresh()
    if dialog:IsShown() then
        dialog:FocusInput()
    end
end

-- A merchant repaint: Blizzard's MerchantFrame_Update, or Expand Vendor UI's
-- grid, which repaints its own tiles (page flips) without one.
local function OnRepaint()
    if dialog and dialog:IsShown() then
        refreshSoon()
    end
end
CludesUI._Merchant_BulkBuyRepaint = OnRepaint

local function Install()
    if hooked then
        return
    end
    hooked = true
    if type(MerchantItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", TakeOver)
    end
    if type(MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", OnRepaint)
    end
end

CludesUI._Merchant_RefreshBulkBuy = function()
    if Enabled() then
        Install()
        return
    end
    if confirm then
        CUI:CloseConfirmPopup(confirm)
        confirm = nil
    end
    if dialog then
        dialog:Hide()
    end
    StopJob()
end

events:SetScript("OnEvent", function(self, evt, arg1)
    if evt == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        if Enabled() then
            Install()
        end
    elseif evt == "BAG_UPDATE_DELAYED" then
        StepJob()
    elseif evt == "MERCHANT_CLOSED" then
        if confirm then
            CUI:CloseConfirmPopup(confirm)
            confirm = nil
        end
        if dialog then
            dialog:Hide()
        end
        StopJob()
    else
        -- UI_ERROR_MESSAGE: any red error during a run ends it, so a purchase
        -- the server refused (full bags, too little money) never stalls it.
        StopJob()
    end
end)
events:RegisterEvent("ADDON_LOADED")
