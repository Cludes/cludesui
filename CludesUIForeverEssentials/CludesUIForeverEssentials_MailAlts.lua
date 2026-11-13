if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_MailAlts.lua  (WoW Forever only)
--  Your characters on this realm and faction, remembered as you log in on
--  each, and what they carry:
--    Alt Item Counts   item tooltips show how many each character holds in
--                      bags, bank (once you open it) and mailbox.
--    Alts Button       beside the mailbox's Send tab: your characters with
--                      level and gold; pick one to fill the To box.
--    Quick Attach      beside it: attach every trade good, one type of trade
--                      good, or your unbound gear, up to the 12 slots.
--    Mail Expiry       at login, names characters with mail that expires
--                      within three days.
--  "Forget a character" removes a deleted or moved one.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("mailAlts", { altCounts = false, mailAlts = false, quickAttach = false, expiry = false })
local Get = F.Get

local SEND_SLOTS, MAIL_ATTACHMENTS = 12, 16
local DAY = 86400
local EXPIRY_WARN = 3 * DAY
local TRADE_GOODS = Enum.ItemClass.Tradegoods
local GEAR = { [Enum.ItemClass.Weapon] = true, [Enum.ItemClass.Armor] = true }

local function Say(text) CludesUI.Print("|cff4cc9f0Mail:|r " .. text) end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function ClassName(name, class)
    local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
    return c and c:WrapTextInColorCode(name) or name
end
local function Coins(copper) return C_CurrencyInfo.GetCoinTextureString(copper, 12) end

-------------------------------------------------------------------------------
--  Characters
-------------------------------------------------------------------------------
local realmKey, me
local function All() local c = F.Cfg(); c.alts = c.alts or {}; return c.alts end
local function Realm()
    realmKey = realmKey or ((GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or ""))
    All()[realmKey] = All()[realmKey] or {}
    return All()[realmKey]
end
-- Forever names have a surname: the key is the full name without the realm.
local function MyName()
    me = me or ((GetUnitName("player", true) or UnitName("player")):match("^[^-]+"))
    return me
end
local function Me()
    local realm, name, first = Realm(), MyName(), UnitName("player")
    local old = first ~= name and realm[first]
    if not realm[name] and old and old.class == select(2, UnitClass("player")) then realm[name], realm[first] = old, nil end
    realm[name] = realm[name] or {}
    realm[name].full = true
    return realm[name]
end

local function RosterOn() return Get("altCounts") or Get("mailAlts") or Get("expiry") end

local function UpdateRoster()
    local c = Me()
    c.class = select(2, UnitClass("player"))
    c.level = UnitLevel("player")
    c.money = GetMoney()
end

local here = ItemLocation:CreateEmpty()
local function Count(into, first, last)
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id then
                here:SetBagAndSlot(bag, slot)
                into[id] = (into[id] or 0) + C_Item.GetStackCount(here)
            end
        end
    end
    return into
end
local function Emptied(c, key) c[key] = {}; return c[key] end
local function ScanBags() Count(Emptied(Me(), "bags"), BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) end
-- Forever has the character bank tabs; an older client the bank and its bags.
local function ScanBank()
    local into = Emptied(Me(), "bank")
    local first, last = Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9
    if first and last then return Count(into, first, last) end
    if BANK_CONTAINER then Count(into, BANK_CONTAINER, BANK_CONTAINER) end
    if NUM_BAG_SLOTS and NUM_BANKBAGSLOTS then Count(into, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS) end
end

local mailPending
local function ScanMail()
    mailPending = nil
    if not RosterOn() then return end
    local shown, total = GetInboxNumItems()
    local items, soonest, now = {}, nil, time()
    for i = 1, shown do
        local _, _, _, _, _, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if daysLeft then
            local expires = now + math.floor(daysLeft * DAY)
            if not soonest or expires < soonest then soonest = expires end
        end
        if itemCount and itemCount > 0 then
            for a = 1, MAIL_ATTACHMENTS do
                local _, id, _, count = GetInboxItem(i, a)
                if id then items[id] = (items[id] or 0) + (count or 1) end
            end
        end
    end
    local c = Me()
    c.mail, c.mailCount, c.mailExpires = items, total or shown, soonest
