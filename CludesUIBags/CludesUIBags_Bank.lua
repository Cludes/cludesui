if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_Bank.lua
--  Bank UI module - opens when interacting with a banker NPC
--  Visually matches the Bags module with sidebar, search, and sorting
-------------------------------------------------------------------------------
local CUI = CludesUI
local mod = select(2, ...) -- helpers shared with CludesUIBags.lua and the CUI_Bags_*.lua files (loaded first)
local GetItemInfo = C_Item.GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetItemQualityColor = C_Item.GetItemQualityColor
-- Profile access helper (DB created in CUI_Bags_Options.lua, loaded first per TOC)
local _emptyP = {}
local function BagsProfile()
    return (CUI._bagsDB and CUI._bagsDB.profile) or _emptyP
end

-- The bank has no MultiBank view, so both the OneBag and MultiBag default
-- types open the bank to its consolidated OneBank/OneWarbank view; only the
-- "all" default opens the categorized All-Tabs view. Resolver lives in the
-- main bags file (CUI._GetBagDefaultType) and honors the legacy boolean.
local function BankDefaultsToOne()
    if not CUI._GetBagDefaultType then
        return false
    end
    return CUI._GetBagDefaultType() ~= "all"
end

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local SLOT_SIZE, SPACING = mod.SLOT_SIZE, mod.SPACING
mod.OnSlotMetrics(function(m)
    SLOT_SIZE, SPACING = m[1], m[2]
end)
local HEADER_H = 35
local FOOTER_H = 32
local SIDEBAR_W = 160
local SIDEBAR_W_COLLAPSED = 32
local SIDEBAR_BTN_H = 26
local SIDEBAR_ICON_SIZE = 18
local SIDEBAR_PAD = 2
-- Grid columns and window height; the resize grip saves both
local function GetBankColumns()
    return BagsProfile().bankColumns or 14
end
local function GetBankHeight()
    return BagsProfile().bankHeight or 500
end
local SCROLLBAR_HIT_W = 16

-- Runtime state
local _selectedView = 0 -- 0 = All Bank Tabs, -1 = OneBank, -2 = All Warbank, -3 = OneWarbank, >0 = tab index
local _allTabs = {} -- populated on bank open: { bagID, name, isWarband, numSlots, icon, depositFlags }
local _warbandOnly = false -- true when opened via portable warbank (AccountBanker interaction)
-- Category sidebar selection. nil = a normal view/tab is showing; otherwise
-- { group = "<group name>" } or { key = "<category _defaultName>", detail = "<bucket label>" }.
-- Keyed by _defaultName rather than list index so a drag-reorder in the bags
-- sidebar cannot silently repoint the bank selection at another category.
local _catSel = nil
local _catIndex = nil -- rebuilt every refresh; see BuildBankCategoryIndex

local function GetBankSidebarWidth()
    local navCollapsed = BagsProfile().bankSidebarCollapsed
    return navCollapsed and SIDEBAR_W_COLLAPSED or SIDEBAR_W
end

local function GetFont()
    return CUI.GetFontPath("bags")
end
local function SetBankFont(fontStr, size)
    CludesUI.PrimeFontShadow(fontStr, true)
    fontStr:SetFont(GetFont(), size, CUI.GetFontOutlineFlag("bags"))
end
local GetUpgradeTrack = CUI.GetUpgradeTrack
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon
local ITEM_CLASS_ARMOR = Enum.ItemClass.Armor
local function IsGearItem(linkText)
    if not linkText then
        return false
    end
    local _, _, _, _, _, classID = GetItemInfoInstant(linkText)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
local function GetItemLevelAtLocation(loc, linkText)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
        local level = C_Item.GetCurrentItemLevel(loc)
        if level and level > 0 then
            return level
        end
    end
    return linkText and C_Item.GetDetailedItemLevelInfo(linkText) or nil
end
local function GetAccentRGB()
    if CUI.GetAccentColor then
        return CUI.GetAccentColor()
    end
    return 0.30, 0.79, 0.94
end

local SetInsetBorderColor = mod.SetInsetBorderColor

-------------------------------------------------------------------------------
--  Bank Tab Discovery (Midnight 12.0+ uses CharacterBankTab / AccountBankTab enums)
-------------------------------------------------------------------------------
-- Fallback icons for tabs without a user-assigned icon
local FALLBACK_ICONS = {
    5524917,
    133668,
    4641307,
    133659,
    133656,
    348524,
    348520,
    133660,
    4549238,
    5931149,
    4549226,
    1379173,
    348523,
    2023244,
}
local _usedFallbackIdx = 0
local _tabIconCache = {} -- bagID -> icon (persists for session)

