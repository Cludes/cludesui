-- Forever: The Market's panel (CludesUIForeverEssentials_MarketPanel.lua)
-- beside a stand-in auction house. Bags: 25 Copper Bar (a commodity, scan
-- 8s) and a Runed Copper Bracers (an item, no scan). Opening it picks the
-- bar and searches its listings (others at 7s 50c, yours at 7s 60c):
-- price one copper under, Post (records PostCommodity), the game's answer,
-- the next item. My Auctions: a bar auction at 9s (undercut by 7s 50c) and
-- the bracers at 2g (nobody else lists them): checked one search at a time
-- after the Sell search, the chat alert, Cancel Next Undercut. Each step's
-- state is written as == lines.
local CUI = rawget(_G, "CludesUI")
local MK, MP = CUI and CUI._Market, CUI and CUI._MarketPanel
OUT:write("== panel " .. tostring(MP ~= nil) .. "\n")
if not MP then return end

CludesUIDB.market = {
    enabled = true,
    houses = { [GetRealmName() .. "-" .. UnitFactionGroup("player")] = { time = GetServerTime(), prices = { [2840] = 800 }, listed = {} } },
}
MK.Apply()
local said = {}
local realPrint = CUI.Print
CUI.Print = function(text) said[#said + 1] = (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Bags: slot 1 = 25 bars, slot 2 = the bracers.
local slots = {
    [1] = { itemID = 2840, stackCount = 25, hyperlink = "[Copper Bar]", iconFileID = 1, commodity = true },
    [2] = { itemID = 2854, stackCount = 1, hyperlink = "[Runed Copper Bracers]", iconFileID = 2 },
}
rawset(C_Container, "GetContainerNumSlots", function(bag) return bag == 0 and 2 or 0 end)
rawset(C_Container, "GetContainerItemInfo", function(bag, slot) return bag == 0 and slots[slot] or nil end)
rawset(_G, "ItemLocation", {
    CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
})
local names = { [2840] = "Copper Bar", [2854] = "Runed Copper Bracers" }
rawset(C_Item, "GetItemNameByID", function(id) return names[id] end)
rawset(C_Item, "GetItemInfo", function(id) return names[id], nil, 1, 1, 1, "", "", 20, "", 1, id == 2840 and 150 or 900 end)
rawset(C_Item, "GetItemIconByID", function() return 1 end)

local AH = C_AuctionHouse
local calls = {}
local function Note(text) calls[#calls + 1] = text end
local function Set(name, fn) rawset(AH, name, fn) end
Set("IsSellItemValid", function(loc) return slots[loc.slot] ~= nil end)
Set("GetItemCommodityStatus", function(loc) return slots[loc.slot].commodity and Enum.ItemCommodityStatus.Commodity or Enum.ItemCommodityStatus.Item end)
Set("IsThrottledMessageSystemReady", function() return true end)
Set("SupportsCopperValues", function() return true end)
Set("MakeItemKey", function(id) return { itemID = id } end)
Set("GetItemKeyFromItem", function(loc) return { itemID = slots[loc.slot].itemID, itemLevel = 0, itemSuffix = 0 } end)
Set("SendSearchQuery", function(key) Note("search " .. key.itemID) end)
local commodity = {
    { unitPrice = 750, quantity = 20, numOwnerItems = 0 },
    { unitPrice = 760, quantity = 5, numOwnerItems = 5 },
}
Set("GetNumCommoditySearchResults", function() return #commodity end)
Set("GetCommoditySearchResultInfo", function(_, i) return commodity[i] end)
Set("GetNumItemSearchResults", function() return 1 end)
Set("GetItemSearchResultInfo", function() return { buyoutAmount = 20000, quantity = 1, containsOwnerItem = true } end)
Set("CalculateCommodityDeposit", function(_, duration, quantity) return 15 * duration * quantity end)
Set("CalculateItemDeposit", function() return 300 end)
Set("PostCommodity", function(loc, duration, quantity, price)
    Note(("post commodity slot %d x%d at %d for %d"):format(loc.slot, quantity, price, duration))
    return false
end)
Set("PostItem", function() Note("post item") return false end)
local owned = {
    { auctionID = 11, itemKey = { itemID = 2840, itemLevel = 0, itemSuffix = 0 }, quantity = 10, buyoutAmount = 900, status = 0 },
    { auctionID = 12, itemKey = { itemID = 2854, itemLevel = 0, itemSuffix = 0 }, quantity = 1, buyoutAmount = 20000, status = 0 },
}
Set("QueryOwnedAuctions", function() Note("query owned") end)
Set("GetNumOwnedAuctions", function() return #owned end)
Set("GetOwnedAuctionInfo", function(i) return owned[i] end)
Set("GetItemKeyInfo", function(key) return { isCommodity = key.itemID == 2840 } end)
Set("CanCancelAuction", function() return true end)
Set("CancelAuction", function(id) Note("cancel " .. id) end)

local house = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
house:SetSize(800, 600)
house:SetPoint("CENTER")
house:Show()
HARNESS_FIRE_EVENT("AUCTION_HOUSE_SHOW")
HARNESS_ADVANCE(0.1)
local panel = rawget(_G, "CludesUIMarketPanel")
OUT:write("== shown: " .. tostring(panel and panel:IsShown()) .. " calls: " .. table.concat(calls, ", ") .. "\n")
if not panel then return end
local card = panel.sell.card
local function Card(label)
    local queue = {}
    for _, row in ipairs(panel.sell.queue) do
        if row:IsShown() then queue[#queue + 1] = row.name:GetText() .. " " .. row.right:GetText() end
    end
    local listings = {}
    for _, row in ipairs(panel.sell.listings) do
        if row:IsShown() then listings[#listings + 1] = (row.name:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. " " .. row.right:GetText() end
    end
    OUT:write(
        ("== %s: %s | %s | price %s qty %s | %s | %s\n   listings: %s\n   bags: %s\n   message: %s\n"):format(
            label,
            tostring(card.name:GetText()),
            tostring(card.sub:GetText()),
            tostring(card.price:GetText()),
            tostring(card.qty:GetText()),
            tostring(card.reason:GetText()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " / "),
            tostring(card.deposit:GetText()),
            table.concat(listings, "; "),
            table.concat(queue, "; "),
            tostring(panel.message:GetText())
        )
    )
end
Card("picked")

-- The listings come back; then the owned auctions arrive.
HARNESS_FIRE_EVENT("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
Card("listed")
SNAP("market panel", panel)

-- Post 20 of them.
card.qty:SetText("20")
card.qty:GetScript("OnEditFocusLost")(card.qty)
card.post:GetScript("OnClick")(card.post)
OUT:write("== posting: " .. tostring(card.post:GetText()) .. " calls: " .. table.concat(calls, ", ") .. "\n")
slots[1].stackCount = 5
HARNESS_FIRE_EVENT("AUCTION_HOUSE_AUCTION_CREATED")
Card("after post")

-- My Auctions: the owned list, then each one's listings, then the alert.
wipe(calls)
HARNESS_FIRE_EVENT("OWNED_AUCTIONS_UPDATED")
HARNESS_FIRE_EVENT("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
HARNESS_FIRE_EVENT("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2854, itemLevel = 0, itemSuffix = 0 })
-- The Sell page's search for the bracers ran first (it was picked after the post).
HARNESS_FIRE_EVENT("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2854, itemLevel = 0, itemSuffix = 0 })
HARNESS_FIRE_EVENT("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
HARNESS_FIRE_EVENT("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2854, itemLevel = 0, itemSuffix = 0 })
OUT:write("== checks: " .. table.concat(calls, ", ") .. "\n")
panel.tabs[2]:GetScript("OnClick")(panel.tabs[2])
HARNESS_FIRE_EVENT("OWNED_AUCTIONS_UPDATED")
HARNESS_FIRE_EVENT("COMMODITY_SEARCH_RESULTS_UPDATED", 2840)
HARNESS_FIRE_EVENT("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 2854, itemLevel = 0, itemSuffix = 0 })
local rows = {}
for _, row in ipairs(panel.mine.rows) do
    if row:IsShown() then rows[#rows + 1] = row.name:GetText() .. " " .. (row.right:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
end
OUT:write(
    ("== mine: tab=%s | %s\n   %s\n"):format(
        tostring(panel.tabs[2]:GetText()),
        tostring(panel.mine.summary:GetText()):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""),
        table.concat(rows, "\n   ")
    )
)
wipe(calls)
panel.mine.next:GetScript("OnClick")(panel.mine.next)
OUT:write("== cancel next: " .. table.concat(calls, ", ") .. "\n")
OUT:write("== said:\n   " .. table.concat(said, "\n   ") .. "\n")
CUI.Print = realPrint