end

local bankOpen
local rEv = CreateFrame("Frame")
rEv:SetScript("OnEvent", function(_, event, arg)
    if event == "BAG_UPDATE_DELAYED" then
        if Get("altCounts") then ScanBags() end
        if bankOpen then ScanBank() end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        ScanBank()
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = nil
    elseif event == "MAIL_INBOX_UPDATE" then
        if not mailPending then mailPending = true; C_Timer.After(1, ScanMail) end
    elseif event == "PLAYER_LEVEL_UP" then
        Me().level = arg
    else
        UpdateRoster()
    end
end)

local function RosterApply()
    rEv:UnregisterAllEvents()
    if RosterOn() then
        UpdateRoster()
        for _, e in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "MAIL_INBOX_UPDATE" }) do rEv:RegisterEvent(e) end
    end
    if Get("altCounts") then
        ScanBags()
        for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do rEv:RegisterEvent(e) end
    end
end

local function AltList()
    local list, mine = {}, MyName()
    for name, c in pairs(Realm()) do
        if name ~= mine then
            list[#list + 1] = { name = name, class = c.class, level = c.level or 0, money = c.money or 0, full = c.full == true }
        end
    end
    table.sort(list, function(a, b) if a.level ~= b.level then return a.level > b.level end return a.name < b.name end)
    return list
end

-- Alt Item Counts on item tooltips.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not Get("altCounts") then return end
        local id = data and data.id
        if not id or Secret(id) then return end
        local rows, total, elsewhere, mine = {}, 0, false, MyName()
        for name, c in pairs(Realm()) do
            local bags, bank, mail = c.bags and c.bags[id] or 0, c.bank and c.bank[id] or 0, c.mail and c.mail[id] or 0
            local count = bags + bank + mail
            if count > 0 then
                total = total + count
                if name ~= mine or bank > 0 or mail > 0 then elsewhere = true end
                local parts = {}
                if bags > 0 then parts[#parts + 1] = bags .. " bags" end
                if bank > 0 then parts[#parts + 1] = bank .. " bank" end
                if mail > 0 then parts[#parts + 1] = mail .. " mail" end
                rows[#rows + 1] = { name = name, class = c.class, count = count, text = table.concat(parts, ", ") }
            end
        end
        if not elsewhere then return end
        table.sort(rows, function(a, b) return a.count > b.count end)
        tooltip:AddDoubleLine("Total owned", total, 1, 1, 1, 1, 1, 1)
        for i = 1, math.min(#rows, 8) do
            tooltip:AddDoubleLine("  " .. ClassName(rows[i].name, rows[i].class), rows[i].text, 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end)
end

-------------------------------------------------------------------------------
--  Mailbox buttons
-------------------------------------------------------------------------------
local altsButton, attachButton
local qBag, qSlot, qItem = {}, {}, {}
local qHead, qCount = 1, 0
local pendingSlot, pendingItem, pendingBag, pendingBagSlot
local clicking = false
local mEv = CreateFrame("Frame")

local function Menu(owner, fill)
    if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(owner, fill) end
end

local function OpenAltsMenu(owner)
    local list = AltList()
    local total = GetMoney()
    for _, alt in ipairs(list) do total = total + alt.money end
    Menu(owner, function(_, root)
        root:CreateTitle("Gold on this realm: " .. Coins(total))
        if #list == 0 then root:CreateTitle("Log in on your other characters once and they appear here.", WHITE_FONT_COLOR) return end
        local firstOnly = false
        for _, alt in ipairs(list) do
            root:CreateButton(("%s  |cff808080%d|r  %s"):format(ClassName(alt.name, alt.class), alt.level, Coins(alt.money)), function()
                SendMailNameEditBox:SetText(alt.name)
                SendMailSubjectEditBox:SetFocus()
            end)
            if not alt.full then firstOnly = true end
        end
        if firstOnly then root:CreateTitle("A name without its last name gets it the next time you log in on that character.", GRAY_FONT_COLOR) end
    end)
end

local function FreeSlot()
    for i = 1, SEND_SLOTS do if not HasSendMailItem(i) then return i end end
end

local function StopAttaching()
    qHead, qCount = 1, 0
    pendingSlot, pendingItem, pendingBag, pendingBagSlot = nil, nil, nil, nil
    clicking = false
    mEv:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
    mEv:UnregisterEvent("MAIL_SEND_SUCCESS")
end

local function Mailable(bag, slot)
    local id = C_Container.GetContainerItemID(bag, slot)
    if not id then return end
    local _, _, subType, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
    if classID ~= TRADE_GOODS and not GEAR[classID] then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isBound or info.isLocked or info.itemID ~= id then return end
    if GEAR[classID] and (info.quality or 0) < Enum.ItemQuality.Uncommon then return end
    return id, classID, subClassID or -1, subType
end

local function Matches(key, classID, subClassID)
    if key == "gear" then return GEAR[classID] end
    return classID == TRADE_GOODS and (key == "all" or key == subClassID)
end

local function OnCursor(id)
    local kind, cursorID = GetCursorInfo()
    return kind == "item" and cursorID == id, kind
end

local function StillPending()
    if HasSendMailItem(pendingSlot) and select(2, GetSendMailItem(pendingSlot)) == pendingItem then
        pendingSlot = nil
        return false
    end
    local info = C_Container.GetContainerItemInfo(pendingBag, pendingBagSlot)
    if not GetCursorInfo() and not (info and info.isLocked) then StopAttaching() end
    return true
end

-- One item per mail-slot update: the game takes a moment to place each.
local function AttachNext()
    if clicking then return end
    while true do
        if pendingSlot and StillPending() then return end
        if qHead > qCount or GetCursorInfo() then StopAttaching() return end
        local slot = FreeSlot()
        if not slot then
            local left = qCount - qHead + 1
            Say(("%d stack%s didn't fit, all %d attachment slots are full. Send this one and attach again."):format(left, left == 1 and "" or "s", SEND_SLOTS))
            StopAttaching()
            return
        end
        local bag, bagSlot, id = qBag[qHead], qSlot[qHead], qItem[qHead]
        qHead = qHead + 1
        local info = C_Container.GetContainerItemInfo(bag, bagSlot)
        if info and info.itemID == id and not info.isLocked and not info.isBound then
            C_Container.PickupContainerItem(bag, bagSlot)
            local held, kind = OnCursor(id)
            if not held then if kind then ClearCursor() end StopAttaching() return end
            pendingSlot, pendingItem, pendingBag, pendingBagSlot = slot, id, bag, bagSlot
            clicking = true
            ClickSendMailItemButton(slot)
            clicking = false
            if OnCursor(id) then ClearCursor(); StopAttaching() return end
        end
    end
end

local function Attach(key)
    StopAttaching()
    local n = 0
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id, classID, subClassID = Mailable(bag, slot)
            if id and Matches(key, classID, subClassID) then
                n = n + 1
                qBag[n], qSlot[n], qItem[n] = bag, slot, id
            end
        end
    end
    if n == 0 then return end
    qHead, qCount = 1, n
    mEv:RegisterEvent("MAIL_SEND_INFO_UPDATE")
    mEv:RegisterEvent("MAIL_SEND_SUCCESS")
    AttachNext()
end

local function OpenAttachMenu(owner)
    local counts, labels, order = {}, {}, {}
    local function Tally(key, label)
        if not counts[key] then counts[key], labels[key] = 0, label; order[#order + 1] = key end
        counts[key] = counts[key] + 1
    end
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id, classID, subClassID, subType = Mailable(bag, slot)
            if id then
                if classID == TRADE_GOODS then
                    Tally("all", "All trade goods")
                    Tally(subClassID, subType or "Other trade goods")
                else
                    Tally("gear", "Unbound gear")
                end
            end
        end
    end
    Menu(owner, function(_, root)
        root:CreateTitle("Attach from your bags")
        if #order == 0 then root:CreateTitle("No trade goods or unbound gear in your bags.", WHITE_FONT_COLOR) return end
        for _, key in ipairs(order) do
            local n = counts[key]
            root:CreateButton(("%s (%d stack%s)"):format(labels[key], n, n == 1 and "" or "s"), function() Attach(key) end)
        end
    end)
end

local function MailButton(text, tip, fn)
    local b = CreateFrame("Button", nil, SendMailFrame, "UIPanelButtonTemplate")
    b:SetSize(64, 22)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function BuildButtons()
    if altsButton or not (SendMailFrame and MailFrame) then return end
    altsButton = MailButton("Alts", "Your characters on this realm and faction with their level and gold. Pick one to fill the To box.",
        function(self) OpenAltsMenu(self) end)
    altsButton:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    attachButton = MailButton("Attach", "Attach every trade good, one type of trade good, or your unbound gear from your bags, up to the 12 attachment slots.",
        function(self) OpenAttachMenu(self) end)
end

local function PlaceButtons()
    if not altsButton then return end
    altsButton:SetShown(Get("mailAlts"))
    attachButton:ClearAllPoints()
    if altsButton:IsShown() then attachButton:SetPoint("TOPLEFT", altsButton, "BOTTOMLEFT", 0, -4)
    else attachButton:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30) end
    attachButton:SetShown(Get("quickAttach"))
end

local function WarnExpiring()
    local now, soon = time(), {}
    for _, realm in pairs(All()) do
        for name, c in pairs(realm) do
            if c.mailExpires and (c.mailCount or 0) > 0 and c.mailExpires - now < EXPIRY_WARN then
                local left = c.mailExpires - now
                local when = left <= 0 and "may have expired" or (left < DAY and "less than a day" or (math.floor(left / DAY) .. "d"))
                soon[#soon + 1] = ClassName(name, c.class) .. " (" .. when .. ")"
            end
        end
    end
    if #soon > 0 then Say("mail expiring soon on " .. table.concat(soon, ", ") .. ". Open the mailbox on those characters to keep it.") end
end

mEv:SetScript("OnEvent", function(_, event, isLogin)
    if event == "MAIL_SEND_INFO_UPDATE" then AttachNext()
    elseif event == "MAIL_SHOW" then BuildButtons(); PlaceButtons()
    elseif event == "MAIL_CLOSED" or event == "MAIL_SEND_SUCCESS" then StopAttaching()
    elseif event == "PLAYER_ENTERING_WORLD" then
        mEv:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if isLogin and Get("expiry") then C_Timer.After(5, WarnExpiring) end
    end
end)

local function Apply()
    RosterApply()
    if Get("mailAlts") or Get("quickAttach") then
        BuildButtons()
        mEv:RegisterEvent("MAIL_SHOW")
        mEv:RegisterEvent("MAIL_CLOSED")
    else
        StopAttaching()
        mEv:UnregisterEvent("MAIL_SHOW")
        mEv:UnregisterEvent("MAIL_CLOSED")
    end
    PlaceButtons()
end

--- Forget menu for the options page.
local function ForgetMenu(owner)
    owner = owner or (GetMouseFoci and GetMouseFoci()[1]) or UIParent
    Menu(owner, function(_, root)
        root:CreateTitle("Forget a character")
        local any
        for realm, chars in pairs(All()) do
            for name, c in pairs(chars) do
                any = true
                root:CreateButton(ClassName(name, c.class) .. "  |cff808080" .. realm .. "|r", function()
                    chars[name] = nil
                    if not next(chars) then All()[realm] = nil end
                    Say("forgot " .. name .. ". It comes back the next time you log in on it.")
                end)
            end
        end
        if not any then root:CreateTitle("No characters recorded yet.", WHITE_FONT_COLOR) end
    end)
end

CludesUI._MailAlts = { Get = Get, Cfg = F.Cfg, Apply = Apply, Forget = ForgetMenu }

F.Start(function()
    Apply()
    if Get("expiry") then mEv:RegisterEvent("PLAYER_ENTERING_WORLD") end
end)
