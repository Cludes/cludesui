if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Footer.lua
--
--  Gold tracking and its tooltip, the footer with the tracked currencies
--  and the reagent bag window.
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

local BP, CurrencyOrder, SetBagFont, FOOTER_H =
    Inner.BP, Inner.CurrencyOrder, Inner.SetBagFont, Inner.FOOTER_H

-------------------------------------------------------------------------------
--  Gold tracking + Footer
-------------------------------------------------------------------------------
local GoldLedger = CludesUI.GetGoldLedger()

local function FormatNumberWithCommas(num)
    local str = tostring(math.floor(num))
    local result = ""
    local total = 0
    for i = #str, 1, -1 do
        if total > 0 and total % 3 == 0 then
            result = "," .. result
        end
        result = str:sub(i, i) .. result
        total = total + 1
    end
    return result
end

local function FormatGoldOnly(gold)
    local goldAmount = math.floor(gold / 10000)
    return FormatNumberWithCommas(goldAmount) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:14|t"
end

local WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B = 1, 0.8, 0.5

local function UpdateBagMoneyDisplay()
    if not CUI_Bags.Money then
        return
    end
    MoneyFrame_UpdateMoney(CUI_Bags.Money)
    local goldBtn = _G["CUI_BagMoneyFrameGoldButton"]
    if goldBtn then
        local txt = goldBtn:GetFontString()
        if txt then
            txt:SetText(FormatNumberWithCommas(math.floor((GoldLedger.Money() or 0) / 10000)))
        end
    end
end

local function ResetAllGoldData()
    GoldLedger.Reset()
    GoldLedger.RecordCharacter()
    GoldLedger.RecordWarband()
end

-- Ledger callback: repaint the money readouts after every recorded change.
local function OnGoldChanged()
    UpdateBagMoneyDisplay()
    local bank = _G.CUI_BankFrame
    if bank and bank.UpdateFooterGold and bank:IsVisible() then
        bank:UpdateFooterGold()
    end
end

-------------------------------------------------------------------------------
--  Gold tooltip (custom multi-column, matches vault tooltip pattern)
-------------------------------------------------------------------------------
local _goldTT
local _goldTTRows = {}
local GOLD_COL_GAP = 20
local GOLD_ROW_H = 14
local GOLD_PAD = 8

local function GetGoldTooltip()
    if _goldTT then
        return _goldTT
    end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25)
    fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function()
        f:SetAlpha(1)
    end)
    f._fadeInAG = fadeInAG
    f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25)
    fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function()
        f:SetAlpha(0)
        f:Hide()
    end)
    f._fadeOutAG = fadeOutAG
    f._fadeOut = fadeOut

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -GOLD_PAD)
    title:SetText(CludesUI.L("Gold Summary"))
    f._title = title

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetTextColor(1, 0.4, 0.4, 1)
    hint:SetText(CludesUI.L("Ctrl + Right-Click: Reset all data"))
    f._hint = hint

    _goldTT = f
    return f
end