local function GetFallbackIcon(bagId)
    if _tabIconCache[bagId] then
        return _tabIconCache[bagId]
    end
    _usedFallbackIdx = _usedFallbackIdx + 1
    local iconTex = FALLBACK_ICONS[((_usedFallbackIdx - 1) % #FALLBACK_ICONS) + 1]
    _tabIconCache[bagId] = iconTex
    return iconTex
end

mod.BankDefaultsToOne = BankDefaultsToOne -- the offline view orders its sidebar the same way

-- a tab's icon, or a fallback if it has none (saved tabs use it too)
function mod.BankTabIcon(bagId, iconTex)
    if iconTex and iconTex ~= 134400 then
        return iconTex
    end
    return bagId and GetFallbackIcon(bagId) or 134400
end

local CHARACTER_BANK_BAGS = {}
local WARBAND_BANK_BAGS = {}
if Enum and Enum.BagIndex then
    -- Character bank: CharacterBankTab_1 through _6 (WoW Forever has up to _9:
    -- the base bank plus its bank bag slots). Missing enum keys are skipped.
    for i = 1, 9 do
        local sortKey = "CharacterBankTab_" .. i
        if Enum.BagIndex[sortKey] then
            CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex[sortKey]
        end
    end
    -- Warband bank: AccountBankTab_1 through AccountBankTab_5
    for i = 1, 5 do
        local sortKey = "AccountBankTab_" .. i
        if Enum.BagIndex[sortKey] then
            WARBAND_BANK_BAGS[#WARBAND_BANK_BAGS + 1] = Enum.BagIndex[sortKey]
        end
    end
end

local function GetCharacterBankTabs()
    local tabList = {}
    -- Use C_Bank.FetchPurchasedBankTabData for tab metadata (name, icon)
    local tabInfo
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabInfo = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    end
    if tabInfo then
        for i, td in ipairs(tabInfo) do
            local bagId = CHARACTER_BANK_BAGS[i]
            if bagId then
                local slotCount = C_Container.GetContainerNumSlots(bagId)
                if slotCount > 0 then
                    local iconTex = td.icon
                    if not iconTex or iconTex == 134400 then
                        iconTex = GetFallbackIcon(bagId)
                    end
                    tabList[#tabList + 1] = {
                        bagID = bagId,
                        numSlots = slotCount,
                        name = td.name or CUI.Lf("Bank Tab %1$d", i),
                        icon = iconTex,
                        depositFlags = td.depositFlags or 0,
                    }
                end
            end
        end
    else
        for i, bagId in ipairs(CHARACTER_BANK_BAGS) do
            local slotCount = C_Container.GetContainerNumSlots(bagId)
            if slotCount > 0 then
                tabList[#tabList + 1] = {
                    bagID = bagId,
                    numSlots = slotCount,
                    name = CUI.Lf("Bank Tab %1$d", #tabList + 1),
                    icon = GetFallbackIcon(bagId),
                    depositFlags = 0,
                }
            end
        end
    end
    return tabList
end

local function GetWarbandBankTabs()
    local tabList = {}
    -- Check if warband bank is locked
    if C_Bank and C_Bank.FetchBankLockedReason and Enum.BankType then
        if C_Bank.FetchBankLockedReason(Enum.BankType.Account) ~= nil then
            return tabList
        end
    end
    local tabInfo
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabInfo = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
    end
    if tabInfo then
        for i, td in ipairs(tabInfo) do
            local bagId = WARBAND_BANK_BAGS[i]
            if bagId then
                local slotCount = C_Container.GetContainerNumSlots(bagId)
                if slotCount > 0 then
                    local caption = td.name or CUI.Lf("Tab %1$d", i)
                    local iconTex = td.icon
                    if not iconTex or iconTex == 134400 then
                        iconTex = GetFallbackIcon(bagId)
                    end
                    tabList[#tabList + 1] = {
                        bagID = bagId,
                        numSlots = slotCount,
                        name = CUI.L("Warbank") .. " " .. caption,
                        shortName = caption,
                        icon = iconTex,
                        depositFlags = td.depositFlags or 0,
                    }
                end
            end
        end
    else
        for i, bagId in ipairs(WARBAND_BANK_BAGS) do
            local slotCount = C_Container.GetContainerNumSlots(bagId)
            if slotCount > 0 then
                tabList[#tabList + 1] = {
                    bagID = bagId,
                    numSlots = slotCount,
                    name = CUI.L("Warbank") .. " " .. CUI.Lf("Tab %1$d", #tabList + 1),
                    icon = GetFallbackIcon(bagId),
                    depositFlags = 0,
                }
            end
        end
    end
    return tabList
end

-------------------------------------------------------------------------------
--  Main Frame
-------------------------------------------------------------------------------
local CUI_Bank = CreateFrame("Frame", "CUI_BankFrame", UIParent)
CUI_Bank:SetToplevel(true)
do
    local frameStrata = mod.BagFrameStrata()
    CUI_Bank:SetFrameStrata(frameStrata)
    CUI_Bank:SetFrameLevel(frameStrata == "HIGH" and 50 or 1)
end
CUI_Bank:EnableMouse(true)
CUI_Bank:SetMovable(true)
CUI_Bank:SetClampedToScreen(true)
CUI_Bank:Hide()

-- Background: atlas matching bags module (full alpha, covers entire window)
local bgAtlas = CUI_Bank:CreateTexture(nil, "BACKGROUND")
bgAtlas:SetAllPoints()
bgAtlas:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
local bgOverlay = CUI_Bank:CreateTexture(nil, "BACKGROUND", nil, 1)
bgOverlay:SetAllPoints()
bgOverlay:SetColorTexture(0, 0, 0, 0.25)
CUI_Bank._bg, CUI_Bank._bgOverlay = bgAtlas, bgOverlay -- background color/opacity
CUI_Bank._flatBorder = CUI.MakeBorder(CUI_Bank, 1, 1, 1, 0.15, CUI.PP)._frame

-------------------------------------------------------------------------------
--  Header
-------------------------------------------------------------------------------
local headerBar = CreateFrame("Frame", nil, CUI_Bank)
headerBar:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", 0, 0)
headerBar:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", 0, 0)
headerBar:SetHeight(HEADER_H)
local hdrBg = headerBar:CreateTexture(nil, "BACKGROUND", nil, 1)
hdrBg:SetAllPoints()
hdrBg:SetColorTexture(0, 0, 0, 0.5)

local titleText = headerBar:CreateFontString(nil, "OVERLAY")
SetBankFont(titleText, 13)
titleText:SetPoint("LEFT", headerBar, "LEFT", 8, 0)
titleText:SetTextColor(1, 1, 1)
titleText:SetText(CludesUI.L("Bank"))
CUI_Bank._headerTitle = titleText -- the alt button sits next to this

local itemCount = headerBar:CreateFontString(nil, "OVERLAY")
SetBankFont(itemCount, 11)
itemCount:SetPoint("LEFT", titleText, "RIGHT", 8, 0)
itemCount:SetTextColor(0.6, 0.6, 0.6)
CUI_Bank._headerItemCount = itemCount

-- Search box
local searchBox = CreateFrame("EditBox", "CUI_BankSearchBox", headerBar)
searchBox:SetSize(160, 22)
searchBox:SetPoint("RIGHT", headerBar, "RIGHT", -35, 0)
searchBox:SetFont(GetFont(), 12, "")
searchBox:SetAutoFocus(false)
searchBox:SetTextInsets(5, 26, 0, 0)
local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
searchBg:SetAllPoints()
searchBg:SetColorTexture(0.02, 0.02, 0.02, 1)
if CUI and CUI.PanelPP then
    CUI.PanelPP.CreateBorder(searchBox, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
end

local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
SetBankFont(searchPlaceholder, 11)
searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
searchPlaceholder:SetText(CludesUI.L("Search..."))
searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
CUI_Bank._searchBox = searchBox

-- Search clear button
local clearSearchBtn = CreateFrame("Button", nil, searchBox)
clearSearchBtn:SetSize(22, 22)
clearSearchBtn:SetPoint("RIGHT", searchBox, "RIGHT", 0, 0)
clearSearchBtn.tex = clearSearchBtn:CreateFontString(nil, "OVERLAY")
SetBankFont(clearSearchBtn.tex, 14)
clearSearchBtn.tex:SetText("x")
clearSearchBtn.tex:SetPoint("CENTER", 0, 1)
clearSearchBtn.tex:SetTextColor(0.8, 0.8, 0.8)
clearSearchBtn:Hide()
clearSearchBtn:SetScript("OnClick", function()
    searchBox:SetText("")
    searchBox:ClearFocus()
    CUI_Bags.ClearSearch()
end)

searchBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    CUI_Bags.ClearSearch()
end)
-- Both windows repaint when the game reports the search (CUI_Bags.SetSearchText).
local bankSearchChanged = CUI_Bags.WatchSearchBox(searchBox, CUI_Bags.SetSearchText)
searchBox:SetScript("OnTextChanged", function(self, userInput)
    local textValue = self:GetText()
    searchPlaceholder:SetShown(textValue == "")
    clearSearchBtn:SetShown(textValue ~= "")
    bankSearchChanged(userInput)
end)

-- Sort button
local sortButton = CreateFrame("Button", nil, headerBar)
sortButton:SetSize(24, 24)
sortButton:SetPoint("RIGHT", searchBox, "LEFT", -13, 0)
sortButton.icon = sortButton:CreateTexture(nil, "OVERLAY")
sortButton.icon:SetAllPoints()
sortButton.icon:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\clean-up.png")
sortButton.icon:SetAlpha(0.9)

local bankSortLocked = false
local function LockBankSort()
    bankSortLocked = true
    sortButton:EnableMouse(false)
    sortButton.icon:SetAlpha(0.2)
end
local function UnlockBankSort()
    if not bankSortLocked then
        return
    end
    bankSortLocked = false
    sortButton:EnableMouse(true)
    sortButton.icon:SetAlpha(0.9)
end

sortButton:SetScript("OnEnter", function(self)
    self.icon:SetAlpha(1)
    CUI.ShowWidgetTooltip(self, "Sort Items")
end)
sortButton:SetScript("OnLeave", function(self)
    self.icon:SetAlpha(0.9)
    CUI.HideWidgetTooltip()
end)
sortButton:SetScript("OnClick", function()
    if bankSortLocked then
        return
    end
    PlaySound(SOUNDKIT.UI_BAG_SORTING_01)
    LockBankSort()
    -- Bank cleanup is Blizzard's, and it reads the same fill-direction setting
    -- the bags module's MultiBag sort uses. Right-to-left starts at the first
    -- container (our top); clearing it packs items into the last slots instead.
    -- Written only while Sort to Bottom is on, so an untouched setup keeps the
    -- player's own cleanup direction.
    if BagsProfile().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
        C_Container.SetSortBagsRightToLeft(false)
    end
    local warbandBank = (_selectedView == -2 or _selectedView == -3)
    if not warbandBank and _selectedView > 0 and _allTabs[_selectedView] then
        warbandBank = _allTabs[_selectedView].isWarband
    end
    if warbandBank then
        C_Container.SortBank(Enum.BankType.Account)
    else
        C_Container.SortBank(Enum.BankType.Character)
    end
    C_Timer.After(3, UnlockBankSort)
end)

-- Close button (created after search/sort so it renders on top)
local closeBtn = CreateFrame("Button", nil, headerBar)
closeBtn:SetSize(12, 12)
closeBtn:SetPoint("RIGHT", headerBar, "RIGHT", -9, 0)
closeBtn.icon = closeBtn:CreateTexture(nil, "OVERLAY")
closeBtn.icon:SetAllPoints()
closeBtn.icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
closeBtn.icon:SetAlpha(0.7)
closeBtn:SetScript("OnEnter", function()
    closeBtn.icon:SetAlpha(0.9)
end)
closeBtn:SetScript("OnLeave", function()
    closeBtn.icon:SetAlpha(0.7)
end)
closeBtn:SetScript("OnClick", function()
    CUI_Bank:Hide()
end)

-- Header bottom-edge separator (1px physical pixel)
do
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local hdrSep = headerBar:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(px)
    hdrSep:SetPoint("BOTTOMLEFT", headerBar, "BOTTOMLEFT", 0, 0)
    hdrSep:SetPoint("BOTTOMRIGHT", headerBar, "BOTTOMRIGHT", 0, 0)
    hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    headerBar.separator = hdrSep
end

-------------------------------------------------------------------------------
--  Bank bag slots (WoW Forever)
--  Forever's character bank tabs are bag slots: a bought tab holds nothing
--  until a bag is placed in it (Blizzard's Camelot BankFrame bag buttons).
-------------------------------------------------------------------------------
local RefreshBankBags
local bankBagsWindow
if CUI.IS_FOREVER then
    local BANK_BAG_SLOTS = Enum.BagIndex.Characterbanktab

    local bankBagsPanel = CreateFrame("Frame", nil, CUI_Bank)
    bankBagsWindow = bankBagsPanel
    bankBagsPanel:Hide()
    bankBagsPanel:SetFrameLevel(CUI_Bank:GetFrameLevel() + 20)
    bankBagsPanel:EnableMouse(true)
    bankBagsPanel:SetClampedToScreen(true)
    local winBg = bankBagsPanel:CreateTexture(nil, "BACKGROUND")
    winBg:SetAllPoints()
    winBg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    CUI.PanelPP.CreateBorder(bankBagsPanel, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)

    local bankBagsBtn = CreateFrame("Button", nil, headerBar)
    CUI_Bank._bagsBtn = bankBagsBtn
    bankBagsBtn:SetSize(24, 24)
    bankBagsBtn:SetPoint("RIGHT", sortButton, "LEFT", -6, 0)
    bankBagsBtn.icon = bankBagsBtn:CreateTexture(nil, "ARTWORK")
    bankBagsBtn.icon:SetAllPoints()
    bankBagsBtn.icon:SetAtlas("bag-main")
    bankBagsBtn.icon:SetAlpha(0.9)
    bankBagsPanel:SetPoint("BOTTOMRIGHT", bankBagsBtn, "TOPRIGHT", 0, 2)

    bankBagsBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not bankBagsPanel:IsShown() then
            CUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bankBagsBtn:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)
    bankBagsBtn:SetScript("OnClick", function()
        if bankBagsPanel:IsShown() then
            bankBagsPanel:Hide()
        else
            CUI.HideWidgetTooltip()
            bankBagsPanel:Show()
        end
    end)

    local function PickupBag(self)
        if self.bought then
            C_Container.PickupContainerItem(BANK_BAG_SLOTS, self.bagSlot)
        end
    end

    local slotTable = {}
    local function GetOrCreateBagSlot(position)
        if slotTable[position] then
            return slotTable[position]
        end
        local button = CreateFrame("Button", nil, bankBagsPanel)
        mod.SizeSlot(button)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.Count = button:CreateFontString(nil, "OVERLAY")
        CludesUI.ApplyIconTextFont(button.Count, GetFont(), BagsProfile().bagCountFontSize or 11, "bags")
        button.Count:SetPoint("BOTTOMRIGHT", -2, 2)
        button.Count:SetTextColor(1, 1, 1)
        mod.CreateInsetBorder(button, true)
        button:SetScript("OnClick", PickupBag)
        button:SetScript("OnDragStart", PickupBag)
        button:SetScript("OnReceiveDrag", PickupBag)
        button:SetScript("OnEnter", function(self)
            SetInsetBorderColor(self, 1, 1, 1, 1)
            if self.hasBag then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetBagItem(BANK_BAG_SLOTS, self.bagSlot)
                GameTooltip:Show()
            else
                CUI.ShowWidgetTooltip(self, self.bought and BANK_BAG or BANK_BAG_PURCHASE)
            end
        end)
        button:SetScript("OnLeave", function(self)
            SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
            GameTooltip:Hide()
            CUI.HideWidgetTooltip()
        end)
        slotTable[position] = button
        return button
    end

    RefreshBankBags = function()
        if not bankBagsPanel:IsShown() then
            return
        end
        local maxBags = C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character)
        local bought = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
        local zoom = BagsProfile().bagItemIconZoom or 0.08
        local num = 0
        -- Slot 1 is the bank itself; bag slots start at 2.
        for bagSlot = 2, maxBags do
            num = num + 1
            local button = GetOrCreateBagSlot(num)
            button.bagSlot = bagSlot
            button.bought = bought[bagSlot] ~= nil
            local details = button.bought and C_Container.GetContainerItemInfo(BANK_BAG_SLOTS, bagSlot)
            button.hasBag = details and true or false
            button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            button.icon:SetTexture(
                details and details.iconFileID or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
            )
            button.icon:SetDesaturated(not button.bought)
            button.icon:SetAlpha(button.bought and 1 or 0.35)
            if details then
                button.Count:SetText(
                    C_Container.GetContainerNumFreeSlots(Enum.BagIndex.CharacterBankTab_1 + bagSlot - 1)
                )
                button.Count:Show()
            else
                button.Count:Hide()
            end
            -- quality is nilable (item data not cached yet).
            local q = details and details.quality
            if q and q > 0 then
                button._bdrR, button._bdrG, button._bdrB = mod.QualityBorderColor(q)
            else
                button._bdrR, button._bdrG, button._bdrB = 0.25, 0.25, 0.25
            end
            SetInsetBorderColor(button, button._bdrR, button._bdrG, button._bdrB, 1)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", bankBagsPanel, "TOPLEFT", 10 + (num - 1) * (SLOT_SIZE + SPACING), -10)
            button:Show()
        end
        for i = num + 1, #slotTable do
            slotTable[i]:Hide()
        end
        bankBagsPanel:SetSize(math.max(num, 1) * (SLOT_SIZE + SPACING) + 16, SLOT_SIZE + 20)
    end
    bankBagsPanel:SetScript("OnShow", function(self)
        if not self._foreverStyled and mod.SkinForeverBagWindow(self, winBg) then
            self._foreverStyled = true
            CUI.PanelPP.HideBorder(self)
        end
        RefreshBankBags()
    end)
end

-------------------------------------------------------------------------------
--  Footer: Player Gold (left) + Warband Gold (right)
-------------------------------------------------------------------------------
do
    local footerBar = CreateFrame("Frame", nil, CUI_Bank)
    footerBar:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", 0, 0)
    footerBar:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", 0, 0)
    footerBar:SetHeight(FOOTER_H)
    local ftrBg = footerBar:CreateTexture(nil, "BACKGROUND", nil, 1)
    ftrBg:SetAllPoints()
    ftrBg:SetColorTexture(0, 0, 0, 0.35)

    -- Top-edge separator
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local ftrSep = footerBar:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footerBar, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    footerBar.bg, footerBar.separator = ftrBg, ftrSep
    CUI_Bank.Footer = footerBar

    -- Shared formatting
    local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"
    local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:0:0|t"
    local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:0:0|t"
    -- gold, plus silver and copper if there's any (the warbank takes both)
    local function FormatGold(copperAmount)
        if not copperAmount or copperAmount == 0 then
            return "0" .. GOLD_ICON
        end
        local gold = math.floor(copperAmount / 10000)
        local silver = math.floor(copperAmount / 100) % 100
        local cop = copperAmount % 100
        local parts = {}
        if gold > 0 then
            parts[#parts + 1] = BreakUpLargeNumbers(gold) .. GOLD_ICON
        end
        if silver > 0 then
            parts[#parts + 1] = silver .. SILVER_ICON
        end
        if cop > 0 then
            parts[#parts + 1] = cop .. COPPER_ICON
        end
        return table.concat(parts, " ")
    end

    -- Layout: | [10px] [player gold] ... [withdraw] [deposit] [10px] [warband gold] [10px] |
    local goldText = footerBar:CreateFontString(nil, "OVERLAY")
    SetBankFont(goldText, 11)
    goldText:SetPoint("LEFT", footerBar, "LEFT", 10, 0)
    goldText:SetTextColor(1, 1, 1)
    footerBar.playerGold = goldText

    local goldHitbox = CreateFrame("Frame", nil, footerBar)
    goldHitbox:SetPoint("TOPLEFT", goldText, "TOPLEFT", -4, 4)
    goldHitbox:SetPoint("BOTTOMRIGHT", goldText, "BOTTOMRIGHT", 4, -4)
    goldHitbox:SetFrameLevel(footerBar:GetFrameLevel() + 5)
    goldHitbox:EnableMouse(true)
    goldHitbox:SetScript("OnEnter", function(self)
        CUI.ShowWidgetTooltip(self, "Player Gold")
    end)
    goldHitbox:SetScript("OnLeave", function()
        CUI.HideWidgetTooltip()
    end)

    local warbandMoney = footerBar:CreateFontString(nil, "OVERLAY")
    SetBankFont(warbandMoney, 11)
    warbandMoney:SetPoint("RIGHT", footerBar, "RIGHT", -10, 0)
    warbandMoney:SetTextColor(1, 1, 1)
    -- The resize grip's inset moves it clear of the grip (_bankGripCfg)
    CUI_Bank._warbandGoldText = warbandMoney

    local warbandHitbox = CreateFrame("Frame", nil, footerBar)
    warbandHitbox:SetPoint("TOPLEFT", warbandMoney, "TOPLEFT", -4, 4)
    warbandHitbox:SetPoint("BOTTOMRIGHT", warbandMoney, "BOTTOMRIGHT", 4, -4)
    warbandHitbox:SetFrameLevel(footerBar:GetFrameLevel() + 5)
    warbandHitbox:EnableMouse(true)
    warbandHitbox:SetScript("OnEnter", function(self)
        CUI.ShowWidgetTooltip(self, "Warband Gold")
    end)
    warbandHitbox:SetScript("OnLeave", function()
        CUI.HideWidgetTooltip()
    end)

    -- Withdraw / Deposit styled buttons (next to warband gold)
    local Pix = CUI and CUI.PP
    local accR, accG, accB = GetAccentRGB()

    local GOLD_R, GOLD_G, GOLD_B = 0.855, 0.722, 0.259 -- #dab842

    local function MakeStyledFooterBtn(caption, tooltipText)
        local button = CreateFrame("Button", nil, footerBar)
        button:SetSize(70, 18)
        button:EnableMouse(true)
        button:SetFrameLevel(footerBar:GetFrameLevel() + 2)

        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(button, GOLD_R, GOLD_G, GOLD_B, 0.8, 1, "OVERLAY", 7)
        end

        local labelFS = button:CreateFontString(nil, "OVERLAY")
        SetBankFont(labelFS, 9)
        labelFS:SetPoint("CENTER", button, "CENTER", 0, 0)
        labelFS:SetText(CludesUI.L(caption))
        labelFS:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
        button._label = labelFS

        button:SetScript("OnEnter", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
            if Pix and Pix.SetBorderColor then
                Pix.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 1)
            end
            CUI.ShowWidgetTooltip(self, CludesUI.L(tooltipText))
        end)
        button:SetScript("OnLeave", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
            if Pix and Pix.SetBorderColor then
                Pix.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 0.8)
            end
            CUI.HideWidgetTooltip()
        end)
        return button
    end

    local depositGoldBtn = MakeStyledFooterBtn("Deposit", "Deposit to Warbank")
    depositGoldBtn:SetPoint("RIGHT", warbandMoney, "LEFT", -14, 0)
    local withdrawGoldBtn = MakeStyledFooterBtn("Withdraw", "Withdraw from Warbank")
    withdrawGoldBtn:SetPoint("RIGHT", depositGoldBtn, "LEFT", -8, 0)

    local function ShowMoneyPopup(titleText, onAccept)
        if not CUI.ShowInputPopup then
            return
        end
        CUI:ShowInputPopup({
            title = CludesUI.L(titleText),
            message = CludesUI.L("Enter an amount:"),
            money = true, -- gold/silver/copper boxes, onConfirm gets copper
            confirmText = ACCEPT,
            cancelText = CANCEL,
            modernBlizz = true,
            onConfirm = function(copperAmount)
                if copperAmount and copperAmount > 0 then
                    onAccept(copperAmount)
                end
            end,
        })
    end

    withdrawGoldBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanWithdrawMoney then
            return
        end
        if not C_Bank.CanWithdrawMoney(Enum.BankType.Account) then
            return
        end
        ShowMoneyPopup("Withdraw from Warbank", function(copperAmount)
            C_Bank.WithdrawMoney(Enum.BankType.Account, copperAmount)
        end)
    end)
    depositGoldBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanDepositMoney then
            return
        end
        if not C_Bank.CanDepositMoney(Enum.BankType.Account) then
            return
        end
        ShowMoneyPopup("Deposit to Warbank", function(copperAmount)
            C_Bank.DepositMoney(Enum.BankType.Account, copperAmount)
        end)
    end)

    -- Deposit Warbound Items / Deposit Reagents button, left of Withdraw so a long
    -- warband total pushes it along instead of overlapping it.
    local depositAllBtn = CreateFrame("Button", nil, footerBar)
    depositAllBtn:SetHeight(18)
    depositAllBtn:SetPoint("RIGHT", withdrawGoldBtn, "LEFT", -8, 0)
    depositAllBtn:EnableMouse(true)

    local depositText = depositAllBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(depositText, 10)
    depositText:SetPoint("CENTER", depositAllBtn, "CENTER", 0, 0)
    depositText:SetTextColor(accR, accG, accB, 1)
    depositAllBtn._label = depositText

    depositAllBtn:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1, 1)
    end)
    depositAllBtn:SetScript("OnLeave", function(self)
        local red, green, blue = GetAccentRGB()
        self._label:SetTextColor(red, green, blue, 1)
    end)
    depositAllBtn:SetScript("OnClick", function(self)
        if not C_Bank or not C_Bank.AutoDepositItemsIntoBank then
            return
        end
        local bankKind = self._bankType
        if bankKind then
            C_Bank.AutoDepositItemsIntoBank(bankKind)
        end
    end)

    function CUI_Bank:UpdateFooterGold()
        local GL = CUI.GetGoldLedger()
        goldText:SetText(FormatGold(GL.Money() or 0))
        warbandMoney:SetText(FormatGold(GL.WarbandMoney() or 0))
    end

    function CUI_Bank:UpdateDepositButton(warbandBank)
        if warbandBank then
            depositText:SetText(CludesUI.L("Deposit Warbound Items"))
            depositAllBtn._bankType = Enum.BankType.Account
        else
            depositText:SetText(CludesUI.L("Deposit Reagents"))
            depositAllBtn._bankType = Enum.BankType.Character
        end
        local red, green, blue = GetAccentRGB()
        depositText:SetTextColor(red, green, blue, 1)
        depositAllBtn:SetWidth(depositText:GetStringWidth() + 16)
        depositAllBtn:Show()
        withdrawGoldBtn:Show()
        depositGoldBtn:Show()
    end
end

-------------------------------------------------------------------------------
--  Drag to Move (not while the footer's lock icon is locked)
-------------------------------------------------------------------------------
CUI_Bank:SetScript("OnMouseDown", function(self, btnFrame)
    self:Raise()
    self:RepinIconLevels()
    if btnFrame == "LeftButton" and not BagsProfile().bankWindowLocked then
        self:StartMoving()
        self._moving = true
    end
end)
CUI_Bank:SetScript("OnMouseUp", function(self, btnFrame)
    if self._moving then
        self:StopMovingOrSizing()
        self._moving = nil
        -- Save position
        local anchorPoint, _, relPoint, posX, posY = self:GetPoint(1)
        if anchorPoint then
            BagsProfile().bankPosition = { point = anchorPoint, relativePoint = relPoint, x = posX, y = posY }
        end
    end
end)

-------------------------------------------------------------------------------
-- Bank Tab Settings Dialog
-------------------------------------------------------------------------------
local CUI_BankTabConfigFrame = CreateFrame("Frame", "CUI_BankFrame_TabSettingsMenu", CUI_Bank)
CUI_BankTabConfigFrame:SetWidth(240) -- Height is automatically determined by content
CUI_BankTabConfigFrame:SetFrameStrata("DIALOG")
CUI_BankTabConfigFrame:Hide()

-- Built lazily on the first right-click of a bank tab.
local function EnsureBankTabConfigFrame()
    if CUI_BankTabConfigFrame.OpenBankTabSettings then
        return
    end
    -- Options surface is LoadOnDemand; load it so CUI.BuildCheckboxControl exists.
    if not CUI.BuildCheckboxControl then
        CUI:EnsureLoaded()
    end
    if not CUI.BuildCheckboxControl then
        return
    end
    local bgAtlasBTC = CUI_BankTabConfigFrame:CreateTexture(nil, "BACKGROUND")
    bgAtlasBTC:SetAllPoints()
    bgAtlasBTC:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    local bgOverlayBTC = CUI_BankTabConfigFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgOverlayBTC:SetAllPoints()
    bgOverlayBTC:SetColorTexture(0, 0, 0, 0.25)
    CUI.MakeBorder(CUI_BankTabConfigFrame, 1, 1, 1, 0.15, CUI.PP)

    -- Header
    local buyHeader = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    buyHeader:SetPoint("TOPLEFT", CUI_BankTabConfigFrame, "TOPLEFT", 0, 0)
    buyHeader:SetPoint("TOPRIGHT", CUI_BankTabConfigFrame, "TOPRIGHT", 0, 0)
    buyHeader:SetHeight(35)
    local hdrBgBTC = buyHeader:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBgBTC:SetAllPoints()
    hdrBgBTC:SetColorTexture(0, 0, 0, 0.5)

    local titleBTC = buyHeader:CreateFontString(nil, "OVERLAY")
    SetBankFont(titleBTC, 13)
    titleBTC:SetPoint("LEFT", buyHeader, "LEFT", 8, 0)
    titleBTC:SetTextColor(1, 1, 1)
    titleBTC:SetText(CludesUI.L("Edit Tab Settings"))

    -- Footer
    local tabCfgFooter = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    tabCfgFooter:SetPoint("BOTTOMLEFT", CUI_BankTabConfigFrame, "BOTTOMLEFT", 0, 0)
    tabCfgFooter:SetPoint("BOTTOMRIGHT", CUI_BankTabConfigFrame, "BOTTOMRIGHT", 0, 0)
    tabCfgFooter:SetHeight(FOOTER_H)
    local ftrBgBTC = tabCfgFooter:CreateTexture(nil, "BACKGROUND", nil, 1)
    ftrBgBTC:SetAllPoints()
    ftrBgBTC:SetColorTexture(0, 0, 0, 0.35)

    -- Top-edge separator
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local tabCfgFooterRule = tabCfgFooter:CreateTexture(nil, "ARTWORK")
    tabCfgFooterRule:SetHeight(px)
    tabCfgFooterRule:SetPoint("TOPLEFT", tabCfgFooter, "TOPLEFT", 0, 0)
    tabCfgFooterRule:SetPoint("TOPRIGHT", tabCfgFooter, "TOPRIGHT", 0, 0)
    tabCfgFooterRule:SetColorTexture(0.15, 0.15, 0.15, 1)

    -------------------------------------------------------------------------------
    -- Content for Bank Tab Settings Frame
    -------------------------------------------------------------------------------
    local WIDGET_HEIGHT = 22
    local PADDING_X = 8
    local PADDING_Y = 8
    local accR, accG, accB = GetAccentRGB()

    local contentH = 0

    local tabCfgBody = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    tabCfgBody:SetPoint("TOPLEFT", buyHeader, "BOTTOMLEFT", 0, 0)
    tabCfgBody:SetPoint("BOTTOMRIGHT", tabCfgFooter, "TOPRIGHT", 0, 0)
    tabCfgBody:SetWidth(CUI_BankTabConfigFrame:GetWidth()) -- Height is automatically determined by content

    -- Bank Tab Name Label
    local tabNameText = tabCfgBody:CreateFontString(nil, "OVERLAY")
    SetBankFont(tabNameText, 10)
    tabNameText:SetPoint("TOPLEFT", tabCfgBody, "TOPLEFT", PADDING_X, -PADDING_Y)
    tabNameText:SetTextColor(1, 1, 1, 1)
    tabNameText:SetText(CHARACTER_BANK_TAB_NAME_PROMPT)
    contentH = contentH + tabNameText:GetStringHeight() + PADDING_Y

    -- Bank Tab Name EditBox
    local tabNameBox = CreateFrame("EditBox", "CUI_BankFrame_TabSettingsMenu_NameBox", tabCfgBody)
    tabNameBox:SetSize(170, WIDGET_HEIGHT)
    tabNameBox:SetPoint("TOPLEFT", tabNameText, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    SetBankFont(tabNameBox, 10)
    tabNameBox:SetAutoFocus(false)
    tabNameBox:SetTextInsets(5, 5, 0, 0)
    local bankTabNameBg = tabNameBox:CreateTexture(nil, "BACKGROUND")
    bankTabNameBg:SetAllPoints()
    bankTabNameBg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if CUI and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(tabNameBox, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
    end
    contentH = contentH + tabNameBox:GetHeight() + (PADDING_Y / 2)

    -- Tab Icon Preview Visual
    local iconBTCTexture = tabCfgBody:CreateTexture(nil, "ARTWORK")
    iconBTCTexture:SetSize(32, 32)
    iconBTCTexture:SetPoint(
        "TOPRIGHT",
        tabCfgBody,
        "TOPRIGHT",
        -PADDING_X,
        select(5, tabNameText:GetPoint(1)) + select(5, tabNameBox:GetPoint(1))
    ) -- Align with the edit box

    -- Assign To Tab Label
    local assignText = tabCfgBody:CreateFontString(nil, "OVERLAY")
    SetBankFont(assignText, 10)
    assignText:SetPoint("TOPLEFT", tabNameBox, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    assignText:SetTextColor(1, 1, 1, 1)
    assignText:SetText(BAG_FILTER_ASSIGN_TO)
    contentH = contentH + assignText:GetStringHeight() + (PADDING_Y / 2)

    -- Assign To Tab Checkboxes (2 columns, 3 rows)
    local ASSIGN_TO_TAB_COLUMNS = 2
    local ASSIGN_TO_TAB_ROWS = 3
    local assignToTabCheckboxesCfg = {
        { text = BAG_FILTER_EQUIPMENT, value = Enum.BagSlotFlags.ClassEquipment, row = 1, column = 1 },
        { text = BAG_FILTER_CONSUMABLES, value = Enum.BagSlotFlags.ClassConsumables, row = 2, column = 1 },
        {
            text = BAG_FILTER_PROFESSION_GOODS,
            value = Enum.BagSlotFlags.ClassProfessionGoods,
            row = 3,
            column = 1,
        },
        { text = BAG_FILTER_REAGENTS, value = Enum.BagSlotFlags.ClassReagents, row = 1, column = 2 },
        { text = BAG_FILTER_JUNK, value = Enum.BagSlotFlags.ClassJunk, row = 2, column = 2 },
    }

    local assignToTabFrame = CreateFrame("Frame", nil, tabCfgBody) -- Switched to standard Frame context
    assignToTabFrame:SetSize(tabCfgBody:GetWidth(), WIDGET_HEIGHT * ASSIGN_TO_TAB_ROWS)
    assignToTabFrame:SetPoint("TOPLEFT", assignText, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    contentH = contentH + assignToTabFrame:GetHeight() + (PADDING_Y / 2)

    local function makeAssignToTabBtn(assignOpt)
        local button = CreateFrame("Button", nil, assignToTabFrame)
        button:SetSize(assignToTabFrame:GetWidth() / ASSIGN_TO_TAB_COLUMNS, WIDGET_HEIGHT)

        local xOffset = (assignOpt.column - 1) * (assignToTabFrame:GetWidth() / ASSIGN_TO_TAB_COLUMNS)
        local yOffset = -(assignOpt.row - 1) * WIDGET_HEIGHT
        button:SetPoint("TOPLEFT", assignToTabFrame, "TOPLEFT", xOffset, yOffset)
        button:SetFrameLevel(assignToTabFrame:GetFrameLevel() + 2)

        local box, _, _, cbApply = CUI.BuildCheckboxControl(button, assignToTabFrame:GetFrameLevel() + 2)
        Pix.Point(box, "LEFT", button, "LEFT", 0, 0)

        local caption = CUI.MakeFont(button, 14, nil, CUI.TEXT_WHITE.r, CUI.TEXT_WHITE.g, CUI.TEXT_WHITE.b)
        SetBankFont(caption, 10)
        caption:SetPoint("LEFT", box, "RIGHT", 8, 0)
        caption:SetText(assignOpt.text)

        local isHovering = false

        local getValue = function()
            if not CUI_BankTabConfigFrame.depositFlags then
                return false
            end
            return bit.band(CUI_BankTabConfigFrame.depositFlags, assignOpt.value) ~= 0
        end
        local setValue = function(val)
            CUI_BankTabConfigFrame.depositFlags = CUI_BankTabConfigFrame.depositFlags or 0
            if val then
                CUI_BankTabConfigFrame.depositFlags =
                    bit.bor(CUI_BankTabConfigFrame.depositFlags, assignOpt.value)
            else
                CUI_BankTabConfigFrame.depositFlags =
                    bit.band(CUI_BankTabConfigFrame.depositFlags, bit.bnot(assignOpt.value))
            end
        end

        local function ApplyVisual()
            local enabled = getValue()
            cbApply(enabled, isHovering)
            if enabled then
                caption:SetTextColor(CUI.TEXT_WHITE.r, CUI.TEXT_WHITE.g, CUI.TEXT_WHITE.b, 1)
            else
                local a = isHovering and 1 or 0.8
                caption:SetTextColor(CUI.TEXT_WHITE.r * a, CUI.TEXT_WHITE.g * a, CUI.TEXT_WHITE.b * a, a)
            end
        end
        ApplyVisual()

        button:SetScript("OnClick", function()
            local val = not getValue()
            setValue(val)
            ApplyVisual()
        end)
        button:SetScript("OnEnter", function()
            isHovering = true
            ApplyVisual()
        end)
        button:SetScript("OnLeave", function()
            isHovering = false
            ApplyVisual()
        end)

        button.Refresh = function()
            ApplyVisual()
        end

        return button
    end

    local assignToTabCheckboxesFrames = {}
    for _, assignOpt in ipairs(assignToTabCheckboxesCfg) do
        table.insert(assignToTabCheckboxesFrames, makeAssignToTabBtn(assignOpt))
    end

    tabCfgBody:SetHeight(contentH + (PADDING_Y / 2)) -- Adjusted height to accommodate three rows with padding

    -- Save Button
    local tabCfgSaveBtn = CreateFrame("Button", nil, tabCfgFooter)
    tabCfgSaveBtn:SetSize(100, WIDGET_HEIGHT)
    tabCfgSaveBtn:SetPoint("RIGHT", tabCfgFooter, "RIGHT", -10, 0)
    tabCfgSaveBtn:EnableMouse(true)

    local tabCfgSaveLabel = tabCfgSaveBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(tabCfgSaveLabel, 10)
    tabCfgSaveLabel:SetPoint("CENTER", tabCfgSaveBtn, "CENTER", 0, 0)
    tabCfgSaveLabel:SetTextColor(accR, accG, accB, 0.9)
    tabCfgSaveBtn._label = tabCfgSaveLabel

    tabCfgSaveBtn:SetScript("OnEnter", function(self)
        local red, green, blue = GetAccentRGB()
        self._label:SetTextColor(red, green, blue, 1)
        self._border:SetColor(red, green, blue, 1)
    end)
    tabCfgSaveBtn:SetScript("OnLeave", function(self)
        local red, green, blue = GetAccentRGB()
        self._label:SetTextColor(red, green, blue, 0.9)
        self._border:SetColor(red, green, blue, 0.9)
    end)
    tabCfgSaveBtn._label:SetText(CludesUI.L("Save"))
    if CUI.MakeBorder then
        tabCfgSaveBtn._border = CUI.MakeBorder(tabCfgSaveBtn, accR, accG, accB, 0.9, CUI.PP)
    end

    tabCfgSaveBtn:SetScript("OnClick", function()
        local hostFrame = CUI_BankTabConfigFrame
        if hostFrame.bankType and hostFrame.tabId then
            local newName = tabNameBox:GetText()
            if not newName or newName == "" then
                newName = hostFrame.fallbackName or CUI.Lf("Tab %1$d", hostFrame.tabId)
            end

            C_Bank.UpdateBankTabSettings(
                hostFrame.bankType,
                hostFrame.tabId,
                newName,
                hostFrame.icon,
                hostFrame.depositFlags or 0
            )
        end
        CUI_BankTabConfigFrame:Hide()
    end)

    -- Cancel Button
    local cancelBuyBtn = CreateFrame("Button", nil, tabCfgFooter)
    cancelBuyBtn:SetSize(100, WIDGET_HEIGHT)
    cancelBuyBtn:SetPoint("LEFT", tabCfgFooter, "LEFT", 10, 0)
    cancelBuyBtn:EnableMouse(true)

    local cancelBtnLabel = cancelBuyBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(cancelBtnLabel, 10)
    cancelBtnLabel:SetPoint("CENTER", cancelBuyBtn, "CENTER", 0, 0)
    cancelBtnLabel:SetTextColor(1, 1, 1, 0.7)
    cancelBuyBtn._label = cancelBtnLabel

    cancelBuyBtn:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1, 0.9)
        self._border:SetColor(1, 1, 1, 0.6)
    end)
    cancelBuyBtn:SetScript("OnLeave", function(self)
        self._label:SetTextColor(1, 1, 1, 0.7)
        self._border:SetColor(1, 1, 1, 0.5)
    end)
    cancelBuyBtn._label:SetText(CludesUI.L("Cancel"))
    cancelBuyBtn:SetScript("OnClick", function()
        CUI_BankTabConfigFrame:Hide()
    end)
    if CUI.MakeBorder then
        cancelBuyBtn._border = CUI.MakeBorder(cancelBuyBtn, 1, 1, 1, 0.5, CUI.PP)
    end
    -- Controller cursor: Cancel finds this dialog's Cancel button.
    if CUI.PadCP() then
        CUI_BankTabConfigFrame.CloseButton = cancelBuyBtn
    end

    function CUI_BankTabConfigFrame:OpenBankTabSettings(tabInfo, tabId)
        self:Hide()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", CUI_Bank, "TOPRIGHT", PADDING_X, 0)

        -- Save datas for use in Save button logic
        self.bankType = tabInfo.isWarband and Enum.BankType.Account or Enum.BankType.Character
        self.tabId = tabId
        self.icon = tabInfo.icon
        self.depositFlags = tabInfo.depositFlags or 0

        -- Setup widgets
        local displayName = tabInfo.name
        if self.bankType == Enum.BankType.Account then
            -- Remove "Warbank " prefix as this is a prefix added by CUI and not the real tab name. This is necessary to edit the tab
            local prefixText = CUI.L("Warbank") .. " "
            local prefix_len = #prefixText
            if strsub(tabInfo.name, 1, prefix_len) == prefixText then
                displayName = strsub(tabInfo.name, prefix_len + 1)
            end
        end
        self.fallbackName = displayName
        tabNameBox:SetText(displayName or "")
        iconBTCTexture:SetTexture(tabInfo.icon)
        if assignToTabCheckboxesFrames then
            for _, button in ipairs(assignToTabCheckboxesFrames) do
                if button.Refresh then
                    button:Refresh()
                end
            end
        end

        self:Show()
    end

    CUI_BankTabConfigFrame:SetHeight(buyHeader:GetHeight() + tabCfgBody:GetHeight() + tabCfgFooter:GetHeight())
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local sideBar = CreateFrame("Frame", nil, CUI_Bank)
sideBar._leftInset = 0
local function GetBankSidebarContentWidth()
    return GetBankSidebarWidth() - sideBar._leftInset
end
sideBar:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, 0)
sideBar:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", 0, FOOTER_H)
sideBar:SetWidth(GetBankSidebarContentWidth())
local sidebarBg = sideBar:CreateTexture(nil, "BACKGROUND", nil, 2)
sidebarBg:SetAllPoints()
sidebarBg:SetColorTexture(0, 0, 0, 0.25)

-- Right-edge separator
do
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local sidebarSep = sideBar:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(px)
    sidebarSep:SetPoint("TOPRIGHT", sideBar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    sideBar.separator = sidebarSep
end

-- Secure purchase buttons: inherit BankPanelPurchaseButtonScriptTemplate so
-- PurchaseBankTab() runs in Blizzard's secure context, not ours.
local _purchaseBtnChar, _purchaseBtnWarband
do
    local function MakeSecurePurchaseBtn(bankKind)
        local widget = CreateFrame("Button", nil, sideBar, "BankPanelPurchaseButtonScriptTemplate")
        widget:SetAttribute("overrideBankType", bankKind)
        widget:SetFrameStrata(sideBar:GetFrameStrata())
        widget:SetFrameLevel(sideBar:GetFrameLevel() + 20)
        widget:EnableMouse(true)
        widget:SetAlpha(0)
        widget:Hide()
        -- Hover: brighten the visual entry underneath
        widget:SetScript("OnEnter", function(self)
            if self._visualBtn then
                self._visualBtn._bg:SetColorTexture(1, 1, 1, 0.06)
            end
        end)
        widget:SetScript("OnLeave", function(self)
            if self._visualBtn then
                self._visualBtn._bg:SetColorTexture(1, 1, 1, 0)
            end
        end)
        return widget
    end
    _purchaseBtnChar = MakeSecurePurchaseBtn(Enum.BankType.Character)
    _purchaseBtnWarband = MakeSecurePurchaseBtn(Enum.BankType.Account)
end

function CUI_Bank:ApplyWindowLayering()
    local frameStrata = mod.BagFrameStrata()
    self:SetFrameStrata(frameStrata)
    -- High starts above that layer's other windows (see CUI_Bags:ApplyWindowLayering)
    self:SetFrameLevel(frameStrata == "HIGH" and 50 or 1)
    if bankBagsWindow then
        bankBagsWindow:SetFrameLevel(self:GetFrameLevel() + 20)
    end
    _purchaseBtnChar:SetFrameStrata(frameStrata)
    _purchaseBtnWarband:SetFrameStrata(frameStrata)
    _purchaseBtnChar:SetFrameLevel(sideBar:GetFrameLevel() + 20)
    _purchaseBtnWarband:SetFrameLevel(sideBar:GetFrameLevel() + 20)
    self:RepinIconLevels()
end

-- As CUI_Bags:RepinIconLevels, for the bank's own buttons
function CUI_Bank:RepinIconLevels()
    mod.PinItemPool(self._bankSlots, self, "_slotPinLevel")
    mod.ResyncListRowLevels()
end

-- Sidebar header: "Tabs" label + collapse arrow
local sidebarHdr, collapseBtn, UpdateBankCollapseArrow =
    mod.CreateSidebarHeader(sideBar, CludesUI.L("Tabs"), "bankSidebarCollapsed")

collapseBtn:SetScript("OnClick", function()
    -- Determine which edge to preserve based on screen position
    local center = CUI_Bank:GetCenter()
    local screenW = UIParent:GetWidth()
    local onRightSide = center and screenW and (center > screenW / 2)
    local oldWidth = onRightSide and CUI_Bank:GetWidth() or nil

    BagsProfile().bankSidebarCollapsed = not BagsProfile().bankSidebarCollapsed
    UpdateBankCollapseArrow()
    sideBar:SetWidth(GetBankSidebarContentWidth())
    CUI_Bank:RefreshBank()

    -- Shift frame by width difference to preserve right edge
    if onRightSide and oldWidth then
        local newWidth = CUI_Bank:GetWidth()
        local shift = oldWidth - newWidth
        if math.abs(shift) > 0.5 then
            local anchorPoint, relTo, relPoint, posX, posY = CUI_Bank:GetPoint()
            CUI_Bank:ClearAllPoints()
            CUI_Bank:SetPoint(anchorPoint, relTo, relPoint, posX + shift, posY)
            BagsProfile().bankPosition = { point = anchorPoint, relativePoint = relPoint, x = posX + shift, y = posY }
        end
    end
end)

-- Sidebar scroll frame (below header, fills rest of sidebar)
local sidebarSF = CreateFrame("ScrollFrame", nil, sideBar)
CUI_Bank._sidebarSF = sidebarSF -- an alt's tabs get drawn over this
sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
sidebarSF:SetPoint("BOTTOMRIGHT", sideBar, "BOTTOMRIGHT", 0, 0)
sidebarSF:EnableMouseWheel(true)
local sideChild = CreateFrame("Frame", nil, sidebarSF)
sideChild:SetSize(GetBankSidebarContentWidth(), 1)
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

local _sidebarBtns = {}
-- _selectedView and _allTabs moved to top of file for scope access

-------------------------------------------------------------------------------
--  Scroll Frame + Scrollbar
-------------------------------------------------------------------------------
local scrollFrame = CreateFrame("ScrollFrame", nil, CUI_Bank)
scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", GetBankSidebarWidth(), -HEADER_H)
scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -1, FOOTER_H)
scrollFrame:EnableMouseWheel(true)
local childFrame = CreateFrame("Frame", nil, scrollFrame)
childFrame:SetWidth(1)
childFrame:SetHeight(1)
childFrame:EnableMouse(false)
scrollFrame:SetScrollChild(childFrame)

-- Track (always visible when content scrolls)
local track, thumb, UpdateThumb = mod.AttachGridScrollbar(CUI_Bank, scrollFrame, false, true)
track:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", -1, -1)
track:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -1, FOOTER_H)

CUI_Bank._scrollFrame = scrollFrame
CUI_Bank._scrollChild = childFrame
CUI_Bank._scrollTrack = track
CUI_Bank._scrollThumb = thumb
CUI_Bank._updateThumb = UpdateThumb

-------------------------------------------------------------------------------
--  Base bank slots (WoW Forever)
--  Forever's base bank slots are the first character bank tab, which costs
--  nothing and which Blizzard's own bank buys the first time it opens. Ours
--  replaces that frame and PurchaseBankTab is protected, so while the next
--  character tab is free and no tab shows, the empty bank offers it through
--  Blizzard's own purchase button (its confirmation does the buying).
-------------------------------------------------------------------------------
local UpdateBaseTabPrompt
if CUI.IS_FOREVER then
    local promptText

    local function BaseTabFree()
        if _warbandOnly or not C_Bank.CanPurchaseBankTab(Enum.BankType.Character) then
            return false
        end
        local payload = C_Bank.FetchNextPurchasableBankTabData(Enum.BankType.Character)
        return payload ~= nil and payload.tabCost == 0
    end

    local function BuildPrompt()
        promptText = CreateFrame("Frame", nil, CUI_Bank)
        promptText:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        promptText:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
        promptText:SetFrameLevel(scrollFrame:GetFrameLevel() + 10)
        local message = promptText:CreateFontString(nil, "OVERLAY")
        message:SetFont(GetFont(), 13, "")
        message:SetTextColor(1, 1, 1, 0.75)
        message:SetWidth(300)
        message:SetJustifyH("CENTER")
        message:SetPoint("BOTTOM", promptText, "CENTER", 0, 14)
        message:SetText(
            CludesUI.L(
                "Your base bank slots come with a free bank tab. Open it once to start using your bank."
            )
        )
        local g = CUI.CLUDES_GREEN
        local visual = CUI.MakeActionButton(
            promptText,
            GetFont(),
            CludesUI.L("Open Bank Slots"),
            g.r,
            g.g,
            g.b,
            { w = 200, square = true }
        )
        visual:SetPoint("TOP", promptText, "CENTER", 0, -6)
        visual:EnableMouse(false)
        -- The click goes to Blizzard's purchase button laid over the visual one.
        local buy = CreateFrame("Button", nil, promptText, "BankPanelPurchaseButtonScriptTemplate")
        buy:SetAttribute("overrideBankType", Enum.BankType.Character)
        buy:SetAllPoints(visual)
        buy:SetFrameLevel(visual:GetFrameLevel() + 5)
        buy:SetScript("OnEnter", function()
            visual:GetScript("OnEnter")(visual)
        end)
        buy:SetScript("OnLeave", function()
            visual:GetScript("OnLeave")(visual)
        end)
    end

    -- show: true while the bank has no tab to show.
    UpdateBaseTabPrompt = function(show)
        if show and BaseTabFree() then
            if not promptText then
                BuildPrompt()
            end
            promptText:Show()
        elseif promptText then
            promptText:Hide()
        end
    end
end

-------------------------------------------------------------------------------
--  Button Pool
-------------------------------------------------------------------------------
local _bankSlots = {}
local _bankSlotIdx = 0
CUI_Bank._bankSlots = _bankSlots

--- Returns the bagID of the currently selected bank tab, or nil if viewing
--- "All Tabs" / "OneBank" (in which case default Blizzard routing applies).
--- For aggregate warband views (-2, -3), returns the first warband tab
--- with an empty slot so right-click deposits go to warband, not character bank.
function CUI_Bank:GetSelectedTabBagID()
    if _selectedView == -2 or _selectedView == -3 then
        -- Aggregate warband view: find first warband tab with space
        for _, tabBtn in ipairs(_allTabs) do
            if tabBtn.isWarband then
                local slotCount = C_Container.GetContainerNumSlots(tabBtn.bagID)
                for slotBtn = 1, slotCount do
                    if not C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn) then
                        return tabBtn.bagID
                    end
                end
            end
        end
        return nil
    end
    if _selectedView <= 0 then
        return nil
    end
    local tabBtn = _allTabs[_selectedView]
    return tabBtn and tabBtn.bagID or nil
end

--- Bags an Auto Split from srcBag may fill: the source tab first, then the
--- other tabs of the same bank type. Character and warband slots never mix.
function CUI_Bank:GetSplitTargetBags(sourceBag)
    local targets = { sourceBag }
    local warbandBank = false
    for _, tabBtn in ipairs(_allTabs) do
        if tabBtn.bagID == sourceBag then
            warbandBank = tabBtn.isWarband
        end
    end
    for _, tabBtn in ipairs(_allTabs) do
        if tabBtn.bagID ~= sourceBag and tabBtn.isWarband == warbandBank then
            targets[#targets + 1] = tabBtn.bagID
        end
    end
    return targets
end

--- Returns true if the current view is any warband view (all warbank,
--- onewarbank, or an individual warband tab).
function CUI_Bank:IsWarbandView()
    if _selectedView == -2 or _selectedView == -3 then
        return true
    end
    if _selectedView > 0 and _allTabs[_selectedView] then
        return _allTabs[_selectedView].isWarband
    end
    return false
end

-------------------------------------------------------------------------------
--  TradeSkillMaster compatibility
-------------------------------------------------------------------------------
-- TSM decides whether its Banking UI targets the character bank or the warband bank by
-- watching Blizzard's BankPanel, which CUI reparents to a hidden frame, so TSM never
-- sees bank/warbank switches made in the CUI sidebar. TSM supports addon-provided bank
-- frames through two globals (TSM Core/Service/Banking/Core.lua): it calls
-- Addon_GetBankType() to read the active bank type, and hooksecurefunc's
-- Addon_SetBankType at init so it can re-check whenever the view changes. Both globals
-- must exist before TSM initializes; CUI loads first alphabetically. Cost when TSM is
-- absent is one comparison per RefreshBank. Guarded so another bag addon that already
-- implements the contract wins.

local _lastTSMBankType = nil

if not _G.Addon_GetBankType then
    _G.Addon_GetBankType = function()
        if CUI_Bank:IsVisible() then
            return CUI_Bank:IsWarbandView() and Enum.BankType.Account or Enum.BankType.Character
        end
        if BankFrame and BankFrame.GetActiveBankType then
            return BankFrame:GetActiveBankType()
        end
        return Enum.BankType.Character
    end
end

if not _G.Addon_SetBankType then
    -- Intentionally empty: TSM reacts to the call itself via hooksecurefunc.
    _G.Addon_SetBankType = function() end
end

local function NotifyBankTypeForTSM()
    local bankKind = _G.Addon_GetBankType()
    if bankKind ~= _lastTSMBankType then
        _lastTSMBankType = bankKind
        -- Dynamic lookup so the call goes through TSM's hooked wrapper.
        _G.Addon_SetBankType(bankKind)
    end
end

-------------------------------------------------------------------------------
--  Transfer Queue: queues rapid right-click deposits so they don't collide
--
--  allocatedSlots tracks target bank slots that have a pending transfer so
--  the next deposit picks a different slot.  Items that are still locked from
--  a prior move get queued and re-processed on the next BAG_UPDATE.
-------------------------------------------------------------------------------
local _transferQueue = {} -- { {bag, slot}, ... }
local _allocatedSlots = {} -- [bagID*1000+slot] = true
local _transferEventFrame

local function WipeTransferState()
    wipe(_transferQueue)
    wipe(_allocatedSlots)
    if _transferEventFrame then
        _transferEventFrame:UnregisterAllEvents()
    end
end

local function IsSlotAllocated(bagId, slotBtn)
    return _allocatedSlots[bagId * 1000 + slotBtn]
end

local function AllocateSlot(bagId, slotBtn)
    _allocatedSlots[bagId * 1000 + slotBtn] = true
end

--- Find target in a specific bank bag, skipping allocated slots.
--- Tries partial stacks first, then empty slots.
local function FindTargetSlot(destBag, srcItemID)
    local slotCount = C_Container.GetContainerNumSlots(destBag)
    if slotCount == 0 then
        return nil
    end
    local maxStack = C_Item.GetItemMaxStackSizeByID(srcItemID) or 1
    -- Partial stack first
    if maxStack > 1 then
        for slotBtn = 1, slotCount do
            if not IsSlotAllocated(destBag, slotBtn) then
                local details = C_Container.GetContainerItemInfo(destBag, slotBtn)
                if details and details.itemID == srcItemID and details.stackCount < maxStack then
                    return slotBtn
                end
            end
        end
    end
    -- Empty slot
    for slotBtn = 1, slotCount do
        if not IsSlotAllocated(destBag, slotBtn) then
            if not C_Container.GetContainerItemInfo(destBag, slotBtn) then
                return slotBtn
            end
        end
    end
    return nil
end

local function ProcessTransfer(sourceBag, srcSlot)
    local loc = ItemLocation:CreateFromBagAndSlot(sourceBag, srcSlot)
    if not C_Item.DoesItemExist(loc) or C_Item.IsLocked(loc) then
        return false -- still locked, needs re-queue
    end
    local bank = _G.CUI_BankFrame
    if not bank or not bank:IsVisible() then
        return true
    end -- bank closed, discard
    local details = C_Container.GetContainerItemInfo(sourceBag, srcSlot)
    if not details or not details.itemID then
        return true
    end

    local destBag, destSlot
    -- Aggregate warband views: search ALL warband tabs for stacking, then empty
    if _selectedView == -2 or _selectedView == -3 then
        local maxStack = C_Item.GetItemMaxStackSizeByID(details.itemID) or 1
        -- Pass 1: partial stack in any warband tab
        if maxStack > 1 then
            for _, tabBtn in ipairs(_allTabs) do
                if tabBtn.isWarband then
                    local slotCount = C_Container.GetContainerNumSlots(tabBtn.bagID)
                    for slotBtn = 1, slotCount do
                        if not IsSlotAllocated(tabBtn.bagID, slotBtn) then
                            local si = C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn)
                            if si and si.itemID == details.itemID and si.stackCount < maxStack then
                                destBag, destSlot = tabBtn.bagID, slotBtn
                                break
                            end
                        end
                    end
                    if destSlot then
                        break
                    end
                end
            end
        end
        -- Pass 2: first empty slot in any warband tab
        if not destSlot then
            for _, tabBtn in ipairs(_allTabs) do
                if tabBtn.isWarband then
                    local slotCount = C_Container.GetContainerNumSlots(tabBtn.bagID)
                    for slotBtn = 1, slotCount do
                        if not IsSlotAllocated(tabBtn.bagID, slotBtn) then
                            if not C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn) then
                                destBag, destSlot = tabBtn.bagID, slotBtn
                                break
                            end
                        end
                    end
                    if destSlot then
                        break
                    end
                end
            end
        end
    else
        destBag = bank:GetSelectedTabBagID()
        if not destBag then
            return true
        end
        destSlot = FindTargetSlot(destBag, details.itemID)
    end

    if not destBag or not destSlot then
        return true
    end -- no space, discard
    AllocateSlot(destBag, destSlot)
    C_Container.PickupContainerItem(sourceBag, srcSlot)
    C_Container.PickupContainerItem(destBag, destSlot)
    return true
