if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then return end
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

local function Say(text) CludesUI.Print("|cff4cc9f0BiS:|r " .. text) end
local function Font() return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT end
local function Secret(v) return issecretvalue and issecretvalue(v) end

local SLOTS = {   -- inventory slot, name, in window order
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulders" }, { 15, "Back" }, { 5, "Chest" }, { 9, "Wrist" },
    { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" }, { 11, "Ring" }, { 12, "Ring" },
    { 13, "Trinket" }, { 14, "Trinket" }, { 16, "Main Hand" }, { 17, "Off Hand" }, { 18, "Ranged" },
}
local SLOT_NAME = {}
for _, s in ipairs(SLOTS) do SLOT_NAME[s[1]] = s[2] end

local BY_EQUIP = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local _, CLASS = UnitClass("player")

-- lists[class] = { [invSlot] = itemID }
local function List()
    local c = F.Cfg()
    c.lists = c.lists or {}
    c.lists[CLASS] = c.lists[CLASS] or {}
    return c.lists[CLASS]
end

local Refresh   -- the window's repaint, set below

local function IDFrom(v)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    return tonumber(v:match("item:(%d+)") or v:match("^%s*(%d+)%s*$"))
end

--- The slot this item has on the list, if any.
function module.BisSlotOf(itemID)
    for slot, id in pairs(List()) do
        if id == itemID then return slot end
    end
end

function module.Owned(itemID)
    return C_Item.IsEquippedItem(itemID) or (C_Item.GetItemCount(itemID, true) or 0) > 0
end

--- Adds an item to its slot (or takes it off when it is already listed).
function module.ToggleBis(link)
    local id = IDFrom(link)
    if not id then return Say("that is not an item.") end
    local slot = module.BisSlotOf(id)
    if slot then
        List()[slot] = nil
        Say(("took %s off your list."):format(select(2, C_Item.GetItemInfo(id)) or ("item " .. id)))
        if Refresh then Refresh() end
        return
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(id)
    local slots = BY_EQUIP[equipLoc or ""]
    if not slots then return Say("that item is not gear.") end
    local target = slots[1]
    for _, s in ipairs(slots) do
        if not List()[s] then target = s; break end
    end
    List()[target] = id
    Say(("%s is your BiS for %s."):format(select(2, C_Item.GetItemInfo(id)) or ("item " .. id), SLOT_NAME[target]))
    if Refresh then Refresh() end
end

function module.ExportBis()
    local parts = {}
    for _, s in ipairs(SLOTS) do
        local id = List()[s[1]]
        if id then parts[#parts + 1] = s[1] .. "=" .. id end
    end
    return "CUIBIS1:" .. CLASS .. ":" .. table.concat(parts, ",")
end

function module.ImportBis(text)
    local class, body = (text or ""):match("^%s*CUIBIS1:(%u+):([%d=,]*)%s*$")
    if not class then return Say("that is not a CludesUI BiS line.") end
    if class ~= CLASS then return Say("that list is for another class.") end
    local list, n = {}, 0
    for slot, id in body:gmatch("(%d+)=(%d+)") do
        slot, id = tonumber(slot), tonumber(id)
        if SLOT_NAME[slot] then list[slot] = id; n = n + 1 end
    end
    F.Cfg().lists[CLASS] = list
    Say(("imported %d pick%s."):format(n, n == 1 and "" or "s"))
    if Refresh then Refresh() end
end

-------------------------------------------------------------------------------
--  Alt+Shift-click
-------------------------------------------------------------------------------
if HandleModifiedItemClick then hooksecurefunc("HandleModifiedItemClick", function(link)
    if not (Get("enabled") and IsAltKeyDown() and IsShiftKeyDown()) then return end
    if type(link) ~= "string" or Secret(link) or not link:find("item:") then return end
    module.ToggleBis(link)
end) end

-------------------------------------------------------------------------------
--  Tooltips
-------------------------------------------------------------------------------
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if not (Get("enabled") and Get("tooltip")) or not data then return end
        local id = data.id
        if type(id) ~= "number" or Secret(id) then return end
        local slot = module.BisSlotOf(id)
        if slot then
            tooltip:AddLine(("|cffff9933*|r |cff4cc9f0BiS for %s|r%s"):format(SLOT_NAME[slot],
                module.Owned(id) and "  |cff60d080(yours)|r" or ""))
        end
    end)
end

-------------------------------------------------------------------------------
--  Drop Alert
-------------------------------------------------------------------------------
local said = {}
local function Announce(link)
    if not (Get("enabled") and Get("alert")) then return end
    local id = IDFrom(link)
    if not id or module.Owned(id) then return end
    local slot = module.BisSlotOf(id)
    if not slot then return end
    if said[id] and GetTime() - said[id] < 30 then return end
    said[id] = GetTime()
    local text = ("BiS dropped: %s (%s)"):format(link, SLOT_NAME[slot])
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.6, b = 0.2 })
    end
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    Say(text)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function(_, event, a1)
    if event == "START_LOOT_ROLL" then
        -- Not seen in Forever's own UI code: used only where the client has it.
        local link = GetLootRollItemLink and GetLootRollItemLink(a1)
        if link and not Secret(link) then Announce(link) end
    elseif event == "LOOT_OPENED" then
        for i = 1, GetNumLootItems() do
            local link = GetLootSlotLink(i)
            if link and not Secret(link) then Announce(link) end
        end
    elseif event == "CHAT_MSG_LOOT" then
        if type(a1) == "string" and not Secret(a1) then
            local link = a1:match("|c%x+|Hitem:.-|h.-|h|r")
            if link then Announce(link) end
        end
    elseif Refresh then
        Refresh()
    end
