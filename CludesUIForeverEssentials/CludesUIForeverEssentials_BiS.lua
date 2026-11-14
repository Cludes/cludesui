if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_BiS.lua  (WoW Forever only)
--  Best in Slot: your own BiS list, one item per gear slot, shared by every
--  character of your class on the account.
--    Add an item     Alt+Shift-click it anywhere (bags, chat, the loot window,
--                    the dungeon journal), or paste a link or item ID in the
--                    window. It goes in the slot it is worn in; a ring or a
--                    trinket fills the first of the two that is free.
--    Remove          Alt+Shift-click it again, or right-click its row.
--    The window      /cbis: every slot with its pick and whether you have it
--                    (worn, in your bags or in the bank).
--    Tooltips        a BiS item says so on its tooltip, with its slot.
--    Drop Alert      when a BiS item you do not have yet drops (a roll, the
--                    loot window, or someone looting it), a warning on screen,
--                    a sound and a chat line.
--    Sharing         export your list as a line, import one.
--  The picks are yours: no ranking is built in.
-------------------------------------------------------------------------------
local _, module = ...

local F = module.Feature("bis", { enabled = true, tooltip = true, alert = true })
local Get = F.Get

local function Say(textValue)
    CludesUI.Print("|cff4cc9f0BiS:|r " .. textValue)
end
local function Font()
    return CludesUI.GetFontPath("essentials")
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end

local SLOTS = { -- inventory slot, name, in window order
    { 1, "Head" },
    { 2, "Neck" },
    { 3, "Shoulders" },
    { 15, "Back" },
    { 5, "Chest" },
    { 9, "Wrist" },
    { 10, "Hands" },
    { 6, "Waist" },
    { 7, "Legs" },
    { 8, "Feet" },
    { 11, "Ring" },
    { 12, "Ring" },
    { 13, "Trinket" },
    { 14, "Trinket" },
    { 16, "Main Hand" },
    { 17, "Off Hand" },
    { 18, "Ranged" },
}
local SLOT_NAME = {}
for _, s in ipairs(SLOTS) do
    SLOT_NAME[s[1]] = s[2]
end

local BY_EQUIP = {
    INVTYPE_HEAD = { 1 },
    INVTYPE_NECK = { 2 },
    INVTYPE_SHOULDER = { 3 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 },
    INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 },
    INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}

module.BIS_EQUIP_SLOTS = BY_EQUIP

local _, CLASS = UnitClass("player")

-- lists[class] = { [invSlot] = itemID }
local function List()
    local c = F.Cfg()
    c.lists = c.lists or {}
    c.lists[CLASS] = c.lists[CLASS] or {}
    return c.lists[CLASS]
end

local Refresh -- the window's repaint, set below

local function IDFrom(val)
    if type(val) == "number" then
        return val
    end
    if type(val) ~= "string" then
        return nil
    end
    return tonumber(val:match("item:(%d+)") or val:match("^%s*(%d+)%s*$"))
end

--- The slot this item has on the list, if any.
function module.BisSlotOf(itemId)
    for slotIndex, ident in pairs(List()) do
        if ident == itemId then
            return slotIndex
        end
    end
end

function module.Owned(itemId)
    return C_Item.IsEquippedItem(itemId) or (C_Item.GetItemCount(itemId, true) or 0) > 0
end

--- Adds an item to its slot (or takes it off when it is already listed).
function module.ToggleBis(itemLink)
    local ident = IDFrom(itemLink)
    if not ident then
        return Say("that is not an item.")
    end
    local slotIndex = module.BisSlotOf(ident)
    if slotIndex then
        List()[slotIndex] = nil
        Say(("took %s off your list."):format(select(2, C_Item.GetItemInfo(ident)) or ("item " .. ident)))
        if Refresh then
            Refresh()
        end
        return
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(ident)
    local slots = BY_EQUIP[equipLoc or ""]
    if not slots then
        return Say("that item is not gear.")
    end
    local targetUnit = slots[1]
    for _, s in ipairs(slots) do
        if not List()[s] then
            targetUnit = s
            break
        end
    end
    List()[targetUnit] = ident
    Say(
        ("%s is your BiS for %s."):format(
            select(2, C_Item.GetItemInfo(ident)) or ("item " .. ident),
            SLOT_NAME[targetUnit]
        )
    )
    if Refresh then
        Refresh()
    end
