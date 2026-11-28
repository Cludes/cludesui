if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
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

local F =
    module.Feature("mailAlts", { altCounts = false, mailAlts = false, quickAttach = false, expiry = false })
local Get = F.Get

local SEND_SLOTS, MAIL_ATTACHMENTS = 12, 16
local DAILY = 86400
local EXPIRY_CAUTION = 3 * DAILY
local TRADE_GOODS = Enum.ItemClass.Tradegoods
local GEAR = { [Enum.ItemClass.Weapon] = true, [Enum.ItemClass.Armor] = true }

local function Say(labelValue) CUI.Print("|cff4cc9f0Mail:|r " .. labelValue) end
local function Secret(val) return issecretvalue and issecretvalue(val) end
local function CallingTitle(title, calling)
    local tint = calling and C_ClassColor and C_ClassColor.GetClassColor(calling)
    return tint and tint:WrapTextInColorCode(title) or title
end
local function Coins(copper) return C_CurrencyInfo.GetCoinTextureString(copper, 12) end

-------------------------------------------------------------------------------
--  Characters
-------------------------------------------------------------------------------
local realmId, me
local function All()
    local cfg = F.Cfg()
    cfg.alts = cfg.alts or {}
    return cfg.alts
end
local function Realm()
    realmId = realmId or ((GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or ""))
    All()[realmId] = All()[realmId] or {}
    return All()[realmId]
end
-- Forever names have a surname: the key is the full name without the realm.
local function MyTitle()
    me = me or ((GetUnitName("player", true) or UnitName("player")):match("^[^-]+"))
    return me
end
local function Me()
    local realm, title, first = Realm(), MyTitle(), UnitName("player")
    local old = first ~= title and realm[first]
    if not realm[title] and old and old.class == select(2, UnitClass("player")) then
        realm[title], realm[first] = old, nil
    end
    realm[title] = realm[title] or {}
    realm[title].full = true
    return realm[title]
end

local function RosterOn() return Get("altCounts") or Get("mailAlts") or Get("expiry") end

local function RefreshRoster()
    local c = Me()
    c.class = select(2, UnitClass("player"))
    c.level = UnitLevel("player")
    c.money = GetMoney()
end

local here = ItemLocation:CreateEmpty()
local function Count(into, first, last)
    for bag = first, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ident = C_Container.GetContainerItemID(bag, slot)
            if ident then
                here:SetBagAndSlot(bag, slot)
                into[ident] = (into[ident] or 0) + C_Item.GetStackCount(here)
            end
        end
    end
    return into
end
local function Emptied(cfg, key)
    cfg[key] = {}
    return cfg[key]
end
local function SweepBags()
    Count(Emptied(Me(), "bags"), BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS)
end
-- Forever has the character bank tabs; an older client the bank and its bags.
local function SweepBank()
    local into = Emptied(Me(), "bank")
    local first, last = Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9
    if first and last then return Count(into, first, last) end
    if BANK_CONTAINER then Count(into, BANK_CONTAINER, BANK_CONTAINER) end
    if NUM_BAG_SLOTS and NUM_BANKBAGSLOTS then
        Count(into, NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS)
    end
end

local mailPending
local function SweepMail()
    mailPending = nil
    if not RosterOn() then return end
    local isShown, sum = GetInboxNumItems()
    local thingRoster, soonest, nowTime = {}, nil, time()
    for catalog = 1, isShown do
        local _, _, _, _, _, _, daysLeft, thingTally = GetInboxHeaderInfo(catalog)
        if daysLeft then
            local expires = nowTime + math.floor(daysLeft * DAILY)
            if not soonest or expires < soonest then soonest = expires end
        end
        if thingTally and thingTally > 0 then
            for a = 1, MAIL_ATTACHMENTS do
                local _, ident, _, tally = GetInboxItem(catalog, a)
                if ident then thingRoster[ident] = (thingRoster[ident] or 0) + (tally or 1) end
            end
        end
    end
    local c = Me()
    c.mail, c.mailCount, c.mailExpires = thingRoster, sum or isShown, soonest
end

