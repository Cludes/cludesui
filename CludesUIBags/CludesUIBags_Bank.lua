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
local function BP()
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
    return BP().bankColumns or 14
end
local function GetBankHeight()
    return BP().bankHeight or 500
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
    local collapsed = BP().bankSidebarCollapsed
    return collapsed and SIDEBAR_W_COLLAPSED or SIDEBAR_W
end

local function GetFont()
    return CUI.GetFontPath("bags")
end
local function SetBankFont(fontStr, dim)
    CludesUI.PrimeFontShadow(fontStr, true)
    fontStr:SetFont(GetFont(), dim, CUI.GetFontOutlineFlag("bags"))
end
local GetUpgradeTrack = CUI.GetUpgradeTrack
local ITEM_CLASS_WEAPON = Enum.ItemClass.Weapon
local ITEM_CLASS_ARMOR = Enum.ItemClass.Armor
local function IsGearItem(itemLink)
    if not itemLink then
        return false
    end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == ITEM_CLASS_WEAPON or classID == ITEM_CLASS_ARMOR
end
local function GetItemLevelAtLocation(loc, itemLink)
    if loc and loc:IsValid() and C_Item.DoesItemExist(loc) then
        local level = C_Item.GetCurrentItemLevel(loc)
        if level and level > 0 then
            return level
        end
    end
    return itemLink and C_Item.GetDetailedItemLevelInfo(itemLink) or nil
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

local function GetFallbackIcon(bagID)
    if _tabIconCache[bagID] then
        return _tabIconCache[bagID]
    end
    _usedFallbackIdx = _usedFallbackIdx + 1
    local glyph = FALLBACK_ICONS[((_usedFallbackIdx - 1) % #FALLBACK_ICONS) + 1]
    _tabIconCache[bagID] = glyph
    return glyph
end

mod.BankDefaultsToOne = BankDefaultsToOne -- the offline view orders its sidebar the same way

-- a tab's icon, or a fallback if it has none (saved tabs use it too)
function mod.BankTabIcon(bagID, glyph)
    if glyph and glyph ~= 134400 then
        return glyph
    end
    return bagID and GetFallbackIcon(bagID) or 134400
end

local CHARACTER_BANK_BAGS = {}
local WARBAND_BANK_BAGS = {}
if Enum and Enum.BagIndex then
    -- Character bank: CharacterBankTab_1 through _6 (WoW Forever has up to _9:
    -- the base bank plus its bank bag slots). Missing enum keys are skipped.
    for i = 1, 9 do
        local key = "CharacterBankTab_" .. i
        if Enum.BagIndex[key] then
            CHARACTER_BANK_BAGS[#CHARACTER_BANK_BAGS + 1] = Enum.BagIndex[key]
        end
    end
    -- Warband bank: AccountBankTab_1 through AccountBankTab_5
    for i = 1, 5 do
        local key = "AccountBankTab_" .. i
        if Enum.BagIndex[key] then
            WARBAND_BANK_BAGS[#WARBAND_BANK_BAGS + 1] = Enum.BagIndex[key]
        end
    end
end

local function GetCharacterBankTabs()
    local tabs = {}
    -- Use C_Bank.FetchPurchasedBankTabData for tab metadata (name, icon)
    local tabData
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
    end
    if tabData then
        for i, td in ipairs(tabData) do
            local bagID = CHARACTER_BANK_BAGS[i]
            if bagID then
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots > 0 then
                    local glyph = td.icon
                    if not glyph or glyph == 134400 then
                        glyph = GetFallbackIcon(bagID)
                    end
                    tabs[#tabs + 1] = {
                        bagID = bagID,
                        numSlots = numSlots,
                        name = td.name or CUI.Lf("Bank Tab %1$d", i),
                        icon = glyph,
                        depositFlags = td.depositFlags or 0,
                    }
                end
            end
        end
    else
        for i, bagID in ipairs(CHARACTER_BANK_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots > 0 then
                tabs[#tabs + 1] = {
                    bagID = bagID,
                    numSlots = numSlots,
                    name = CUI.Lf("Bank Tab %1$d", #tabs + 1),
                    icon = GetFallbackIcon(bagID),
                    depositFlags = 0,
                }
            end
        end
    end
    return tabs
end

local function GetWarbandBankTabs()
    local tabs = {}
    -- Check if warband bank is locked
    if C_Bank and C_Bank.FetchBankLockedReason and Enum.BankType then
        if C_Bank.FetchBankLockedReason(Enum.BankType.Account) ~= nil then
            return tabs
        end
    end
    local tabData
    if C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
        tabData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Account)
    end
    if tabData then
        for i, td in ipairs(tabData) do
            local bagID = WARBAND_BANK_BAGS[i]
            if bagID then
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots > 0 then
                    local name = td.name or CUI.Lf("Tab %1$d", i)
                    local glyph = td.icon
                    if not glyph or glyph == 134400 then
                        glyph = GetFallbackIcon(bagID)
                    end
                    tabs[#tabs + 1] = {
                        bagID = bagID,
                        numSlots = numSlots,
                        name = CUI.L("Warbank") .. " " .. name,
                        shortName = name,
                        icon = glyph,
                        depositFlags = td.depositFlags or 0,
                    }
                end
            end
        end
    else
        for i, bagID in ipairs(WARBAND_BANK_BAGS) do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots > 0 then
                tabs[#tabs + 1] = {
                    bagID = bagID,
                    numSlots = numSlots,
                    name = CUI.L("Warbank") .. " " .. CUI.Lf("Tab %1$d", #tabs + 1),
                    icon = GetFallbackIcon(bagID),
                    depositFlags = 0,
                }
            end
        end
    end
    return tabs
end

-------------------------------------------------------------------------------
--  Main Frame
-------------------------------------------------------------------------------
local CUI_Bank = CreateFrame("Frame", "CUI_BankFrame", UIParent)
CUI_Bank:SetToplevel(true)
do
    local strata = mod.BagFrameStrata()
    CUI_Bank:SetFrameStrata(strata)
    CUI_Bank:SetFrameLevel(strata == "HIGH" and 50 or 1)
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
local headerFrame = CreateFrame("Frame", nil, CUI_Bank)
headerFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", 0, 0)
headerFrame:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", 0, 0)
headerFrame:SetHeight(HEADER_H)
local hdrBg = headerFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
hdrBg:SetAllPoints()
hdrBg:SetColorTexture(0, 0, 0, 0.5)

local titleText = headerFrame:CreateFontString(nil, "OVERLAY")
SetBankFont(titleText, 13)
titleText:SetPoint("LEFT", headerFrame, "LEFT", 8, 0)
titleText:SetTextColor(1, 1, 1)
titleText:SetText(CludesUI.L("Bank"))
CUI_Bank._headerTitle = titleText -- the alt button sits next to this

local itemCount = headerFrame:CreateFontString(nil, "OVERLAY")
SetBankFont(itemCount, 11)
itemCount:SetPoint("LEFT", titleText, "RIGHT", 8, 0)
itemCount:SetTextColor(0.6, 0.6, 0.6)
CUI_Bank._headerItemCount = itemCount

-- Search box
local bankSearch = CreateFrame("EditBox", "CUI_BankSearchBox", headerFrame)
bankSearch:SetSize(160, 22)
bankSearch:SetPoint("RIGHT", headerFrame, "RIGHT", -35, 0)
bankSearch:SetFont(GetFont(), 12, "")
bankSearch:SetAutoFocus(false)
bankSearch:SetTextInsets(5, 26, 0, 0)
local searchBg = bankSearch:CreateTexture(nil, "BACKGROUND")
searchBg:SetAllPoints()
searchBg:SetColorTexture(0.02, 0.02, 0.02, 1)
if CUI and CUI.PanelPP then
    CUI.PanelPP.CreateBorder(bankSearch, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
end

local searchPlaceholder = bankSearch:CreateFontString(nil, "OVERLAY")
SetBankFont(searchPlaceholder, 11)
searchPlaceholder:SetPoint("LEFT", bankSearch, "LEFT", 5, 0)
searchPlaceholder:SetText(CludesUI.L("Search..."))
searchPlaceholder:SetTextColor(0.4, 0.4, 0.4)
CUI_Bank._searchBox = bankSearch

-- Search clear button
local searchClear = CreateFrame("Button", nil, bankSearch)
searchClear:SetSize(22, 22)
searchClear:SetPoint("RIGHT", bankSearch, "RIGHT", 0, 0)
searchClear.tex = searchClear:CreateFontString(nil, "OVERLAY")
SetBankFont(searchClear.tex, 14)
searchClear.tex:SetText("x")
searchClear.tex:SetPoint("CENTER", 0, 1)
searchClear.tex:SetTextColor(0.8, 0.8, 0.8)
searchClear:Hide()
searchClear:SetScript("OnClick", function()
    bankSearch:SetText("")
    bankSearch:ClearFocus()
    CUI_Bags.ClearSearch()
end)

bankSearch:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
end)
bankSearch:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    CUI_Bags.ClearSearch()
end)
-- Both windows repaint when the game reports the search (CUI_Bags.SetSearchText).
local bankSearchChanged = CUI_Bags.WatchSearchBox(bankSearch, CUI_Bags.SetSearchText)
bankSearch:SetScript("OnTextChanged", function(self, userInput)
    local textValue = self:GetText()
    searchPlaceholder:SetShown(textValue == "")
    searchClear:SetShown(textValue ~= "")
    bankSearchChanged(userInput)
end)

-- Sort button
local sortBtn = CreateFrame("Button", nil, headerFrame)
sortBtn:SetSize(24, 24)
sortBtn:SetPoint("RIGHT", bankSearch, "LEFT", -13, 0)
sortBtn.icon = sortBtn:CreateTexture(nil, "OVERLAY")
sortBtn.icon:SetAllPoints()
sortBtn.icon:SetTexture("Interface\\AddOns\\CludesUIBags\\Media\\clean-up.png")
sortBtn.icon:SetAlpha(0.9)

local bankSortLocked = false
local function LockBankSort()
    bankSortLocked = true
    sortBtn:EnableMouse(false)
    sortBtn.icon:SetAlpha(0.2)
end
local function UnlockBankSort()
    if not bankSortLocked then
        return
    end
    bankSortLocked = false
    sortBtn:EnableMouse(true)
    sortBtn.icon:SetAlpha(0.9)
end

sortBtn:SetScript("OnEnter", function(self)
    self.icon:SetAlpha(1)
    CUI.ShowWidgetTooltip(self, "Sort Items")
end)
sortBtn:SetScript("OnLeave", function(self)
    self.icon:SetAlpha(0.9)
    CUI.HideWidgetTooltip()
end)
sortBtn:SetScript("OnClick", function()
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
    if BP().bagSortToBottom and C_Container.SetSortBagsRightToLeft then
        C_Container.SetSortBagsRightToLeft(false)
    end
    local isWarband = (_selectedView == -2 or _selectedView == -3)
    if not isWarband and _selectedView > 0 and _allTabs[_selectedView] then
        isWarband = _allTabs[_selectedView].isWarband
    end
    if isWarband then
        C_Container.SortBank(Enum.BankType.Account)
    else
        C_Container.SortBank(Enum.BankType.Character)
    end
    C_Timer.After(3, UnlockBankSort)
end)

-- Close button (created after search/sort so it renders on top)
local close = CreateFrame("Button", nil, headerFrame)
close:SetSize(12, 12)
close:SetPoint("RIGHT", headerFrame, "RIGHT", -9, 0)
close.icon = close:CreateTexture(nil, "OVERLAY")
close.icon:SetAllPoints()
close.icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
close.icon:SetAlpha(0.7)
close:SetScript("OnEnter", function()
    close.icon:SetAlpha(0.9)
end)
close:SetScript("OnLeave", function()
    close.icon:SetAlpha(0.7)
end)
close:SetScript("OnClick", function()
    CUI_Bank:Hide()
end)

-- Header bottom-edge separator (1px physical pixel)
do
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local hdrSep = headerFrame:CreateTexture(nil, "ARTWORK")
    hdrSep:SetHeight(px)
    hdrSep:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    hdrSep:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", 0, 0)
    hdrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    headerFrame.separator = hdrSep
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

    local bagsWin = CreateFrame("Frame", nil, CUI_Bank)
    bankBagsWindow = bagsWin
    bagsWin:Hide()
    bagsWin:SetFrameLevel(CUI_Bank:GetFrameLevel() + 20)
    bagsWin:EnableMouse(true)
    bagsWin:SetClampedToScreen(true)
    local winBg = bagsWin:CreateTexture(nil, "BACKGROUND")
    winBg:SetAllPoints()
    winBg:SetColorTexture(0.02, 0.02, 0.02, 0.95)
    CUI.PanelPP.CreateBorder(bagsWin, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7)

    local bagsBtn = CreateFrame("Button", nil, headerFrame)
    CUI_Bank._bagsBtn = bagsBtn
    bagsBtn:SetSize(24, 24)
    bagsBtn:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
    bagsBtn.icon = bagsBtn:CreateTexture(nil, "ARTWORK")
    bagsBtn.icon:SetAllPoints()
    bagsBtn.icon:SetAtlas("bag-main")
    bagsBtn.icon:SetAlpha(0.9)
    bagsWin:SetPoint("BOTTOMRIGHT", bagsBtn, "TOPRIGHT", 0, 2)

    bagsBtn:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        if not bagsWin:IsShown() then
            CUI.ShowWidgetTooltip(self, "Show Bags")
        end
    end)
    bagsBtn:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.9)
        CUI.HideWidgetTooltip()
    end)
    bagsBtn:SetScript("OnClick", function()
        if bagsWin:IsShown() then
            bagsWin:Hide()
        else
            CUI.HideWidgetTooltip()
            bagsWin:Show()
        end
    end)

    local function PickupBag(self)
        if self.bought then
            C_Container.PickupContainerItem(BANK_BAG_SLOTS, self.bagSlot)
        end
    end

    local slots = {}
    local function GetOrCreateBagSlot(position)
        if slots[position] then
            return slots[position]
        end
        local btn = CreateFrame("Button", nil, bagsWin)
        mod.SizeSlot(btn)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        btn.Count = btn:CreateFontString(nil, "OVERLAY")
        CludesUI.ApplyIconTextFont(btn.Count, GetFont(), BP().bagCountFontSize or 11, "bags")
        btn.Count:SetPoint("BOTTOMRIGHT", -2, 2)
        btn.Count:SetTextColor(1, 1, 1)
        mod.CreateInsetBorder(btn, true)
        btn:SetScript("OnClick", PickupBag)
        btn:SetScript("OnDragStart", PickupBag)
        btn:SetScript("OnReceiveDrag", PickupBag)
        btn:SetScript("OnEnter", function(self)
            SetInsetBorderColor(self, 1, 1, 1, 1)
            if self.hasBag then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetBagItem(BANK_BAG_SLOTS, self.bagSlot)
                GameTooltip:Show()
            else
                CUI.ShowWidgetTooltip(self, self.bought and BANK_BAG or BANK_BAG_PURCHASE)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            SetInsetBorderColor(self, self._bdrR, self._bdrG, self._bdrB, 1)
            GameTooltip:Hide()
            CUI.HideWidgetTooltip()
        end)
        slots[position] = btn
        return btn
    end

    RefreshBankBags = function()
        if not bagsWin:IsShown() then
            return
        end
        local maxBags = C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character)
        local bought = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)
        local z = BP().bagItemIconZoom or 0.08
        local num = 0
        -- Slot 1 is the bank itself; bag slots start at 2.
        for bagSlot = 2, maxBags do
            num = num + 1
            local btn = GetOrCreateBagSlot(num)
            btn.bagSlot = bagSlot
            btn.bought = bought[bagSlot] ~= nil
            local details = btn.bought and C_Container.GetContainerItemInfo(BANK_BAG_SLOTS, bagSlot)
            btn.hasBag = details and true or false
            btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
            btn.icon:SetTexture(
                details and details.iconFileID or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
            )
            btn.icon:SetDesaturated(not btn.bought)
            btn.icon:SetAlpha(btn.bought and 1 or 0.35)
            if details then
                btn.Count:SetText(
                    C_Container.GetContainerNumFreeSlots(Enum.BagIndex.CharacterBankTab_1 + bagSlot - 1)
                )
                btn.Count:Show()
            else
                btn.Count:Hide()
            end
            -- quality is nilable (item data not cached yet).
            local q = details and details.quality
            if q and q > 0 then
                btn._bdrR, btn._bdrG, btn._bdrB = mod.QualityBorderColor(q)
            else
                btn._bdrR, btn._bdrG, btn._bdrB = 0.25, 0.25, 0.25
            end
            SetInsetBorderColor(btn, btn._bdrR, btn._bdrG, btn._bdrB, 1)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", bagsWin, "TOPLEFT", 10 + (num - 1) * (SLOT_SIZE + SPACING), -10)
            btn:Show()
        end
        for i = num + 1, #slots do
            slots[i]:Hide()
        end
        bagsWin:SetSize(math.max(num, 1) * (SLOT_SIZE + SPACING) + 16, SLOT_SIZE + 20)
    end
    bagsWin:SetScript("OnShow", function(self)
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
    local footer = CreateFrame("Frame", nil, CUI_Bank)
    footer:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    local ftrBg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    ftrBg:SetAllPoints()
    ftrBg:SetColorTexture(0, 0, 0, 0.35)

    -- Top-edge separator
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    footer.bg, footer.separator = ftrBg, ftrSep
    CUI_Bank.Footer = footer

    -- Shared formatting
    local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:0:0|t"
    local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:0:0|t"
    local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:0:0|t"
    -- gold, plus silver and copper if there's any (the warbank takes both)
    local function FormatGold(copper)
        if not copper or copper == 0 then
            return "0" .. GOLD_ICON
        end
        local gold = math.floor(copper / 10000)
        local silver = math.floor(copper / 100) % 100
        local cop = copper % 100
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
    local playerGold = footer:CreateFontString(nil, "OVERLAY")
    SetBankFont(playerGold, 11)
    playerGold:SetPoint("LEFT", footer, "LEFT", 10, 0)
    playerGold:SetTextColor(1, 1, 1)
    footer.playerGold = playerGold

    local playerHitbox = CreateFrame("Frame", nil, footer)
    playerHitbox:SetPoint("TOPLEFT", playerGold, "TOPLEFT", -4, 4)
    playerHitbox:SetPoint("BOTTOMRIGHT", playerGold, "BOTTOMRIGHT", 4, -4)
    playerHitbox:SetFrameLevel(footer:GetFrameLevel() + 5)
    playerHitbox:EnableMouse(true)
    playerHitbox:SetScript("OnEnter", function(self)
        CUI.ShowWidgetTooltip(self, "Player Gold")
    end)
    playerHitbox:SetScript("OnLeave", function()
        CUI.HideWidgetTooltip()
    end)

    local warbandGold = footer:CreateFontString(nil, "OVERLAY")
    SetBankFont(warbandGold, 11)
    warbandGold:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
    warbandGold:SetTextColor(1, 1, 1)
    -- The resize grip's inset moves it clear of the grip (_bankGripCfg)
    CUI_Bank._warbandGoldText = warbandGold

    local warbandHitbox = CreateFrame("Frame", nil, footer)
    warbandHitbox:SetPoint("TOPLEFT", warbandGold, "TOPLEFT", -4, 4)
    warbandHitbox:SetPoint("BOTTOMRIGHT", warbandGold, "BOTTOMRIGHT", 4, -4)
    warbandHitbox:SetFrameLevel(footer:GetFrameLevel() + 5)
    warbandHitbox:EnableMouse(true)
    warbandHitbox:SetScript("OnEnter", function(self)
        CUI.ShowWidgetTooltip(self, "Warband Gold")
    end)
    warbandHitbox:SetScript("OnLeave", function()
        CUI.HideWidgetTooltip()
    end)

    -- Withdraw / Deposit styled buttons (next to warband gold)
    local Pix = CUI and CUI.PP
    local ar, ag, ab = GetAccentRGB()

    local GOLD_R, GOLD_G, GOLD_B = 0.855, 0.722, 0.259 -- #dab842

    local function MakeStyledFooterBtn(label, tooltipText)
        local btn = CreateFrame("Button", nil, footer)
        btn:SetSize(70, 18)
        btn:EnableMouse(true)
        btn:SetFrameLevel(footer:GetFrameLevel() + 2)

        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(btn, GOLD_R, GOLD_G, GOLD_B, 0.8, 1, "OVERLAY", 7)
        end

        local labelFS = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(labelFS, 9)
        labelFS:SetPoint("CENTER", btn, "CENTER", 0, 0)
        labelFS:SetText(CludesUI.L(label))
        labelFS:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
        btn._label = labelFS

        btn:SetScript("OnEnter", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 1)
            if Pix and Pix.SetBorderColor then
                Pix.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 1)
            end
            CUI.ShowWidgetTooltip(self, CludesUI.L(tooltipText))
        end)
        btn:SetScript("OnLeave", function(self)
            self._label:SetTextColor(GOLD_R, GOLD_G, GOLD_B, 0.8)
            if Pix and Pix.SetBorderColor then
                Pix.SetBorderColor(self, GOLD_R, GOLD_G, GOLD_B, 0.8)
            end
            CUI.HideWidgetTooltip()
        end)
        return btn
    end

    local depositMoneyBtn = MakeStyledFooterBtn("Deposit", "Deposit to Warbank")
    depositMoneyBtn:SetPoint("RIGHT", warbandGold, "LEFT", -14, 0)
    local withdrawMoneyBtn = MakeStyledFooterBtn("Withdraw", "Withdraw from Warbank")
    withdrawMoneyBtn:SetPoint("RIGHT", depositMoneyBtn, "LEFT", -8, 0)

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
            onConfirm = function(copper)
                if copper and copper > 0 then
                    onAccept(copper)
                end
            end,
        })
    end

    withdrawMoneyBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanWithdrawMoney then
            return
        end
        if not C_Bank.CanWithdrawMoney(Enum.BankType.Account) then
            return
        end
        ShowMoneyPopup("Withdraw from Warbank", function(copper)
            C_Bank.WithdrawMoney(Enum.BankType.Account, copper)
        end)
    end)
    depositMoneyBtn:SetScript("OnClick", function()
        if not C_Bank or not C_Bank.CanDepositMoney then
            return
        end
        if not C_Bank.CanDepositMoney(Enum.BankType.Account) then
            return
        end
        ShowMoneyPopup("Deposit to Warbank", function(copper)
            C_Bank.DepositMoney(Enum.BankType.Account, copper)
        end)
    end)

    -- Deposit Warbound Items / Deposit Reagents button, left of Withdraw so a long
    -- warband total pushes it along instead of overlapping it.
    local depositItemsBtn = CreateFrame("Button", nil, footer)
    depositItemsBtn:SetHeight(18)
    depositItemsBtn:SetPoint("RIGHT", withdrawMoneyBtn, "LEFT", -8, 0)
    depositItemsBtn:EnableMouse(true)

    local depositItemsLabel = depositItemsBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(depositItemsLabel, 10)
    depositItemsLabel:SetPoint("CENTER", depositItemsBtn, "CENTER", 0, 0)
    depositItemsLabel:SetTextColor(ar, ag, ab, 1)
    depositItemsBtn._label = depositItemsLabel

    depositItemsBtn:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1, 1)
    end)
    depositItemsBtn:SetScript("OnLeave", function(self)
        local r, g, b = GetAccentRGB()
        self._label:SetTextColor(r, g, b, 1)
    end)
    depositItemsBtn:SetScript("OnClick", function(self)
        if not C_Bank or not C_Bank.AutoDepositItemsIntoBank then
            return
        end
        local bankType = self._bankType
        if bankType then
            C_Bank.AutoDepositItemsIntoBank(bankType)
        end
    end)

    function CUI_Bank:UpdateFooterGold()
        local GL = CUI.GetGoldLedger()
        playerGold:SetText(FormatGold(GL.Money() or 0))
        warbandGold:SetText(FormatGold(GL.WarbandMoney() or 0))
    end

    function CUI_Bank:UpdateDepositButton(isWarband)
        if isWarband then
            depositItemsLabel:SetText(CludesUI.L("Deposit Warbound Items"))
            depositItemsBtn._bankType = Enum.BankType.Account
        else
            depositItemsLabel:SetText(CludesUI.L("Deposit Reagents"))
            depositItemsBtn._bankType = Enum.BankType.Character
        end
        local r, g, b = GetAccentRGB()
        depositItemsLabel:SetTextColor(r, g, b, 1)
        depositItemsBtn:SetWidth(depositItemsLabel:GetStringWidth() + 16)
        depositItemsBtn:Show()
        withdrawMoneyBtn:Show()
        depositMoneyBtn:Show()
    end