end)

-------------------------------------------------------------------------------
--  Window
-------------------------------------------------------------------------------
local ROW_H = 22
local win, rows = nil, {}

local function Build()
    if win then return end
    win = CreateFrame("Frame", "CludesUIBiSWindow", UIParent, "BackdropTemplate")
    win:SetSize(420, 74 + #SLOTS * ROW_H)
    win:SetPoint("CENTER", 0, 40)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    win:SetBackdropColor(0.06, 0.07, 0.09, 0.95)
    win:SetBackdropBorderColor(0.30, 0.79, 0.94, 0.8)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("HIGH")
    win.title = win:CreateFontString(nil, "OVERLAY")
    win.title:SetFont(Font(), 15, "OUTLINE")
    win.title:SetPoint("TOPLEFT", 10, -8)
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    win.hint = win:CreateFontString(nil, "OVERLAY")
    win.hint:SetFont(Font(), 11, "")
    win.hint:SetPoint("BOTTOMLEFT", 10, 8)
    win.hint:SetText("|cff9aa6b2Alt+Shift-click an item to add or remove it. Right-click a row to clear it.|r")

    for i, s in ipairs(SLOTS) do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(400, ROW_H)
        r:SetPoint("TOPLEFT", 10, -32 - (i - 1) * ROW_H)
        r:RegisterForClicks("AnyUp")
        r.slot = s[1]
        r.label = r:CreateFontString(nil, "OVERLAY")
        r.label:SetFont(Font(), 12, "")
        r.label:SetPoint("LEFT")
        r.label:SetWidth(70)
        r.label:SetJustifyH("LEFT")
        r.label:SetText("|cff9aa6b2" .. s[2] .. "|r")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 4, ROW_H - 4)
        r.icon:SetPoint("LEFT", 74, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY")
        r.text:SetFont(Font(), 12, "")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetWidth(310)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        r:SetScript("OnClick", function(self, button)
            local id = List()[self.slot]
            if button == "RightButton" and id then
                List()[self.slot] = nil
                Refresh()
            elseif id and IsModifiedClick("CHATLINK") then
                local link = select(2, C_Item.GetItemInfo(id))
                if link then ChatEdit_InsertLink(link) end
            end
        end)
        r:SetScript("OnEnter", function(self)
            local id = List()[self.slot]
            if not id then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(id)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIBiSWindow")
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local have, total = 0, 0
    for _, r in ipairs(rows) do
        local id = List()[r.slot]
        if id then
            total = total + 1
            local name, link, quality = C_Item.GetItemInfo(id)
            r.icon:SetTexture(C_Item.GetItemIconByID(id))
            r.icon:Show()
            local mine = module.Owned(id)
            if mine then have = have + 1 end
            r.text:SetText((link or name or ("item " .. id)) .. (mine and "  |cff60d080yours|r" or "  |cff9aa6b2needed|r"))
        else
            r.icon:Hide()
            r.text:SetText("|cff606870none picked|r")
        end
    end
    win.title:SetText(("|cff4cc9f0Best in Slot|r  |cff9aa6b2%d of %d yours|r"):format(have, total))
end

function module.ShowBis()
    Build()
    win:Show()
    Refresh()
end

-- Item names load later on a fresh login: repaint when they arrive.
local nameEv = CreateFrame("Frame")
nameEv:RegisterEvent("GET_ITEM_INFO_RECEIVED")
nameEv:SetScript("OnEvent", function() if Refresh then Refresh() end end)

CludesUI._BiS = { Get = Get, Cfg = F.Cfg, Show = module.ShowBis, Export = module.ExportBis, Import = module.ImportBis,
                  Toggle = module.ToggleBis }

SLASH_CUIBIS1 = "/cbis"
SlashCmdList.CUIBIS = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$")
    if msg ~= "" then return module.ToggleBis(msg) end
    if win and win:IsShown() then win:Hide() else module.ShowBis() end
end

F.Start(function() end)
