-- Bags: Bank Marker (CludesUIBags_BankMarker.lua). Alt + Left Click on a bag
-- slot holding Linen Cloth marks it (and the icon paints); opening the bank
-- deposits the two marked stacks one by one (UseContainerItem recorded), the
-- unmarked one stays; Ask First asks instead; marking again unmarks.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
local BM = ns and ns.BankMarker
OUT:write("== bank marker " .. tostring(BM ~= nil) .. "\n")
if not BM then return end

local bag = {
    [1] = { itemID = 2589, stackCount = 20, hyperlink = "[Linen Cloth]" },
    [2] = { itemID = 2589, stackCount = 7, hyperlink = "[Linen Cloth]" },
    [3] = { itemID = 118, stackCount = 5, hyperlink = "[Minor Healing Potion]" },
}
rawset(C_Container, "GetContainerNumSlots", function(b) return b == 0 and 3 or 0 end)
rawset(C_Container, "GetContainerItemInfo", function(b, s) return b == 0 and bag[s] or nil end)
rawset(C_Container, "GetContainerNumFreeSlots", function(b) return b == -1 and 10 or 0 end)
local used = {}
rawset(C_Container, "UseContainerItem", function(b, s) used[#used + 1] = b .. "/" .. s; bag[s] = nil end)
rawset(_G, "CursorHasItem", function() return false end)
rawset(_G, "BANK_CONTAINER", -1) -- the game's value; the fake client names unknown constants
rawset(C_PlayerInteractionManager, "IsInteractingWithNpcOfType", function() return false end)
local bags = rawget(_G, "CUI_Bags")
if bags then bags.RefreshInventory = function() end end -- its grid is not under test
local said = {}
local realPrint = CludesUI.Print
CludesUI.Print = function(t) said[#said + 1] = (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Alt + Left Click on slot 1.
local parent = CreateFrame("Frame", nil, UIParent)
parent:SetID(0)
local button = CreateFrame("Button", nil, parent)
button:SetID(1)
rawset(_G, "IsAltKeyDown", function() return true end)
ns.BankMarkerOnClick(button, "LeftButton")
ns.PaintBankMark(button, 2589)
OUT:write(("== marked: %s %s icon=%s\n"):format(tostring(BM.IsMarked(2589)), tostring(BM.IsMarked(118)), tostring(button._bankMark and button._bankMark:IsShown())))

-- The bank opens: two stacks go in.
local bankFrame = rawget(_G, "BankFrame") or CreateFrame("Frame", "BankFrame", UIParent)
bankFrame:Show()
HARNESS_FIRE_EVENT("BANKFRAME_OPENED")
for _ = 1, 12 do HARNESS_ADVANCE(0.1) end
OUT:write("== deposited: " .. table.concat(used, ", ") .. "\n")

-- Unmark (a new stack in the slot).
bag[1] = { itemID = 2589, stackCount = 3, hyperlink = "[Linen Cloth]" }
ns.BankMarkerOnClick(button, "LeftButton")
OUT:write("== unmarked: " .. tostring(BM.IsMarked(2589)) .. "\n")
CludesUI.Print = realPrint
OUT:write("== said:\n   " .. table.concat(said, "\n   ") .. "\n")
