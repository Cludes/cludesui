-- Forever: The Market panel's Shopping tab. RestedXP .collect lines count
-- too (with fields, or only "Name: 8/10" text); quest-only items are left out.
-- (CludesUIForeverEssentials_MarketPanel.lua).
-- A RestedXP step wants 5 Refreshing Spring Water (2 in bags) and 1 Coarse
-- Thread (already have it); a quest wants Linen Cloth 3/10 and has a done
-- item objective and a kill objective. The tab lists the water and the cloth;
-- a click searches the Buy tab; Shopping Tab off hides the tab.
local CUI = rawget(_G, "CludesUI")
local MK, MP = CUI and CUI._Market, CUI and CUI._MarketPanel
OUT:write("== panel " .. tostring(MP ~= nil and MP.Shop ~= nil) .. "\n")
if not (MP and MP.Shop) then return end

CludesUIDB.market = { enabled = true }
MK.Apply()

local names = { [159] = "Refreshing Spring Water", [2320] = "Coarse Thread", [9259] = "Troll Tribal Necklace", [2522] = "Gorilla Fang" }
local counts = { [159] = 2, [2320] = 1, [2522] = 8 }
rawset(C_Item, "GetItemInfo", function(id) return names[id], "[" .. tostring(names[id]) .. "]", 1, 1, 1, "", "", 20, "", 7 end)
rawset(C_Item, "GetItemCount", function(id) return counts[id] or 0 end)
local instant = { ["Linen Cloth"] = { 2589, 7 }, ["Gorilla Fang"] = { 2522, 15 }, ["Otto's Head"] = { 5000, 12 } }
rawset(C_Item, "GetItemInfoInstant", function(name)
    local i = instant[name]
    if i then return i[1], "", "", "", 9, i[2] end
end)
rawset(_G, "RXP", { RXPFrame = { activeSteps = {
    { active = true, elements = {
        { tag = "buy", id = 159, qty = 5, text = "Buy water" },
        { tag = "buy", id = 2320, qty = 1, text = "Buy thread" },
        { tag = "collect", id = 9259, qty = 5, text = "Troll Tribal Necklace" },
        { tag = "collect", frame = { text = { GetText = function() return "|cffffaa00Gorilla Fang: 8/10|r" end } } },
        { tag = "goto", text = "Go there" },
    } },
    { active = false, elements = { { tag = "buy", id = 2320, qty = 9 } } },
} } })
rawset(C_QuestLog, "GetNumQuestLogEntries", function() return 2 end)
rawset(C_QuestLog, "GetInfo", function(i)
    if i == 1 then return { isHeader = true, title = "Elwynn Forest" } end
    return { questID = 77, title = "Cloth for Tailors" }
end)
rawset(C_QuestLog, "GetQuestObjectives", function(id)
    if id ~= 77 then return {} end
    return {
        { type = "item", text = "Linen Cloth: 3/10", finished = false, numFulfilled = 3, numRequired = 10 },
        { type = "item", text = "Wool Cloth: 2/2", finished = true, numFulfilled = 2, numRequired = 2 },
        { type = "item", text = "Otto's Head: 0/1", finished = false, numFulfilled = 0, numRequired = 1 },
        { type = "monster", text = "Kobold Miner slain: 1/8", finished = false, numFulfilled = 1, numRequired = 8 },
    }
end)
for _, name in ipairs({ "SendSearchQuery", "QueryOwnedAuctions" }) do rawset(C_AuctionHouse, name, function() end) end
rawset(C_AuctionHouse, "IsThrottledMessageSystemReady", function() return true end)
rawset(C_AuctionHouse, "GetNumOwnedAuctions", function() return 0 end)

local searched = {}
local house = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
house:SetSize(800, 600)
house:SetPoint("CENTER")
house.SearchBar = {
    SetSearchText = function(_, text) searched[#searched + 1] = text end,
    StartSearch = function() searched[#searched + 1] = "go" end,
}
house:Show()
HARNESS_FIRE_EVENT("AUCTION_HOUSE_SHOW")
HARNESS_ADVANCE(0.1)
local panel = rawget(_G, "CludesUIMarketPanel")
if not panel then return OUT:write("== no panel\n") end

local function Tabs()
    local list = {}
    for _, tab in ipairs(panel.tabs) do
        if tab:IsShown() then list[#list + 1] = tab:GetText() end
    end
    return table.concat(list, ", ")
end
local function Rows()
    local list = {}
    for _, row in ipairs(panel.shop.rows) do
        if row:IsShown() then list[#list + 1] = row.name:GetText() .. " " .. (row.right:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
    return table.concat(list, "; ")
end

OUT:write("== tabs: " .. Tabs() .. "\n")
panel.tabs[4]:GetScript("OnClick")(panel.tabs[4])
OUT:write(("== shop: shown=%s | %s\n   %s\n"):format(tostring(panel.shop:IsShown()), panel.shop.status:GetText(), Rows()))
SNAP("market shopping", panel)

local row = panel.shop.rows[1]
row:GetScript("OnClick")(row)
OUT:write("== searched: " .. table.concat(searched, ", ") .. "\n")

-- Three more waters bought: the guide has its five.
counts[159] = 5
HARNESS_FIRE_EVENT("BAG_UPDATE_DELAYED")
OUT:write("== after buying water: " .. Rows() .. "\n")

CludesUIDB.market.shopping = false
MP.Panel.Render()
OUT:write(("== shopping off: tabs %s | page %s\n"):format(Tabs(), tostring(MP.Panel.page)))