local bankReveal
local rEv = CreateFrame("Frame")
rEv:SetScript("OnEvent", function(_, evt, arg)
    if evt == "BAG_UPDATE_DELAYED" then
        if Get("altCounts") then SweepBags() end
        if bankReveal then SweepBank() end
    elseif evt == "BANKFRAME_OPENED" then
        bankReveal = true
        SweepBank()
    elseif evt == "BANKFRAME_CLOSED" then
        bankReveal = nil
    elseif evt == "MAIL_INBOX_UPDATE" then
        if not mailPending then
            mailPending = true
            C_Timer.After(1, SweepMail)
        end
    elseif evt == "PLAYER_LEVEL_UP" then
        Me().level = arg
    else
        RefreshRoster()
    end
end)

local function RosterUse()
    rEv:UnregisterAllEvents()
    if RosterOn() then
        RefreshRoster()
        for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "MAIL_INBOX_UPDATE" }) do
            rEv:RegisterEvent(event)
        end
    end
    if Get("altCounts") then
        SweepBags()
        for _, event in ipairs({ "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }) do
            rEv:RegisterEvent(event)
        end
    end
end

local function AltRoster()
    local items, mine = {}, MyTitle()
    for title, c in pairs(Realm()) do
        if title ~= mine then
            items[#items + 1] = {
                name = title,
                class = c.class,
                level = c.level or 0,
                money = c.money or 0,
                full = c.full == true,
            }
        end
    end
    table.sort(items, function(lhs, rhs)
        if lhs.level ~= rhs.level then return lhs.level > rhs.level end
        return lhs.name < rhs.name
    end)
    return items
end

-- Alt Item Counts on item tooltips.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not Get("altCounts") then return end
        local ident = payload and payload.id
        if not ident or Secret(ident) then return end
        local lineRoster, sum, elsewhere, mine = {}, 0, false, MyTitle()
        for title, c in pairs(Realm()) do
            local bags, bank, mail =
                c.bags and c.bags[ident] or 0, c.bank and c.bank[ident] or 0, c.mail and c.mail[ident] or 0
            local tally = bags + bank + mail
            if tally > 0 then
                sum = sum + tally
                if title ~= mine or bank > 0 or mail > 0 then elsewhere = true end
                local parts = {}
                if bags > 0 then parts[#parts + 1] = bags .. " bags" end
                if bank > 0 then parts[#parts + 1] = bank .. " bank" end
                if mail > 0 then parts[#parts + 1] = mail .. " mail" end
                lineRoster[#lineRoster + 1] =
                    { name = title, class = c.class, count = tally, text = table.concat(parts, ", ") }
            end
        end
        if not elsewhere then return end
        table.sort(lineRoster, function(lhs, rhs) return lhs.count > rhs.count end)
        tooltip:AddDoubleLine("Total owned", sum, 1, 1, 1, 1, 1, 1)
        for catalog = 1, math.min(#lineRoster, 8) do
            tooltip:AddDoubleLine(
                "  " .. CallingTitle(lineRoster[catalog].name, lineRoster[catalog].class),
                lineRoster[catalog].text,
                1,
                1,
                1,
                0.8,
                0.8,
                0.8
            )
        end
    end)
end

-------------------------------------------------------------------------------
--  Mailbox buttons
-------------------------------------------------------------------------------
local altsBtn, attachBtn
local qBag, qSlot, qThing = {}, {}, {}
local qHead, qTally = 1, 0
local pendingSlot, pendingThing, pendingBag, pendingBagSlot
local clicking = false
local mEv = CreateFrame("Frame")

local function Menu(ownerWindow, fillTex) CUI.Kit.ContextMenu(ownerWindow, fillTex) end

local function RevealAltsMenu(ownerWindow)
    local items = AltRoster()
    local sum = GetMoney()
    for _, alt in ipairs(items) do
        sum = sum + alt.money
    end
    Menu(ownerWindow, function(_, root)
        root:CreateTitle("Gold on this realm: " .. Coins(sum))
        if #items == 0 then
            root:CreateTitle("Log in on your other characters once and they appear here.", WHITE_FONT_COLOR)
            return
        end
        local firstOnly = false
        for _, alt in ipairs(items) do
            root:CreateButton(
                ("%s  |cff808080%d|r  %s"):format(CallingTitle(alt.name, alt.class), alt.level, Coins(alt.money)),
                function()
                    SendMailNameEditBox:SetText(alt.name)
                    SendMailSubjectEditBox:SetFocus()
                end
            )
            if not alt.full then firstOnly = true end
        end
        if firstOnly then
            root:CreateTitle(
                "A name without its last name gets it the next time you log in on that character.",
                GRAY_FONT_COLOR
            )
        end
    end)
end

local function FreeSlot()
    for catalog = 1, SEND_SLOTS do
        if not HasSendMailItem(catalog) then return catalog end
    end
end

local function HaltAttaching()
    qHead, qTally = 1, 0
    pendingSlot, pendingThing, pendingBag, pendingBagSlot = nil, nil, nil, nil
    clicking = false
    mEv:UnregisterEvent("MAIL_SEND_INFO_UPDATE")
    mEv:UnregisterEvent("MAIL_SEND_SUCCESS")
end

local function Mailable(bag, slot)
    local ident = C_Container.GetContainerItemID(bag, slot)
    if not ident then return end
    local _, _, subType, _, _, callingID, subCallingID = C_Item.GetItemInfoInstant(ident)
    if callingID ~= TRADE_GOODS and not GEAR[callingID] then return end
    local details = C_Container.GetContainerItemInfo(bag, slot)
    if not details or details.isBound or details.isLocked or details.itemID ~= ident then return end
    if GEAR[callingID] and (details.quality or 0) < Enum.ItemQuality.Uncommon then return end
    return ident, callingID, subCallingID or -1, subType
end

local function Fits(key, callingID, subCallingID)
    if key == "gear" then return GEAR[callingID] end
    return callingID == TRADE_GOODS and (key == "all" or key == subCallingID)
end

local function OnCursor(ident)
    local kind, cursorID = GetCursorInfo()
    return kind == "item" and cursorID == ident, kind
end

local function StillPending()
    if HasSendMailItem(pendingSlot) and select(2, GetSendMailItem(pendingSlot)) == pendingThing then
        pendingSlot = nil
        return false
    end
    local details = C_Container.GetContainerItemInfo(pendingBag, pendingBagSlot)
    if not GetCursorInfo() and not (details and details.isLocked) then HaltAttaching() end
    return true
end

-- One item per mail-slot update: the game takes a moment to place each.
local function AttachNext()
    if clicking then return end
    while true do
        if pendingSlot and StillPending() then return end
        if qHead > qTally or GetCursorInfo() then
            HaltAttaching()
            return
        end
        local slot = FreeSlot()
        if not slot then
            local leftX = qTally - qHead + 1
            Say(
                ("%d stack%s didn't fit, all %d attachment slots are full. Send this one and attach again."):format(
                    leftX,
                    leftX == 1 and "" or "s",
                    SEND_SLOTS
                )
            )
            HaltAttaching()
            return
        end
        local bag, bagSlot, ident = qBag[qHead], qSlot[qHead], qThing[qHead]
        qHead = qHead + 1
        local details = C_Container.GetContainerItemInfo(bag, bagSlot)
        if details and details.itemID == ident and not details.isLocked and not details.isBound then
            C_Container.PickupContainerItem(bag, bagSlot)
            local kept, kind = OnCursor(ident)
            if not kept then
                if kind then ClearCursor() end
                HaltAttaching()
                return
            end
            pendingSlot, pendingThing, pendingBag, pendingBagSlot = slot, ident, bag, bagSlot
            clicking = true
            ClickSendMailItemButton(slot)
            clicking = false
            if OnCursor(ident) then
                ClearCursor()
                HaltAttaching()
                return
            end
        end
    end
end

local function Attach(key)
    HaltAttaching()
    local num = 0
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ident, callingID, subCallingID = Mailable(bag, slot)
            if ident and Fits(key, callingID, subCallingID) then
                num = num + 1
                qBag[num], qSlot[num], qThing[num] = bag, slot, ident
            end
        end
    end
    if num == 0 then return end
    qHead, qTally = 1, num
    mEv:RegisterEvent("MAIL_SEND_INFO_UPDATE")
    mEv:RegisterEvent("MAIL_SEND_SUCCESS")
    AttachNext()
end

local function RevealAttachMenu(ownerWindow)
    local tallies, labels, sequence = {}, {}, {}
    local function Tally(key, labelLabel)
        if not tallies[key] then
            tallies[key], labels[key] = 0, labelLabel
            sequence[#sequence + 1] = key
        end
        tallies[key] = tallies[key] + 1
    end
    for bag = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ident, callingID, subCallingID, subType = Mailable(bag, slot)
            if ident then
                if callingID == TRADE_GOODS then
                    Tally("all", "All trade goods")
                    Tally(subCallingID, subType or "Other trade goods")
                else
                    Tally("gear", "Unbound gear")
                end
            end
        end
    end
    Menu(ownerWindow, function(_, root)
        root:CreateTitle("Attach from your bags")
        if #sequence == 0 then
            root:CreateTitle("No trade goods or unbound gear in your bags.", WHITE_FONT_COLOR)
            return
        end
        for _, key in ipairs(sequence) do
            local num = tallies[key]
            root:CreateButton(
                ("%s (%d stack%s)"):format(labels[key], num, num == 1 and "" or "s"),
                function() Attach(key) end
            )
        end
    end)
end

local function MailBtn(labelValue, hintLabel, func)
    local b =
        CUI.Kit.Button(SendMailFrame, labelValue, 64, 22, func, { key = "essentials", tip = hintLabel })
    return b
end

local function MakeButtons()
    if altsBtn or not (SendMailFrame and MailFrame) then return end
    altsBtn = MailBtn(
        "Alts",
        "Your characters on this realm and faction with their level and gold. Pick one to fill the To box.",
        function(self) RevealAltsMenu(self) end
    )
    altsBtn:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    attachBtn = MailBtn(
        "Attach",
        "Attach every trade good, one type of trade good, or your unbound gear from your bags, up to the 12 attachment slots.",
        function(self) RevealAttachMenu(self) end
    )
end

local function PlaceButtons()
    if not altsBtn then return end
    altsBtn:SetShown(Get("mailAlts"))
    attachBtn:ClearAllPoints()
    if altsBtn:IsShown() then
        attachBtn:SetPoint("TOPLEFT", altsBtn, "BOTTOMLEFT", 0, -4)
    else
        attachBtn:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    end
    attachBtn:SetShown(Get("quickAttach"))
end

local function CautionExpiring()
    local nowTime, soon = time(), {}
    for _, realm in pairs(All()) do
        for title, c in pairs(realm) do
            if c.mailExpires and (c.mailCount or 0) > 0 and c.mailExpires - nowTime < EXPIRY_CAUTION then
                local leftX = c.mailExpires - nowTime
                local when = leftX <= 0 and "may have expired"
                    or (leftX < DAILY and "less than a day" or (math.floor(leftX / DAILY) .. "d"))
                soon[#soon + 1] = CallingTitle(title, c.class) .. " (" .. when .. ")"
            end
        end
    end
    if #soon > 0 then
        Say(
            "mail expiring soon on "
                .. table.concat(soon, ", ")
                .. ". Open the mailbox on those characters to keep it."
        )
    end
end

mEv:SetScript("OnEvent", function(_, evt, isLogin)
    if evt == "MAIL_SEND_INFO_UPDATE" then
        AttachNext()
    elseif evt == "MAIL_SHOW" then
        MakeButtons()
        PlaceButtons()
    elseif evt == "MAIL_CLOSED" or evt == "MAIL_SEND_SUCCESS" then
        HaltAttaching()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        mEv:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if isLogin and Get("expiry") then C_Timer.After(5, CautionExpiring) end
    end
end)

local function Apply()
    RosterUse()
    if Get("mailAlts") or Get("quickAttach") then
        MakeButtons()
        mEv:RegisterEvent("MAIL_SHOW")
        mEv:RegisterEvent("MAIL_CLOSED")
    else
        HaltAttaching()
        mEv:UnregisterEvent("MAIL_SHOW")
        mEv:UnregisterEvent("MAIL_CLOSED")
    end
    PlaceButtons()
end

--- Forget menu for the options page.
local function ForgetMenu(ownerWindow)
    ownerWindow = ownerWindow or (GetMouseFoci and GetMouseFoci()[1]) or UIParent
    Menu(ownerWindow, function(_, root)
        root:CreateTitle("Forget a character")
        local any
        for realm, chars in pairs(All()) do
            for title, c in pairs(chars) do
                any = true
                root:CreateButton(CallingTitle(title, c.class) .. "  |cff808080" .. realm .. "|r", function()
                    chars[title] = nil
                    if not next(chars) then All()[realm] = nil end
                    Say("forgot " .. title .. ". It comes back the next time you log in on it.")
                end)
            end
        end
        if not any then root:CreateTitle("No characters recorded yet.", WHITE_FONT_COLOR) end
    end)
end

CUI._MailAlts = { Get = Get, Cfg = F.Cfg, Apply = Apply, Forget = ForgetMenu }

F.Start(function()
    Apply()
    if Get("expiry") then mEv:RegisterEvent("PLAYER_ENTERING_WORLD") end
end)