end

local function DrainQueue()
    -- Clear allocations for slots that now have items (transfer completed)
    for sortKey in pairs(_allocatedSlots) do
        local bagId = math.floor(sortKey / 1000)
        local slotBtn = sortKey % 1000
        if C_Container.GetContainerItemInfo(bagId, slotBtn) then
            _allocatedSlots[sortKey] = nil
        end
    end
    -- Process queued items
    local remaining = {}
    for _, record in ipairs(_transferQueue) do
        if not ProcessTransfer(record[1], record[2]) then
            remaining[#remaining + 1] = record
        end
    end
    wipe(_transferQueue)
    for _, record in ipairs(remaining) do
        _transferQueue[#_transferQueue + 1] = record
    end
    -- Unregister when idle
    if #_transferQueue == 0 and not next(_allocatedSlots) then
        if _transferEventFrame then
            _transferEventFrame:UnregisterAllEvents()
        end
    end
end

local function EnsureTransferEventFrame()
    if _transferEventFrame then
        return
    end
    _transferEventFrame = CreateFrame("Frame")
    _transferEventFrame:SetScript("OnEvent", function()
        DrainQueue()
    end)
end

--- Public: queue a bag item for transfer to the selected bank tab.
--- Called from the bag button PreClick hook.
function CUI_Bank:QueueTransfer(sourceBag, srcSlot)
    EnsureTransferEventFrame()
    _transferEventFrame:RegisterEvent("BAG_UPDATE")
    if not ProcessTransfer(sourceBag, srcSlot) then
        _transferQueue[#_transferQueue + 1] = { sourceBag, srcSlot }
    end
end

-- A slot or row skipped in combat is filled by one refresh at combat end
-- (RefreshBank returns while the bank is closed).
local function RetryBankRefresh()
    CUI_Bank:RefreshBank()
end
local function QueueBankRetry()
    mod.CombatQueue.Defer("bankRetry", RetryBankRefresh)
end

-- Never created in combat (tainted secure button); the slot is skipped instead.
local function GetOrCreateBankSlot(position)
    if _bankSlots[position] then
        return _bankSlots[position]
    end
    if InCombatLockdown() then
        QueueBankRetry()
        return nil
    end
    local slotParent = CreateFrame("Frame", nil, CUI_Bank)
    mod.SizeSlot(slotParent)
    local button = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    mod.PinItemButton(button, CUI_Bank)
    button:SetAllPoints(slotParent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, CUI_Bank:GetSplitTargetBags(self:GetParent():GetID()), CUI_Bank)
    end)

    -- OnReceiveDrag: handles native Blizzard drags (shift-click pickup etc.)
    button:SetScript("OnReceiveDrag", function(self)
        local bagId = self:GetParent():GetID()
        local slotID = self:GetID()
        C_Container.PickupContainerItem(bagId, slotID)
    end)

    mod.SkinItemButton(button, { flatHighlight = true })

    -- Empty bg
    button._emptyBg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    button._emptyBg:SetAllPoints()
    mod.SetSlotBackgroundTexture(button._emptyBg, true)

    _bankSlots[position] = button
    return button
end

-------------------------------------------------------------------------------
--  List view (bankListView): rows from CludesUIBags_List.lua
-------------------------------------------------------------------------------
local _bankRows = {}

-- Latched on the first read after the profile loads, like CUI_Bags.IsListMode:
-- switching needs a reload, so only one bank display builds per session.
-- "grid" | "list" | "compact", from ns.BankDisplayMode (CludesUIBags_Compact.lua).
local _bankMode
function CUI_Bank.IsListMode()
    if _bankMode == nil then
        if not CUI.Lite.IsDBReady() then
            return nil
        end
        _bankMode = mod.BankDisplayMode(BagsProfile())
    end
    return _bankMode == "list"
end
-- Compact display: the grid's entries packed into full rows (same latch)
function CUI_Bank.IsCompactMode()
    if CUI_Bank.IsListMode() == nil then
        return nil
    end
    return _bankMode == "compact"
end

-- Never created in combat (tainted secure button); the row is skipped instead.
local function GetOrCreateBankRow(position)
    if _bankRows[position] then
        return _bankRows[position]
    end
    if InCombatLockdown() then
        QueueBankRetry()
        return nil
    end
    local button = mod.CreateListRow(CUI_Bank)
    button:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, CUI_Bank:GetSplitTargetBags(self:GetParent():GetID()), CUI_Bank)
    end)
    button:SetScript("OnReceiveDrag", function(self)
        C_Container.PickupContainerItem(self:GetParent():GetID(), self:GetID())
    end)
    _bankRows[position] = button
    return button