end

function module.ExportBis()
    local parts = {}
    for _, s in ipairs(SLOTS) do
        local ident = List()[s[1]]
        if ident then
            parts[#parts + 1] = s[1] .. "=" .. ident
        end
    end
    return "CUIBIS1:" .. CLASS .. ":" .. table.concat(parts, ",")
end

function module.ImportBis(textValue)
    local classFile, body = (textValue or ""):match("^%s*CUIBIS1:(%u+):([%d=,]*)%s*$")
    if not classFile then
        return Say("that is not a CludesUI BiS line.")
    end
    if classFile ~= CLASS then
        return Say("that list is for another class.")
    end
    local entries, num = {}, 0
    for slotIndex, ident in body:gmatch("(%d+)=(%d+)") do
        slotIndex, ident = tonumber(slotIndex), tonumber(ident)
        if SLOT_NAME[slotIndex] then
            entries[slotIndex] = ident
            num = num + 1
        end
    end
    F.Cfg().lists[CLASS] = entries
    Say(("imported %d pick%s."):format(num, num == 1 and "" or "s"))
    if Refresh then
        Refresh()
    end
end

-------------------------------------------------------------------------------
--  Alt+Shift-click
-------------------------------------------------------------------------------
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(itemLink)
        if not (Get("enabled") and IsAltKeyDown() and IsShiftKeyDown()) then
            return
        end
        if type(itemLink) ~= "string" or Secret(itemLink) or not itemLink:find("item:") then
            return
        end
        module.ToggleBis(itemLink)
    end)
end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, payload)
        if not (Get("enabled") and Get("tooltip")) or not payload then
            return
        end
        local ident = payload.id
        if type(ident) ~= "number" or Secret(ident) then
            return
        end
        local slotIndex = module.BisSlotOf(ident)
        if slotIndex then
            tooltip:AddLine(
                ("|cffff9933*|r %sBiS for %s|r%s"):format(
                    CludesUI.Kit.AccentHex(),
                    SLOT_NAME[slotIndex],
                    module.Owned(ident) and "  |cff60d080(yours)|r" or ""
                )
            )
        end
    end)
end

-------------------------------------------------------------------------------
--  Drop Alert
-------------------------------------------------------------------------------
local said = {}
local function Announce(itemLink)
    if not (Get("enabled") and Get("alert")) then
        return
    end
    local ident = IDFrom(itemLink)
    if not ident or module.Owned(ident) then
        return
    end
    local slotIndex = module.BisSlotOf(ident)
    if not slotIndex then
        return
    end
    if said[ident] and GetTime() - said[ident] < 30 then
        return
    end
    said[ident] = GetTime()
    local textValue = ("BiS dropped: %s (%s)"):format(itemLink, SLOT_NAME[slotIndex])
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(
            RaidWarningFrame,
            textValue,
            ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.6, b = 0.2 }
        )
    end
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    Say(textValue)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function(_, evt, a1)
    if evt == "START_LOOT_ROLL" then
        -- Not seen in Forever's own UI code: used only where the client has it.
        local itemLink = GetLootRollItemLink and GetLootRollItemLink(a1)
        if itemLink and not Secret(itemLink) then
            Announce(itemLink)
        end
    elseif evt == "LOOT_OPENED" then
        for idx = 1, GetNumLootItems() do
            local itemLink = GetLootSlotLink(idx)
            if itemLink and not Secret(itemLink) then
                Announce(itemLink)
            end
        end
    elseif evt == "CHAT_MSG_LOOT" then
        if type(a1) == "string" and not Secret(a1) then
            local itemLink = a1:match("|c%x+|Hitem:.-|h.-|h|r")
            if itemLink then
                Announce(itemLink)
            end
        end
    elseif Refresh then
        Refresh()
    end
end)

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local ROW_H = 22
local window, rowList = nil, {}

