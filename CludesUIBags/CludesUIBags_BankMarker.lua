if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBags_BankMarker.lua
--  Bank Marker: Alt + Left Click a bag item marks it for the bank (every
--  copy of it, account-wide; again to unmark). A marked item carries a small
--  banker icon in its top-left corner. Opening your bank deposits the marked
--  stacks in your bags: by itself, after asking, or not at all (Bank Marker
--  in the Bags options). Deposits go one stack at a time, as right-clicks
--  would, and stop when the bank is full.
-------------------------------------------------------------------------------
local mod = select(2, ...)
local CUI = CludesUI

local ICON = "Interface\\Minimap\\Tracking\\Banker"
local STEP = 0.15 -- seconds between deposits (the server locks a moving stack)

local BankMarker = {}
mod.BankMarker = BankMarker

local function Profile() return (CUI._bagsDB and CUI._bagsDB.profile) or {} end
function BankMarker.On() return Profile().bankMarker ~= false end
function BankMarker.Mode() return Profile().bankMarkerMode or "move" end -- move | ask | none

local function Marks()
    CludesUIDB.bankMarked = CludesUIDB.bankMarked or {}
    return CludesUIDB.bankMarked
end

function BankMarker.IsMarked(itemID)
    local marks = CludesUIDB and CludesUIDB.bankMarked
    return BankMarker.On() and itemID ~= nil and marks ~= nil and marks[itemID] == true
end

local function Say(text) CUI.Print(CUI.HexColor(CUI.Kit.Accent()) .. "Bank Marker|r: " .. text) end

function BankMarker.Toggle(itemID, link)
    if not itemID then return end
    local marks = Marks()
    marks[itemID] = not marks[itemID] or nil
    Say((link or ("item " .. itemID)) .. (marks[itemID] and " marked for the bank." or " is no longer marked."))
    if CUI_Bags and CUI_Bags:IsShown() and CUI_Bags.RefreshInventory then CUI_Bags:RefreshInventory() end
end

-- Hooked on every bag slot's OnClick (Grid and List): Alt + Left Click.
function mod.BankMarkerOnClick(self, mouse)
    if mouse ~= "LeftButton" or not IsAltKeyDown() or not BankMarker.On() or CursorHasItem() then return end
    local bag, slot = self:GetParent():GetID(), self:GetID()
    local info = bag and slot and C_Container.GetContainerItemInfo(bag, slot)
    if info and info.itemID then BankMarker.Toggle(info.itemID, info.hyperlink) end
end

-- The icon on a slot (Grid's paint, beside the Junk Marker's coin).
function mod.PaintBankMark(button, itemID)
    local on = BankMarker.IsMarked(itemID)
    local icon = button._bankMark
    if not icon then
        if not on then return end
        icon = button:CreateTexture(nil, "OVERLAY", nil, 6)
        icon:SetTexture(ICON)
        icon:SetSize(13, 13)
        icon:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        button._bankMark = icon
    end
    icon:SetShown(on)
end

-------------------------------------------------------------------------------
--  Depositing on bank open
-------------------------------------------------------------------------------
local function MarkedStacks()
    local stacks = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and BankMarker.IsMarked(info.itemID) and not info.isLocked then
                stacks[#stacks + 1] = { bag = bag, slot = slot, count = info.stackCount or 1 }
            end
        end
    end
    return stacks
end

-- Free slots in the character bank: its base slots, its tabs (or, on WoW
-- Forever, its bank bags) by the game's own bag indices.
local function BankFree()
    local seen, free = {}, 0
    local function Add(id)
        if id and not seen[id] then
            seen[id] = true
            free = free + (C_Container.GetContainerNumFreeSlots(id) or 0)
        end
    end
    Add(BANK_CONTAINER or -1)
    local index = Enum.BagIndex or {}
    for tab = 1, 9 do
        Add(index["CharacterBankTab_" .. tab])
    end
    local first = (NUM_BAG_SLOTS or 4) + 1
    for id = first, first + (NUM_BANKBAGSLOTS or 0) - 1 do
        Add(id)
    end
    return free
end

local running = 0
function BankMarker.Deposit()
    local stacks = MarkedStacks()
    if #stacks == 0 then return end
    running = running + 1
    local run, moved, items = running, 0, 0
    local function Next(index)
        if run ~= running then return end
        local bank = rawget(_G, "BankFrame")
        local ours = rawget(_G, "CUI_BankFrame")
        if not ((bank and bank:IsShown()) or (ours and ours:IsShown())) then return end
        local stack = stacks[index]
        if not stack then
            local left = #MarkedStacks()
            Say(("deposited %d %s (%d items)%s."):format(
                moved,
                moved == 1 and "stack" or "stacks",
                items,
                left > 0 and ("; %d marked %s left in your bags: the bank is full"):format(left, left == 1 and "stack" or "stacks") or ""
            ))
            return
        end
        if BankFree() <= 0 then
            stacks = {}
            return Next(1)
        end
        local info = C_Container.GetContainerItemInfo(stack.bag, stack.slot)
        if info and BankMarker.IsMarked(info.itemID) and not info.isLocked then
            C_Container.UseContainerItem(stack.bag, stack.slot)
            moved, items = moved + 1, items + (info.stackCount or 1)
        end
        C_Timer.After(STEP, function() Next(index + 1) end)
    end
    Next(1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_CLOSED" then
        running = running + 1
        return
    end
    if not BankMarker.On() or InCombatLockdown() then return end
    -- The portable warbank (an account banker) has no character bank.
    if C_PlayerInteractionManager and Enum.PlayerInteractionType
        and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.AccountBanker) then
        return
    end
    local mode = BankMarker.Mode()
    if mode == "none" then return end
    C_Timer.After(0.25, function()
        local stacks = #MarkedStacks()
        if stacks == 0 then return end
        if mode == "ask" and CUI.ShowConfirmPopup then
            CUI:ShowConfirmPopup({
                title = "Bank Marker",
                message = ("Deposit %d marked %s in your character bank?"):format(stacks, stacks == 1 and "stack" or "stacks"),
                confirmText = "Deposit",
                cancelText = "Not Now",
                onConfirm = function() BankMarker.Deposit() end,
            })
        else
            BankMarker.Deposit()
        end
    end)
end)

CUI._BankMarker = BankMarker