local function EnsureGoldRows(total)
    local fontFile = (CludesUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (CludesUI.GetFontOutlineFlag("bags")) or ""
    local tt = GetGoldTooltip()
    for i = 1, total do
        if not _goldTTRows[i] then
            _goldTTRows[i] = {}
            for col = 0, 1 do
                local fontStr = tt:CreateFontString(nil, "OVERLAY")
                fontStr:SetFont(fontFile, 11, fontFlags)
                fontStr:SetJustifyH(col == 0 and "LEFT" or "RIGHT")
                _goldTTRows[i][col] = fontStr
            end
        end
    end
    tt._title:SetFont(fontFile, 11, fontFlags)
    tt._hint:SetFont(fontFile, 10, fontFlags)
    for i = 1, total do
        for col = 0, 1 do
            _goldTTRows[i][col]:SetFont(fontFile, 11, fontFlags)
        end
    end
end

local function StripRealm(name)
    if not name then
        return "Unknown"
    end
    if Ambiguate then
        return Ambiguate(name, "short") or name
    end
    return name
end

local function ShowGoldTooltip(anchor)
    if not GoldLedger.IsTracking() then
        return
    end

    local ledger = GoldLedger.Data()
    local totalGold = 0
    local charList = {}
    for charID, payload in pairs(ledger.chars) do
        charList[#charList + 1] = { id = charID, data = payload }
        totalGold = totalGold + payload.money
    end
    table.sort(charList, function(a, b)
        return (a.data.name or a.id) < (b.data.name or b.id)
    end)

    local warbandGold = ledger.warband and ledger.warband.money
    -- An empty warband bank gets no row, as on the Data Bars Gold block.
    if warbandGold and warbandGold <= 0 then
        warbandGold = nil
    end
    if warbandGold then
        totalGold = totalGold + warbandGold
    end
    if #charList == 0 and not warbandGold then
        return
    end

    local rowCount = #charList + 1
    if warbandGold then
        rowCount = rowCount + 1
    end
    EnsureGoldRows(rowCount)
    local tt = GetGoldTooltip()

    local colWidths = { 0, 0 }
    for r, record in ipairs(charList) do
        local nameFS = _goldTTRows[r][0]
        local goldFS = _goldTTRows[r][1]
        local cc = RAID_CLASS_COLORS[record.data.class] or { r = 1, g = 1, b = 1 }
        local hex = string.format("%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
        nameFS:SetText("|cff" .. hex .. StripRealm(record.data.name or record.id) .. "|r")
        goldFS:SetText(FormatGoldOnly(record.data.money))
        goldFS:SetTextColor(1, 1, 1, 1)
        nameFS:Show()
        goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then
            colWidths[1] = nw
        end
        if gw > colWidths[2] then
            colWidths[2] = gw
        end
    end

    local totalRow = #charList + 1
    if warbandGold then
        local nameFS = _goldTTRows[totalRow][0]
        local goldFS = _goldTTRows[totalRow][1]
        nameFS:SetText("|cffffcc80" .. CludesUI.L("Warbank") .. "|r")
        goldFS:SetText(FormatGoldOnly(warbandGold))
        goldFS:SetTextColor(WARBANK_GOLD_R, WARBANK_GOLD_G, WARBANK_GOLD_B, 1)
        nameFS:Show()
        goldFS:Show()
        local nw = nameFS:GetStringWidth() or 0
        local gw = goldFS:GetStringWidth() or 0
        if nw > colWidths[1] then
            colWidths[1] = nw
        end
        if gw > colWidths[2] then
            colWidths[2] = gw
        end
        totalRow = totalRow + 1
    end

    local totalNameFS = _goldTTRows[totalRow][0]
    local totalGoldFS = _goldTTRows[totalRow][1]
    totalNameFS:SetText("|cffffcc80" .. CludesUI.L("Total") .. "|r")
    totalGoldFS:SetText(FormatGoldOnly(totalGold))
    totalGoldFS:SetTextColor(1, 1, 0.5, 1)
    totalNameFS:Show()
    totalGoldFS:Show()
    local tnw = totalNameFS:GetStringWidth() or 0
    local tgw = totalGoldFS:GetStringWidth() or 0
    if tnw > colWidths[1] then
        colWidths[1] = tnw
    end
    if tgw > colWidths[2] then
        colWidths[2] = tgw
    end

    for i = totalRow + 1, #_goldTTRows do
        _goldTTRows[i][0]:Hide()
        _goldTTRows[i][1]:Hide()
    end

    local titleTop = GOLD_PAD + (tt._title:GetStringHeight() or 14) + 6
    local col1X = GOLD_PAD
    local col2X = col1X + colWidths[1] + GOLD_COL_GAP
    local totalW = col2X + colWidths[2] + GOLD_PAD

    for r = 1, rowCount do
        local posY = -(titleTop + (r - 1) * GOLD_ROW_H)
        -- Add gap before total row
        if r == totalRow then
            posY = posY - 4
        end
        _goldTTRows[r][0]:ClearAllPoints()
        _goldTTRows[r][0]:SetPoint("TOPLEFT", tt, "TOPLEFT", col1X, posY)
        _goldTTRows[r][1]:ClearAllPoints()
        _goldTTRows[r][1]:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -GOLD_PAD, posY)
    end

    local lastRowY = titleTop + (rowCount - 1) * GOLD_ROW_H + 4 + GOLD_ROW_H + 6
    tt._hint:ClearAllPoints()
    tt._hint:SetPoint("TOPLEFT", tt, "TOPLEFT", GOLD_PAD, -lastRowY)
    local hintW = (tt._hint:GetStringWidth() or 0) + GOLD_PAD * 2
    if hintW > totalW then
        totalW = hintW
    end
    local totalH = lastRowY + (tt._hint:GetStringHeight() or 10) + GOLD_PAD

    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)

    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideGoldTooltip()
    if not _goldTT or not _goldTT:IsShown() then
        return
    end
    _goldTT._fadeInAG:Stop()
    _goldTT._fadeOutAG:Stop()
    _goldTT._fadeOut:SetFromAlpha(_goldTT:GetAlpha())
    _goldTT._fadeOut:SetToAlpha(0)
    _goldTT._fadeOutAG:Play()
end

local function PositionBagMoney(inset)
    local footer, money = CUI_Bags.Footer, CUI_Bags.Money
    if not money then
        return
    end
    money:ClearAllPoints()
    if footer._coinBox then
        money:SetPoint("RIGHT", footer._coinBox, "RIGHT", -inset, 0)
    else
        money:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -inset, 7)
    end