local function Build()
    if window then
        return
    end
    window = CreateFrame("Frame", "CludesUIBiSWindow", UIParent)
    window:SetSize(420, 74 + #SLOTS * ROW_H)
    window:SetPoint("CENTER", 0, 40)
    CludesUI.Kit.Panel(window, 0.95)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetFrameStrata("HIGH")
    window.title = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(window.title, 15, "essentials")
    window.title:SetPoint("TOPLEFT", 10, -8)
    local close = CludesUI.Kit.Glyph(window, "x", function()
        window:Hide()
    end, nil, "essentials")
    close:SetPoint("TOPRIGHT", -5, -5)
    window.hint = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(window.hint, 11, "essentials")
    window.hint:SetPoint("BOTTOMLEFT", 10, 8)
    window.hint:SetText(
        "|cff9aa6b2Alt+Shift-click an item to add or remove it. Right-click a row to clear it.|r"
    )

    for idx, s in ipairs(SLOTS) do
        local r = CreateFrame("Button", nil, window)
        r:SetSize(400, ROW_H)
        r:SetPoint("TOPLEFT", 10, -32 - (idx - 1) * ROW_H)
        r:RegisterForClicks("AnyUp")
        r.slot = s[1]
        r.label = r:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(r.label, 12, "essentials")
        r.label:SetPoint("LEFT")
        r.label:SetWidth(70)
        r.label:SetJustifyH("LEFT")
        r.label:SetText("|cff9aa6b2" .. s[2] .. "|r")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 4, ROW_H - 4)
        r.icon:SetPoint("LEFT", 74, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(r.text, 12, "essentials")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetWidth(310)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        local highlight = r:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.05)
        r:SetScript("OnClick", function(self, btnFrame)
            local ident = List()[self.slot]
            if btnFrame == "RightButton" and ident then
                List()[self.slot] = nil
                Refresh()
            elseif ident and IsModifiedClick("CHATLINK") then
                local itemLink = select(2, C_Item.GetItemInfo(ident))
                if itemLink then
                    ChatEdit_InsertLink(itemLink)
                end
            end
        end)
        r:SetScript("OnEnter", function(self)
            local ident = List()[self.slot]
            if not ident then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(ident)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        rowList[idx] = r
    end
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIBiSWindow")
end

Refresh = function()
    if not (window and window:IsShown()) then
        return
    end
    local have, sum = 0, 0
    for _, r in ipairs(rowList) do
        local ident = List()[r.slot]
        if ident then
            sum = sum + 1
            local name, itemLink, quality = C_Item.GetItemInfo(ident)
            r.icon:SetTexture(C_Item.GetItemIconByID(ident))
            r.icon:Show()
            local mine = module.Owned(ident)
            if mine then
                have = have + 1
            end
            local gain = not mine and module.ItemGain and module.ItemGain(ident, itemLink)
            r.text:SetText(
                (itemLink or name or ("item " .. ident))
                    .. (mine and "  |cff60d080yours|r" or "  |cff9aa6b2needed|r")
                    .. (gain and ("  |cff60d080+%.1f%%|r"):format(gain) or "")
            )
        else
            r.icon:Hide()
            r.text:SetText("|cff606870none picked|r")
        end
    end
    window.title:SetText(
        ("%sBest in Slot|r  |cff9aa6b2%d of %d yours|r"):format(CludesUI.Kit.AccentHex(), have, sum)
    )
end

function module.ShowBis()
    Build()
    window:Show()
    Refresh()
end

-- Item names load later on a fresh login: repaint when they arrive.
local nameEv = CreateFrame("Frame")
nameEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
nameEv:SetScript("OnEvent", function()
    if Refresh then
        Refresh()
    end
end)

CludesUI._BiS = {
    Get = Get,
    Cfg = F.Cfg,
    Show = module.ShowBis,
    Export = module.ExportBis,
    Import = module.ImportBis,
    Toggle = module.ToggleBis,
}

SLASH_CUIBIS1 = "/cbis"
SlashCmdList.CUIBIS = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg ~= "" then
        return module.ToggleBis(msg)
    end
    if window and window:IsShown() then
        window:Hide()
    else
        module.ShowBis()
    end
end

F.Start(function() end)