end

-------------------------------------------------------------------------------
--  Drag to Move (not while the footer's lock icon is locked)
-------------------------------------------------------------------------------
CUI_Bank:SetScript("OnMouseDown", function(self, btnFrame)
    self:Raise()
    self:RepinIconLevels()
    if btnFrame == "LeftButton" and not BP().bankWindowLocked then
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
            BP().bankPosition = { point = anchorPoint, relativePoint = relPoint, x = posX, y = posY }
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
    local headerBTC = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    headerBTC:SetPoint("TOPLEFT", CUI_BankTabConfigFrame, "TOPLEFT", 0, 0)
    headerBTC:SetPoint("TOPRIGHT", CUI_BankTabConfigFrame, "TOPRIGHT", 0, 0)
    headerBTC:SetHeight(35)
    local hdrBgBTC = headerBTC:CreateTexture(nil, "BACKGROUND", nil, 1)
    hdrBgBTC:SetAllPoints()
    hdrBgBTC:SetColorTexture(0, 0, 0, 0.5)

    local titleBTC = headerBTC:CreateFontString(nil, "OVERLAY")
    SetBankFont(titleBTC, 13)
    titleBTC:SetPoint("LEFT", headerBTC, "LEFT", 8, 0)
    titleBTC:SetTextColor(1, 1, 1)
    titleBTC:SetText(CludesUI.L("Edit Tab Settings"))

    -- Footer
    local footerBTC = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    footerBTC:SetPoint("BOTTOMLEFT", CUI_BankTabConfigFrame, "BOTTOMLEFT", 0, 0)
    footerBTC:SetPoint("BOTTOMRIGHT", CUI_BankTabConfigFrame, "BOTTOMRIGHT", 0, 0)
    footerBTC:SetHeight(FOOTER_H)
    local ftrBgBTC = footerBTC:CreateTexture(nil, "BACKGROUND", nil, 1)
    ftrBgBTC:SetAllPoints()
    ftrBgBTC:SetColorTexture(0, 0, 0, 0.35)

    -- Top-edge separator
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local ftrSepBTC = footerBTC:CreateTexture(nil, "ARTWORK")
    ftrSepBTC:SetHeight(px)
    ftrSepBTC:SetPoint("TOPLEFT", footerBTC, "TOPLEFT", 0, 0)
    ftrSepBTC:SetPoint("TOPRIGHT", footerBTC, "TOPRIGHT", 0, 0)
    ftrSepBTC:SetColorTexture(0.15, 0.15, 0.15, 1)

    -------------------------------------------------------------------------------
    -- Content for Bank Tab Settings Frame
    -------------------------------------------------------------------------------
    local WIDGET_HEIGHT = 22
    local PADDING_X = 8
    local PADDING_Y = 8
    local ar, ag, ab = GetAccentRGB()

    local contentHeight = 0

    local bodyBTC = CreateFrame("Frame", nil, CUI_BankTabConfigFrame)
    bodyBTC:SetPoint("TOPLEFT", headerBTC, "BOTTOMLEFT", 0, 0)
    bodyBTC:SetPoint("BOTTOMRIGHT", footerBTC, "TOPRIGHT", 0, 0)
    bodyBTC:SetWidth(CUI_BankTabConfigFrame:GetWidth()) -- Height is automatically determined by content

    -- Bank Tab Name Label
    local bankTabNameLabel = bodyBTC:CreateFontString(nil, "OVERLAY")
    SetBankFont(bankTabNameLabel, 10)
    bankTabNameLabel:SetPoint("TOPLEFT", bodyBTC, "TOPLEFT", PADDING_X, -PADDING_Y)
    bankTabNameLabel:SetTextColor(1, 1, 1, 1)
    bankTabNameLabel:SetText(CHARACTER_BANK_TAB_NAME_PROMPT)
    contentHeight = contentHeight + bankTabNameLabel:GetStringHeight() + PADDING_Y

    -- Bank Tab Name EditBox
    local bankTabNameEditBox = CreateFrame("EditBox", "CUI_BankFrame_TabSettingsMenu_NameBox", bodyBTC)
    bankTabNameEditBox:SetSize(170, WIDGET_HEIGHT)
    bankTabNameEditBox:SetPoint("TOPLEFT", bankTabNameLabel, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    SetBankFont(bankTabNameEditBox, 10)
    bankTabNameEditBox:SetAutoFocus(false)
    bankTabNameEditBox:SetTextInsets(5, 5, 0, 0)
    local bankTabNameBg = bankTabNameEditBox:CreateTexture(nil, "BACKGROUND")
    bankTabNameBg:SetAllPoints()
    bankTabNameBg:SetColorTexture(0.02, 0.02, 0.02, 1)
    if CUI and CUI.PanelPP then
        CUI.PanelPP.CreateBorder(bankTabNameEditBox, 0.25, 0.25, 0.25, 1, 1, "OVERLAY", 7)
    end
    contentHeight = contentHeight + bankTabNameEditBox:GetHeight() + (PADDING_Y / 2)

    -- Tab Icon Preview Visual
    local iconBTCTexture = bodyBTC:CreateTexture(nil, "ARTWORK")
    iconBTCTexture:SetSize(32, 32)
    iconBTCTexture:SetPoint(
        "TOPRIGHT",
        bodyBTC,
        "TOPRIGHT",
        -PADDING_X,
        select(5, bankTabNameLabel:GetPoint(1)) + select(5, bankTabNameEditBox:GetPoint(1))
    ) -- Align with the edit box

    -- Assign To Tab Label
    local assignToTabLabel = bodyBTC:CreateFontString(nil, "OVERLAY")
    SetBankFont(assignToTabLabel, 10)
    assignToTabLabel:SetPoint("TOPLEFT", bankTabNameEditBox, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    assignToTabLabel:SetTextColor(1, 1, 1, 1)
    assignToTabLabel:SetText(BAG_FILTER_ASSIGN_TO)
    contentHeight = contentHeight + assignToTabLabel:GetStringHeight() + (PADDING_Y / 2)

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

    local assignToTabFrame = CreateFrame("Frame", nil, bodyBTC) -- Switched to standard Frame context
    assignToTabFrame:SetSize(bodyBTC:GetWidth(), WIDGET_HEIGHT * ASSIGN_TO_TAB_ROWS)
    assignToTabFrame:SetPoint("TOPLEFT", assignToTabLabel, "BOTTOMLEFT", 0, -PADDING_Y / 2)
    contentHeight = contentHeight + assignToTabFrame:GetHeight() + (PADDING_Y / 2)

    local function makeAssignToTabBtn(option)
        local btn = CreateFrame("Button", nil, assignToTabFrame)
        btn:SetSize(assignToTabFrame:GetWidth() / ASSIGN_TO_TAB_COLUMNS, WIDGET_HEIGHT)

        local xOffset = (option.column - 1) * (assignToTabFrame:GetWidth() / ASSIGN_TO_TAB_COLUMNS)
        local yOffset = -(option.row - 1) * WIDGET_HEIGHT
        btn:SetPoint("TOPLEFT", assignToTabFrame, "TOPLEFT", xOffset, yOffset)
        btn:SetFrameLevel(assignToTabFrame:GetFrameLevel() + 2)

        local boxFrame, _, _, cbApply = CUI.BuildCheckboxControl(btn, assignToTabFrame:GetFrameLevel() + 2)
        Pix.Point(boxFrame, "LEFT", btn, "LEFT", 0, 0)

        local label = CUI.MakeFont(btn, 14, nil, CUI.TEXT_WHITE.r, CUI.TEXT_WHITE.g, CUI.TEXT_WHITE.b)
        SetBankFont(label, 10)
        label:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
        label:SetText(option.text)

        local isHovering = false

        local getValue = function()
            if not CUI_BankTabConfigFrame.depositFlags then
                return false
            end
            return bit.band(CUI_BankTabConfigFrame.depositFlags, option.value) ~= 0
        end
        local setValue = function(val)
            CUI_BankTabConfigFrame.depositFlags = CUI_BankTabConfigFrame.depositFlags or 0
            if val then
                CUI_BankTabConfigFrame.depositFlags =
                    bit.bor(CUI_BankTabConfigFrame.depositFlags, option.value)
            else
                CUI_BankTabConfigFrame.depositFlags =
                    bit.band(CUI_BankTabConfigFrame.depositFlags, bit.bnot(option.value))
            end
        end

        local function ApplyVisual()
            local enabled = getValue()
            cbApply(enabled, isHovering)
            if enabled then
                label:SetTextColor(CUI.TEXT_WHITE.r, CUI.TEXT_WHITE.g, CUI.TEXT_WHITE.b, 1)
            else
                local a = isHovering and 1 or 0.8
                label:SetTextColor(CUI.TEXT_WHITE.r * a, CUI.TEXT_WHITE.g * a, CUI.TEXT_WHITE.b * a, a)
            end
        end
        ApplyVisual()

        btn:SetScript("OnClick", function()
            local val = not getValue()
            setValue(val)
            ApplyVisual()
        end)
        btn:SetScript("OnEnter", function()
            isHovering = true
            ApplyVisual()
        end)
        btn:SetScript("OnLeave", function()
            isHovering = false
            ApplyVisual()
        end)

        btn.Refresh = function()
            ApplyVisual()
        end

        return btn
    end

    local assignToTabCheckboxesFrames = {}
    for _, option in ipairs(assignToTabCheckboxesCfg) do
        table.insert(assignToTabCheckboxesFrames, makeAssignToTabBtn(option))
    end

    bodyBTC:SetHeight(contentHeight + (PADDING_Y / 2)) -- Adjusted height to accommodate three rows with padding

    -- Save Button
    local saveBTCBtn = CreateFrame("Button", nil, footerBTC)
    saveBTCBtn:SetSize(100, WIDGET_HEIGHT)
    saveBTCBtn:SetPoint("RIGHT", footerBTC, "RIGHT", -10, 0)
    saveBTCBtn:EnableMouse(true)

    local saveBtnLabel = saveBTCBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(saveBtnLabel, 10)
    saveBtnLabel:SetPoint("CENTER", saveBTCBtn, "CENTER", 0, 0)
    saveBtnLabel:SetTextColor(ar, ag, ab, 0.9)
    saveBTCBtn._label = saveBtnLabel

    saveBTCBtn:SetScript("OnEnter", function(self)
        local r, g, b = GetAccentRGB()
        self._label:SetTextColor(r, g, b, 1)
        self._border:SetColor(r, g, b, 1)
    end)
    saveBTCBtn:SetScript("OnLeave", function(self)
        local r, g, b = GetAccentRGB()
        self._label:SetTextColor(r, g, b, 0.9)
        self._border:SetColor(r, g, b, 0.9)
    end)
    saveBTCBtn._label:SetText(CludesUI.L("Save"))
    if CUI.MakeBorder then
        saveBTCBtn._border = CUI.MakeBorder(saveBTCBtn, ar, ag, ab, 0.9, CUI.PP)
    end

    saveBTCBtn:SetScript("OnClick", function()
        local hostFrame = CUI_BankTabConfigFrame
        if hostFrame.bankType and hostFrame.tabId then
            local newName = bankTabNameEditBox:GetText()
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
    local cancelBTCBtn = CreateFrame("Button", nil, footerBTC)
    cancelBTCBtn:SetSize(100, WIDGET_HEIGHT)
    cancelBTCBtn:SetPoint("LEFT", footerBTC, "LEFT", 10, 0)
    cancelBTCBtn:EnableMouse(true)

    local cancelBtnLabel = cancelBTCBtn:CreateFontString(nil, "OVERLAY")
    SetBankFont(cancelBtnLabel, 10)
    cancelBtnLabel:SetPoint("CENTER", cancelBTCBtn, "CENTER", 0, 0)
    cancelBtnLabel:SetTextColor(1, 1, 1, 0.7)
    cancelBTCBtn._label = cancelBtnLabel

    cancelBTCBtn:SetScript("OnEnter", function(self)
        self._label:SetTextColor(1, 1, 1, 0.9)
        self._border:SetColor(1, 1, 1, 0.6)
    end)
    cancelBTCBtn:SetScript("OnLeave", function(self)
        self._label:SetTextColor(1, 1, 1, 0.7)
        self._border:SetColor(1, 1, 1, 0.5)
    end)
    cancelBTCBtn._label:SetText(CludesUI.L("Cancel"))
    cancelBTCBtn:SetScript("OnClick", function()
        CUI_BankTabConfigFrame:Hide()
    end)
    if CUI.MakeBorder then
        cancelBTCBtn._border = CUI.MakeBorder(cancelBTCBtn, 1, 1, 1, 0.5, CUI.PP)
    end
    -- Controller cursor: Cancel finds this dialog's Cancel button.
    if CUI.PadCP() then
        CUI_BankTabConfigFrame.CloseButton = cancelBTCBtn
    end

    function CUI_BankTabConfigFrame:OpenBankTabSettings(tabData, tabId)
        self:Hide()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", CUI_Bank, "TOPRIGHT", PADDING_X, 0)

        -- Save datas for use in Save button logic
        self.bankType = tabData.isWarband and Enum.BankType.Account or Enum.BankType.Character
        self.tabId = tabId
        self.icon = tabData.icon
        self.depositFlags = tabData.depositFlags or 0

        -- Setup widgets
        local displayName = tabData.name
        if self.bankType == Enum.BankType.Account then
            -- Remove "Warbank " prefix as this is a prefix added by CUI and not the real tab name. This is necessary to edit the tab
            local prefixText = CUI.L("Warbank") .. " "
            local prefix_len = #prefixText
            if strsub(tabData.name, 1, prefix_len) == prefixText then
                displayName = strsub(tabData.name, prefix_len + 1)
            end
        end
        self.fallbackName = displayName
        bankTabNameEditBox:SetText(displayName or "")
        iconBTCTexture:SetTexture(tabData.icon)
        if assignToTabCheckboxesFrames then
            for _, btn in ipairs(assignToTabCheckboxesFrames) do
                if btn.Refresh then
                    btn:Refresh()
                end
            end
        end

        self:Show()
    end

    CUI_BankTabConfigFrame:SetHeight(headerBTC:GetHeight() + bodyBTC:GetHeight() + footerBTC:GetHeight())
end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local sidebar = CreateFrame("Frame", nil, CUI_Bank)
sidebar._leftInset = 0
local function GetBankSidebarContentWidth()
    return GetBankSidebarWidth() - sidebar._leftInset
end
sidebar:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
sidebar:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", 0, FOOTER_H)
sidebar:SetWidth(GetBankSidebarContentWidth())
local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
sidebarBg:SetAllPoints()
sidebarBg:SetColorTexture(0, 0, 0, 0.25)

-- Right-edge separator
do
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local sidebarSep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetWidth(px)
    sidebarSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    sidebar.separator = sidebarSep
end

-- Secure purchase buttons: inherit BankPanelPurchaseButtonScriptTemplate so
-- PurchaseBankTab() runs in Blizzard's secure context, not ours.
local _purchaseBtnChar, _purchaseBtnWarband
do
    local function MakeSecurePurchaseBtn(bankType)
        local b = CreateFrame("Button", nil, sidebar, "BankPanelPurchaseButtonScriptTemplate")
        b:SetAttribute("overrideBankType", bankType)
        b:SetFrameStrata(sidebar:GetFrameStrata())
        b:SetFrameLevel(sidebar:GetFrameLevel() + 20)
        b:EnableMouse(true)
        b:SetAlpha(0)
        b:Hide()
        -- Hover: brighten the visual entry underneath
        b:SetScript("OnEnter", function(self)
            if self._visualBtn then
                self._visualBtn._bg:SetColorTexture(1, 1, 1, 0.06)
            end
        end)
        b:SetScript("OnLeave", function(self)
            if self._visualBtn then
                self._visualBtn._bg:SetColorTexture(1, 1, 1, 0)
            end
        end)
        return b
    end
    _purchaseBtnChar = MakeSecurePurchaseBtn(Enum.BankType.Character)
    _purchaseBtnWarband = MakeSecurePurchaseBtn(Enum.BankType.Account)
end

function CUI_Bank:ApplyWindowLayering()
    local strata = mod.BagFrameStrata()
    self:SetFrameStrata(strata)
    -- High starts above that layer's other windows (see CUI_Bags:ApplyWindowLayering)
    self:SetFrameLevel(strata == "HIGH" and 50 or 1)
    if bankBagsWindow then
        bankBagsWindow:SetFrameLevel(self:GetFrameLevel() + 20)
    end
    _purchaseBtnChar:SetFrameStrata(strata)
    _purchaseBtnWarband:SetFrameStrata(strata)
    _purchaseBtnChar:SetFrameLevel(sidebar:GetFrameLevel() + 20)
    _purchaseBtnWarband:SetFrameLevel(sidebar:GetFrameLevel() + 20)
    self:RepinIconLevels()
end

-- As CUI_Bags:RepinIconLevels, for the bank's own buttons
function CUI_Bank:RepinIconLevels()
    mod.PinItemPool(self._bankSlots, self, "_slotPinLevel")
    mod.ResyncListRowLevels()
end

-- Sidebar header: "Tabs" label + collapse arrow
local sidebarHdr, collapseBtn, UpdateBankCollapseArrow =
    mod.CreateSidebarHeader(sidebar, CludesUI.L("Tabs"), "bankSidebarCollapsed")

collapseBtn:SetScript("OnClick", function()
    -- Determine which edge to preserve based on screen position
    local center = CUI_Bank:GetCenter()
    local screenW = UIParent:GetWidth()
    local onRightSide = center and screenW and (center > screenW / 2)
    local oldWidth = onRightSide and CUI_Bank:GetWidth() or nil

    BP().bankSidebarCollapsed = not BP().bankSidebarCollapsed
    UpdateBankCollapseArrow()
    sidebar:SetWidth(GetBankSidebarContentWidth())
    CUI_Bank:RefreshBank()

    -- Shift frame by width difference to preserve right edge
    if onRightSide and oldWidth then
        local newWidth = CUI_Bank:GetWidth()
        local shift = oldWidth - newWidth
        if math.abs(shift) > 0.5 then
            local anchorPoint, rel, relPoint, posX, posY = CUI_Bank:GetPoint()
            CUI_Bank:ClearAllPoints()
            CUI_Bank:SetPoint(anchorPoint, rel, relPoint, posX + shift, posY)
            BP().bankPosition = { point = anchorPoint, relativePoint = relPoint, x = posX + shift, y = posY }
        end
    end
end)

-- Sidebar scroll frame (below header, fills rest of sidebar)
local sidebarSF = CreateFrame("ScrollFrame", nil, sidebar)
CUI_Bank._sidebarSF = sidebarSF -- an alt's tabs get drawn over this
sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
sidebarSF:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
sidebarSF:EnableMouseWheel(true)
local sidebarChild = CreateFrame("Frame", nil, sidebarSF)
sidebarChild:SetSize(GetBankSidebarContentWidth(), 1)
sidebarSF:SetScrollChild(sidebarChild)

local SIDEBAR_SCROLL_STEP = 28
sidebarSF:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = sidebarChild:GetHeight() - self:GetHeight()
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
track:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", -1, -1)
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
    local prompt

    local function BaseTabFree()
        if _warbandOnly or not C_Bank.CanPurchaseBankTab(Enum.BankType.Character) then
            return false
        end
        local payload = C_Bank.FetchNextPurchasableBankTabData(Enum.BankType.Character)
        return payload ~= nil and payload.tabCost == 0
    end

    local function BuildPrompt()
        prompt = CreateFrame("Frame", nil, CUI_Bank)
        prompt:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        prompt:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
        prompt:SetFrameLevel(scrollFrame:GetFrameLevel() + 10)
        local msg = prompt:CreateFontString(nil, "OVERLAY")
        msg:SetFont(GetFont(), 13, "")
        msg:SetTextColor(1, 1, 1, 0.75)
        msg:SetWidth(300)
        msg:SetJustifyH("CENTER")
        msg:SetPoint("BOTTOM", prompt, "CENTER", 0, 14)
        msg:SetText(
            CludesUI.L(
                "Your base bank slots come with a free bank tab. Open it once to start using your bank."
            )
        )
        local g = CUI.CLUDES_GREEN
        local visual = CUI.MakeActionButton(
            prompt,
            GetFont(),
            CludesUI.L("Open Bank Slots"),
            g.r,
            g.g,
            g.b,
            { w = 200, square = true }
        )
        visual:SetPoint("TOP", prompt, "CENTER", 0, -6)
        visual:EnableMouse(false)
        -- The click goes to Blizzard's purchase button laid over the visual one.
        local buy = CreateFrame("Button", nil, prompt, "BankPanelPurchaseButtonScriptTemplate")
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
            if not prompt then
                BuildPrompt()
            end
            prompt:Show()
        elseif prompt then
            prompt:Hide()
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
        for _, tabButton in ipairs(_allTabs) do
            if tabButton.isWarband then
                local numSlots = C_Container.GetContainerNumSlots(tabButton.bagID)
                for slotIndex = 1, numSlots do
                    if not C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex) then
                        return tabButton.bagID
                    end
                end
            end
        end
        return nil
    end
    if _selectedView <= 0 then
        return nil
    end
    local tabButton = _allTabs[_selectedView]
    return tabButton and tabButton.bagID or nil
end

--- Bags an Auto Split from srcBag may fill: the source tab first, then the
--- other tabs of the same bank type. Character and warband slots never mix.
function CUI_Bank:GetSplitTargetBags(srcBag)
    local targets = { srcBag }
    local isWarband = false
    for _, tabButton in ipairs(_allTabs) do
        if tabButton.bagID == srcBag then
            isWarband = tabButton.isWarband
        end
    end
    for _, tabButton in ipairs(_allTabs) do
        if tabButton.bagID ~= srcBag and tabButton.isWarband == isWarband then
            targets[#targets + 1] = tabButton.bagID
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
    local bankType = _G.Addon_GetBankType()
    if bankType ~= _lastTSMBankType then
        _lastTSMBankType = bankType
        -- Dynamic lookup so the call goes through TSM's hooked wrapper.
        _G.Addon_SetBankType(bankType)
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

local function IsSlotAllocated(bagID, slotIndex)
    return _allocatedSlots[bagID * 1000 + slotIndex]
end

local function AllocateSlot(bagID, slotIndex)
    _allocatedSlots[bagID * 1000 + slotIndex] = true
end

--- Find target in a specific bank bag, skipping allocated slots.
--- Tries partial stacks first, then empty slots.
local function FindTargetSlot(targetBag, srcItemID)
    local numSlots = C_Container.GetContainerNumSlots(targetBag)
    if numSlots == 0 then
        return nil
    end
    local maxStack = C_Item.GetItemMaxStackSizeByID(srcItemID) or 1
    -- Partial stack first
    if maxStack > 1 then
        for slotIndex = 1, numSlots do
            if not IsSlotAllocated(targetBag, slotIndex) then
                local details = C_Container.GetContainerItemInfo(targetBag, slotIndex)
                if details and details.itemID == srcItemID and details.stackCount < maxStack then
                    return slotIndex
                end
            end
        end
    end
    -- Empty slot
    for slotIndex = 1, numSlots do
        if not IsSlotAllocated(targetBag, slotIndex) then
            if not C_Container.GetContainerItemInfo(targetBag, slotIndex) then
                return slotIndex
            end
        end
    end
    return nil
end

local function ProcessTransfer(srcBag, srcSlot)
    local loc = ItemLocation:CreateFromBagAndSlot(srcBag, srcSlot)
    if not C_Item.DoesItemExist(loc) or C_Item.IsLocked(loc) then
        return false -- still locked, needs re-queue
    end
    local bank = _G.CUI_BankFrame
    if not bank or not bank:IsVisible() then
        return true
    end -- bank closed, discard
    local details = C_Container.GetContainerItemInfo(srcBag, srcSlot)
    if not details or not details.itemID then
        return true
    end

    local targetBag, targetSlot
    -- Aggregate warband views: search ALL warband tabs for stacking, then empty
    if _selectedView == -2 or _selectedView == -3 then
        local maxStack = C_Item.GetItemMaxStackSizeByID(details.itemID) or 1
        -- Pass 1: partial stack in any warband tab
        if maxStack > 1 then
            for _, tabButton in ipairs(_allTabs) do
                if tabButton.isWarband then
                    local numSlots = C_Container.GetContainerNumSlots(tabButton.bagID)
                    for slotIndex = 1, numSlots do
                        if not IsSlotAllocated(tabButton.bagID, slotIndex) then
                            local si = C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex)
                            if si and si.itemID == details.itemID and si.stackCount < maxStack then
                                targetBag, targetSlot = tabButton.bagID, slotIndex
                                break
                            end
                        end
                    end
                    if targetSlot then
                        break
                    end
                end
            end
        end
        -- Pass 2: first empty slot in any warband tab
        if not targetSlot then
            for _, tabButton in ipairs(_allTabs) do
                if tabButton.isWarband then
                    local numSlots = C_Container.GetContainerNumSlots(tabButton.bagID)
                    for slotIndex = 1, numSlots do
                        if not IsSlotAllocated(tabButton.bagID, slotIndex) then
                            if not C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex) then
                                targetBag, targetSlot = tabButton.bagID, slotIndex
                                break
                            end
                        end
                    end
                    if targetSlot then
                        break
                    end
                end
            end
        end
    else
        targetBag = bank:GetSelectedTabBagID()
        if not targetBag then
            return true
        end
        targetSlot = FindTargetSlot(targetBag, details.itemID)
    end

    if not targetBag or not targetSlot then
        return true
    end -- no space, discard
    AllocateSlot(targetBag, targetSlot)
    C_Container.PickupContainerItem(srcBag, srcSlot)
    C_Container.PickupContainerItem(targetBag, targetSlot)
    return true
end

local function DrainQueue()
    -- Clear allocations for slots that now have items (transfer completed)
    for key in pairs(_allocatedSlots) do
        local bagID = math.floor(key / 1000)
        local slotIndex = key % 1000
        if C_Container.GetContainerItemInfo(bagID, slotIndex) then
            _allocatedSlots[key] = nil
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
function CUI_Bank:QueueTransfer(srcBag, srcSlot)
    EnsureTransferEventFrame()
    _transferEventFrame:RegisterEvent("BAG_UPDATE")
    if not ProcessTransfer(srcBag, srcSlot) then
        _transferQueue[#_transferQueue + 1] = { srcBag, srcSlot }
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
    local btn = CreateFrame("ItemButton", nil, slotParent, "ContainerFrameItemButtonTemplate")
    mod.PinItemButton(btn, CUI_Bank)
    btn:SetAllPoints(slotParent)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, CUI_Bank:GetSplitTargetBags(self:GetParent():GetID()), CUI_Bank)
    end)

    -- OnReceiveDrag: handles native Blizzard drags (shift-click pickup etc.)
    btn:SetScript("OnReceiveDrag", function(self)
        local bagID = self:GetParent():GetID()
        local slotID = self:GetID()
        C_Container.PickupContainerItem(bagID, slotID)
    end)

    mod.SkinItemButton(btn, { flatHighlight = true })

    -- Empty bg
    btn._emptyBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn._emptyBg:SetAllPoints()
    mod.SetSlotBackgroundTexture(btn._emptyBg, true)

    _bankSlots[position] = btn
    return btn
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
        _bankMode = mod.BankDisplayMode(BP())
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
    local btn = mod.CreateListRow(CUI_Bank)
    btn:HookScript("PostClick", function(self)
        CUI_Bags.ShowStackSplitter(self, CUI_Bank:GetSplitTargetBags(self:GetParent():GetID()), CUI_Bank)
    end)
    btn:SetScript("OnReceiveDrag", function(self)
        C_Container.PickupContainerItem(self:GetParent():GetID(), self:GetID())
    end)
    _bankRows[position] = btn
    return btn
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
        for i, d in ipairs(run) do
            result[#result + 1] = { isRow = true, data = d, stripe = i % 2 == 0 }
        end
        wipe(run)
    end
    for _, e in ipairs(layout) do
        local details = e._cachedInfo
        if e.isHeader then
            Flush()
            result[#result + 1] = e
        elseif details and details.hyperlink then
            local link = details.hyperlink
            local d = { bag = e.bagID, slot = e.slot, info = details, itemLink = link }
            if forever then
                d._isQuest, d._isQuestStarter = mod.GetSlotQuestFlags(e.bagID, e.slot)
            end
            d._isGear = IsGearItem(link)
            if d._isGear then
                d._giIlvl = GetItemLevelAtLocation(ItemLocation:CreateFromBagAndSlot(e.bagID, e.slot), link)
                -- Track column, same rule as the bags scan
                if wantTrack then
                    local rankText, trackColor = GetUpgradeTrack(link)
                    if rankText ~= "" then
                        d._giTrackRank, d._giTrackColor = rankText, trackColor
                    else
                        d._giTrackColor = CUI.GetCraftedTrackColor(link)
                    end
                end
            end
            local cdS, cdD, cdE = C_Container.GetContainerItemCooldown(e.bagID, e.slot)
            if cdE and cdE ~= 0 and cdS > 0 and cdD > 0 then
                d._cdStart, d._cdDuration = cdS, cdD
            end
            mod.StampListItem(d)
            run[#run + 1] = d
        end
    end
    Flush()

    local placed, posY = {}, -6
    for i, e in ipairs(result) do
        if e.isRow then
            e.x, e.y = listX, posY
            posY = posY - ROW_H
            placed[#placed + 1] = e
        else
            local depth = e.depth or 0
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
                e.x, e.y = e.x - startX + listX, posY
                posY = posY - (depth == 0 and 22 or 18)
                placed[#placed + 1] = e
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
    local dim, labelW, labelText, labelEntry = {}, {}, {}, {}
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
        local num = mod.CompactSegmentLayout(layout, dim, labelText, labelEntry)
        local bandH = mod.CompactBandHeight(LABEL_SIZE)
        local k = 0
        for g = 1, num do
            local textValue = labelText[g]
            if textValue then
                k = k + 1
                labelW[g] =
                    mod.CompactMeasureLabel(mod.CompactLabel(pool, k, CUI_Bank), textValue, LABEL_SIZE)
                local le = labelEntries[k]
                if not le then
                    le = {
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
                    labelEntries[k] = le
                end
                labelEntry[g] = le
            else
                labelW[g] = 0
            end
        end
        local _, _, bottomY = mod.CompactPack(dim, labelW, num, columns, bandH, -6, result)
        local cellX, cellY = result.cellX, result.cellY
        local li, ci = 0, 0
        for g = 1, num do
            local le = labelEntry[g]
            if le then
                li = li + 1
                layout[li] = le
                le.label = labelText[g]
                le.textW = labelW[g]
                le.x = startX + result.groupX[g]
                le.y = result.groupY[g]
                le.w = result.labelRoom[g]
                le.h = bandH
                le.bw = result.groupW[g] -- the divider runs to the block's right edge
            end
            for _ = 1, dim[g] do
                li, ci = li + 1, ci + 1
                local e = layout[li]
                e.x = startX + cellX[ci]
                e.y = cellY[ci]
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

local function GetItemExpansionIDFromLink(itemLink)
    if not itemLink then
        return nil
    end
    local itemId = tonumber(itemLink:match("item:(%d+)")) or tonumber(itemLink:match("keystone:(%d+)"))
    if itemId and EXPANSION_ID_OVERRIDES[itemId] then
        return EXPANSION_ID_OVERRIDES[itemId]
    end
    if C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, _, expID = C_Item.GetItemInfo(itemLink)
        return expID
    end
    return select(15, GetItemInfo(itemLink))
end

-- sortKey: higher = newer expansion, shown first. Unknown / uncached last.
local EXP_KEY_UNKNOWN = -999
local EXP_KEY_EMPTY = -1000

local function GetExpansionBucketKeyAndLabel(itemLink)
    local expID = GetItemExpansionIDFromLink(itemLink)
    if expID == nil then
        return EXP_KEY_UNKNOWN, (UNKNOWN or CludesUI.L("Unknown"))
    end
    local ident = tonumber(expID)
    if ident == nil then
        return EXP_KEY_UNKNOWN, (UNKNOWN or CludesUI.L("Unknown"))
    end
    -- Classic-era sentinel from some clients / items
    if ident == 254 or ident == 255 then
        local name = _G["EXPANSION_NAME0"] or CludesUI.L("Classic")
        return 0, name
    end
    local name = _G["EXPANSION_NAME" .. ident]
    if name and name ~= "" then
        return ident, name
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
local function GetSubTypeBucket(link)
    local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(link)
    if classID == nil then
        return "__other__", CludesUI.L("Other"), true
    end
    local name
    if C_Item and C_Item.GetItemSubClassInfo then
        name = C_Item.GetItemSubClassInfo(classID, subclassID or 0)
    end
    if (not name or name == "") and _G.GetItemSubClassInfo then
        name = _G.GetItemSubClassInfo(classID, subclassID or 0)
    end
    if not name or name == "" then
        name = select(7, GetItemInfo(link))
    end
    if not name or name == "" then
        return "__other__", CludesUI.L("Other"), true
    end
    return name, name, false
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

local function GetSlotBucket(link)
    local _, _, _, equipSlot, _, classID, subclassID = GetItemInfoInstant(link)
    if classID == Enum.ItemClass.Armor and ARM_COSMETIC and subclassID == ARM_COSMETIC then
        return 130, CludesUI.L("Cosmetic"), false
    end
    equipSlot = equipSlot or ""
    if
        equipSlot == "INVTYPE_WEAPONOFFHAND"
        or equipSlot == "INVTYPE_HOLDABLE"
        or equipSlot == "INVTYPE_SHIELD"
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
        if equipSlot == "INVTYPE_2HWEAPON" then
            return 160, CludesUI.L("2H"), false
        end
        if equipSlot == "INVTYPE_RANGED" or equipSlot == "INVTYPE_RANGEDRIGHT" then
            return 190, _G["INVTYPE_RANGED"] or CludesUI.L("Ranged"), false
        end
        if equipSlot == "INVTYPE_WEAPON" or equipSlot == "INVTYPE_WEAPONMAINHAND" then
            return 170, CludesUI.L("1H"), false
        end
    end
    local record = ARMORY_SLOT_KEYS[equipSlot]
    if record then
        return record[1], _G[record[2]] or equipSlot, false
    end
    return 999, CludesUI.L("Other"), true
end

-- slotList entries are { bagID, slot, _cachedInfo }. mode is "expansion",
-- "type" or "slot". Empty slots have no _cachedInfo and always collect into a
-- single trailing bucket rather than landing under Unknown / Other.
local function BuildBankBuckets(slotList, modeName)
    local byKey, entries = {}, {}
    for _, s in ipairs(slotList) do
        local link = s._cachedInfo and s._cachedInfo.hyperlink
        local k, label, isOther
        if not link then
            k, label, isOther = EXP_KEY_EMPTY, CludesUI.L("Empty Slots"), false
        elseif modeName == "type" then
            k, label, isOther = GetSubTypeBucket(link)
        elseif modeName == "slot" then
            k, label, isOther = GetSlotBucket(link)
        else
            k, label = GetExpansionBucketKeyAndLabel(link)
            isOther = (k == EXP_KEY_UNKNOWN)
        end
        local b = byKey[k]
        if not b then
            b = { key = k, label = label, isOther = isOther, isEmpty = (link == nil), slots = {} }
            byKey[k] = b
            entries[#entries + 1] = b
        end
        b.slots[#b.slots + 1] = s
    end
    -- Empty slots last, then unknown/other, then per-mode order. Keys can be
    -- numbers or strings depending on mode, so never compare across buckets
    -- until those two flags have been settled.
    table.sort(entries, function(a, b)
        if a.isEmpty ~= b.isEmpty then
            return b.isEmpty
        end
        if a.isOther ~= b.isOther then
            return b.isOther
        end
        if a.isEmpty or a.isOther then
            return a.label < b.label
        end
        if modeName == "type" then
            return a.label < b.label
        end
        if modeName == "slot" then
            return a.key < b.key
        end
        return a.key > b.key -- expansion: newest first
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
local function BuildCategoryBuckets(slotList)
    local CM = _G.CUI_CategoryManager
    if not CM or not CM.ClassifyAll or not CM.GetCategories then
        return nil
    end
    local itemList = {}
    for _, sl in ipairs(slotList) do
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
    local cats = CM:GetCategories()
    local byCat = {}
    for _, d in ipairs(itemList) do
        local ci = d.categoryIndex
        if ci then
            local t = byCat[ci]
            if not t then
                t = {}
                byCat[ci] = t
            end
            t[#t + 1] = d._slotRef
        end
    end
    local result = {}
    for ci, category in ipairs(cats) do
        local entries = byCat[ci]
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
local function ClassifyOnce(slotList)
    local cbs = BuildCategoryBuckets(slotList)
    if not cbs then
        return nil
    end
    for ci, cb in ipairs(cbs) do
        for _, sl in ipairs(cb.slots) do
            sl._catBucket = ci
        end
    end
    return cbs
end

-- The categories present in one subset of an already-classified list, kept in the
-- order ClassifyOnce produced.
local function RegroupByCategory(cbs, slotList)
    local byIdx = {}
    for _, sl in ipairs(slotList) do
        local ci = sl._catBucket
        if ci then
            local t = byIdx[ci]
            if not t then
                t = {}
                byIdx[ci] = t
            end
            t[#t + 1] = sl
        end
    end
    local result = {}
    for ci, cb in ipairs(cbs) do
        local entries = byIdx[ci]
        if entries and #entries > 0 then
            result[#result + 1] = { cat = cb.cat, label = cb.label, slots = entries }
        end
    end
    return result
end

-- One classification pass per refresh, shared by the sidebar (entry counts) and
-- the grid (filtered slot lists) so the two can never disagree. Returns nil if
-- the CategoryManager is unavailable, which makes every caller fall back.
local function BuildBankCategoryIndex(tabs, passes)
    local slots = {}
    for _, tabButton in ipairs(tabs) do
        for slotIndex = 1, tabButton.numSlots do
            local details = C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex)
            if details and details.hyperlink and (not passes or passes(tabButton.bagID, slotIndex)) then
                slots[#slots + 1] = { bagID = tabButton.bagID, slot = slotIndex, _cachedInfo = details }
            end
        end
    end
    local cbs = ClassifyOnce(slots)
    if not cbs then
        return nil
    end
    local position = { list = cbs, byKey = {}, detailByKey = {} }
    for _, cb in ipairs(cbs) do
        local key = cb.cat._defaultName
        if key then
            position.byKey[key] = cb
            local modeName = DetailModeForCategory(cb.cat)
            if modeName then
                local bs = BuildBankBuckets(cb.slots, modeName)
                -- A single bucket is the whole category; no point offering it.
                if #bs > 1 then
                    position.detailByKey[key] = bs
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
        for _, cb in ipairs(_catIndex.list) do
            if cb.cat.groupName == _catSel.group then
                for _, sl in ipairs(cb.slots) do
                    result[#result + 1] = sl
                end
            end
        end
        return result
    end
    local cb = _catIndex.byKey[_catSel.key]
    if not cb then
        return {}
    end
    if _catSel.detail then
        local bs = _catIndex.detailByKey[_catSel.key]
        if bs then
            for _, b in ipairs(bs) do
                if b.label == _catSel.detail then
                    return b.slots
                end
            end
        end
        return {}
    end
    return cb.slots
end

-------------------------------------------------------------------------------
--  Category Headers
-------------------------------------------------------------------------------
local _bankHeaders = {}
local function GetOrCreateBankHeader(position)
    if _bankHeaders[position] then
        return _bankHeaders[position]
    end
    local f = CreateFrame("Frame", nil, CUI_Bank)
    f:SetHeight(20)
    f._label = f:CreateFontString(nil, "OVERLAY")
    SetBankFont(f._label, 11)
    f._label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f._label:SetTextColor(0.7, 0.7, 0.7)
    f._label:SetJustifyH("LEFT")
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    f._line = f:CreateTexture(nil, "ARTWORK")
    f._line:SetHeight(px)
    f._line:SetPoint("LEFT", f._label, "RIGHT", 6, 0)
    f._line:SetPoint("RIGHT", f, "RIGHT", -SPACING, 0)
    f._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
    _bankHeaders[position] = f
    return f
end

local function DiscoverBankTabs()
    _allTabs = {}
    local charTabs = GetCharacterBankTabs()
    for _, t in ipairs(charTabs) do
        t.isWarband = false
        _allTabs[#_allTabs + 1] = t
    end
    local warbandTabs = GetWarbandBankTabs()
    for _, t in ipairs(warbandTabs) do
        t.isWarband = true
        _allTabs[#_allTabs + 1] = t
    end
    CUI_Bank._allTabs = _allTabs
end

-- Fast font size update for bank slots (mirrors bags RefreshTextSizes)
local function RefreshBankTextSizes()
    local countSize = BP().bagCountFontSize or 11
    local ilvlSize = BP().itemlevelFontSize or 12
    local bindTypeSize = BP().bagBindTypeFontSize or 11
    for _, btn in pairs(_bankSlots) do
        if btn.Count then
            CludesUI.ApplyIconTextFont(btn.Count, GetFont(), countSize, "bags")
        end
        if btn.ItemLevelText then
            btn.ItemLevelText:SetFont(
                GetFont(),
                ilvlSize,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
        end
        if btn.BindTypeText then
            btn.BindTypeText:SetFont(
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
    local z = BP().bagItemIconZoom or 0.08
    for _, btn in pairs(_bankSlots) do
        if btn.icon then
            btn.icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
end
CUI_Bank.RefreshIconZoom = RefreshBankIconZoom

local function CountUsedSlots(bagID, numSlots)
    local used = 0
    for slotIndex = 1, numSlots do
        if C_Container.GetContainerItemInfo(bagID, slotIndex) then
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
        BP().bankColumns, BP().bankHeight = cols, hgt
        UpdateThumb()
    end,
    finish = function()
        CUI_Bank:RefreshBank()
    end,
    savePos = function(leftX, topY)
        BP().bankPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = leftX, y = topY }
    end,
    reset = function()
        local p = BP()
        p.bankColumns, p.bankHeight, p.bankListWidth = nil, nil, nil
        CUI_Bank:RefreshBank()
    end,
    -- The warband gold text sits at the footer's right edge
    inset = function(px)
        local wg = CUI_Bank._warbandGoldText
        if not wg then
            return
        end
        wg:ClearAllPoints()
        local footer = wg:GetParent()
        if footer._coinBox then
            wg:SetPoint("RIGHT", footer._coinBox, "RIGHT", -(5 + px), 0)
        else
            wg:SetPoint("RIGHT", footer, "RIGHT", -(8 + px), 0)
        end
    end,
    isLocked = function()
        return BP().bankWindowLocked == true
    end,
    setLocked = function(val)
        BP().bankWindowLocked = val and true or false
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
        return BP().bankListWidth or GetBankColumns() * LIST_PITCH
    end,
    save = function(wid, hgt)
        BP().bankListWidth, BP().bankHeight = wid, hgt
        UpdateThumb()
    end,
}, { __index = _bankGripCfg })
-- a new slot size: grow-only widths start over, header lines take the new
-- inset and the bag bar lays out again
mod.OnSlotMetrics(function(m)
    _bankGripCfg.step = m[1] + m[2]
    _bankGripCfg.minCols = math.max(1, math.ceil(8 * 38 / (m[1] + m[2])))
    CUI_Bank._compactCols, CUI_Bank._compactW = nil, nil
    for _, f in pairs(_bankHeaders) do
        f._line:ClearAllPoints()
        f._line:SetPoint("LEFT", f._label, "RIGHT", 6, 0)
        f._line:SetPoint("RIGHT", f, "RIGHT", -m[2], 0)
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
    sidebar:SetWidth(GetBankSidebarContentWidth())
    local rightInset = forever and 7 or 1
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", sidebarW, -HEADER_H)
    scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -rightInset, FOOTER_H)

    local gridPadX = 10
    local COLUMNS = GetBankColumns()
    local gridW = COLUMNS * (SLOT_SIZE + SPACING)
    -- List rows take the grip-set width, by default the default pitch's
    if CUI_Bank.IsListMode() then
        gridW = BP().bankListWidth or COLUMNS * LIST_PITCH
    end
    local startX = gridPadX + 5
    local contentPad = gridPadX * 2 + SCROLLBAR_HIT_W + 1 - rightInset

    -- Set frame size BEFORE rendering so scroll frame has non-zero bounds
    local totalW = sidebarW + gridW + gridPadX * 2 + SCROLLBAR_HIT_W + 2
    CUI_Bank:SetWidth(totalW)
    CUI_Bank:SetHeight(GetBankHeight())
    childFrame:SetWidth(gridW + contentPad)

    -- Helper: check if a slot passes the search filter
    local function PassesSearch(bagID, slotIndex)
        if not hasSearch then
            return true
        end
        local details = C_Container.GetContainerItemInfo(bagID, slotIndex)
        if not details then
            return false
        end
        CUI_Bags.ApplyBindKeyword(details, bagID, slotIndex)
        return not details.isFiltered
    end

    -- Phase 1: Build flat layout list (no button creation, just positions).
    -- Each entry = { bagID, slot, x, y } for items, or "header" entries.
    local _layout = {}
    local curY = -6
    local headerIdx = 0

    -- Helper: build flat slot list for a set of tabs
    local function BuildOneView(tabs)
        local collected = {}
        local filled = 0
        for _, tabButton in ipairs(tabs) do
            for slotIndex = 1, tabButton.numSlots do
                if PassesSearch(tabButton.bagID, slotIndex) then
                    local details = C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex)
                    collected[#collected + 1] =
                        { bagID = tabButton.bagID, slot = slotIndex, _cachedInfo = details }
                    if details then
                        filled = filled + 1
                    end
                end
            end
        end
        return collected, filled
    end

    local function LayoutFlatSlots(slotList, headerLabel)
        if #slotList > 0 or not hasSearch then
            headerIdx = headerIdx + 1
            _layout[#_layout + 1] = {
                isHeader = true,
                headerIdx = headerIdx,
                label = headerLabel,
                x = startX,
                y = curY,
                w = gridW,
            }
            curY = curY - 22
            for vi, s in ipairs(slotList) do
                local col = (vi - 1) % COLUMNS
                local rowFrame = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = s.bagID,
                    slot = s.slot,
                    _cachedInfo = s._cachedInfo,
                    x = startX + (col * (SLOT_SIZE + SPACING)),
                    y = curY - (rowFrame * (SLOT_SIZE + SPACING)),
                }
            end
            local rowList = math.ceil(math.max(#slotList, 1) / COLUMNS)
            curY = curY - (rowList * (SLOT_SIZE + SPACING)) - 6
        end
    end

    -- Header depth: 0 = expansion (or the outermost level in use), 1 = category,
    -- 2 = the detail split inside a category.
    local function EmitHeader(label, count, depth)
        headerIdx = headerIdx + 1
        local indent = depth * 12
        _layout[#_layout + 1] = {
            isHeader = true,
            depth = depth,
            headerIdx = headerIdx,
            label = label .. " (" .. count .. ")",
            name = label,
            x = startX + indent,
            y = curY,
            w = gridW - indent,
        }
        curY = curY - (depth == 0 and 22 or 18)
    end

    local function EmitSlots(entries)
        for vi, sl in ipairs(entries) do
            local col = (vi - 1) % COLUMNS
            local rowFrame = math.floor((vi - 1) / COLUMNS)
            _layout[#_layout + 1] = {
                bagID = sl.bagID,
                slot = sl.slot,
                _cachedInfo = sl._cachedInfo,
                x = startX + (col * (SLOT_SIZE + SPACING)),
                y = curY - (rowFrame * (SLOT_SIZE + SPACING)),
            }
        end
        local rowList = math.ceil(math.max(#entries, 1) / COLUMNS)
        curY = curY - (rowList * (SLOT_SIZE + SPACING)) - 6
    end

    -- One category, plus its detail split when it has one. A split that yields a
    -- single bucket is collapsed -- "Armor (1) > Chest (1)" is a header for
    -- nothing, and at three levels deep that noise adds up fast.
    local function LayoutCategoryBucket(cb, depth)
        EmitHeader(cb.label, #cb.slots, depth)
        local modeName = DetailModeForCategory(cb.cat)
        if not modeName then
            EmitSlots(cb.slots)
            return
        end
        local buckets = BuildBankBuckets(cb.slots, modeName)
        if #buckets < 2 then
            EmitSlots(cb.slots)
            return
        end
        for _, b in ipairs(buckets) do
            EmitHeader(b.label, #b.slots, depth + 1)
            EmitSlots(b.slots)
        end
    end

    -- classified: an already-stamped list to regroup, when the caller has one.
    local function LayoutCategoryRun(slotList, depth, classified)
        local cbs
        if classified then
            cbs = RegroupByCategory(classified, slotList)
        else
            cbs = BuildCategoryBuckets(slotList)
        end
        if not cbs then
            EmitSlots(slotList)
            return
        end
        for _, cb in ipairs(cbs) do
            LayoutCategoryBucket(cb, depth)
        end
    end

    -- Grouped layout for OneBank / OneWarbank. Expansion is the outer level when
    -- Nest by Expansion is on, category nests inside it, and the per-category
    -- detail split sits inside that. Either toggle works on its own.
    local function LayoutGroupedSlots(slotList, headerLabel)
        local byExp = BP().bankNestByExpansion
        local byCat = BP().bankGroupByCategory
        if not byExp and not byCat then
            return LayoutFlatSlots(slotList, headerLabel)
        end
        if #slotList == 0 and hasSearch then
            return
        end

        -- Empty slots cannot be classified and always trail the whole view.
        local filled, empties = {}, {}
        for _, sl in ipairs(slotList) do
            local details = sl._cachedInfo
            if details and details.hyperlink then
                filled[#filled + 1] = sl
            else
                empties[#empties + 1] = sl
            end
        end

        if byExp then
            local classified = byCat and ClassifyOnce(filled) or nil
            for _, eb in ipairs(BuildBankBuckets(filled, "expansion")) do
                EmitHeader(eb.label, #eb.slots, 0)
                if byCat then
                    LayoutCategoryRun(eb.slots, 1, classified)
                else
                    EmitSlots(eb.slots)
                end
            end
        else
            LayoutCategoryRun(filled, 0)
        end

        if #empties > 0 and not BP().bankHideEmptyWhenNested then
            EmitHeader(CludesUI.L("Empty Slots"), #empties, 0)
            EmitSlots(empties)
        end
    end

    -- Grid for a category-sidebar selection. Expansion stays the outer level when
    -- Nest by Expansion is on; the level below it depends on what was picked --
    -- a group lists its categories, a category its detail split, a detail split
    -- entry just its items.
    local function LayoutSelectionSlots(slotList)
        if #slotList == 0 then
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
            local cb = _catIndex and _catIndex.byKey[_catSel.key]
            local modeName = cb and DetailModeForCategory(cb.cat)
            if modeName then
                local bs = BuildBankBuckets(entries, modeName)
                if #bs > 1 then
                    for _, b in ipairs(bs) do
                        EmitHeader(b.label, #b.slots, depth)
                        EmitSlots(b.slots)
                    end
                    return
                end
            end
            EmitSlots(entries)
        end
        if BP().bankNestByExpansion then
            for _, eb in ipairs(BuildBankBuckets(slotList, "expansion")) do
                EmitHeader(eb.label, #eb.slots, 0)
                Inner(eb.slots, 1)
            end
        else
            -- Without expansion headers a detail selection would render as a
            -- bare grid, so name what is on screen.
            if _catSel.detail or _catSel.group then
                EmitHeader(
                    _catSel.detail or _G.CUI_CategoryManager:GroupDisplayName(_catSel.group),
                    #slotList,
                    0
                )
                if _catSel.detail then
                    EmitSlots(slotList)
                else
                    LayoutCategoryRun(slotList, 1, classified)
                end
            else
                Inner(slotList, 0)
            end
        end
    end

    -- Helper: build per-tab header layout for a set of tabs
    local function LayoutTabHeaders(tabs)
        for _, tabButton in ipairs(tabs) do
            if tabButton.numSlots > 0 then
                local visibleSlots = {}
                local used = 0
                for slotIndex = 1, tabButton.numSlots do
                    local details = C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex)
                    if details then
                        used = used + 1
                    end
                    CUI_Bags.ApplyBindKeyword(details, tabButton.bagID, slotIndex)
                    -- use native search filter so type keywords work too
                    if not hasSearch or (details and not details.isFiltered) then
                        visibleSlots[#visibleSlots + 1] = { slot = slotIndex, _cachedInfo = details }
                    end
                end
                if not hasSearch or #visibleSlots > 0 then
                    headerIdx = headerIdx + 1
                    _layout[#_layout + 1] = {
                        isHeader = true,
                        headerIdx = headerIdx,
                        label = tabButton.name .. " (" .. used .. ")",
                        name = tabButton.name,
                        x = startX,
                        y = curY,
                        w = gridW,
                    }
                    curY = curY - 22
                    local count = hasSearch and #visibleSlots or tabButton.numSlots
                    for vi = 1, count do
                        local slotIndex, cachedInfo
                        if hasSearch then
                            slotIndex = visibleSlots[vi].slot
                            cachedInfo = visibleSlots[vi]._cachedInfo
                        else
                            slotIndex = vi
                            cachedInfo = visibleSlots[vi] and visibleSlots[vi]._cachedInfo
                        end
                        local col = (vi - 1) % COLUMNS
                        local rowFrame = math.floor((vi - 1) / COLUMNS)
                        _layout[#_layout + 1] = {
                            bagID = tabButton.bagID,
                            slot = slotIndex,
                            _cachedInfo = cachedInfo,
                            x = startX + (col * (SLOT_SIZE + SPACING)),
                            y = curY - (rowFrame * (SLOT_SIZE + SPACING)),
                        }
                    end
                    local rowList = math.ceil(count / COLUMNS)
                    curY = curY - (rowList * (SLOT_SIZE + SPACING)) - 6
                end
            end
        end
    end

    -- Split tabs into char and warband
    local charTabs, warbTabs = {}, {}
    for _, tabButton in ipairs(_allTabs) do
        if tabButton.isWarband then
            warbTabs[#warbTabs + 1] = tabButton
        else
            charTabs[#charTabs + 1] = tabButton
        end
    end

    local LayoutOneView = LayoutGroupedSlots

    -- Category index spans whatever the sidebar can browse: warband only for
    -- a portable warbank, otherwise both banks together.
    if BP().bankCategorySidebar then
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
        local slots, filled = BuildOneView(charTabs)
        LayoutOneView(slots, CludesUI.Lf("Bank (%1$d / %2$d)", filled, #slots))
    elseif _selectedView == -3 then
        -- OneWarbank: warband bank only, flat with "Warband Bank" header
        local slots, filled = BuildOneView(warbTabs)
        LayoutOneView(slots, CludesUI.Lf("Warband Bank (%1$d / %2$d)", filled, #slots))
    elseif _selectedView == -2 then
        -- All Warbank Tabs: per-tab headers for warband only
        LayoutTabHeaders(warbTabs)
    elseif _selectedView == 0 then
        -- All Bank Tabs: per-tab headers for character only
        LayoutTabHeaders(charTabs)
    else
        local tabButton = _allTabs[_selectedView]
        if tabButton then
            local allSlots = {}
            local used = 0
            for slotIndex = 1, tabButton.numSlots do
                local details = C_Container.GetContainerItemInfo(tabButton.bagID, slotIndex)
                if details then
                    used = used + 1
                end
                CUI_Bags.ApplyBindKeyword(details, tabButton.bagID, slotIndex)
                allSlots[#allSlots + 1] = { slot = slotIndex, _cachedInfo = details }
            end
            local visibleSlots = allSlots
            if hasSearch then
                -- use native search filter so type keywords work too
                local filtered = {}
                for _, vs in ipairs(allSlots) do
                    if vs._cachedInfo and not vs._cachedInfo.isFiltered then
                        filtered[#filtered + 1] = vs
                    end
                end
                visibleSlots = filtered
            end
            headerIdx = headerIdx + 1
            _layout[#_layout + 1] = {
                isHeader = true,
                headerIdx = headerIdx,
                label = tabButton.name .. " (" .. used .. ")",
                name = tabButton.name,
                x = startX,
                y = curY,
                w = gridW,
            }
            curY = curY - 22
            local count = #visibleSlots
            for vi = 1, count do
                local vs = visibleSlots[vi]
                local col = (vi - 1) % COLUMNS
                local rowFrame = math.floor((vi - 1) / COLUMNS)
                _layout[#_layout + 1] = {
                    bagID = tabButton.bagID,
                    slot = vs.slot,
                    _cachedInfo = vs._cachedInfo,
                    x = startX + (col * (SLOT_SIZE + SPACING)),
                    y = curY - (rowFrame * (SLOT_SIZE + SPACING)),
                }
            end
            local rowList = math.ceil(count / COLUMNS)
            curY = curY - (rowList * (SLOT_SIZE + SPACING))
        end
    end

    local listCols, listRowW
    if CUI_Bank.IsListMode() then
        -- Left / Right Gap: space between the list area edges and the rows
        local listX = BP().bagListGapL or 15
        listRowW = math.max(100, gridW + contentPad - listX - (BP().bagListGapR or 23))
        _layout, curY = ToListLayout(_layout, startX, listX)
        listCols = mod.ListLayoutColumns(listRowW)
        local hdrH = mod.UpdateListHeaderBar(CUI_Bank, listCols, sidebarW, -HEADER_H, listX)
        scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", sidebarW, -(HEADER_H + hdrH))
    elseif CUI_Bank.IsCompactMode() then
        -- Compact: the same entries as blocks, each under a thin label band.
        -- The window drops the remainder its widest band leaves short of the
        -- columns, less than a cell; while open it only grows back, and a new
        -- column count, or a close, starts over (as the bag window does).
        local contentW
        _layout, curY, contentW = ToCompactLayout(_layout, startX, COLUMNS)
        if contentW and contentW < gridW then
            if CUI_Bank._compactCols ~= COLUMNS then
                CUI_Bank._compactCols, CUI_Bank._compactW = COLUMNS, contentW
            elseif contentW > (CUI_Bank._compactW or 0) then
                CUI_Bank._compactW = contentW
            end
            gridW = CUI_Bank._compactW
        else
            CUI_Bank._compactCols, CUI_Bank._compactW = COLUMNS, gridW
        end
        CUI_Bank:SetWidth(sidebarW + gridW + gridPadX * 2 + SCROLLBAR_HIT_W + 2)
        childFrame:SetWidth(gridW + contentPad)
    end

    -- Update deposit button based on current view
    local isWarbandView = (_selectedView == -2 or _selectedView == -3)
    if not isWarbandView and _selectedView > 0 and _allTabs[_selectedView] then
        isWarbandView = _allTabs[_selectedView].isWarband
    end
    CUI_Bank:UpdateDepositButton(isWarbandView)

    -- Set scroll child height from layout
    childFrame:SetHeight(math.abs(curY) + 10)

    -- Phase 2: render the layout, 100 entries per frame (all at once while the resize grip is dragged).
    CUI_Bank._layout = _layout
    CUI_Bank._layoutStartX = startX
    CUI_Bank._layoutGridW = gridW

    -- Shared slot render: updates a single button with item or empty state
    -- One reused data table for third-party overlay painters (CUI_Bags.RunItemOverlays).
    local overlayData = {}
    -- Junk Item Visuals' Desaturate greys grey items and Junk Marker junk here
    -- as on the bank's list rows (read once per refresh)
    local junkOn = _G.CUI_CategoryManager:IsJunkMarkerEnabled()
    local desatJunk = BP().bagDesaturateJunkItems == true
    local function RenderSlotContent(btn, bagID, slotIndex, cachedInfo)
        if btn.ProfessionQualityOverlay then
            btn.ProfessionQualityOverlay:SetAlpha(0)
        end
        if btn.IconOverlay then
            btn.IconOverlay:SetAlpha(0)
            btn.IconOverlay:Hide()
        end
        if btn.IconOverlay2 then
            btn.IconOverlay2:SetAlpha(0)
            btn.IconOverlay2:Hide()
        end
        local details = cachedInfo or C_Container.GetContainerItemInfo(bagID, slotIndex)
        if not details then
            btn:SetItemButtonTexture(nil)
            btn:SetItemButtonCount(0)
            SetItemButtonDesaturated(btn, false)
            if btn.icon then
                btn.icon:Hide()
            end
            btn._emptyBg:Show()
            mod.PaintSlotBackground(btn._emptyBg, 0.35)
            btn:EnableMouse(true)
            SetInsetBorderColor(btn, 0, 0, 0, 0.3)
            if btn._fvSlotBorder then
                mod.SetForeverSlotQuestBorder(btn, false)
            end
            if btn.Cooldown then
                btn.Cooldown:Clear()
            end
            if btn.ItemLevelText then
                btn.ItemLevelText:SetText("")
            end
            if btn.BindTypeText then
                btn.BindTypeText:SetText("")
            end
            if btn.IconBorder then
                btn.IconBorder:Hide()
            end
            if btn.NormalTexture then
                btn.NormalTexture:SetAlpha(0)
            end
        else
            btn:EnableMouse(true)
            btn._emptyBg:Hide()
            if btn.icon then
                btn.icon:Show()
            end
            mod.SetSlotIcon(btn, details.iconFileID)
            btn:SetItemButtonCount(details.stackCount)
            local quality = details.quality or 1
            SetItemButtonDesaturated(
                btn,
                details.isLocked
                    or (desatJunk and (quality == 0 or (junkOn and _G.CUI_CategoryManager:IsJunk(
                        details.itemID,
                        quality
                    ))))
                    or false
            )
            local itemLink = C_Container.GetContainerItemLink(bagID, slotIndex)
            if itemLink then
                btn:SetItemButtonQuality(quality, itemLink, false, false)
            end
            if
                btn.ProfessionQualityOverlay
                and btn.ProfessionQualityOverlay:IsShown()
                and btn._textOverlay
            then
                btn.ProfessionQualityOverlay:SetAlpha(1)
                btn.ProfessionQualityOverlay:SetParent(btn._textOverlay)
            end
            if btn.IconOverlay then
                if btn.IconOverlay:IsShown() then
                    btn.IconOverlay:SetAlpha(1)
                    if btn._textOverlay then
                        btn.IconOverlay:SetParent(btn._textOverlay)
                    end
                else
                    btn.IconOverlay:SetAlpha(0)
                end
            end
            if btn.icon and details and details.itemID then
                local unusable = CUI._BagsItemUnusable
                    and CUI._BagsItemUnusable(bagID, slotIndex, details.hyperlink, details.itemID)
                btn.icon:SetVertexColor(1, unusable and 0.1 or 1, unusable and 0.1 or 1)
            end
            if btn.IconOverlay2 then
                if btn.IconOverlay2:IsShown() then
                    btn.IconOverlay2:SetAlpha(1)
                    if btn._textOverlay then
                        btn.IconOverlay2:SetParent(btn._textOverlay)
                    end
                else
                    btn.IconOverlay2:SetAlpha(0)
                end
            end
            if btn.IconBorder then
                btn.IconBorder:Hide()
            end
            if btn.NormalTexture then
                btn.NormalTexture:SetAlpha(0)
            end
            local qr, qg, qb = mod.QualityBorderColor(quality)
            SetInsetBorderColor(btn, qr, qg, qb, 1)
            if btn._fvSlotBorder then
                mod.SetForeverSlotQuestBorder(btn, mod.GetSlotQuestFlags(bagID, slotIndex))
            end

            -- One gear check + one GetItemInfo fetch shared by the bind-type
            -- and item-level texts
            local isGear = itemLink and IsGearItem(itemLink)
            local showBindType = isGear and not details.isBound and BP().bagDisplayBindType
            local showIlvl = isGear and BP().showItemlevelInBags ~= false
            local giIlvl, giBindType
            local loc
            if showBindType or showIlvl then
                local _, _, _, _, _, _, _, _, _, _, _, _, _, b14 = GetItemInfo(itemLink)
                loc = ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
                giIlvl = showIlvl and GetItemLevelAtLocation(loc, itemLink) or nil
                giBindType = b14
            end

            -- Bind Type : BoE / WuE bottom-left (gear only)
            if btn.BindTypeText then
                if showBindType then
                    local isWuE = false
                    if loc and C_Item.DoesItemExist(loc) then
                        isWuE = C_Item.IsBoundToAccountUntilEquip(loc)
                    end
                    CUI_Bags.SetBindTypeText(btn.BindTypeText, isWuE, giBindType, quality)
                else
                    btn.BindTypeText:SetText("")
                end
            end

            -- Item level (gear only)
            if btn.ItemLevelText then
                if showIlvl then
                    btn.ItemLevelText:SetText(giIlvl or "")
                    local r, g, b
                    if GetUpgradeTrack then
                        local rankText, trackColor = GetUpgradeTrack(itemLink)
                        if BP().itemlevelUseCustomColor and BP().itemlevelCustomColor then
                            r, g, b =
                                BP().itemlevelCustomColor.r,
                                BP().itemlevelCustomColor.g,
                                BP().itemlevelCustomColor.b
                        elseif rankText and rankText ~= "" and trackColor then
                            r, g, b = trackColor.r, trackColor.g, trackColor.b
                        else
                            local craftedColor = CUI.GetCraftedTrackColor(itemLink)
                            if craftedColor then
                                r, g, b = craftedColor.r, craftedColor.g, craftedColor.b
                            end
                        end
                    end
                    if not r then
                        r, g, b = GetItemQualityColor(quality)
                    end
                    btn.ItemLevelText:SetTextColor(r, g, b, 1)
                else
                    btn.ItemLevelText:SetText("")
                end
            end
            if btn.Cooldown then
                local cdS, cdD, cdE = C_Container.GetContainerItemCooldown(bagID, slotIndex)
                if cdE and cdE ~= 0 and cdS > 0 and cdD > 0 then
                    btn.Cooldown:SetDrawEdge(true)
                    btn.Cooldown:SetCooldown(cdS, cdD)
                else
                    btn.Cooldown:Clear()
                end
            end
        end
        if next(CUI_Bags.itemOverlayIcons) ~= nil then
            overlayData.bag, overlayData.slot, overlayData.info = bagID, slotIndex, details
            overlayData.itemLink = details and C_Container.GetContainerItemLink(bagID, slotIndex) or nil
            CUI_Bags.RunItemOverlays(btn, overlayData)
        end
    end

    -- Render in batches of 100 per frame via OnUpdate. While the resize grip
    -- is dragged, render everything this frame so headers never blink.
    local BATCH_SIZE = CUI_Bank._resizing and math.huge or 100
    local rendered = 0
    local slotIdx, rowIdx = 0, 0

    local function RenderBatch()
        local batchEnd = math.min(rendered + BATCH_SIZE, #_layout)
        for li = rendered + 1, batchEnd do
            local record = _layout[li]
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
                    local d = record.depth or 0
                    if d >= 2 then
                        SetBankFont(heading._label, 10)
                        heading._label:SetTextColor(0.45, 0.45, 0.45)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.06)
                    elseif d == 1 then
                        SetBankFont(heading._label, 10)
                        heading._label:SetTextColor(0.55, 0.55, 0.55)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.10)
                    else
                        SetBankFont(heading._label, 11)
                        heading._label:SetTextColor(0.7, 0.7, 0.7)
                        heading._line:SetColorTexture(0.7, 0.7, 0.7, 0.2)
                    end
                    if forever then
                        mod.SetForeverBagSectionColors(heading._label, heading._line, d)
                    end
                    heading._label:SetText(record.label)
                    heading:Show()
                end -- compact label vs grid header
            elseif record.isRow then
                local btn = GetOrCreateBankRow(rowIdx + 1)
                if btn then
                    rowIdx = rowIdx + 1
                    btn:GetParent():SetParent(childFrame)
                    mod.RenderListRow(btn, record.data, listCols, listRowW, record.x, record.y, record.stripe)
                end
            else
                slotIdx = slotIdx + 1
                -- nil in combat: the cell stays empty until the combat-end refresh
                local btn = GetOrCreateBankSlot(slotIdx)
                if btn then
                    btn:GetParent():SetParent(childFrame)
                    local hostFrame = btn:GetParent()
                    hostFrame:ClearAllPoints()
                    hostFrame:SetPoint("TOPLEFT", record.x, record.y)
                    hostFrame:Show()
                    btn:Show()
                    btn:SetID(record.slot)
                    hostFrame:SetID(record.bagID)

                    RenderSlotContent(btn, record.bagID, record.slot, record._cachedInfo)
                end -- slot built
            end
        end
        rendered = batchEnd
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
    if rendered >= #_layout then
        CUI_Bank._batchFrame:SetScript("OnUpdate", nil)
        HideUnused()
    else
        CUI_Bank._batchFrame:SetScript("OnUpdate", function(self)
            if rendered >= #_layout or not CUI_Bank:IsVisible() then
                self:SetScript("OnUpdate", nil)
                HideUnused()
                return
            end
            RenderBatch()
            if rendered >= #_layout then
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
local function RowSel(btn)
    return not btn._isPurchaseTab and btn._catSel or nil
end

-- a selection's block id + category indices in this scope ("top" or "group:<name>"), nil if it's not in it
local function DragBlock(sel, scope)
    local CM = _G.CUI_CategoryManager
    if not (sel and CM) then
        return nil
    end
    local cats = CM:GetCategories()
    local group, i = sel.group, nil
    if not group then
        for ci, c in ipairs(cats) do
            if c._defaultName == sel.key then
                i = ci
                break
            end
        end
        if not i or cats[i].isJunk or cats[i].isEquipSet or cats[i].isVirtual then
            return nil
        end
        group = cats[i].groupName
    end
    if scope == "top" then
        if group then
            return "g:" .. group, CM:GetGroupMembers(group)
        end
        -- item set gear drags its set categories with it
        local blockData = { i }
        if cats[i].isSetGear then
            for ci, c in ipairs(cats) do
                if c.isEquipSet then
                    blockData[#blockData + 1] = ci
                end
            end
        end
        return "k:" .. sel.key, blockData
    end
    if i and group and scope == "group:" .. group then
        return "k:" .. sel.key, { i }
    end
end

-- what pressing this row would drag (detail rows and junk don't move)
local function DragScope(btn)
    local sel = btn._catSel
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

local dragFrame = CreateFrame("Frame")
dragFrame:Hide()
local dragGhost, dragLine

local function DragVisuals(btn)
    if not dragGhost then
        dragGhost = CreateFrame("Frame", nil, UIParent)
        dragGhost:SetFrameStrata("TOOLTIP")
        dragGhost:SetSize(150, SIDEBAR_BTN_H)
        dragGhost:SetAlpha(0.7)
        local backdrop = dragGhost:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.6)
        dragGhost._icon = dragGhost:CreateTexture(nil, "ARTWORK")
        dragGhost._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        dragGhost._label = dragGhost:CreateFontString(nil, "OVERLAY")
        SetBankFont(dragGhost._label, 11)
        dragGhost._label:SetPoint("LEFT", dragGhost._icon, "RIGHT", 6, 0)
        dragLine = sidebarChild:CreateTexture(nil, "OVERLAY")
        dragLine:SetHeight(2)
    end
    dragGhost._icon:SetTexture(btn._icon:GetTexture())
    dragGhost._icon:SetTexCoord(btn._icon:GetTexCoord())
    dragGhost._label:SetText(btn._entryName or "")
    local collapsed = BP().bankSidebarCollapsed and mod.BagsForever()
    mod.AnchorBagSidebarIcon(dragGhost._icon, collapsed, 6)
    dragGhost._label:SetShown(not collapsed)
    dragGhost:SetWidth(
        collapsed and btn:GetWidth()
            or math.max(dragGhost._label:GetStringWidth() + SIDEBAR_ICON_SIZE + 24, 80)
    )
    local r, g, b = GetAccentRGB()
    dragLine:SetColorTexture(r, g, b, 1)
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
    for _, b in pairs(_sidebarBtns) do
        if b:IsShown() and b:IsMouseOver() then
            over = b
            break
        end
    end
    if not over then
        return nil
    end
    local ident, blockData = RowBlock(over)
    if not ident or ident == _drag.id then
        return nil
    end
    -- all of the block's rows (a group's header, members, details)
    local topY, bottom
    for _, b in pairs(_sidebarBtns) do
        if b:IsShown() and RowBlock(b) == ident then
            if not topY or b:GetTop() > topY:GetTop() then
                topY = b
            end
            if not bottom or b:GetBottom() < bottom:GetBottom() then
                bottom = b
            end
        end
    end
    local _, cy = GetCursorPosition()
    cy = cy / sidebarChild:GetEffectiveScale()
    local after = cy < (topY:GetTop() + bottom:GetBottom()) / 2
    return blockData, after, after and bottom or topY
end

local function FinishDrag(apply)
    local d = _drag
    _drag = nil
    dragFrame:Hide()
    if dragGhost then
        dragGhost:Hide()
        dragLine:Hide()
    end
    if not (d and d.live) then
        return
    end
    d.btn:SetAlpha(1)
    local targetUnit = apply and d.target
    if not targetUnit then
        return
    end
    local CM = _G.CUI_CategoryManager
    local cats = CM:GetCategories()
    -- from the row's selection at press time: a refresh mid-drag can hand the pooled row to another category
    local _, blockData = DragBlock(d.sel, d.scope)
    if not blockData then
        return
    end
    local insertAt = d.after and (math.max(unpack(targetUnit)) + 1) or math.min(unpack(targetUnit))
    table.sort(blockData)
    if insertAt >= blockData[1] and insertAt <= blockData[#blockData] + 1 then
        return
    end
    -- equip sets follow item set gear on their own (SaveState), so the rest
    -- moves one ReorderCategory at a time (its junk / set rules apply), each
    -- dropped in just above the target row; found by reference every step
    local moving, sets = {}, false
    for _, i in ipairs(blockData) do
        if cats[i].isEquipSet then
            sets = true
        else
            moving[#moving + 1] = cats[i]
        end
    end
    local before = cats[insertAt] -- nil: the end of the list
    -- keep the bags' selection on the same category, not the same index
    local selIdx, selGroup = mod.GetSelection()
    local selKey = selIdx and selIdx > 0 and cats[selIdx] and cats[selIdx]._defaultName
    local function IndexOf(c)
        for i, posX in ipairs(cats) do
            if posX == c then
                return i
            end
        end
    end
    for _, c in ipairs(moving) do
        local from = IndexOf(c)
        if from then
            CM:ReorderCategory(from, before and IndexOf(before) or #cats + 1)
        end
    end
    -- the sets catch up with their anchor on a rebuild from the saved order
    if sets then
        CM:OnEquipmentSetsChanged()
    end
    if selKey then
        for ci, c in ipairs(CM:GetCategories()) do
            if c._defaultName == selKey then
                mod.SetSelection(ci, selGroup)
                break
            end
        end
    end
    CUI_Bank:RefreshBank()
    if CUI_Bags:IsVisible() then
        CUI_Bags:RefreshInventory()
    end
end

dragFrame:SetScript("OnUpdate", function()
    local d = _drag
    if not d then
        dragFrame:Hide()
        return
    end
    local posX, posY = GetCursorPosition()
    if not IsMouseButtonDown("LeftButton") then
        FinishDrag(true)
        return
    end
    if not d.live then
        -- only counts as a drag after a few pixels
        if math.abs(posY - d.startY) <= 4 then
            return
        end
        d.live = true
        d.btn._didDrag = true
        d.btn:SetAlpha(0.4)
        DragVisuals(d.btn)
        dragGhost:Show()
    end
    local sc = UIParent:GetEffectiveScale()
    dragGhost:ClearAllPoints()
    dragGhost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", posX / sc + 12, posY / sc)
    local blockData, after, rowFrame = DragTarget()
    d.target, d.after = blockData, after
    if rowFrame then
        dragLine:ClearAllPoints()
        local inset = math.floor(sidebarChild:GetWidth() * 0.05)
        local edge = after and "BOTTOM" or "TOP"
        dragLine:SetPoint("LEFT", rowFrame, edge .. "LEFT", inset, 0)
        dragLine:SetPoint("RIGHT", rowFrame, edge .. "RIGHT", -inset, 0)
        dragLine:Show()
    else
        dragLine:Hide()
    end
end)

local function BeginDrag(btn)
    local scope = DragScope(btn)
    if not scope then
        return
    end
    local _, posY = GetCursorPosition()
    local sel = RowSel(btn)
    _dragGen = _dragGen + 1
    _drag = { btn = btn, sel = sel, scope = scope, id = DragBlock(sel, scope), startY = posY }
    dragFrame:Show()
end
-- closing the bank mid-drag hides the rows, so the drop just goes nowhere

function BuildBankSidebar()
    local collapsed = BP().bankSidebarCollapsed
    local sidebarW = GetBankSidebarContentWidth()
    local posY = 0
    local ar, ag, ab = GetAccentRGB()
    sidebarChild:SetWidth(sidebarW)
    local btnIdx = 0
    -- While a category is selected no view or tab entry is current.
    local selView = _catSel and -99 or _selectedView

    -- Update sidebar header label visibility
    if collapsed then
        sidebarHdr._label:Hide()
    else
        sidebarHdr._label:Show()
    end

    local function MakeSidebarBtn(position)
        if _sidebarBtns[position] then
            return _sidebarBtns[position]
        end
        local btn = CreateFrame("Button", nil, sidebarChild)
        btn:SetHeight(SIDEBAR_BTN_H)
        btn._indicator = btn:CreateTexture(nil, "OVERLAY")
        local Pix = CUI and CUI.PP
        local px = (Pix and Pix.mult) or 1
        btn._indicator:SetWidth(px * 2)
        btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
        btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
        btn._bg:SetAllPoints()
        btn._bg:SetColorTexture(1, 1, 1, 0)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._label = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(btn._label, 11)
        btn._label:SetJustifyH("LEFT")
        btn._label:SetWordWrap(false)
        btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
        btn._label:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
        btn._count = btn:CreateFontString(nil, "OVERLAY")
        SetBankFont(btn._count, 10)
        btn._count:SetJustifyH("RIGHT")
        btn._count:SetTextColor(0.5, 0.5, 0.5)
        btn._count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
        btn:SetScript("OnEnter", function(self)
            local showEditableTabTooltip = CUI.ShowWidgetTooltip
                and not self._isPurchaseTab
                and self._viewIdx
                and self._viewIdx > 0

            if not self._isSelected then
                self._bg:SetColorTexture(1, 1, 1, 0.06)
            end
            if BP().bankSidebarCollapsed and CUI.ShowWidgetTooltip then
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
            if not BP().bankSidebarCollapsed and showEditableTabTooltip then
                CUI.ShowWidgetTooltip(self, "|cffdab842" .. BANK_TAB_TOOLTIP_CLICK_INSTRUCTION .. "|r")
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self._isSelected then
                self._bg:SetColorTexture(1, 1, 1, 0)
            end
            CUI.HideWidgetTooltip()
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnMouseDown", function(self, btnFrame)
            -- a drop over another row never clicks this one, so clear it here
            self._didDrag = false
            if btnFrame == "LeftButton" and not self._isPurchaseTab then
                BeginDrag(self)
            end
        end)
        btn:SetScript("OnClick", function(self, btnFrame)
            if self._isPurchaseTab then
                return
            end
            -- letting go of a drag isn't a click
            if self._didDrag then
                self._didDrag = false
                return
            end

            if btnFrame == "RightButton" and self._viewIdx and self._viewIdx > 0 then
                local tabData = _allTabs[self._viewIdx]
                if tabData then
                    -- The bagID is the tab ID UpdateBankTabSettings expects:
                    -- Enum.BagIndex.CharacterBankTab_1..6 / AccountBankTab_1..5
                    EnsureBankTabConfigFrame()
                    if CUI_BankTabConfigFrame.OpenBankTabSettings then
                        CUI_BankTabConfigFrame:OpenBankTabSettings(tabData, tabData.bagID)
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
        _sidebarBtns[position] = btn
        return btn
    end

    local function RenderPurchaseEntry(bankType, label)
        btnIdx = btnIdx + 1
        local btn = MakeSidebarBtn(btnIdx)
        local locLabel = CludesUI.L(label)
        btn._viewIdx = nil
        btn._catSel = nil
        btn._isPurchaseTab = true
        btn._purchaseBankType = bankType
        btn._isSelected = false
        -- Store the localized label so the collapsed-sidebar hover tooltip (which
        -- reads _entryName) matches the expanded label on non-English clients.
        btn._entryName = locLabel
        btn._entryCount = 0
        btn._indicator:Hide()
        btn._bg:SetColorTexture(1, 1, 1, 0)
        btn:SetParent(sidebarChild)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, posY)
        btn:SetWidth(sidebarW)
        mod.AnchorBagSidebarIcon(btn._icon, collapsed, 8)
        btn._icon:SetTexture(133784)
        btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._icon:SetDesaturated(false)
        btn._icon:SetAlpha(0.6)
        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(locLabel)
            btn._label:SetTextColor(1, 1, 1, 0.6)
            btn._count:Hide()
        end
        btn:SetAlpha(0.6)
        btn:Show()
        -- Overlay the secure purchase button on top of this visual entry
        local secBtn = (bankType == Enum.BankType.Character) and _purchaseBtnChar or _purchaseBtnWarband
        secBtn._visualBtn = btn
        secBtn:SetParent(sidebarChild)
        secBtn:ClearAllPoints()
        secBtn:SetAllPoints(btn)
        secBtn:SetFrameLevel(btn:GetFrameLevel() + 20)
        secBtn:Show()
        posY = posY - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    local function RenderSidebarEntry(viewIdx, name, glyph, count, isSelected, indent, catSel, isAtlas)
        btnIdx = btnIdx + 1
        local btn = MakeSidebarBtn(btnIdx)
        btn._viewIdx = viewIdx
        btn._catSel = catSel
        btn._isPurchaseTab = false
        btn._isSelected = isSelected
        btn._entryName = name
        btn._entryCount = count
        btn:SetAlpha(1)
        btn:SetParent(sidebarChild)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, posY)
        btn:SetWidth(sidebarW)
        mod.AnchorBagSidebarIcon(btn._icon, collapsed, 8 + (indent or 0) * 10)
        if isAtlas and btn._icon.SetAtlas then
            btn._icon:SetAtlas(glyph)
        else
            -- Through the client icon map, like the bag window's sidebar: a
            -- default the Forever client cannot draw takes its stand-in there.
            -- Cropped on every paint (a pooled row may last have drawn an atlas).
            btn._icon:SetTexture(CludesUI.ClientIcon(glyph))
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        btn._icon:SetAlpha(isSelected and 1 or 0.75)

        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(name)
            btn._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)
            btn._count:Show()
            btn._count:SetText(tostring(count))
        end

        if isSelected then
            btn._indicator:SetColorTexture(ar, ag, ab, 1)
            btn._indicator:Show()
            btn._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            btn._indicator:Hide()
            btn._bg:SetColorTexture(1, 1, 1, 0)
        end
        btn:Show()
        posY = posY - SIDEBAR_BTN_H - SIDEBAR_PAD
    end

    -- Hide all sidebar buttons + secure purchase overlays
    for _, btn in pairs(_sidebarBtns) do
        btn:Hide()
    end
    _purchaseBtnChar:Hide()
    _purchaseBtnWarband:Hide()

    -- Count used slots per tab, split by bank/warbank
    local charUsed, charTotal = 0, 0
    local warbUsed, warbTotal = 0, 0
    for _, tabButton in ipairs(_allTabs) do
        tabButton._usedSlots = CountUsedSlots(tabButton.bagID, tabButton.numSlots)
        if tabButton.isWarband then
            warbUsed = warbUsed + tabButton._usedSlots
            warbTotal = warbTotal + tabButton.numSlots
        else
            charUsed = charUsed + tabButton._usedSlots
            charTotal = charTotal + tabButton.numSlots
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
    local function ShowDivider(key)
        if not sidebarChild[key] then
            local Pix = CUI and CUI.PP
            local px = (Pix and Pix.mult) or 1
            local div = sidebarChild:CreateTexture(nil, "ARTWORK")
            div:SetHeight(px)
            div:SetColorTexture(0.2, 0.2, 0.2, 1)
            sidebarChild[key] = div
        end
        posY = posY - 4
        local div = sidebarChild[key]
        div:ClearAllPoints()
        local inset = math.floor(sidebarW * 0.08)
        div:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", inset, posY)
        div:SetPoint("TOPRIGHT", sidebarChild, "TOPRIGHT", -inset, posY)
        div:Show()
        posY = posY - (div:GetHeight() or 1) - 4
    end

    -- Physical tabs can be hidden once the category list is doing the
    -- navigating, but only when it is actually on -- otherwise the sidebar
    -- would have nothing left to click.
    local showTabs = not (BP().bankHideTabsInSidebar and BP().bankCategorySidebar and _catIndex)

    -- offline bank on: tabs nest under their all entry, a divider splits the
    -- bank and warbank views and the buy entries go last (an alt's bank draws
    -- the same way). off: the usual layout
    local nested = mod.Offline and mod.Offline.Enabled()
    for _, k in ipairs(SIDEBAR_DIVIDERS) do
        if sidebarChild[k] then
            sidebarChild[k]:Hide()
        end
    end
    -- the rows may be handed to other entries: a drag works their blocks out again
    _dragGen = _dragGen + 1

    local defaultOneBag = BankDefaultsToOne()
    local hasWarband = false
    for _, tabButton in ipairs(_allTabs) do
        if tabButton.isWarband then
            hasWarband = true
            break
        end
    end
    if nested then
        -- tabs nested under their all entry
        local function NestTabs(warband)
            if not showTabs then
                return
            end
            for ti, tabButton in ipairs(_allTabs) do
                if (tabButton.isWarband == true) == warband then
                    RenderSidebarEntry(
                        ti,
                        tabButton.shortName or tabButton.name,
                        tabButton.icon or (warband and 1542854 or 133652),
                        tabButton._usedSlots,
                        selView == ti,
                        1
                    )
                end
            end
        end
        if not _warbandOnly then
            local function All()
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selView == 0)
                NestTabs(false)
            end
            local function One()
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selView == -1)
            end
            if defaultOneBag then
                One()
                All()
            else
                All()
                One()
            end
        end
        if hasWarband then
            -- keeps the bank and warbank views apart
            if not _warbandOnly then
                ShowDivider("_warbandViewDivider")
            end
            local function All()
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selView == -2)
                NestTabs(true)
            end
            local function One()
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selView == -3)
            end
            if defaultOneBag then
                One()
                All()
            else
                All()
                One()
            end
        end
    else
        if not _warbandOnly then
            if defaultOneBag then
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selView == -1)
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selView == 0)
            else
                RenderSidebarEntry(0, CludesUI.L("All Bank Tabs"), 413587, charUsed, selView == 0)
                RenderSidebarEntry(-1, CludesUI.L("OneBank"), 1542860, charUsed, selView == -1)
            end
        end

        -- Warband "All" and "One" entries
        if hasWarband then
            if defaultOneBag then
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selView == -3)
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selView == -2)
            else
                RenderSidebarEntry(-2, CludesUI.L("All Warbank Tabs"), 1542854, warbUsed, selView == -2)
                RenderSidebarEntry(-3, CludesUI.L("OneWarbank"), 1542854, warbUsed, selView == -3)
            end
        end
    end

    -- Category entries, mirroring the bags sidebar: group header, then its
    -- members indented under it, then the per-category detail split as a third
    -- level -- shown only for the selected branch, or the sidebar would run to
    -- fifty-odd entries on a full bank.
    if _catIndex and BP().bankCategorySidebar then
        local CM = _G.CUI_CategoryManager
        local cats = (CM and CM:GetCategories()) or {}

        local function CountFor(category)
            local cb = category._defaultName and _catIndex.byKey[category._defaultName]
            return cb and #cb.slots or 0
        end

        local function EmitDetail(category, indent)
            local key = category._defaultName
            local bs = key and _catIndex.detailByKey[key]
            if not bs or collapsed then
                return
            end
            -- Expand only under the selected category, or under a selected group
            -- that this category belongs to.
            local open = _catSel
                and (_catSel.key == key or (_catSel.group and _catSel.group == category.groupName))
            if not open then
                return
            end
            for _, b in ipairs(bs) do
                RenderSidebarEntry(
                    nil,
                    b.label,
                    category.icon or 134400,
                    #b.slots,
                    _catSel.key == key and _catSel.detail == b.label,
                    indent,
                    { key = key, detail = b.label },
                    category.isAtlas
                )
            end
        end

        local anyCat = false
        local renderedGroups = {}
        for _, category in ipairs(cats) do
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
                            local mc = cats[mi]
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
                                local mc = cats[mi]
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
        if not anyCat and sidebarChild._catDivider then
            sidebarChild._catDivider:Hide()
        end
    elseif sidebarChild._catDivider then
        sidebarChild._catDivider:Hide()
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
            for ti, tabButton in ipairs(_allTabs) do
                if not tabButton.isWarband then
                    RenderSidebarEntry(
                        ti,
                        tabButton.name,
                        tabButton.icon or 133652,
                        tabButton._usedSlots,
                        selView == ti
                    )
                end
            end
        else
            if sidebarChild._bankTabDivider then
                sidebarChild._bankTabDivider:Hide()
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
        if hasWarband and showTabs then
            ShowDivider("_warbandDivider")

            for ti, tabButton in ipairs(_allTabs) do
                if tabButton.isWarband then
                    RenderSidebarEntry(
                        ti,
                        tabButton.name,
                        tabButton.icon or 1542854,
                        tabButton._usedSlots,
                        selView == ti
                    )
                end
            end
        else
            if sidebarChild._warbandDivider then
                sidebarChild._warbandDivider:Hide()
            end
            if sidebarChild._warbandTabDivider then
                sidebarChild._warbandTabDivider:Hide()
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
            if not hasWarband then
                ShowDivider("_warbandDivider")
            end
            RenderPurchaseEntry(Enum.BankType.Account, "Buy Warbank Tab")
        end
    end

    -- Set scroll child height so scrolling works when content overflows
    sidebarChild:SetHeight(math.abs(posY) + 4)
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
eventFrame:RegisterEvent("BANK_TABS_CHANGED")
eventFrame:RegisterEvent("BANK_TAB_SETTINGS_UPDATED")
eventFrame:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
if CUI.IS_FOREVER then
    eventFrame:RegisterEvent("BAG_CONTAINER_UPDATE")
end
eventFrame:SetScript("OnEvent", function(_, evt)
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
            local defaultOneBag = BankDefaultsToOne()
            _selectedView = defaultOneBag and -3 or -2
        end
        -- Position
        CUI_Bank:ClearAllPoints()
        if BP().bankPosition then
            local place = BP().bankPosition
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
        local bankScale = BP().bagScale or 1
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
            mod.PadSidebarSync(sidebarHdr, sidebarSF, sidebarChild, "bankSidebarCollapsed", enabled)
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
        local gridW = GetBankColumns() * (SLOT_SIZE + SPACING)
        CUI_Bank:SetWidth(GetBankSidebarWidth() + gridW + 10 * 2 + SCROLLBAR_HIT_W + 2)
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
                local poller = CUI_Bank._tabPoller
                if not poller then
                    -- Hidden while idle: a poll request arms its fields and shows it,
                    -- and it hides itself when the poll ends.
                    poller = CreateFrame("Frame")
                    poller:Hide()
                    poller:SetScript("OnUpdate", function(self)
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
                    CUI_Bank._tabPoller = poller
                end
                poller.attempts = 0
                poller.prevCount = prevCount
                poller:Show()
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
                for i, tabButton in ipairs(_allTabs) do
                    if tabButton.bagID == selTab.bagID then
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
        headerFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", 1, -1)
        headerFrame:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", -1, -1)
        mod.LayoutForeverBagHeader(headerFrame)
        HEADER_H = headerFrame:GetHeight() + 1
        local inset = mod.ForeverBagSidebarInset(CUI_Bank)
        sidebar._leftInset = inset
        sidebar:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", inset, -headerFrame:GetHeight())
        sidebar:SetPoint("BOTTOMLEFT", CUI_Bank, "BOTTOMLEFT", inset, FOOTER_H)
        sidebar:SetWidth(GetBankSidebarContentWidth())
        sidebarChild:SetWidth(GetBankSidebarContentWidth())
        scrollFrame:SetPoint("TOPLEFT", CUI_Bank, "TOPLEFT", GetBankSidebarWidth(), -HEADER_H)
        scrollFrame:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -7, FOOTER_H)
        track:SetPoint("TOPRIGHT", CUI_Bank, "TOPRIGHT", -7, -HEADER_H)
        track:SetPoint("BOTTOMRIGHT", CUI_Bank, "BOTTOMRIGHT", -7, FOOTER_H)
        hdrBg:Hide()
        headerFrame.separator:Hide()
        sidebarBg:SetColorTexture(0.10, 0.065, 0.035, 0.45)
        sidebar.separator:SetColorTexture(0.45, 0.33, 0.21, 0.85)

        mod.SkinForeverBagTitle(titleText, itemCount)
        mod.AddForeverBagPortrait(headerFrame, "Interface\\Icons\\INV_Misc_Coin_01")
        mod.PositionForeverBagClose(close)

        sortBtn:ClearAllPoints()
        sortBtn:SetPoint("RIGHT", headerFrame, "TOPRIGHT", -9, headerFrame._foreverToolsY)
        bankSearch:ClearAllPoints()
        bankSearch:SetPoint("LEFT", headerFrame, "TOPLEFT", 45, headerFrame._foreverToolsY)
        bankSearch:SetPoint("RIGHT", CUI_Bank._bagsBtn or sortBtn, "LEFT", -6, 0)
        bankSearch:SetFont(GetFont(), 12, CUI.GetFontOutlineFlag("bags"))
        CUI.PanelPP.HideBorder(bankSearch)
        mod.SkinForeverBagSearch(bankSearch, searchBg, searchPlaceholder, searchClear)
        local footer = CUI_Bank.Footer
        mod.SkinForeverBagFooter(footer, footer.bg, footer.separator)
        footer.playerGold:ClearAllPoints()
        footer.playerGold:SetPoint("LEFT", footer._coinBox, "LEFT", 5, 0)
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
        CUI_Bank.CloseButton = close
    end

    -- Auto-shift DressUpFrame to the right of the bank when both are open
    local dressUp = _G.DressUpFrame
    if dressUp then
        local _duIgnoreSP = false
        local function ShiftDressUp()
            if not CUI_Bank:IsVisible() or InCombatLockdown() then
                return
            end
            _duIgnoreSP = true
            dressUp:ClearAllPoints()
            dressUp:SetPoint("TOPLEFT", CUI_Bank, "TOPRIGHT", 4, 0)
            _duIgnoreSP = false
        end
        dressUp:HookScript("OnShow", ShiftDressUp)
        hooksecurefunc(dressUp, "SetPoint", function()
            if _duIgnoreSP then
                return
            end
            ShiftDressUp()
        end)
        CUI_Bank:HookScript("OnShow", function()
            if dressUp:IsVisible() then
                ShiftDressUp()
            end
        end)
    end
end)