end

local function CreateFooter()
    if CUI_Bags.Footer then
        return
    end
    local footer = CreateFrame("Frame", nil, CUI_Bags)
    footer:SetPoint("BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    footer.bg = footer:CreateTexture(nil, "BACKGROUND", nil, 1)
    footer.bg:SetAllPoints()
    footer.bg:SetColorTexture(0, 0, 0, 0.35)

    -- Currency displays are created dynamically from Blizzard's tracked currencies
    if not CUI_Bags._currencyPool then
        CUI_Bags._currencyPool = { displays = {}, hitboxes = {} }
    end

    local money = CreateFrame("Frame", "CUI_BagMoneyFrame", footer, "SmallMoneyFrameTemplate")
    MoneyFrame_SetType(money, "PLAYER")

    for _, suffix in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
        local btn = _G["CUI_BagMoneyFrame" .. suffix]
        if btn then
            local txt = btn:GetFontString()
            if txt then
                SetBagFont(txt, 11)
            end
        end
    end

    -- Disable mouse on all SmallMoneyFrameTemplate children so our hitbox catches events
    for _, childFrame in pairs({ money:GetChildren() }) do
        childFrame:EnableMouse(false)
    end
    local moneyHitbox = CreateFrame("Frame", nil, footer)
    moneyHitbox:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT", 5, -5)
    moneyHitbox:SetPoint("TOPLEFT", money, "TOPLEFT", -5, 5)
    moneyHitbox:SetFrameLevel(money:GetFrameLevel() + 10)
    moneyHitbox:EnableMouse(true)

    moneyHitbox:SetScript("OnEnter", function(self)
        ShowGoldTooltip(self)
    end)
    moneyHitbox:SetScript("OnLeave", function()
        HideGoldTooltip()
    end)
    moneyHitbox:SetScript("OnMouseDown", function(self, btnFrame)
        if not GoldLedger.IsTracking() then
            return
        end
        if btnFrame == "RightButton" and IsControlKeyDown() then
            ResetAllGoldData()
            HideGoldTooltip()
            return
        end
    end)

    -- Top-edge separator (1px physical pixel)
    local Pix = CUI and CUI.PP
    local px = (Pix and Pix.mult) or 1
    local ftrSep = footer:CreateTexture(nil, "ARTWORK")
    ftrSep:SetHeight(px)
    ftrSep:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    ftrSep:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    ftrSep:SetColorTexture(0.15, 0.15, 0.15, 1)
    if mod.BagsForever() then
        mod.SkinForeverBagFooter(footer, footer.bg, ftrSep)
        money:SetHeight(16)
    end

    CUI_Bags.Footer, CUI_Bags.Money = footer, money
    PositionBagMoney(0)
end

local function UpdateCurrencyDisplays(footerWidth)
    local pool = CUI_Bags._currencyPool
    if not pool or not CUI_Bags.Footer then
        return FOOTER_H
    end
    local footer = CUI_Bags.Footer

    for _, d in ipairs(pool.displays) do
        d:Hide()
    end
    for _, hgt in ipairs(pool.hitboxes) do
        hgt:Hide()
    end

    -- Build tracked list from internal order table (decoupled from Blizzard)
    local tracked = {}
    local orderDB = CurrencyOrder()
    if orderDB and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        for cID, sequence in pairs(orderDB) do
            if type(sequence) == "number" then
                tracked[#tracked + 1] = { currencyTypesID = cID, order = sequence }
            end
        end
        table.sort(tracked, function(a, b)
            return a.order < b.order
        end)
    end

    for i = #pool.displays + 1, #tracked do
        local display = footer:CreateFontString(nil, "OVERLAY")
        SetBagFont(display, 11)
        display:SetTextColor(1, 1, 1)
        pool.displays[i] = display

        local hb = CreateFrame("Frame", nil, footer)
        hb:SetFrameLevel(footer:GetFrameLevel() + 5)
        hb:EnableMouse(true)
        hb:SetScript("OnEnter", function(self)
            if self._currencyID and GameTooltip.SetCurrencyByID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetCurrencyByID(self._currencyID)
            end
        end)
        hb:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        pool.hitboxes[i] = hb
    end

    local padding = 5
    local rowHeight = 14
    local rowGap = 8
    local bottomPad = 7
    local topPad = 7
    local coinBox = footer._coinBox
    local leftOffset = coinBox and 5 or 10
    local rightMargin = 180
    footerWidth = footerWidth or footer:GetWidth() or CUI_Bags:GetWidth() or 0
    if footerWidth <= 0 then
        footerWidth = CUI_Bags:GetWidth() or 400
    end
    local availableWidth = math.max(40, footerWidth - leftOffset - rightMargin)
    local currentRow = 0
    local currentX = leftOffset
    local currencyLayout = {}

    for i, details in ipairs(tracked) do
        local display = pool.displays[i]
        local fullInfo = C_CurrencyInfo.GetCurrencyInfo(details.currencyTypesID)
        local icon = fullInfo and fullInfo.iconFileID or details.iconFileID
        local quantity = fullInfo and fullInfo.quantity or 0
        local discovered = fullInfo and fullInfo.discovered
        local name = fullInfo and fullInfo.name or ""
        if icon and (discovered ~= false) then
            display:SetText("|T" .. tostring(icon) .. ":17:17:0:0:64:64:5:59:5:59|t " .. quantity)
            local itemWidth = display:GetStringWidth() + padding
            if currentX + itemWidth > leftOffset + availableWidth and currentX > leftOffset then
                currentRow = currentRow + 1
                currentX = leftOffset
            end
            currencyLayout[#currencyLayout + 1] = {
                idx = i,
                row = currentRow,
                x = currentX,
                currencyID = details.currencyTypesID,
            }
            currentX = currentX + itemWidth
        end
    end

    local numRows = math.max(1, currentRow + 1)
    local footerHeight =
        math.max(FOOTER_H, bottomPad + topPad + numRows * rowHeight + math.max(0, numRows - 1) * rowGap)

    for _, layout in ipairs(currencyLayout) do
        local display = pool.displays[layout.idx]
        display:ClearAllPoints()
        local rowFromBottom = numRows - 1 - layout.row
        local yPos = rowFromBottom * (rowHeight + rowGap)
        if coinBox then
            display:SetPoint("LEFT", coinBox, "LEFT", layout.x, yPos)
        else
            display:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", layout.x, bottomPad + yPos)
        end
        display:Show()

        local hb = pool.hitboxes[layout.idx]
        hb:ClearAllPoints()
        hb:SetPoint("TOPLEFT", display, "TOPLEFT", 0, 2)
        hb:SetPoint("BOTTOMRIGHT", display, "BOTTOMRIGHT", 0, -2)
        hb._currencyID = layout.currencyID
        hb:Show()
    end

    footer:SetHeight(footerHeight)
    CUI_Bags._footerH = footerHeight
    return footerHeight
end

-- Re-lay-out the currency footer and grow/shrink the bag frame by the height delta (grow-only running max under Auto-Size and on WoW Forever); reads the previous height BEFORE UpdateCurrencyDisplays stamps the new one.
local function SyncBagFrameToFooter()
    local prev = CUI_Bags._footerH or FOOTER_H
    local footerH = UpdateCurrencyDisplays() or FOOTER_H
    if footerH == prev then
        return
    end
    if not CUI_Bags:IsVisible() then
        return
    end
    local delta = footerH - prev
    if CUI_Bags.AutoSizeOn() or (CUI.IS_FOREVER and not BP().bagHeight) then
        CUI_Bags._asMaxH =
            math.max(CUI_Bags._asMaxH or CUI_Bags:GetHeight() or 0, CUI_Bags:GetHeight() + delta)
        CUI_Bags:SetHeight(CUI_Bags._asMaxH)
    elseif BP().bagHeight then
        -- Grip-set height is the whole window; the content area absorbs it
        return
    else
        CUI_Bags:SetHeight(CUI_Bags:GetHeight() + delta)
    end
end

-------------------------------------------------------------------------------
--  Reagent Bag UI
-------------------------------------------------------------------------------
local function CreateReagentBagUI()
    if CUI_BagsReagent.Header then
        return
    end
    local header = CreateFrame("Frame", nil, CUI_BagsReagent)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(35)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(0, 0, 0, 0.5)
    header.title = header:CreateFontString(nil, "OVERLAY")
    SetBagFont(header.title, 13)
    header.title:SetPoint("LEFT", 15, 0)
    header.title:SetText(CludesUI.L("REAGENTS"))
    header.title:SetTextColor(1, 1, 1)
    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -5, 0)
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
        CUI_BagsReagent:Hide()
    end)
    if mod.BagsForever() then
        mod.LayoutForeverBagHeader(header, 35)
        header.bg:Hide()
        mod.AddForeverBagPortrait(header, CUI.ClientIcon(3622222))
        mod.SkinForeverBagTitle(header.title)
        mod.PositionForeverBagClose(close)
    end
    -- Controller cursor: Cancel finds the close button.
    if CUI.PadCP() then
        CUI_BagsReagent.CloseButton = close
    end
    CUI_BagsReagent.Header = header
    local footer = CreateFrame("Frame", nil, CUI_BagsReagent)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_H)
    CUI_BagsReagent.Footer = footer
end

Inner.CreateFooter, Inner.CreateReagentBagUI = CreateFooter, CreateReagentBagUI
Inner.GoldLedger, Inner.OnGoldChanged = GoldLedger, OnGoldChanged
Inner.SyncBagFrameToFooter, Inner.UpdateBagMoneyDisplay = SyncBagFrameToFooter, UpdateBagMoneyDisplay
Inner.UpdateCurrencyDisplays = UpdateCurrencyDisplays
Inner.PositionBagMoney = PositionBagMoney
Inner.broken = false