end

-- Rebuilds a grid layout as list rows: empty slots dropped, each run of items
-- sorted by the list column sort, headers with no rows under them dropped.
-- Rows start at listX; headers keep their indent from startX.
-- Returns the new layout and its bottom y.
local function ToListLayout(layout, startX, listX)
    local ROW_H = mod.ListRowH()
    local forever = mod.BagsForever()
    mod.ListSortSetup()
    -- Upgrade tracks only while the Track column shows or sorts the list
    local wantTrack = GetUpgradeTrack and mod.ListUsesColumn("track")
    local result, run = {}, {}
    local function Flush()
        table.sort(run, mod.ListCompare)
        for i, skinData in ipairs(run) do
            result[#result + 1] = { isRow = true, data = skinData, stripe = i % 2 == 0 }
        end
        wipe(run)
    end
    for _, entry in ipairs(layout) do
        local details = entry._cachedInfo
        if entry.isHeader then
            Flush()
            result[#result + 1] = entry
        elseif details and details.hyperlink then
            local itemLinkText = details.hyperlink
            local skinData = { bag = entry.bagID, slot = entry.slot, info = details, itemLink = itemLinkText }
            if forever then
                skinData._isQuest, skinData._isQuestStarter = mod.GetSlotQuestFlags(entry.bagID, entry.slot)
            end
            skinData._isGear = IsGearItem(itemLinkText)
            if skinData._isGear then
                skinData._giIlvl = GetItemLevelAtLocation(ItemLocation:CreateFromBagAndSlot(entry.bagID, entry.slot), itemLinkText)
                -- Track column, same rule as the bags scan
                if wantTrack then
                    local rankText, trackColor = GetUpgradeTrack(itemLinkText)
                    if rankText ~= "" then
                        skinData._giTrackRank, skinData._giTrackColor = rankText, trackColor
                    else
                        skinData._giTrackColor = CUI.GetCraftedTrackColor(itemLinkText)
                    end
                end
            end
            local cdS, cdD, cdE = C_Container.GetContainerItemCooldown(entry.bagID, entry.slot)
            if cdE and cdE ~= 0 and cdS > 0 and cdD > 0 then
                skinData._cdStart, skinData._cdDuration = cdS, cdD
            end
            mod.StampListItem(skinData)
            run[#run + 1] = skinData
        end
    end
    Flush()

    local placed, posY = {}, -6
    for i, entry in ipairs(result) do
        if entry.isRow then
            entry.x, entry.y = listX, posY
            posY = posY - ROW_H
            placed[#placed + 1] = entry
        else
            local depth = entry.depth or 0
            local keep = false
            for jdx = i + 1, #result do
                local num = result[jdx]
                if num.isRow then
                    keep = true
                    break
                end
                if (num.depth or 0) <= depth then
                    break
                end
            end
            if keep then
                if placed[#placed] and placed[#placed].isRow then
                    posY = posY - 6
                end
                entry.x, entry.y = entry.x - startX + listX, posY
                posY = posY - (depth == 0 and 22 or 18)
                placed[#placed + 1] = entry
            end
        end
    end
    return placed, posY
end

-------------------------------------------------------------------------------
--  Compact view (bankCompactView): groups laid out by CludesUIBags_Compact.lua
-------------------------------------------------------------------------------
-- Rebuilds a grid layout as the Compact display: the same entries, each group
-- a block in bands (CludesUIBags_Compact.lua), its label in the band above
-- its first column. Returns the layout, its bottom y, and the px width it
-- gives the grid (nil for the grid's own; see CompactPack's out.contentW).
local ToCompactLayout
do
    local size, labelW, labelText, labelEntry = {}, {}, {}, {}
    local result
    -- One label entry per pooled label, built once with every field and reused:
    -- it takes its group's header entry's place in the layout, so the header
    -- tables the view builders make per refresh never grow
    local labelEntries = {}
    -- Label size of the bank's top-level headers
    local LABEL_SIZE = 11
    ToCompactLayout = function(layout, startX, columns)
        if not result then
            result = mod.CompactNewOut()
        end
        local pool = CUI_Bank._compactLabels
        if not pool then
            pool = {}
            CUI_Bank._compactLabels = pool
        end
        mod.CompactHideLabels(pool, 1)
        local num = mod.CompactSegmentLayout(layout, size, labelText, labelEntry)
        local bandH = mod.CompactBandHeight(LABEL_SIZE)
        local k = 0
        for g = 1, num do
            local textValue = labelText[g]
            if textValue then
                k = k + 1
                labelW[g] =
                    mod.CompactMeasureLabel(mod.CompactLabel(pool, k, CUI_Bank), textValue, LABEL_SIZE)
                local leftEdge = labelEntries[k]
                if not leftEdge then
                    leftEdge = {
                        isHeader = true,
                        compact = true,
                        headerIdx = k,
                        label = textValue,
                        textW = 0,
                        x = 0,
                        y = 0,
                        w = 0,
                        h = bandH,
                        bw = 0,
                    }
                    labelEntries[k] = leftEdge
                end
                labelEntry[g] = leftEdge
            else
                labelW[g] = 0
            end
        end
        local _, _, bottomY = mod.CompactPack(size, labelW, num, columns, bandH, -6, result)
        local cellX, cellY = result.cellX, result.cellY
        local lineIndex, containerInfo = 0, 0
        for g = 1, num do
            local leftEdge = labelEntry[g]
            if leftEdge then
                lineIndex = lineIndex + 1
                layout[lineIndex] = leftEdge
                leftEdge.label = labelText[g]
                leftEdge.textW = labelW[g]
                leftEdge.x = startX + result.groupX[g]
                leftEdge.y = result.groupY[g]
                leftEdge.w = result.labelRoom[g]
                leftEdge.h = bandH
                leftEdge.bw = result.groupW[g] -- the divider runs to the block's right edge
            end
            for _ = 1, size[g] do
                lineIndex, containerInfo = lineIndex + 1, containerInfo + 1
                local entry = layout[lineIndex]
                entry.x = startX + cellX[containerInfo]
                entry.y = cellY[containerInfo]
            end
        end
        return layout, bottomY, result.contentW
    end
end

-------------------------------------------------------------------------------
--  Expansion nesting (OneBank / OneWarbank)
--  Bucket logic follows CUI_Bags_Data.lua, with one deliberate difference: the
--  bags side forces every item of ilvl >= 180 into Midnight before reading the
--  real expansion ID. A bank holds years of gear, so that misfiles most of it --
--  here the expansion ID from C_Item.GetItemInfo always wins.
-------------------------------------------------------------------------------
local EXPANSION_ID_OVERRIDES = {
    [180653] = 11,
}

local function GetItemExpansionIDFromLink(linkText)
    if not linkText then
        return nil
    end
    local itemId = tonumber(linkText:match("item:(%d+)")) or tonumber(linkText:match("keystone:(%d+)"))
    if itemId and EXPANSION_ID_OVERRIDES[itemId] then
        return EXPANSION_ID_OVERRIDES[itemId]
    end
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expID = C_Item.GetItemInfo(linkText)
        return expID
    end
    return select(15, GetItemInfo(linkText))
end

-- sortKey: higher = newer expansion, shown first. Unknown / uncached last.
local EXP_KEY_UNKNOWN = -999
local EXP_KEY_EMPTY = -1000

local function GetExpansionBucketKeyAndLabel(linkText)
    local expID = GetItemExpansionIDFromLink(linkText)
    if expID == nil then
        return EXP_KEY_UNKNOWN, (UNKNOWN or CludesUI.L("Unknown"))
    end
    local ident = tonumber(expID)
    if ident == nil then
        return EXP_KEY_UNKNOWN, (UNKNOWN or CludesUI.L("Unknown"))
    end
    -- Classic-era sentinel from some clients / items
    if ident == 254 or ident == 255 then
        local caption = _G["EXPANSION_NAME0"] or CludesUI.L("Classic")
        return 0, caption
    end
    local caption = _G["EXPANSION_NAME" .. ident]
    if caption and caption ~= "" then
        return ident, caption
    end
    if ident == 11 then
        return ident, "Midnight"
    end
    return ident, CludesUI.Lf("Expansion %1$d", ident)
end

-- Sub-bucket by item subclass: Recipe/Profession subclasses are the professions
-- themselves (Herbalism, Mining, ...), Tradegoods subclasses are the material
-- families (Herb, Cloth, Metal & Stone), Consumable subclasses are Potion /
-- Flask / Food. GetItemInfoInstant reads the local client DB, so unlike
-- GetItemInfo it answers on the first bank open.
local function GetSubTypeBucket(itemLinkText)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(itemLinkText)
    if classID == nil then
        return "__other__", CludesUI.L("Other"), true
    end
    local caption
    if C_Item and C_Item.GetItemSubClassInfo then
        caption = C_Item.GetItemSubClassInfo(classID, subclassID or 0)
    end
    if (not caption or caption == "") and _G.GetItemSubClassInfo then
        caption = _G.GetItemSubClassInfo(classID, subclassID or 0)
    end
    if not caption or caption == "" then
        caption = select(7, GetItemInfo(itemLinkText))
    end
    if not caption or caption == "" then
        return "__other__", CludesUI.L("Other"), true
    end
    return caption, caption, false
end

-- Sub-bucket by equipment slot. Condensed port of GetArmorySlotBucket in
-- CUI_Bags_Data.lua so gear sorts head-to-feet, then weapons, in both windows.
local ARMORY_SLOT_KEYS = {
    INVTYPE_HEAD = { 10, "INVTYPE_HEAD" },
    INVTYPE_NECK = { 20, "INVTYPE_NECK" },
    INVTYPE_SHOULDER = { 30, "INVTYPE_SHOULDER" },
    INVTYPE_CLOAK = { 40, "INVTYPE_CLOAK" },
    INVTYPE_CHEST = { 50, "INVTYPE_CHEST" },
    INVTYPE_ROBE = { 50, "INVTYPE_CHEST" },
    INVTYPE_BODY = { 60, "INVTYPE_BODY" },
    INVTYPE_TABARD = { 70, "INVTYPE_TABARD" },
    INVTYPE_WRIST = { 80, "INVTYPE_WRIST" },
    INVTYPE_HAND = { 90, "INVTYPE_HAND" },
    INVTYPE_WAIST = { 100, "INVTYPE_WAIST" },
    INVTYPE_LEGS = { 110, "INVTYPE_LEGS" },
    INVTYPE_FEET = { 120, "INVTYPE_FEET" },
    INVTYPE_FINGER = { 140, "INVTYPE_FINGER" },
    INVTYPE_TRINKET = { 150, "INVTYPE_TRINKET" },
}
local ARM_WAND = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or 19
local ARM_BOW = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Bow) or 2
local ARM_GUN = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Gun) or 3
local ARM_CROSSBOW = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Crossbow) or 18
local ARM_COSMETIC = Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Cosmetic

local function GetSlotBucket(itemLinkText)
    local _, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(itemLinkText)
    if classID == Enum.ItemClass.Armor and ARM_COSMETIC and subclassID == ARM_COSMETIC then
        return 130, CludesUI.L("Cosmetic"), false
    end
    equipLoc = equipLoc or ""
    if
        equipLoc == "INVTYPE_WEAPONOFFHAND"
        or equipLoc == "INVTYPE_HOLDABLE"
        or equipLoc == "INVTYPE_SHIELD"
    then
        return 180, CludesUI.L("OH"), false
    end
    if classID == Enum.ItemClass.Weapon then
        if subclassID == ARM_WAND then
            return 170, CludesUI.L("1H"), false
        end
        if subclassID == ARM_BOW or subclassID == ARM_GUN or subclassID == ARM_CROSSBOW then
            return 190, _G["INVTYPE_RANGED"] or CludesUI.L("Ranged"), false
        end
        if equipLoc == "INVTYPE_2HWEAPON" then
            return 160, CludesUI.L("2H"), false
        end
        if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
            return 190, _G["INVTYPE_RANGED"] or CludesUI.L("Ranged"), false
        end
        if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
            return 170, CludesUI.L("1H"), false
        end
    end
    local record = ARMORY_SLOT_KEYS[equipLoc]
    if record then
        return record[1], _G[record[2]] or equipLoc, false
    end
    return 999, CludesUI.L("Other"), true
end

-- slotList entries are { bagID, slot, _cachedInfo }. mode is "expansion",
-- "type" or "slot". Empty slots have no _cachedInfo and always collect into a
-- single trailing bucket rather than landing under Unknown / Other.
local function BuildBankBuckets(slotArray, mode)
    local byKey, entries = {}, {}
    for _, slot in ipairs(slotArray) do
        local itemLinkText = slot._cachedInfo and slot._cachedInfo.hyperlink
        local k, caption, isOther
        if not itemLinkText then
            k, caption, isOther = EXP_KEY_EMPTY, CludesUI.L("Empty Slots"), false
        elseif mode == "type" then
            k, caption, isOther = GetSubTypeBucket(itemLinkText)
        elseif mode == "slot" then
            k, caption, isOther = GetSlotBucket(itemLinkText)
        else
            k, caption = GetExpansionBucketKeyAndLabel(itemLinkText)
            isOther = (k == EXP_KEY_UNKNOWN)
        end
        local b = byKey[k]
        if not b then
            b = { key = k, label = caption, isOther = isOther, isEmpty = (itemLinkText == nil), slots = {} }
            byKey[k] = b
            entries[#entries + 1] = b
        end
        b.slots[#b.slots + 1] = slot
    end
    -- Empty slots last, then unknown/other, then per-mode order. Keys can be
    -- numbers or strings depending on mode, so never compare across buckets
    -- until those two flags have been settled.
    table.sort(entries, function(lhs, rhs)
        if lhs.isEmpty ~= rhs.isEmpty then
            return rhs.isEmpty
        end
        if lhs.isOther ~= rhs.isOther then
            return rhs.isOther
        end
        if lhs.isEmpty or lhs.isOther then
            return lhs.label < rhs.label
        end
        if mode == "type" then
            return lhs.label < rhs.label
        end
        if mode == "slot" then
            return lhs.key < rhs.key
        end
        return lhs.key > rhs.key -- expansion: newest first
    end)
    return entries
end

-- The deepest level, applied inside a category once expansion and category
-- headers are already placed. Gear splits by equipment slot, crafting and
-- consumables by item subclass (which is what separates Herbalism from Mining,
-- or Potions from Flasks). Categories absent from this table are not split --
-- expansion is its own top level now, so re-splitting on it would be circular.
local CATEGORY_DETAIL_MODE = {
    ["Armor"] = "slot",
    ["Weapons / Trinkets"] = "slot",
    ["Item Set Gear"] = "slot",
    ["Professions"] = "type",
    ["Trade Goods"] = "type",
    ["Gear Enhancements"] = "type",
    ["Consumables"] = "type",
    ["Miscellaneous"] = "type",
}

local function DetailModeForCategory(category)
    return CATEGORY_DETAIL_MODE[category and category._defaultName or ""]
end

-- Category buckets in CategoryManager order. Returns nil when that module is
-- unavailable so callers can fall back. Slots with no item are never passed in.
local function BuildCategoryBuckets(slotArray)
    local CM = _G.CUI_CategoryManager
    if not CM or not CM.ClassifyAll or not CM.GetCategories then
        return nil
    end
    local itemList = {}
    for _, sl in ipairs(slotArray) do
        local details = sl._cachedInfo
        itemList[#itemList + 1] = {
            info = details,
            itemLink = details.hyperlink,
            bag = sl.bagID,
            slot = sl.slot,
            _slotRef = sl,
        }
    end
    CM:ClassifyAll(itemList)
    local categories = CM:GetCategories()
    local byCat = {}
    for _, skinData in ipairs(itemList) do
        local containerInfo = skinData.categoryIndex
        if containerInfo then
            local t = byCat[containerInfo]
            if not t then
                t = {}
                byCat[containerInfo] = t
            end
            t[#t + 1] = skinData._slotRef
        end
    end
    local result = {}
    for containerInfo, category in ipairs(categories) do
        local entries = byCat[containerInfo]
        if entries and #entries > 0 then
            result[#result + 1] = { cat = category, label = category.name or "?", slots = entries }
        end
    end
    return result
end

-- Mark each slot with the bucket it landed in, so a later split by expansion can
-- regroup the same slots instead of classifying them again. ClassifyAll rebuilds
-- the equipment-set lookup every call, which is a fixed cost per call rather than
-- per item -- paying it once per expansion bucket is what this avoids.
local function ClassifyOnce(slotArray)
    local catBuckets = BuildCategoryBuckets(slotArray)
    if not catBuckets then
        return nil
    end
    for containerInfo, callback in ipairs(catBuckets) do
        for _, sl in ipairs(callback.slots) do
            sl._catBucket = containerInfo
        end
    end
    return catBuckets
end

-- The categories present in one subset of an already-classified list, kept in the
-- order ClassifyOnce produced.
local function RegroupByCategory(catBuckets, slotArray)
    local byIdx = {}
    for _, sl in ipairs(slotArray) do
        local containerInfo = sl._catBucket
        if containerInfo then
            local t = byIdx[containerInfo]
            if not t then
                t = {}
                byIdx[containerInfo] = t
            end
            t[#t + 1] = sl
        end
    end
    local result = {}
    for containerInfo, callback in ipairs(catBuckets) do
        local entries = byIdx[containerInfo]
        if entries and #entries > 0 then
            result[#result + 1] = { cat = callback.cat, label = callback.label, slots = entries }
        end
    end
    return result
end

-- One classification pass per refresh, shared by the sidebar (entry counts) and
-- the grid (filtered slot lists) so the two can never disagree. Returns nil if
-- the CategoryManager is unavailable, which makes every caller fall back.
local function BuildBankCategoryIndex(tabList, passes)
    local slotTable = {}
    for _, tabBtn in ipairs(tabList) do
        for slotBtn = 1, tabBtn.numSlots do
            local details = C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn)
            if details and details.hyperlink and (not passes or passes(tabBtn.bagID, slotBtn)) then
                slotTable[#slotTable + 1] = { bagID = tabBtn.bagID, slot = slotBtn, _cachedInfo = details }
            end
        end
    end
    local catBuckets = ClassifyOnce(slotTable)
    if not catBuckets then
        return nil
    end
    local position = { list = catBuckets, byKey = {}, detailByKey = {} }
    for _, callback in ipairs(catBuckets) do
        local sortKey = callback.cat._defaultName
        if sortKey then
            position.byKey[sortKey] = callback
            local mode = DetailModeForCategory(callback.cat)
            if mode then
                local bagSlot = BuildBankBuckets(callback.slots, mode)
                -- A single bucket is the whole category; no point offering it.
                if #bagSlot > 1 then
                    position.detailByKey[sortKey] = bagSlot
                end
            end
        end
    end
    return position
end

-- Slots behind the current sidebar selection.
local function GetSelectionSlots()
    if not _catSel or not _catIndex then
        return nil
    end
    if _catSel.group then
        local result = {}
        for _, callback in ipairs(_catIndex.list) do
            if callback.cat.groupName == _catSel.group then
                for _, sl in ipairs(callback.slots) do
                    result[#result + 1] = sl
                end
            end
        end
        return result
    end
    local callback = _catIndex.byKey[_catSel.key]
    if not callback then
        return {}
    end
    if _catSel.detail then
        local bagSlot = _catIndex.detailByKey[_catSel.key]
        if bagSlot then
            for _, b in ipairs(bagSlot) do
                if b.label == _catSel.detail then
                    return b.slots
                end
            end
        end
        return {}
    end
    return callback.slots
end

-------------------------------------------------------------------------------
--  Category Headers
-------------------------------------------------------------------------------
local _bankHeaders = {}
local function GetOrCreateBankHeader(position)
    if _bankHeaders[position] then
        return _bankHeaders[position]
    end
    local frame = CreateFrame("Frame", nil, CUI_Bank)
    frame:SetHeight(20)
    frame._label = frame:CreateFontString(nil, "OVERLAY")
    SetBankFont(frame._label, 11)
    frame._label:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame._label:SetTextColor(0.7, 0.7, 0.7)
    frame._label:SetJustifyH("LEFT")
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    frame._line = frame:CreateTexture(nil, "ARTWORK")
    frame._line:SetHeight(px)
    frame._line:SetPoint("LEFT", frame._label, "RIGHT", 6, 0)
    frame._line:SetPoint("RIGHT", frame, "RIGHT", -SPACING, 0)
    frame._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    _bankHeaders[position] = frame
    return frame
end

local function DiscoverBankTabs()
    _allTabs = {}
    local charTabs = GetCharacterBankTabs()
    for _, tab in ipairs(charTabs) do
        tab.isWarband = false
        _allTabs[#_allTabs + 1] = tab
    end
    local warbandTabs = GetWarbandBankTabs()
    for _, tab in ipairs(warbandTabs) do
        tab.isWarband = true
        _allTabs[#_allTabs + 1] = tab
    end
    CUI_Bank._allTabs = _allTabs
end

-- Fast font size update for bank slots (mirrors bags RefreshTextSizes)
local function RefreshBankTextSizes()
    local countSize = BagsProfile().bagCountFontSize or 11
    local ilvlSize = BagsProfile().itemlevelFontSize or 12
    local bindTypeSize = BagsProfile().bagBindTypeFontSize or 11
    for _, button in pairs(_bankSlots) do
        if button.Count then
            CludesUI.ApplyIconTextFont(button.Count, GetFont(), countSize, "bags")
        end
        if button.ItemLevelText then
            button.ItemLevelText:SetFont(
                GetFont(),
                ilvlSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if button.BindTypeText then
            button.BindTypeText:SetFont(
                GetFont(),
                bindTypeSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
    end
end
CUI_Bank.RefreshTextSizes = RefreshBankTextSizes

-- Fast icon-zoom update for bank slots (mirrors bags RefreshIconZoom)
local function RefreshBankIconZoom()
    local zoom = BagsProfile().bagItemIconZoom or 0.08
    for _, button in pairs(_bankSlots) do
        if button.icon then
            button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
end
CUI_Bank.RefreshIconZoom = RefreshBankIconZoom

local function CountUsedSlots(bagId, slotCount)
    local used = 0
    for slotBtn = 1, slotCount do
        if C_Container.GetContainerItemInfo(bagId, slotBtn) then
            used = used + 1
        end
    end
    return used
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
local _bankGripCfg = {
    step = SLOT_SIZE + SPACING,
    minCols = 8,
    minH = 300,
    getCols = GetBankColumns,
    getHeight = GetBankHeight,
    save = function(cols, hgt)
        BagsProfile().bankColumns, BagsProfile().bankHeight = cols, hgt
        UpdateThumb()
    end,
    finish = function()
        CUI_Bank:RefreshBank()
    end,
    savePos = function(leftX, topY)
        BagsProfile().bankPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = leftX, y = topY }
    end,
    reset = function()
        local profile = BagsProfile()
        profile.bankColumns, profile.bankHeight, profile.bankListWidth = nil, nil, nil
        CUI_Bank:RefreshBank()
    end,
    -- The warband gold text sits at the footer's right edge
    inset = function(px)
        local wg = CUI_Bank._warbandGoldText
        if not wg then
            return
        end
        wg:ClearAllPoints()
        local footerBar = wg:GetParent()
        if footerBar._coinBox then
            wg:SetPoint("RIGHT", footerBar._coinBox, "RIGHT", -(5 + px), 0)
        else
            wg:SetPoint("RIGHT", footerBar, "RIGHT", -(8 + px), 0)
        end
    end,
    isLocked = function()
        return BagsProfile().bankWindowLocked == true
    end,
    setLocked = function(val)
        BagsProfile().bankWindowLocked = val and true or false
    end,
}

-- List View: free width in pixels (rows have no cell grid). It keeps the
-- default slot pitch: the slot sliders are for Grid and Compact
local LIST_PITCH = 38
local _bankListGripCfg = setmetatable({
    step = 1,
    relayoutStep = LIST_PITCH,
    minCols = 300,
    getCols = function()
        return BagsProfile().bankListWidth or GetBankColumns() * LIST_PITCH
    end,
    save = function(wid, hgt)
        BagsProfile().bankListWidth, BagsProfile().bankHeight = wid, hgt
        UpdateThumb()
    end,
}, { __index = _bankGripCfg })
-- a new slot size: grow-only widths start over, header lines take the new
-- inset and the bag bar lays out again
mod.OnSlotMetrics(function(m)
    _bankGripCfg.step = m[1] + m[2]
    _bankGripCfg.minCols = math.max(1, math.ceil(8 * 38 / (m[1] + m[2])))
    CUI_Bank._compactCols, CUI_Bank._compactW = nil, nil
    for _, frame in pairs(_bankHeaders) do
        frame._line:ClearAllPoints()
        frame._line:SetPoint("LEFT", frame._label, "RIGHT", 6, 0)
        frame._line:SetPoint("RIGHT", frame, "RIGHT", -m[2], 0)
    end
    if RefreshBankBags then
        RefreshBankBags()
    end
end)

local BuildBankSidebar -- defined further down
function CUI_Bank:RefreshBank()
    if not CUI_Bank:IsVisible() then
        return
    end
    local forever = mod.BagsForever()
    mod.ApplyWindowBackground(bgAtlas, bgOverlay)
    NotifyBankTypeForTSM()
    mod.ApplySlotMetrics()

    -- Re-discover tabs if empty (data may not be ready on the same frame as
    -- BANKFRAME_OPENED; BAG_UPDATE fires shortly after with real slot counts).
    if #_allTabs == 0 then
        DiscoverBankTabs()
        if #_allTabs == 0 then
            -- Still build sidebar so purchase buttons are visible
            BuildBankSidebar()
            if UpdateBaseTabPrompt then
                UpdateBaseTabPrompt(true)
            end
            return
        end
    end
    if UpdateBaseTabPrompt then
        UpdateBaseTabPrompt(false)
    end

    -- Search filter
    local searchQuery = ""
    if CUI_Bank._searchBox then
        searchQuery = CUI_Bank._searchBox:GetText() or ""
    end
    local hasSearch = searchQuery ~= ""

    -- Don't hide slots upfront: the batch renderer overwrites them in place.
    -- Excess slots are hidden after all batches complete (prevents blink).
    for _, heading in pairs(_bankHeaders) do
        heading:Hide()
    end

    -- Update sidebar and scroll frame widths
    local sidebarW = GetBankSidebarWidth()
    sideBar:SetWidth(GetBankSidebarContentWidth())
    local rightInset = forever and 7 or 1
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", sidebarW, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -rightInset, FOOTER_H)

    local gridPadX = 10
    local COLUMNS = GetBankColumns()
    local gridWidth = COLUMNS * (SLOT_SIZE + SPACING)
    -- List rows take the grip-set width, by default the default pitch's
    if CUI_Bank.IsListMode() then
        gridWidth = BagsProfile().bankListWidth or COLUMNS * LIST_PITCH
    end
    local startX = gridPadX + 5
    local contentPad = gridPadX * 2 + SCROLLBAR_HIT_W + 1 - rightInset

    -- Set frame size BEFORE rendering so scroll frame has non-zero bounds
    local totalW = sidebarW + gridWidth + gridPadX * 2 + SCROLLBAR_HIT_W + 2
    CUI_Bank:SetWidth(totalW)
    CUI_Bank:SetHeight(GetBankHeight())
    childFrame:SetWidth(gridWidth + contentPad)

    -- Helper: check if a slot passes the search filter
    local function PassesSearch(bagId, slotBtn)
        if not hasSearch then
            return true
        end
        local details = C_Container.GetContainerItemInfo(bagId, slotBtn)
        if not details then
            return false
        end
        CUI_Bags.ApplyBindKeyword(details, bagId, slotBtn)
        return not details.isFiltered
    end

    -- Phase 1: Build flat layout list (no button creation, just positions).
    -- Each entry = { bagID, slot, x, y } for items, or "header" entries.
    local _layout = {}
    local nextY = -6
    local headerIndex = 0

    -- Helper: build flat slot list for a set of tabs
    local function BuildOneView(tabList)
        local collected = {}
        local filled = 0
        for _, tabBtn in ipairs(tabList) do
            for slotBtn = 1, tabBtn.numSlots do
                if PassesSearch(tabBtn.bagID, slotBtn) then
                    local details = C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn)
                    collected[#collected + 1] = { bagID = tabBtn.bagID, slot = slotBtn, _cachedInfo = details }
                    if details then
                        filled = filled + 1
                    end
                end
            end
        end
        return collected, filled
    end

    local function LayoutFlatSlots(slotArray, headerLabel)
        if #slotArray > 0 or not hasSearch then
            headerIndex = headerIndex + 1
            _layout[#_layout + 1] = {
                isHeader = true,
                headerIdx = headerIndex,
                label = headerLabel,
                x = startX,
                y = nextY,
                w = gridWidth,
            }
            nextY = nextY - 22
            for vi, slot in ipairs(slotArray) do
                local colour = (vi - 1) % COLUMNS
                local line = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = slot.bagID,
                    slot = slot.slot,
                    _cachedInfo = slot._cachedInfo,
                    x = startX + (colour * (SLOT_SIZE + SPACING)),
                    y = nextY - (line * (SLOT_SIZE + SPACING)),
                }
            end
            local rowList = math.ceil(math.max(#slotArray, 1) / COLUMNS)
            nextY = nextY - (rowList * (SLOT_SIZE + SPACING)) - 6
        end
    end

    -- Header depth: 0 = expansion (or the outermost level in use), 1 = category,
    -- 2 = the detail split inside a category.
    local function EmitHeader(caption, count, depth)
        headerIndex = headerIndex + 1
        local indent = depth * 12
        _layout[#_layout + 1] = {
            isHeader = true,
            depth = depth,
            headerIdx = headerIndex,
            label = caption .. " (" .. count .. ")",
            name = caption,
            x = startX + indent,
            y = nextY,
            w = gridWidth - indent,
        }
        nextY = nextY - (depth == 0 and 22 or 18)
    end

    local function EmitSlots(entries)
        for vi, sl in ipairs(entries) do
            local colour = (vi - 1) % COLUMNS
            local line = math.floor((vi - 1) / COLUMNS)
            _layout[#_layout + 1] = {
                bagID = sl.bagID,
                slot = sl.slot,
                _cachedInfo = sl._cachedInfo,
                x = startX + (colour * (SLOT_SIZE + SPACING)),
                y = nextY - (line * (SLOT_SIZE + SPACING)),
            }
        end
        local rowList = math.ceil(math.max(#entries, 1) / COLUMNS)
        nextY = nextY - (rowList * (SLOT_SIZE + SPACING)) - 6
    end

    -- One category, plus its detail split when it has one. A split that yields a
    -- single bucket is collapsed -- "Armor (1) > Chest (1)" is a header for
    -- nothing, and at three levels deep that noise adds up fast.
    local function LayoutCategoryBucket(callback, depth)
        EmitHeader(callback.label, #callback.slots, depth)
        local mode = DetailModeForCategory(callback.cat)
        if not mode then
            EmitSlots(callback.slots)
            return
        end
        local buckets = BuildBankBuckets(callback.slots, mode)
        if #buckets < 2 then
            EmitSlots(callback.slots)
            return
        end
        for _, b in ipairs(buckets) do
            EmitHeader(b.label, #b.slots, depth + 1)
            EmitSlots(b.slots)
        end
    end

    -- classified: an already-stamped list to regroup, when the caller has one.
    local function LayoutCategoryRun(slotArray, depth, classified)
        local catBuckets
        if classified then
            catBuckets = RegroupByCategory(classified, slotArray)
        else
            catBuckets = BuildCategoryBuckets(slotArray)
        end
        if not catBuckets then
            EmitSlots(slotArray)
            return
        end
        for _, callback in ipairs(catBuckets) do
            LayoutCategoryBucket(callback, depth)
        end
    end

    -- Grouped layout for OneBank / OneWarbank. Expansion is the outer level when
    -- Nest by Expansion is on, category nests inside it, and the per-category
    -- detail split sits inside that. Either toggle works on its own.
    local function LayoutGroupedSlots(slotArray, headerLabel)
        local byExp = BagsProfile().bankNestByExpansion
        local byCat = BagsProfile().bankGroupByCategory
        if not byExp and not byCat then
            return LayoutFlatSlots(slotArray, headerLabel)
        end
        if #slotArray == 0 and hasSearch then
            return
        end

        -- Empty slots cannot be classified and always trail the whole view.
        local filled, emptySlots = {}, {}
        for _, sl in ipairs(slotArray) do
            local details = sl._cachedInfo
            if details and details.hyperlink then
                filled[#filled + 1] = sl
            else
                emptySlots[#emptySlots + 1] = sl
            end
        end

        if byExp then
            local classified = byCat and ClassifyOnce(filled) or nil
            for _, editField in ipairs(BuildBankBuckets(filled, "expansion")) do
                EmitHeader(editField.label, #editField.slots, 0)
                if byCat then
                    LayoutCategoryRun(editField.slots, 1, classified)
                else
                    EmitSlots(editField.slots)
                end
            end
        else
            LayoutCategoryRun(filled, 0)
        end

        if #emptySlots > 0 and not BagsProfile().bankHideEmptyWhenNested then
            EmitHeader(CludesUI.L("Empty Slots"), #emptySlots, 0)
            EmitSlots(emptySlots)
        end
    end

    -- Grid for a category-sidebar selection. Expansion stays the outer level when
    -- Nest by Expansion is on; the level below it depends on what was picked --
    -- a group lists its categories, a category its detail split, a detail split
    -- entry just its items.
    local function LayoutSelectionSlots(slotArray)
        if #slotArray == 0 then
            EmitHeader(CludesUI.L("No Items"), 0, 0)
            return
        end
        -- A group selection splits by category, and _catIndex.list already carries
        -- that classification for these very slots.
        local classified = _catSel.group and _catIndex and _catIndex.list or nil
        local function Inner(entries, depth)
            if _catSel.group then
                LayoutCategoryRun(entries, depth, classified)
                return
            end
            if _catSel.detail then
                EmitSlots(entries)
                return
            end
            local callback = _catIndex and _catIndex.byKey[_catSel.key]
            local mode = callback and DetailModeForCategory(callback.cat)
            if mode then
                local bagSlot = BuildBankBuckets(entries, mode)
                if #bagSlot > 1 then
                    for _, b in ipairs(bagSlot) do
                        EmitHeader(b.label, #b.slots, depth)
                        EmitSlots(b.slots)
                    end
                    return
                end
            end
            EmitSlots(entries)
        end
        if BagsProfile().bankNestByExpansion then
            for _, editField in ipairs(BuildBankBuckets(slotArray, "expansion")) do
                EmitHeader(editField.label, #editField.slots, 0)
                Inner(editField.slots, 1)
            end
        else
            -- Without expansion headers a detail selection would render as a
            -- bare grid, so name what is on screen.
            if _catSel.detail or _catSel.group then
                EmitHeader(
                    _catSel.detail or _G.CUI_CategoryManager:GroupDisplayName(_catSel.group),
                    #slotArray,
                    0
                )
                if _catSel.detail then
                    EmitSlots(slotArray)
                else
                    LayoutCategoryRun(slotArray, 1, classified)
                end
            else
                Inner(slotArray, 0)
            end
        end
    end

    -- Helper: build per-tab header layout for a set of tabs
    local function LayoutTabHeaders(tabList)
        for _, tabBtn in ipairs(tabList) do
            if tabBtn.numSlots > 0 then
                local shownSlots = {}
                local used = 0
                for slotBtn = 1, tabBtn.numSlots do
                    local details = C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn)
                    if details then
                        used = used + 1
                    end
                    CUI_Bags.ApplyBindKeyword(details, tabBtn.bagID, slotBtn)
                    -- use native search filter so type keywords work too
                    if not hasSearch or (details and not details.isFiltered) then
                        shownSlots[#shownSlots + 1] = { slot = slotBtn, _cachedInfo = details }
                    end
                end
                if not hasSearch or #shownSlots > 0 then
                    headerIndex = headerIndex + 1
                    _layout[#_layout + 1] = {
                        isHeader = true,
                        headerIdx = headerIndex,
                        label = tabBtn.name .. " (" .. used .. ")",
                        name = tabBtn.name,
                        x = startX,
                        y = nextY,
                        w = gridWidth,
                    }
                    nextY = nextY - 22
                    local count = hasSearch and #shownSlots or tabBtn.numSlots
                    for vi = 1, count do
                        local slotBtn, cachedInfo
                        if hasSearch then
                            slotBtn = shownSlots[vi].slot
                            cachedInfo = shownSlots[vi]._cachedInfo
                        else
                            slotBtn = vi
                            cachedInfo = shownSlots[vi] and shownSlots[vi]._cachedInfo
                        end
                        local colour = (vi - 1) % COLUMNS
                        local line = math.floor((vi - 1) / COLUMNS)
                        _layout[#_layout + 1] = {
                            bagID = tabBtn.bagID,
                            slot = slotBtn,
                            _cachedInfo = cachedInfo,
                            x = startX + (colour * (SLOT_SIZE + SPACING)),
                            y = nextY - (line * (SLOT_SIZE + SPACING)),
                        }
                    end
                    local rowList = math.ceil(count / COLUMNS)
                    nextY = nextY - (rowList * (SLOT_SIZE + SPACING)) - 6
                end
            end
        end
    end

    -- Split tabs into char and warband
    local charTabs, warbTabs = {}, {}
    for _, tabBtn in ipairs(_allTabs) do
        if tabBtn.isWarband then
            warbTabs[#warbTabs + 1] = tabBtn
        else
            charTabs[#charTabs + 1] = tabBtn
        end
    end

    local LayoutOneView = LayoutGroupedSlots

    -- Category index spans whatever the sidebar can browse: warband only for
    -- a portable warbank, otherwise both banks together.
    if BagsProfile().bankCategorySidebar then
        _catIndex = BuildBankCategoryIndex(_warbandOnly and warbTabs or _allTabs, PassesSearch)
    else
        _catIndex = nil
    end
    if _catSel and not _catIndex then
        _catSel = nil
    end

    if _catSel then
        LayoutSelectionSlots(GetSelectionSlots() or {})
    elseif _selectedView == -1 then
        -- OneBank: character bank only, flat with "Bank" header
        local slotTable, filled = BuildOneView(charTabs)
        LayoutOneView(slotTable, CludesUI.Lf("Bank (%1$d / %2$d)", filled, #slotTable))
    elseif _selectedView == -3 then
        -- OneWarbank: warband bank only, flat with "Warband Bank" header
        local slotTable, filled = BuildOneView(warbTabs)
        LayoutOneView(slotTable, CludesUI.Lf("Warband Bank (%1$d / %2$d)", filled, #slotTable))
    elseif _selectedView == -2 then
        -- All Warbank Tabs: per-tab headers for warband only
        LayoutTabHeaders(warbTabs)
    elseif _selectedView == 0 then
        -- All Bank Tabs: per-tab headers for character only
        LayoutTabHeaders(charTabs)
    else
        local tabBtn = _allTabs[_selectedView]
        if tabBtn then
            local allSlots = {}
            local used = 0
            for slotBtn = 1, tabBtn.numSlots do
                local details = C_Container.GetContainerItemInfo(tabBtn.bagID, slotBtn)
                if details then
                    used = used + 1
                end
                CUI_Bags.ApplyBindKeyword(details, tabBtn.bagID, slotBtn)
                allSlots[#allSlots + 1] = { slot = slotBtn, _cachedInfo = details }
            end
            local shownSlots = allSlots
            if hasSearch then
                -- use native search filter so type keywords work too
                local filtered = {}
                for _, slotView in ipairs(allSlots) do
                    if slotView._cachedInfo and not slotView._cachedInfo.isFiltered then
                        filtered[#filtered + 1] = slotView
                    end
                end
                shownSlots = filtered
            end
            headerIndex = headerIndex + 1
            _layout[#_layout + 1] = {
                isHeader = true,
                headerIdx = headerIndex,
                label = tabBtn.name .. " (" .. used .. ")",
                name = tabBtn.name,
                x = startX,
                y = nextY,
                w = gridWidth,
            }
            nextY = nextY - 22
            local count = #shownSlots
            for vi = 1, count do
                local slotView = shownSlots[vi]
                local colour = (vi - 1) % COLUMNS
                local line = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = tabBtn.bagID,
                    slot = slotView.slot,
                    _cachedInfo = slotView._cachedInfo,
                    x = startX + (colour * (SLOT_SIZE + SPACING)),
                    y = nextY - (line * (SLOT_SIZE + SPACING)),
                }
            end
            local rowList = math.ceil(count / COLUMNS)
            nextY = nextY - (rowList * (SLOT_SIZE + SPACING))
        end
    end

    local listCols, listRowW
    if CUI_Bank.IsListMode() then
        -- Left / Right Gap: space between the list area edges and the rows
        local listX = BagsProfile().bagListGapL or 15
        listRowW = math.max(100, gridWidth + contentPad - listX - (BagsProfile().bagListGapR or 23))
        _layout, nextY = ToListLayout(_layout, startX, listX)
        listCols = mod.ListLayoutColumns(listRowW)
        local hdrH = mod.UpdateListHeaderBar(CUI_Bank, listCols, sidebarW, -HEADER_H, listX)
        scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", sidebarW, -(HEADER_H + hdrH))
    elseif CUI_Bank.IsCompactMode() then
        -- Compact: the same entries as blocks, each under a thin label band.
        -- The window drops the remainder its widest band leaves short of the
        -- columns, less than a cell; while open it only grows back, and a new
        -- column count, or a close, starts over (as the bag window does).
        local contentW
        _layout, nextY, contentW = ToCompactLayout(_layout, startX, COLUMNS)
        if contentW and contentW < gridWidth then
            if CUI_Bank._compactCols ~= COLUMNS then
                CUI_Bank._compactCols, CUI_Bank._compactW = COLUMNS, contentW
            elseif contentW > (CUI_Bank._compactW or 0) then
                CUI_Bank._compactW = contentW
            end
            gridWidth = CUI_Bank._compactW
        else
            CUI_Bank._compactCols, CUI_Bank._compactW = COLUMNS, gridWidth
        end
        CUI_Bank:SetWidth(sidebarW + gridWidth + gridPadX * 2 + SCROLLBAR_HIT_W + 2)
        childFrame:SetWidth(gridWidth + contentPad)
    end

    -- Update deposit button based on current view
    local isWarbandView = (_selectedView == -2 or _selectedView == -3)
    if not isWarbandView and _selectedView > 0 and _allTabs[_selectedView] then
        isWarbandView = _allTabs[_selectedView].isWarband
    end
    CUI_Bank:UpdateDepositButton(isWarbandView)

    -- Set scroll child height from layout
    childFrame:SetHeight(math.abs(nextY) + 10)

    -- Phase 2: render the layout, 100 entries per frame (all at once while the resize grip is dragged).
    CUI_Bank._layout = _layout
    CUI_Bank._layoutStartX = startX
    CUI_Bank._layoutGridW = gridWidth

    -- Shared slot render: updates a single button with item or empty state
    -- One reused data table for third-party overlay painters (CUI_Bags.RunItemOverlays).
    local overlayData = {}
    -- Junk Item Visuals' Desaturate greys grey items and Junk Marker junk here
    -- as on the bank's list rows (read once per refresh)
    local junkOn = _G.CUI_CategoryManager:IsJunkMarkerEnabled()
    local desatJunk = BagsProfile().bagDesaturateJunkItems == true
    local function RenderSlotContent(button, bagId, slotBtn, cachedInfo)
        if button.ProfessionQualityOverlay then
            button.ProfessionQualityOverlay:SetAlpha(0)
        end
        if button.IconOverlay then
            button.IconOverlay:SetAlpha(0)
            button.IconOverlay:Hide()
        end
        if button.IconOverlay2 then
            button.IconOverlay2:SetAlpha(0)
            button.IconOverlay2:Hide()
        end
        local details = cachedInfo or C_Container.GetContainerItemInfo(bagId, slotBtn)
        if not details then
            button:SetItemButtonTexture(nil)
            button:SetItemButtonCount(0)
            SetItemButtonDesaturated(button, false)
            if button.icon then
                button.icon:Hide()
            end
            button._emptyBg:Show()
            mod.PaintSlotBackground(button._emptyBg, 0.35)
            button:EnableMouse(true)
            SetInsetBorderColor(button, 0, 0, 0, 0.3)
            if button._fvSlotBorder then
                mod.SetForeverSlotQuestBorder(button, false)
            end
            if button.Cooldown then
                button.Cooldown:Clear()
            end
            if button.ItemLevelText then
                button.ItemLevelText:SetText("")
            end
            if button.BindTypeText then
                button.BindTypeText:SetText("")
            end
            if button.IconBorder then
                button.IconBorder:Hide()
            end
            if button.NormalTexture then
                button.NormalTexture:SetAlpha(0)
            end
        else
            button:EnableMouse(true)
            button._emptyBg:Hide()
            if button.icon then
                button.icon:Show()
            end
            mod.SetSlotIcon(button, details.iconFileID)
            button:SetItemButtonCount(details.stackCount)
            local quality = details.quality or 1
            SetItemButtonDesaturated(
                button,
                details.isLocked
                    or (desatJunk and (quality == 0 or (junkOn and _G.CUI_CategoryManager:IsJunk(
                        details.itemID,
                        quality
                    ))))
                    or false
            )
            local linkText = C_Container.GetContainerItemLink(bagId, slotBtn)
            if linkText then
                button:SetItemButtonQuality(quality, linkText, false, false)
            end
            if
                button.ProfessionQualityOverlay
                and button.ProfessionQualityOverlay:IsShown()
                and button._textOverlay
            then
                button.ProfessionQualityOverlay:SetAlpha(1)
                button.ProfessionQualityOverlay:SetParent(button._textOverlay)
            end
            if button.IconOverlay then
                if button.IconOverlay:IsShown() then
                    button.IconOverlay:SetAlpha(1)
                    if button._textOverlay then
                        button.IconOverlay:SetParent(button._textOverlay)
                    end
                else
                    button.IconOverlay:SetAlpha(0)
                end
            end
            if button.icon and details and details.itemID then
                local unusable = CUI._BagsItemUnusable
                    and CUI._BagsItemUnusable(bagId, slotBtn, details.hyperlink, details.itemID)
                button.icon:SetVertexColor(1, unusable and 0.1 or 1, unusable and 0.1 or 1)
            end
            if button.IconOverlay2 then
                if button.IconOverlay2:IsShown() then
                    button.IconOverlay2:SetAlpha(1)
                    if button._textOverlay then
                        button.IconOverlay2:SetParent(button._textOverlay)
                    end
                else
                    button.IconOverlay2:SetAlpha(0)
                end
            end
            if button.IconBorder then
                button.IconBorder:Hide()
            end
            if button.NormalTexture then
                button.NormalTexture:SetAlpha(0)
            end
            local qr, qg, qb = mod.QualityBorderColor(quality)
            SetInsetBorderColor(button, qr, qg, qb, 1)
            if button._fvSlotBorder then
                mod.SetForeverSlotQuestBorder(button, mod.GetSlotQuestFlags(bagId, slotBtn))
            end

            -- One gear check + one GetItemInfo fetch shared by the bind-type
            -- and item-level texts
            local isGear = linkText and IsGearItem(linkText)
            local showBindType = isGear and not details.isBound and BagsProfile().bagDisplayBindType
            local showIlvl = isGear and BagsProfile().showItemlevelInBags ~= false
            local giIlvl, giBindType
            local loc
            if showBindType or showIlvl then
                local _, _, _, _, _, _, _, _, _, _, _, _, _, b14 = GetItemInfo(linkText)
                loc = ItemLocation:CreateFromBagAndSlot(bagId, slotBtn)
                giIlvl = showIlvl and GetItemLevelAtLocation(loc, linkText) or nil
                giBindType = b14
            end

            -- Bind Type : BoE / WuE bottom-left (gear only)
            if button.BindTypeText then
                if showBindType then
                    local isWuE = false
                    if loc and C_Item.DoesItemExist(loc) then
                        isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                    end
                    CUI_Bags.SetBindTypeText(button.BindTypeText, isWuE, giBindType, quality)
                else
                    button.BindTypeText:SetText("")
                end
            end

            -- Item level (gear only)
            if button.ItemLevelText then
                if showIlvl then
                    button.ItemLevelText:SetText(giIlvl or "")
                    local red, green, blue
                    if GetUpgradeTrack then
                        local rankText, trackColor = GetUpgradeTrack(linkText)
                        if BagsProfile().itemlevelUseCustomColor and BagsProfile().itemlevelCustomColor then
                            red, green, blue =
                                BagsProfile().itemlevelCustomColor.r,
                                BagsProfile().itemlevelCustomColor.g,
                                BagsProfile().itemlevelCustomColor.b
                        elseif rankText and rankText ~= "" and trackColor then
                            red, green, blue = trackColor.r, trackColor.g, trackColor.b
                        else
                            local craftedColor = CUI.GetCraftedTrackColor(linkText)
                            if craftedColor then
                                red, green, blue = craftedColor.r, craftedColor.g, craftedColor.b
                            end
                        end
                    end
                    if not red then
                        red, green, blue = GetItemQualityColor(quality)
                    end
                    button.ItemLevelText:SetTextColor(red, green, blue, 1)
                else
                    button.ItemLevelText:SetText("")
                end
            end
            if button.Cooldown then
                local cdS, cdD, cdE = C_Container.GetContainerItemCooldown(bagId, slotBtn)
                if cdE and cdE ~= 0 and cdS > 0 and cdD > 0 then
                    button.Cooldown:SetDrawEdge(true)
                    button.Cooldown:SetCooldown(cdS, cdD)
                else
                    button.Cooldown:Clear()
                end
            end
        end
        if next(CUI_Bags.itemOverlayIcons) ~= nil then
            overlayData.bag, overlayData.slot, overlayData.info = bagId, slotBtn, details
            overlayData.itemLink = details and C_Container.GetContainerItemLink(bagId, slotBtn) or nil
            CUI_Bags.RunItemOverlays(button, overlayData)
        end
    end

    -- Render in batches of 100 per frame via OnUpdate. While the resize grip
    -- is dragged, render everything this frame so headers never blink.
    local BATCH_SIZE = CUI_Bank._resizing and math.huge or 100
    local wasRendered = 0
    local slotIdx, rowIdx = 0, 0

    local function RenderBatch()
        local batchEnd = math.min(wasRendered + BATCH_SIZE, #_layout)
        for lineIndex = wasRendered + 1, batchEnd do
            local record = _layout[lineIndex]
            if record.isHeader then
                if record.compact then
                    -- Compact group label (font and text set by ToCompactLayout)
                    local lf = mod.CompactLabel(CUI_Bank._compactLabels, record.headerIdx, CUI_Bank)
                    mod.CompactShowLabel(
                        lf,
                        childFrame,
                        record.x,
                        record.y,
                        record.w,
                        record.h,
                        record.label,
                        record.textW,
                        nil,
                        0,
                        record.bw
                    )
                else
                    local heading = GetOrCreateBankHeader(record.headerIdx)
                    heading:SetParent(childFrame)
                    heading:ClearAllPoints()
                    heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", record.x, record.y)
                    heading:SetWidth(record.w)
                    -- Headers are pooled and reused across refreshes, so every
                    -- depth must set every property rather than rely on defaults.
                    local skinData = record.depth or 0
                    if skinData >= 2 then
                        SetBankFont(heading._label, 10)
                        heading._label:SetTextColor(0.45, 0.45, 0.45)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.06)
                    elseif skinData == 1 then
                        SetBankFont(heading._label, 10)
                        heading._label:SetTextColor(0.55, 0.55, 0.55)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.10)
                    else
                        SetBankFont(heading._label, 11)
                        heading._label:SetTextColor(0.7, 0.7, 0.7)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
                    end
                    if forever then
                        mod.SetForeverBagSectionColors(heading._label, heading._line, skinData)
                    end
                    heading._label:SetText(record.label)
                    heading:Show()
                end -- compact label vs grid header
            elseif record.isRow then
                local button = GetOrCreateBankRow(rowIdx + 1)
                if button then
                    rowIdx = rowIdx + 1
                    button:GetParent():SetParent(childFrame)
                    mod.RenderListRow(button, record.data, listCols, listRowW, record.x, record.y, record.stripe)
                end
            else
                slotIdx = slotIdx + 1
                -- nil in combat: the cell stays empty until the combat-end refresh
                local button = GetOrCreateBankSlot(slotIdx)
                if button then
                    button:GetParent():SetParent(childFrame)
                    local hostFrame = button:GetParent()
                    hostFrame:ClearAllPoints()
                    hostFrame:SetPoint("TOPLEFT", record.x, record.y)
                    hostFrame:Show()
                    button:Show()
                    button:SetID(record.slot)
                    hostFrame:SetID(record.bagID)

                    RenderSlotContent(button, record.bagID, record.slot, record._cachedInfo)
                end -- slot built
            end
        end
        wasRendered = batchEnd
    end

    -- Hide pooled slots and rows this refresh did not use
    local function HideUnused()
        for si = slotIdx + 1, #_bankSlots do
            if _bankSlots[si] then
                _bankSlots[si]:GetParent():Hide()
            end
        end
        for ri = rowIdx + 1, #_bankRows do
            _bankRows[ri]:GetParent():Hide()
        end
    end

    -- Render first batch immediately (same frame) so item moves don't blink.
    -- Remaining batches deferred via OnUpdate for large refreshes (tab open).
    RenderBatch()
    if not CUI_Bank._batchFrame then
        CUI_Bank._batchFrame = CreateFrame("Frame")
    end
    if wasRendered >= #_layout then
        CUI_Bank._batchFrame:SetScript("OnUpdate", nil)
        HideUnused()
    else
        CUI_Bank._batchFrame:SetScript("OnUpdate", function(self)
            if wasRendered >= #_layout or not CUI_Bank:IsVisible() then
                self:SetScript("OnUpdate", nil)
                HideUnused()
                return
            end
            RenderBatch()
            if wasRendered >= #_layout then
                self:SetScript("OnUpdate", nil)
                HideUnused()
            end
        end)
    end

    scrollFrame:SetVerticalScroll(
        math.min(scrollFrame:GetVerticalScroll(), scrollFrame:GetVerticalScrollRange())
    )
    UpdateThumb()

    -- Build sidebar
    BuildBankSidebar()
    mod.UpdateResizeGrip(CUI_Bank, CUI_Bank.IsListMode() and _bankListGripCfg or _bankGripCfg)
end

-------------------------------------------------------------------------------
--  Sidebar Build
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  drag to reorder categories: top-level rows move among themselves, group
--  members only inside their group. same order the bags use.
-------------------------------------------------------------------------------
-- every tab divider the sidebar can show; a build hides them all first
local SIDEBAR_DIVIDERS =
    { "_bankTabDivider", "_warbandDivider", "_warbandTabDivider", "_warbandViewDivider", "_buyDivider" }

local _drag -- { btn, scope, id, startY, live } while a drag is going
-- moves at each drag start and each sidebar build: a row's block is worked out
-- once per value (nothing reorders until the drop)
local _dragGen = 0

-- a row's selection, nil for the buy rows
local function RowSel(button)
    return not button._isPurchaseTab and button._catSel or nil
end

-- a selection's block id + category indices in this scope ("top" or "group:<name>"), nil if it's not in it
local function DragBlock(sel, scope)
    local CM = _G.CUI_CategoryManager
    if not (sel and CM) then
        return nil
    end
    local categories = CM:GetCategories()
    local set, i = sel.group, nil
    if not set then
        for containerInfo, c in ipairs(categories) do
            if c._defaultName == sel.key then
                i = containerInfo
                break
            end
        end
        if not i or categories[i].isJunk or categories[i].isEquipSet or categories[i].isVirtual then
            return nil
        end
        set = categories[i].groupName
    end
    if scope == "top" then
        if set then
            return "g:" .. set, CM:GetGroupMembers(set)
        end
        -- item set gear drags its set categories with it
        local block = { i }
        if categories[i].isSetGear then
            for containerInfo, c in ipairs(categories) do
                if c.isEquipSet then
                    block[#block + 1] = containerInfo
                end
            end
        end
        return "k:" .. sel.key, block
    end
    if i and set and scope == "group:" .. set then
        return "k:" .. sel.key, { i }
    end
end

-- what pressing this row would drag (detail rows and junk don't move)
local function DragScope(button)
    local sel = button._catSel
    if not sel or sel.detail then
        return nil
    end
    if sel.group then
        return "top"
    end
    local CM = _G.CUI_CategoryManager
    for _, c in ipairs(CM and CM:GetCategories() or {}) do
        if c._defaultName == sel.key then
            if c.isJunk or c.isEquipSet or c.noMove then
                return nil
            end
            return c.groupName and ("group:" .. c.groupName) or "top"
        end
    end
end

local dragHost = CreateFrame("Frame")
dragHost:Hide()
local dragShade, dragRule

local function DragVisuals(button)
    if not dragShade then
        dragShade = CreateFrame("Frame", nil, UIParent)
        dragShade:SetFrameStrata("TOOLTIP")
        dragShade:SetSize(150, SIDEBAR_BTN_H)
        dragShade:SetAlpha(0.7)
        local backdrop = dragShade:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.6)
        dragShade._icon = dragShade:CreateTexture(nil, "ARTWORK")
        dragShade._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        dragShade._label = dragShade:CreateFontString(nil, "OVERLAY")
        SetBankFont(dragShade._label, 11)
        dragShade._label:SetPoint("LEFT", dragShade._icon, "RIGHT", 6, 0)
        dragRule = sideChild:CreateTexture(nil, "OVERLAY")
        dragRule:SetHeight(2)
    end
    dragShade._icon:SetTexture(button._icon:GetTexture())
    dragShade._icon:SetTexCoord(button._icon:GetTexCoord())
    dragShade._label:SetText(button._entryName or "")
    local navCollapsed = BagsProfile().bankSidebarCollapsed and mod.BagsForever()
    mod.AnchorBagSidebarIcon(dragShade._icon, navCollapsed, 6)
    dragShade._label:SetShown(not navCollapsed)
    dragShade:SetWidth(
        navCollapsed and button:GetWidth()
            or math.max(dragShade._label:GetStringWidth() + SIDEBAR_ICON_SIZE + 24, 80)
    )
    local red, green, blue = GetAccentRGB()
    dragRule:SetColorTexture(red, green, blue, 1)
end

-- a row's block id + indices in the drag's scope, kept on the row for this _dragGen
local function RowBlock(b)
    if b._dragGen ~= _dragGen then
        b._dragGen = _dragGen
        b._dragId, b._dragBlock = DragBlock(RowSel(b), _drag.scope)
    end
    return b._dragId, b._dragBlock
end

-- where the drop lands: the block under the cursor, before or after it
local function DragTarget()
    local over
    for _, btn in pairs(_sidebarBtns) do
        if btn:IsShown() and btn:IsMouseOver() then
            over = btn
            break
        end
    end
    if not over then
        return nil
    end
    local ident, block = RowBlock(over)
    if not ident or ident == _drag.id then
        return nil
    end
    -- all of the block's rows (a group's header, members, details)
    local topY, bottom
    for _, btn in pairs(_sidebarBtns) do
        if btn:IsShown() and RowBlock(btn) == ident then
            if not topY or btn:GetTop() > topY:GetTop() then
                topY = btn
            end
            if not bottom or btn:GetBottom() < bottom:GetBottom() then
                bottom = btn
            end
        end
    end
    local _, curY = GetCursorPosition()
    curY = curY / sideChild:GetEffectiveScale()
    local after = curY < (topY:GetTop() + bottom:GetBottom()) / 2
    return block, after, after and bottom or topY
end

local function FinishDrag(apply)
    local skinData = _drag
    _drag = nil
    dragHost:Hide()
    if dragShade then
        dragShade:Hide()
        dragRule:Hide()
    end
    if not (skinData and skinData.live) then
        return
    end
    skinData.btn:SetAlpha(1)
    local target = apply and skinData.target
    if not target then
        return
    end
    local CM = _G.CUI_CategoryManager
    local categories = CM:GetCategories()
    -- from the row's selection at press time: a refresh mid-drag can hand the pooled row to another category
    local _, block = DragBlock(skinData.sel, skinData.scope)
    if not block then
        return
    end
    local insertAt = skinData.after and (math.max(unpack(target)) + 1) or math.min(unpack(target))
    table.sort(block)
    if insertAt >= block[1] and insertAt <= block[#block] + 1 then
        return
    end
    -- equip sets follow item set gear on their own (SaveState), so the rest
    -- moves one ReorderCategory at a time (its junk / set rules apply), each
    -- dropped in just above the target row; found by reference every step
    local moving, sets = {}, false
    for _, i in ipairs(block) do
        if categories[i].isEquipSet then
            sets = true
        else
            moving[#moving + 1] = categories[i]
        end
    end
    local before = categories[insertAt] -- nil: the end of the list
    -- keep the bags' selection on the same category, not the same index
    local selIdx, selGroup = mod.GetSelection()
    local selKey = selIdx and selIdx > 0 and categories[selIdx] and categories[selIdx]._defaultName
    local function IndexOf(c)
        for i, posX in ipairs(categories) do
            if posX == c then
                return i
            end
        end
    end
    for _, c in ipairs(moving) do
        local from = IndexOf(c)
        if from then
            CM:ReorderCategory(from, before and IndexOf(before) or #categories + 1)
        end
    end
    -- the sets catch up with their anchor on a rebuild from the saved order
    if sets then
        CM:OnEquipmentSetsChanged()
    end
    if selKey then
        for containerInfo, c in ipairs(CM:GetCategories()) do
            if c._defaultName == selKey then
                mod.SetSelection(containerInfo, selGroup)
                break
            end
        end
    end
    CUI_Bank:RefreshBank()
    if CUI_Bags:IsVisible() then
        CUI_Bags:RefreshInventory()
    end
end

dragHost:SetScript("OnUpdate", function()
    local skinData = _drag
    if not skinData then
        dragHost:Hide()
        return
    end
    local posX, posY = GetCursorPosition()
    if not IsMouseButtonDown("LeftButton") then
        FinishDrag(true)
        return
    end
    if not skinData.live then
        -- only counts as a drag after a few pixels
        if math.abs(posY - skinData.startY) <= 4 then
            return
        end
        skinData.live = true
        skinData.btn._didDrag = true
        skinData.btn:SetAlpha(0.4)
        DragVisuals(skinData.btn)
        dragShade:Show()
    end
    local uiScale = UIParent:GetEffectiveScale()
    dragShade:ClearAllPoints()
    dragShade:SetPoint("LEFT", UIParent, "BOTTOMLEFT", posX / uiScale + 12, posY / uiScale)
    local block, after, line = DragTarget()
    skinData.target, skinData.after = block, after
    if line then
        dragRule:ClearAllPoints()
        local inset = math.floor(sideChild:GetWidth() * 0.05)
        local edge = after and "BOTTOM" or "TOP"
        dragRule:SetPoint("LEFT", line, edge .. "LEFT", inset, 0)
        dragRule:SetPoint("RIGHT", line, edge .. "RIGHT", -inset, 0)
        dragRule:Show()
    else
        dragRule:Hide()
    end
end)

local function BeginDrag(button)
    local scope = DragScope(button)
    if not scope then
        return
    end
    local _, posY = GetCursorPosition()
    local sel = RowSel(button)
    _dragGen = _dragGen + 1
    _drag = { btn = button, sel = sel, scope = scope, id = DragBlock(sel, scope), startY = posY }
    dragHost:Show()
end
-- closing the bank mid-drag hides the rows, so the drop just goes nowhere

function BuildBankSidebar()
    local navCollapsed = BagsProfile().bankSidebarCollapsed
    local sidebarW = GetBankSidebarContentWidth()
    local posY = 0
    local accR, accG, accB = GetAccentRGB()
    sideChild:SetWidth(sidebarW)
    local btnCount = 0
    -- While a category is selected no view or tab entry is current.
    local selectedView = _catSel and -99 or _selectedView

    -- Update sidebar header label visibility
    if navCollapsed then
        sidebarHdr._label:Hide()
    else
        sidebarHdr._label:Show()
    end

    local function MakeSidebarBtn(position)
        if _sidebarBtns[position] then
            return _sidebarBtns[position]
        end
        local button = CreateFrame("Button", nil, sideChild)
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
        SetBankFont(button._label, 11)
        button._label:SetJustifyH("LEFT")
        button._label:SetWordWrap(false)
        button._label:SetPoint("LEFT", button._icon, "RIGHT", 6, 0)
        button._label:SetPoint("RIGHT", button, "RIGHT", -30, 0)
        button._count = button:CreateFontString(nil, "OVERLAY")
        SetBankFont(button._count, 10)
        button._count:SetJustifyH("RIGHT")
        button._count:SetTextColor(0.5, 0.5, 0.5)
        button._count:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        button:SetScript("OnEnter", function(self)
            local showEditableTabTooltip = CUI.ShowWidgetTooltip
                and not self._isPurchaseTab
                and self._viewIdx
                and self._viewIdx > 0

            if not self._isSelected then
                self._bg:SetColorTexture(1, 1, 1, 0.06)
            end
            if BagsProfile().bankSidebarCollapsed and CUI.ShowWidgetTooltip then
                CUI.ShowWidgetTooltip(
                    self,
                    (self._entryName or "?")
                        .. " ("
                        .. (self._entryCount or 0)
                        .. ")"
                        .. (
                            showEditableTabTooltip
                                and ("\n|cffdab842" .. BANK_TAB_TOOLTIP_CLICK_INSTRUCTION .. "|r")
                            or ""
                        )
                )
            end
            if not BagsProfile().bankSidebarCollapsed and showEditableTabTooltip then
                CUI.ShowWidgetTooltip(self, "|cffdab842" .. BANK_TAB_TOOLTIP_CLICK_INSTRUCTION .. "|r")
            end
        end)
        button:SetScript("OnLeave", function(self)
            if not self._isSelected then
                self._bg:SetColorTexture(1, 1, 1, 0)
            end
            CUI.HideWidgetTooltip()
        end)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnMouseDown", function(self, btnFrame)
            -- a drop over another row never clicks this one, so clear it here
            self._didDrag = false
            if btnFrame == "LeftButton" and not self._isPurchaseTab then
                BeginDrag(self)
            end
        end)
        button:SetScript("OnClick", function(self, btnFrame)
            if self._isPurchaseTab then
                return
            end
            -- letting go of a drag isn't a click
            if self._didDrag then
                self._didDrag = false
                return
            end

            if btnFrame == "RightButton" and self._viewIdx and self._viewIdx > 0 then
                local tabInfo = _allTabs[self._viewIdx]
                if tabInfo then
                    -- The bagID is the tab ID UpdateBankTabSettings expects:
                    -- Enum.BagIndex.CharacterBankTab_1..6 / AccountBankTab_1..5
                    EnsureBankTabConfigFrame()
                    if CUI_BankTabConfigFrame.OpenBankTabSettings then
                        CUI_BankTabConfigFrame:OpenBankTabSettings(tabInfo, tabInfo.bagID)
                    end
                    return
                end
            end

            if btnFrame == "LeftButton" then
                if self._catSel then
                    -- Re-clicking a selected category steps back out of it.
                    if self._isSelected then
                        _catSel = nil
                    else
                        _catSel = self._catSel
                    end
                else
                    _catSel = nil
                    _selectedView = self._viewIdx
                end
                if CUI_Bank._scrollFrame then
                    CUI_Bank._scrollFrame:SetVerticalScroll(0)
                end
                CUI_Bank:RefreshBank()
                -- Refresh bags so warbank dim overlay updates immediately
                if _G.CUI_Bags and _G.CUI_Bags:IsVisible() and _G.CUI_Bags.RefreshInventory then
                    _G.CUI_Bags:RefreshInventory()
                end
            end
        end)
        _sidebarBtns[position] = button
        return button
    end

    local function RenderPurchaseEntry(bankKind, caption)
        btnCount = btnCount + 1
        local button = MakeSidebarBtn(btnCount)
        local locLabel = CludesUI.L(caption)
        button._viewIdx = nil
        button._catSel = nil
        button._isPurchaseTab = true
        button._purchaseBankType = bankKind
        button._isSelected = false
        -- Store the localized label so the collapsed-sidebar hover tooltip (which
        -- reads _entryName) matches the expanded label on non-English clients.
        button._entryName = locLabel
        button._entryCount = 0
        button._indicator:Hide()
        button._bg:SetColorTexture(1, 1, 1, 0)
        button:SetParent(sideChild)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, posY)
        button:SetWidth(sidebarW)
        mod.AnchorBagSidebarIcon(button._icon, navCollapsed, 8)
        button._icon:SetTexture(133784)
        button._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button._icon:SetDesaturated(false)
        button._icon:SetAlpha(0.6)
        if navCollapsed then
            button._label:Hide()
            button._count:Hide()
        else
            button._label:Show()
            button._label:SetText(locLabel)
            button._label:SetTextColor(1, 1, 1, 0.6)
            button._count:Hide()
        end
        button:SetAlpha(0.6)
        button:Show()
        -- Overlay the secure purchase button on top of this visual entry
        local secBtn = (bankKind == Enum.BankType.Character) and _purchaseBtnChar or _purchaseBtnWarband
        secBtn._visualBtn = button
        secBtn:SetParent(sideChild)
        secBtn:ClearAllPoints()
        secBtn:SetAllPoints(button)
        secBtn:SetFrameLevel(button:GetFrameLevel() + 20)
        secBtn:Show()
        posY = posY - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    local function RenderSidebarEntry(viewIdx, caption, iconTex, count, isSelected, indent, catSel, isAtlas)
        btnCount = btnCount + 1
        local button = MakeSidebarBtn(btnCount)
        button._viewIdx = viewIdx
        button._catSel = catSel
        button._isPurchaseTab = false
        button._isSelected = isSelected
        button._entryName = caption
        button._entryCount = count
        button:SetAlpha(1)
        button:SetParent(sideChild)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, posY)
        button:SetWidth(sidebarW)
        mod.AnchorBagSidebarIcon(button._icon, navCollapsed, 8 + (indent or 0) * 10)
        if isAtlas and button._icon.SetAtlas then
            button._icon:SetAtlas(iconTex)
        else
            -- Through the client icon map, like the bag window's sidebar: a
            -- default the Forever client cannot draw takes its stand-in there.
            -- Cropped on every paint (a pooled row may last have drawn an atlas).
            button._icon:SetTexture(CludesUI.ClientIcon(iconTex))
            button._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        button._icon:SetAlpha(isSelected and 1 or 0.75)

        if navCollapsed then
            button._label:Hide()
            button._count:Hide()
        else
            button._label:Show()
            button._label:SetText(caption)
            button._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)
            button._count:Show()
            button._count:SetText(tostring(count))
        end

        if isSelected then
            button._indicator:SetColorTexture(accR, accG, accB, 1)
            button._indicator:Show()
            button._bg:SetColorTexture(accR, accG, accB, 0.1)
        else
            button._indicator:Hide()
            button._bg:SetColorTexture(1, 1, 1, 0)
        end
        button:Show()
        posY = posY - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    -- Hide all sidebar buttons + secure purchase overlays
    for _, button in pairs(_sidebarBtns) do
        button:Hide()
    end
    _purchaseBtnChar:Hide()
    _purchaseBtnWarband:Hide()

    -- Count used slots per tab, split by bank/warbank
    local charUsed, charTotal = 0, 0
    local warbUsed, warbTotal = 0, 0
    for _, tabBtn in ipairs(_allTabs) do
        tabBtn._usedSlots = CountUsedSlots(tabBtn.bagID, tabBtn.numSlots)
        if tabBtn.isWarband then
            warbUsed = warbUsed + tabBtn._usedSlots
            warbTotal = warbTotal + tabBtn.numSlots
        else
            charUsed = charUsed + tabBtn._usedSlots
            charTotal = charTotal + tabBtn.numSlots
        end
    end

    -- Update header item count
    if CUI_Bank._headerItemCount then
        if _warbandOnly then
            CUI_Bank._headerItemCount:SetText(CludesUI.Lf("%d / %d Slots", warbUsed, warbTotal))
        else
            CUI_Bank._headerItemCount:SetText(
                CludesUI.Lf("%d / %d Slots", charUsed + warbUsed, charTotal + warbTotal)
            )
        end
    end

    -- View indices: 0 = All Bank Tabs, -1 = OneBank, -2 = All Warbank Tabs, -3 = OneWarbank
    -- >0 = individual tab index in _allTabs

    -- Divider
    local function ShowDivider(sortKey)
        if not sideChild[sortKey] then
            local Pix = CUI and CUI.PP
            local px = (Pix and Pix.mult) or 1
            local div = sideChild:CreateTexture(nil, "ARTWORK")
            div:SetHeight(px)
            div:SetColorTexture(0.2, 0.2, 0.2, 1)
            sideChild[sortKey] = div
        end
        posY = posY - 4
        local div = sideChild[sortKey]
        div:ClearAllPoints()
        local inset = math.floor(sidebarW * 0.08)
        div:SetPoint("TOPLEFT", sideChild, "TOPLEFT", inset, posY)
        div:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", -inset, posY)
        div:Show()
        posY = posY - (div:GetHeight() or 1) - 4
    end

    -- Physical tabs can be hidden once the category list is doing the
    -- navigating, but only when it is actually on -- otherwise the sidebar
    -- would have nothing left to click.
    local showTabs = not (BagsProfile().bankHideTabsInSidebar and BagsProfile().bankCategorySidebar and _catIndex)

    -- offline bank on: tabs nest under their all entry, a divider splits the
    -- bank and warbank views and the buy entries go last (an alt's bank draws
    -- the same way). off: the usual layout
    local nested = mod.Offline and mod.Offline.Enabled()
    for _, k in ipairs(SIDEBAR_DIVIDERS) do
        if sideChild[k] then
            sideChild[k]:Hide()
        end
    end
    -- the rows may be handed to other entries: a drag works their blocks out again
    _dragGen = _dragGen + 1

    local oneBagDefault = BankDefaultsToOne()
    local hasWarbandTab = false
    for _, tabBtn in ipairs(_allTabs) do
        if tabBtn.isWarband then
            hasWarbandTab = true
            break
        end
    end
    if nested then
        -- tabs nested under their all entry
        local function NestTabs(warband)
            if not showTabs then
                return
            end
            for ti, tabBtn in ipairs(_allTabs) do
                if (tabBtn.isWarband == true) == warband then
                    RenderSidebarEntry(
                        ti,
                        tabBtn.shortName or tabBtn.name,
                        tabBtn.icon or (warband and 1542854 or 133652),
                        tabBtn._usedSlots,
                        selectedView == ti,
                        1
                    )
                end
            end
        end
        if not _warbandOnly then
            local function All()
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selectedView == 0)
                NestTabs(false)
            end
            local function One()
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selectedView == -1)
            end
            if oneBagDefault then
                One()
                All()
            else
                All()
                One()
            end
        end
        if hasWarbandTab then
            -- keeps the bank and warbank views apart
            if not _warbandOnly then
                ShowDivider("_warbandViewDivider")
            end
            local function All()
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selectedView == -2)
                NestTabs(true)
            end
            local function One()
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selectedView == -3)
            end
            if oneBagDefault then
                One()
                All()
            else
                All()
                One()
            end
        end
    else
        if not _warbandOnly then
            if oneBagDefault then
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selectedView == -1)
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selectedView == 0)
            else
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selectedView == 0)
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selectedView == -1)
            end
        end

        -- Warband "All" and "One" entries
        if hasWarbandTab then
            if oneBagDefault then
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selectedView == -3)
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selectedView == -2)
            else
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selectedView == -2)
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selectedView == -3)
            end
        end
    end

    -- Category entries, mirroring the bags sidebar: group header, then its
    -- members indented under it, then the per-category detail split as a third
    -- level -- shown only for the selected branch, or the sidebar would run to
    -- fifty-odd entries on a full bank.
    if _catIndex and BagsProfile().bankCategorySidebar then
        local CM = _G.CUI_CategoryManager
        local categories = (CM and CM:GetCategories()) or {}

        local function CountFor(category)
            local callback = category._defaultName and _catIndex.byKey[category._defaultName]
            return callback and #callback.slots or 0
        end

        local function EmitDetail(category, indent)
            local sortKey = category._defaultName
            local bagSlot = sortKey and _catIndex.detailByKey[sortKey]
            if not bagSlot or navCollapsed then
                return
            end
            -- Expand only under the selected category, or under a selected group
            -- that this category belongs to.
            local open = _catSel
                and (_catSel.key == sortKey or (_catSel.group and _catSel.group == category.groupName))
            if not open then
                return
            end
            for _, b in ipairs(bagSlot) do
                RenderSidebarEntry(
                    nil,
                    b.label,
                    category.icon or 134400,
                    #b.slots,
                    _catSel.key == sortKey and _catSel.detail == b.label,
                    indent,
                    { key = sortKey, detail = b.label },
                    category.isAtlas
                )
            end
        end

        local anyCat = false
        local renderedGroups = {}
        for _, category in ipairs(categories) do
            -- Pinned / Recent / Reagent Bag / Special Bags are bag-side concepts with
            -- no bank equivalent; ClassifyItem never routes bank items to them anyway.
            if
                not (category.isPinned or category.isRecent or category.isReagentBag or category.isSpecialBag)
            then
                if category.groupName then
                    if not renderedGroups[category.groupName] then
                        renderedGroups[category.groupName] = true
                        local members = (CM and CM:GetGroupMembers(category.groupName)) or {}
                        local sum, firstCat = 0, nil
                        for _, mi in ipairs(members) do
                            local mc = categories[mi]
                            if mc then
                                sum = sum + CountFor(mc)
                                if not firstCat then
                                    firstCat = mc
                                end
                            end
                        end
                        if sum > 0 then
                            if not anyCat then
                                anyCat = true
                                ShowDivider("_catDivider")
                            end
                            RenderSidebarEntry(
                                nil,
                                CM:GroupDisplayName(category.groupName),
                                (firstCat and firstCat.icon) or 134400,
                                sum,
                                _catSel and _catSel.group == category.groupName,
                                0,
                                { group = category.groupName },
                                firstCat and firstCat.isAtlas
                            )
                            for _, mi in ipairs(members) do
                                local mc = categories[mi]
                                local num = mc and CountFor(mc) or 0
                                if mc and num > 0 then
                                    RenderSidebarEntry(
                                        nil,
                                        mc.name,
                                        mc.icon or 134400,
                                        num,
                                        _catSel and _catSel.key == mc._defaultName and not _catSel.detail,
                                        1,
                                        { key = mc._defaultName },
                                        mc.isAtlas
                                    )
                                    EmitDetail(mc, 2)
                                end
                            end
                        end
                    end
                else
                    local num = CountFor(category)
                    if num > 0 then
                        if not anyCat then
                            anyCat = true
                            ShowDivider("_catDivider")
                        end
                        RenderSidebarEntry(
                            nil,
                            category.name,
                            category.icon or 134400,
                            num,
                            _catSel and _catSel.key == category._defaultName and not _catSel.detail,
                            0,
                            { key = category._defaultName },
                            category.isAtlas
                        )
                        EmitDetail(category, 1)
                    end
                end
            end
        end
        if not anyCat and sideChild._catDivider then
            sideChild._catDivider:Hide()
        end
    elseif sideChild._catDivider then
        sideChild._catDivider:Hide()
    end

    if nested then
        -- buy entries go at the bottom
        local canBuyChar = not _warbandOnly
            and C_Bank
            and C_Bank.CanPurchaseBankTab
            and C_Bank.HasMaxBankTabs
            and C_Bank.CanPurchaseBankTab(Enum.BankType.Character)
            and not C_Bank.HasMaxBankTabs(Enum.BankType.Character)
        local canBuyWarband = C_Bank
            and C_Bank.CanPurchaseBankTab
            and C_Bank.HasMaxBankTabs
            and C_Bank.CanPurchaseBankTab(Enum.BankType.Account)
            and not C_Bank.HasMaxBankTabs(Enum.BankType.Account)
        if canBuyChar or canBuyWarband then
            ShowDivider("_buyDivider")
        end
        if canBuyChar then
            RenderPurchaseEntry(Enum.BankType.Character, "Buy Bank Tab")
        end
        if canBuyWarband then
            RenderPurchaseEntry(Enum.BankType.Account, "Buy Warbank Tab")
        end
    else
        if not _warbandOnly and showTabs then
            ShowDivider("_bankTabDivider")

            -- Character bank tabs
            for ti, tabBtn in ipairs(_allTabs) do
                if not tabBtn.isWarband then
                    RenderSidebarEntry(ti, tabBtn.name, tabBtn.icon or 133652, tabBtn._usedSlots, selectedView == ti)
                end
            end
        else
            if sideChild._bankTabDivider then
                sideChild._bankTabDivider:Hide()
            end
        end

        -- Purchase character bank tab, outside the tab list: hiding the tabs must not
        -- remove the only way to buy one. Matches the warband entry below.
        if
            not _warbandOnly
            and C_Bank
            and C_Bank.CanPurchaseBankTab
            and C_Bank.HasMaxBankTabs
            and C_Bank.CanPurchaseBankTab(Enum.BankType.Character)
            and not C_Bank.HasMaxBankTabs(Enum.BankType.Character)
        then
            if not showTabs then
                ShowDivider("_bankTabDivider")
            end
            RenderPurchaseEntry(Enum.BankType.Character, "Buy Bank Tab")
        end

        -- Warband individual tabs
        if hasWarbandTab and showTabs then
            ShowDivider("_warbandDivider")

            for ti, tabBtn in ipairs(_allTabs) do
                if tabBtn.isWarband then
                    RenderSidebarEntry(ti, tabBtn.name, tabBtn.icon or 1542854, tabBtn._usedSlots, selectedView == ti)
                end
            end
        else
            if sideChild._warbandDivider then
                sideChild._warbandDivider:Hide()
            end
            if sideChild._warbandTabDivider then
                sideChild._warbandTabDivider:Hide()
            end
        end
        -- Purchase warband bank tab
        if
            C_Bank
            and C_Bank.CanPurchaseBankTab
            and C_Bank.HasMaxBankTabs
            and C_Bank.CanPurchaseBankTab(Enum.BankType.Account)
            and not C_Bank.HasMaxBankTabs(Enum.BankType.Account)
        then
            if not hasWarbandTab then
                ShowDivider("_warbandDivider")
            end
            RenderPurchaseEntry(Enum.BankType.Account, "Buy Warbank Tab")
        end
    end

    -- Set scroll child height so scrolling works when content overflows
    sideChild:SetHeight(math.abs(posY) + 4)
end

-------------------------------------------------------------------------------
--  Events: Open/Close Bank
-------------------------------------------------------------------------------
-- Debounced refresh (many BAG_UPDATE/PLAYERBANKSLOTS_CHANGED fire rapidly)
local bankRefreshPending = false
local function ScheduleBankRefresh()
    if bankRefreshPending then
        return
    end
    bankRefreshPending = true
    C_Timer.After(0.1, function()
        bankRefreshPending = false
        if CUI_Bank:IsVisible() then
            CUI_Bank:RefreshBank()
            if RefreshBankBags then
                RefreshBankBags()
            end
        end
    end)
end

-- Bags closed by hand: a later open is the player's, so it outlives the bank.
-- Alt-Z also fires OnHide but leaves IsShown true.
CUI_Bags:HookScript("OnHide", function(self)
    if not self:IsShown() then
        CUI_Bank._autoOpenedBags = false
    end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("BANKFRAME_OPENED")
watcher:RegisterEvent("BANKFRAME_CLOSED")
watcher:RegisterEvent("BAG_UPDATE")
watcher:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
watcher:RegisterEvent("BANK_TABS_CHANGED")
watcher:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
watcher:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
if CUI.IS_FOREVER then
    watcher:RegisterEvent("BAG_CONTAINER_UPDATE")
end
watcher:SetScript("OnEvent", function(_, evt)
    if evt == "BANKFRAME_OPENED" then
        -- WoW Forever's Gamepad interface style at login: Blizzard's bank
        -- (left in place) carries the D-pad navigation; ours stays closed.
        if mod.PadUIStandDown() then
            return
        end
        -- Detect portable warbank (AccountBanker = warband only, no character bank)
        _warbandOnly = C_PlayerInteractionManager
                and C_PlayerInteractionManager.IsInteractingWithNpcOfType(
                    Enum.PlayerInteractionType.AccountBanker
                )
            or false
        if _warbandOnly then
            local oneBagDefault = BankDefaultsToOne()
            _selectedView = oneBagDefault and -3 or -2
        end
        -- Position
        CUI_Bank:ClearAllPoints()
        if BagsProfile().bankPosition then
            local place = BagsProfile().bankPosition
            CUI_Bank:SetPoint(place.point, UIParent, place.relativePoint, place.x, place.y)
        else
            CUI_Bank:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 15, -100)
        end
        -- Clear search on open
        if CUI_Bank._searchBox then
            CUI_Bank._searchBox:SetText("")
            CUI_Bank._searchBox:ClearFocus()
        end
        CUI_Bags.ClearSearch()
        local bankScale = BagsProfile().bagScale or 1
        CUI_Bank:SetScale(bankScale)
        CUI_Bank:Show()
        CUI_Bank:Raise()
        CUI_Bank:RepinIconLevels()
        -- Controller cursor: scroll step buttons and a visible scrollbar,
        -- built only once a controller is in use.
        if CUI_Bank._padBuilt or CUI.PadInUse() then
            CUI_Bank._padBuilt = true
            local enabled = CUI.PadInUse()
            track.PadSync(enabled)
            mod.PadSidebarSync(sidebarHdr, sidebarSF, sideChild, "bankSidebarCollapsed", enabled)
        end
        -- Auto-open bags alongside bank if not already visible
        if CUI_Bags and not CUI_Bags:IsVisible() and mod.BagAutoWindowOn("bagAutoOpenWindows", "bank") then
            CUI_Bags:Show()
            if CUI_Bags.RefreshInventory then
                CUI_Bags:RefreshInventory()
            end
            CUI_Bank._autoOpenedBags = true
        else
            CUI_Bank._autoOpenedBags = false
            -- Refresh bags so warbank dim overlay applies immediately
            if CUI_Bags and CUI_Bags:IsVisible() and CUI_Bags.RefreshInventory then
                CUI_Bags:RefreshInventory()
            end
        end
        -- Set initial size so frame is visible immediately
        local gridWidth = GetBankColumns() * (SLOT_SIZE + SPACING)
        CUI_Bank:SetWidth(GetBankSidebarWidth() + gridWidth + 10 * 2 + SCROLLBAR_HIT_W + 2)
        CUI_Bank:SetHeight(GetBankHeight())
        -- Bank item data loads asynchronously after BANKFRAME_OPENED.
        -- Defer discovery + refresh to next frame via OnUpdate.
        if not CUI_Bank._openPoller then
            CUI_Bank._openPoller = CreateFrame("Frame")
        end
        CUI_Bank._openPoller:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            if not CUI_Bank:IsVisible() then
                return
            end
            DiscoverBankTabs()
            CUI_Bank:RefreshBank()
            if RefreshBankBags then
                RefreshBankBags()
            end
            CUI_Bank:UpdateFooterGold()
            -- Money data is ready once the tabs are: the open event can land before it.
            CUI.GetGoldLedger().RecordWarband()
        end)
    elseif evt == "BANKFRAME_CLOSED" then
        if mod.PadUIStandDown() then
            return
        end -- Forever Gamepad style: ours never opened
        _warbandOnly = false
        _lastTSMBankType = nil
        WipeTransferState()
        -- Clear search on close
        if CUI_Bank._searchBox then
            CUI_Bank._searchBox:SetText("")
            CUI_Bank._searchBox:ClearFocus()
        end
        CUI_Bags.ClearSearch()
        CUI_Bank:Hide()
        -- Auto-close bags if we auto-opened them
        if
            CUI_Bank._autoOpenedBags
            and CUI_Bags
            and CUI_Bags:IsVisible()
            and mod.BagAutoWindowOn("bagAutoCloseWindows", "bank")
        then
            CUI_Bags:Hide()
        end
        CUI_Bank._autoOpenedBags = false
    elseif evt == "BANK_TABS_CHANGED" or evt == "BANK_TAB_SETTINGS_UPDATED" then
        if CUI_Bank:IsVisible() then
            local prevCount = #_allTabs
            DiscoverBankTabs()
            ScheduleBankRefresh()
            -- Server may not have slot data ready yet for a newly purchased tab.
            -- Poll until tab count changes or we give up after 300 frames. Only a
            -- purchase changes the count, and one reused frame serves every poll.
            if evt == "BANK_TABS_CHANGED" and #_allTabs == prevCount then
                local pollFrame = CUI_Bank._tabPoller
                if not pollFrame then
                    -- Hidden while idle: a poll request arms its fields and shows it,
                    -- and it hides itself when the poll ends.
                    pollFrame = CreateFrame("Frame")
                    pollFrame:Hide()
                    pollFrame:SetScript("OnUpdate", function(self)
                        self.attempts = self.attempts + 1
                        if self.attempts % 6 ~= 0 then
                            return
                        end -- ~0.1s per check
                        if not CUI_Bank:IsVisible() or self.attempts > 300 then
                            self:Hide()
                            return
                        end
                        DiscoverBankTabs()
                        if #_allTabs ~= self.prevCount then
                            self:Hide()
                            CUI_Bank:RefreshBank()
                        end
                    end)
                    CUI_Bank._tabPoller = pollFrame
                end
                pollFrame.attempts = 0
                pollFrame.prevCount = prevCount
                pollFrame:Show()
            end
        end
    elseif
        evt == "BAG_UPDATE"
        or evt == "PLAYERBANKSLOTS_CHANGED"
        or evt == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED"
    then
        if CUI_Bank:IsVisible() then
            ScheduleBankRefresh()
        end
    elseif evt == "BAG_CONTAINER_UPDATE" then
        -- Forever: a bag went into or came out of a bank bag slot, which adds or
        -- removes that tab.
        if CUI_Bank:IsVisible() then
            local selTab = _selectedView > 0 and _allTabs[_selectedView]
            DiscoverBankTabs()
            if selTab then
                _selectedView = BankDefaultsToOne() and -1 or 0
                for i, tabBtn in ipairs(_allTabs) do
                    if tabBtn.bagID == selTab.bagID then
                        _selectedView = i
                        break
                    end
                end
            end
            ScheduleBankRefresh()
        end
    end
end)

-- Kill Blizzard bank frame: reparent to hidden frame only. Do NOT call BankFrame:Hide()
-- -- that fires BANKFRAME_CLOSED and kills the bank interaction. Reparenting is
-- invisible to the event system. Do NOT use SetScript on BankFrame -- that taints it
-- and breaks PurchaseBankTab() and other secure bank operations.
do
    local hiddenParent = CreateFrame("Frame")
    hiddenParent:Hide()
    if BankFrame then
        BankFrame:SetParent(hiddenParent)
    end
end

-- Close bank when pressing Escape
CUI_Bank:SetScript("OnHide", function()
    -- The Compact display's grow-only width (RefreshBank)
    CUI_Bank._compactCols, CUI_Bank._compactW = nil, nil
    if CUI_BankTabConfigFrame then
        CUI_BankTabConfigFrame:Hide()
    end
    if C_Bank then
        C_Bank.CloseBankFrame()
    end
    -- Clear warbank dim overlays on bags
    if _G.CUI_Bags and _G.CUI_Bags:IsVisible() and _G.CUI_Bags.RefreshInventory then
        _G.CUI_Bags:RefreshInventory()
    end
end)

-------------------------------------------------------------------------------
--  Loader (deferred init)
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if mod.SkinForeverBagWindow(CUI_Bank, bgAtlas, bgOverlay, true, true) then
        CUI_Bank._flatBorder:Hide()
        headerBar:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", 1, -1)
        headerBar:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", -1, -1)
        mod.LayoutForeverBagHeader(headerBar)
        HEADER_H = headerBar:GetHeight() + 1
        local inset = mod.ForeverBagSidebarInset(CUI_Bank)
        sideBar._leftInset = inset
        sideBar:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", inset, -headerBar:GetHeight())
        sideBar:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", inset, FOOTER_H)
        sideBar:SetWidth(GetBankSidebarContentWidth())
        sideChild:SetWidth(GetBankSidebarContentWidth())
        scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", GetBankSidebarWidth(), -HEADER_H)
        scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -7, FOOTER_H)
        track:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", -7, -HEADER_H)
        track:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -7, FOOTER_H)
        hdrBg:Hide()
        headerBar.separator:Hide()
        sidebarBg:SetColorTexture(0.10, 0.065, 0.035, 0.45)
        sideBar.separator:SetColorTexture(0.45, 0.33, 0.21, 0.85)

        mod.SkinForeverBagTitle(titleText, itemCount)
        mod.AddForeverBagPortrait(headerBar, "Interface\\Icons\\INV_Misc_Coin_01")
        mod.PositionForeverBagClose(closeBtn)

        sortButton:ClearAllPoints()
        sortButton:SetPoint("RIGHT", headerBar, "TOPRIGHT", -9, headerBar._foreverToolsY)
        searchBox:ClearAllPoints()
        searchBox:SetPoint("LEFT", headerBar, "TOPLEFT", 45, headerBar._foreverToolsY)
        searchBox:SetPoint("RIGHT", CUI_Bank._bagsBtn or sortButton, "LEFT", -6, 0)
        searchBox:SetFont(GetFont(), 12, CUI.GetFontOutlineFlag("bags"))
        CUI.PanelPP.HideBorder(searchBox)
        mod.SkinForeverBagSearch(searchBox, searchBg, searchPlaceholder, clearSearchBtn)
        local footerBar = CUI_Bank.Footer
        mod.SkinForeverBagFooter(footerBar, footerBar.bg, footerBar.separator)
        footerBar.playerGold:ClearAllPoints()
        footerBar.playerGold:SetPoint("LEFT", footerBar._coinBox, "LEFT", 5, 0)
        _bankGripCfg.inset(CUI_Bank._gripInset or 0)
    end
    -- WoW Forever with the Gamepad interface style at login: Blizzard's bank
    -- keeps the D-pad navigation, so it goes back under its own parent.
    if CUI.IS_FOREVER and BankFrame and mod.PadUIStandDown() then
        BankFrame:SetParent(UIParent)
    end
    -- Apply default view based on setting
    if BankDefaultsToOne() then
        _selectedView = -1
    end
    -- Register for Escape close
    if CUI and CUI.RegisterEscapeClose then
        CUI.RegisterEscapeClose(CUI_Bank)
    end
    -- Controller cursor: Cancel finds the bank's close button.
    if CUI.PadCP() then
        CUI_Bank.CloseButton = closeBtn
    end

    -- Auto-shift DressUpFrame to the right of the bank when both are open
    local dressUpFrame = _G.DressUpFrame
    if dressUpFrame then
        local _duIgnoreSP = false
        local function ShiftDressUp()
            if not CUI_Bank:IsVisible() or InCombatLockdown() then
                return
            end
            _duIgnoreSP = true
            dressUpFrame:ClearAllPoints()
            dressUpFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPRIGHT", 4, 0)
            _duIgnoreSP = false
        end
        dressUpFrame:HookScript("OnShow", ShiftDressUp)
        hooksecurefunc(dressUpFrame, "SetPoint", function()
            if _duIgnoreSP then
                return
            end
            ShiftDressUp()
        end)
        CUI_Bank:HookScript("OnShow", function()
            if dressUpFrame:IsVisible() then
                ShiftDressUp()
            end
        end)
    end
end)
